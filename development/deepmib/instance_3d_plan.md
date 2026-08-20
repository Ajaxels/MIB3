# 3D Instance Stitching — Improvement Plan (`utils.stitchInstances2Dto3D`)

> Deferred DeepMIB ideas (checkpoint weight averaging, two-phase freeze/unfreeze training,
> per-object score export and score-guided gap bridging) are collected in
> [`potential_improvements.md`](potential_improvements.md).

Follow-up to [`stitchInstances2Dto3D.md`](stitchInstances2Dto3D.md) (algorithm + MIB integration,
already done) and the "Future roadmap — 3D instance segmentation" section of
[`instance_2d_plan.md`](instance_2d_plan.md). This plan re-evaluates the three open design
questions raised for the wider 3D phase and lays out an efficient, measurement-driven order of work.

## Current state (verified 2026-07)

- **Utility:** `mib/+utils/stitchInstances2Dto3D.m` — `[H×W×Z]` label volume in/out, `'graph'`
  (union-find over an undirected overlap graph) default, `'hungarian'` kept for paper-faithful
  comparison. Validated once (easy set: 2707→33, median IoU 1.000 vs 3D GT; hard set: 13923→206).
- **MIB path is fully wired** (not pending): ribbon → `MibModel.stitchModelInstances`
  (BatchOpt + dialog + undo backup + progress) → `MibDataset.stitchModelInstances` (per-timepoint
  read/write, `getData3D('labels', t, 3, …)`) → utility. Pixel size **is already at the call site**
  (`MibDataset.stitchModelInstances` holds `obj.image.pixSize`) — it is simply not forwarded.
- **DeepMIB auto-feed** (2D prediction stack → stitcher) — **done (2026-07):**
  `MibDeep.mergeInstancesTo3D` (Predict tab → *Instance segmentation* → "Merge 2D to 3D" button,
  `P_mergeInstancesTo3D` in `MibDeepGUI.mlapp`). Reads the per-slice `*.model` files from
  `PredictionImages/ResultsModels` (alphabetical order = Z-order), shows the same stitch-settings
  dialog as `MibModel.stitchModelInstances` (anisotropy as a direct spinner since raw prediction
  images carry no pixSize), then saves via `io.SaverFactory` in a curated set of labels formats —
  single 3D file or 2D sequence (the TIF/model savers ask their own 3D-stack/2D-sequence policy).
  Core pipeline validated by `temp/testMergeInstances.m` (load → stitch → save round-trips for
  .model single/sequence and TIF stack/sequence). Docs: `deepmib-instance.md` (new "Merging 2D
  predictions into a 3D model" section) + `deepmib-predict.md` (subpanel button).
- **No tests exist** for the utility, and **no false-merge / false-split metric** exists — only a
  one-off note in the markdown.

## Re-evaluation of the three proposals

### 1. Greedy slice-pairwise vs. global optimization — **defer; gate on measurement**
Union-find is already a global *connectivity* solution. Full min-cost-flow / tracking-by-assignment
needs an LP solver, tuning, and is admitted prohibitive at ~14k objects → **rejected as
over-engineering**. The one real failure mode is transitive **over-merge** (two distinct objects
that touch with IoA>threshold on a few slices fuse irreversibly). The right response is the cheap
middle ground — **hysteresis edges** (link only on a strong single pair OR a run of *k* consecutive
medium-overlap pairs) — but **only if the metric proves over-merge actually occurs** on real data.

### 2. Anisotropic Z — **highest value, lowest cost; do first after the harness**
Directly affects "works well" on MIB's actual audience (SBEM / FIB-SEM, e.g. 5 nm in-plane vs
40–50 nm sections). Minimum viable change is small:
- thread `az = pixSize.z / pixSize.x` in (already available at the call site);
- lower `iouThreshold` monotonically with `az`, lean on **IoA** (containment survives displacement
  when IoU does not);
- add an optional **centroid-displacement cap** so relaxed thresholds do not let distant objects
  fuse (centroids are cheap to accumulate alongside the areas already computed in `localLinkPair`).

**Caveat (flagged, not solved here):** threshold relaxation only helps while consecutive masks
*still overlap*. Under extreme anisotropy where an object's masks on `z` and `z+1` do not touch at
all, no candidate pair is even generated (the code keys off `csA>0 & csB>0`), so relaxing thresholds
does nothing — that regime needs **centroid-nearest-neighbour candidate generation** (heavier), and
is itself gated on evidence. `zLookback` partially mitigates single-slice dropouts already.

Shape-predicted overlap and NN-interpolation pre-passes are overkill / fraught → **skip**.

### 3. Whole-slide memory — **defer; document trigger**
The core is already two-slice-scoped, so postponing the streaming refactor loses nothing; it only
bites at tens–hundreds of GB and cannot be done in isolation (needs a BigData / blockedImage sink).
Two-pass streaming is the eventual path; RLE next; full block+seam last. **Trigger condition:** a
single-timepoint labels volume no longer fits comfortably in RAM.

## Phased plan (efficient order)

> Through-line: **Phase A unlocks B and C** (measurement is the objective function); **B is the
> clear win**; **C and D are demand-driven**. No solver, no streaming engine built before proven
> necessary.

### Phase A — Measurement + regression harness  *(do first; touches no production code)*
- New `tests/utils/StitchInstances2Dto3DTest.m` (mirrors `tests/utils/PureUtilsTest.m` conventions:
  `MibPathFixture`, fresh data per method, `Unit` tag).
  - **Unit (synthetic, offline):** build a small known 3D instance volume, split into per-slice
    labels, **scramble per-slice IDs**, stitch, and assert (a) output object count equals GT count,
    (b) one-to-one GT↔output correspondence (each GT object maps to exactly one output label and
    vice versa). Locks in the validated behaviour and guards every later change.
  - **Metric helper** `tests/+mibtest/+helpers/instanceStitchMetrics.m`: given a stitched volume and
    a GT volume, return `numFalseMerge` (one output label covering ≥2 GT objects) and
    `numFalseSplit` (one GT object covered by ≥2 output labels), via the object-overlap contingency
    table. This is the objective function Proposals 1 & 2 both require.
  - **Integration (`Integration`, self-skipping):** if the easy/hard benchmark TIFFs are reachable
    (`hasTestData`-style guard), compute false-merge/false-split vs the 3D GT and assert against a
    recorded baseline. Anisotropy is simulated by z-subsampling the isotropic GT.
- Deliverable: a red/green signal for correctness + the merge/split counts.

### Phase B — Anisotropy  *(highest value)*
- `utils.stitchInstances2Dto3D`: add `options.anisotropyZ` (default `1`, backward-compatible) and
  `options.maxCentroidShift` (default `Inf` = off). Scale `iouThreshold` down with `anisotropyZ`,
  weight toward IoA, and gate links on centroid displacement (accumulate centroids in
  `localLinkPair` next to the existing area accumulators).
- `MibDataset.stitchModelInstances`: forward `pixSize.z/pixSize.x` into `options.anisotropyZ`.
- `MibModel.stitchModelInstances`: surface an "voxels anisotropic in Z (use pixel size)" toggle +
  optional centroid-shift spinner in the dialog + BatchOpt; tooltips + docs.
- Validate with the Phase A harness (both synthetic anisotropic case and, if available, the
  z-subsampled benchmark).

### Phase C — Hysteresis edges  *(conditional on Phase A metric showing over-merge matters)*
- Edge-weighted union-find in `'graph'`: require IoU ≥ `iouStrong` on ≥1 pair, OR ≥ `kConsecutive`
  medium-overlap pairs, before fusing. Keep default behaviour unless enabled.
- Only pursue if the false-merge count justifies it.

### Phase D — Streaming to BigData sink  *(deferred; documented trigger)*
- Two-pass streaming (Pass 1 build union-find over rolling 2-slice window; Pass 2 apply LUT slice by
  slice to a blockedImage / BigData sink). Picked up when a single-timepoint volume stops fitting
  RAM. RLE and block+seam reconciliation are later levers.

## Key files
- New: `tests/utils/StitchInstances2Dto3DTest.m`, `tests/+mibtest/+helpers/instanceStitchMetrics.m`.
- Edit (Phase B): `mib/+utils/stitchInstances2Dto3D.m`,
  `mib/+core/@MibDataset/stitchModelInstances.m`, `mib/+models/@MibModel/stitchModelInstances.m`;
  docs in `docs_api/` + `docs/` per repo doc rules.
- Shared settings dialog: `mib/+utils/+dlgs/stitchInstancesSettingsDlg.m` - **add any new stitching
  parameter here**, not in the two callers.

## Status
- **Phase A — done.** `tests/utils/StitchInstances2Dto3DTest.m` (9 Unit cases) +
  `tests/+mibtest/+helpers/instanceStitchMetrics.m`. All green (0.28 s). Covers: scrambled-ID
  reconstruction for both `graph` and `hungarian` (zero false merge/split, one-to-one), empty /
  single-slice / class-promotion edge cases, `zLookback` dropout bridging, `minObjectVoxels`
  fragment removal, and two self-checks that the merge/split metric itself fires correctly.
  Test-data note: GT objects are placed on a **non-overlapping grid** — the "no false merge"
  invariant only holds when GT objects are spatially disjoint.
- **Phase B — done.** Anisotropy support:
  - `utils.stitchInstances2Dto3D` — new `anisotropyZ` (relaxes effective IoU to
    `max(iouThreshold/anisotropyZ, iouFloor)`, IoA left unchanged), `iouFloor`, and
    `maxCentroidShift` (centroid-distance gate, scaled by the slice gap). Applies to both `graph`
    and `hungarian`. Defaults (`anisotropyZ=1`, `maxCentroidShift=Inf`) are fully backward-compatible.
  - `MibModel.stitchModelInstances` — new `UseAnisotropy` checkbox + `MaxCentroidShift` spinner in
    the dialog/BatchOpt; `anisotropyZ` derived from `pixSize.z/pixSize.x` at the call site. `MibDataset`
    backend unchanged (options flow straight through).
  - Tests: 2 new Unit cases (drifting-tube recovery; centroid gate prevents a far containment merge)
    — 11/11 green. End-to-end batch smoke test passed (az=4 + 6px gate → correct 2 instances).
  - Docs: user table in `docs/.../ribbon/model/index.md`; note in `stitchInstances2Dto3D.md`.
- **Phase C (hysteresis edges) — measured and REJECTED (not implemented).** The benchmark data is
  now local (`c:\MATLAB\Data\SOLOv2_Implementation\MitoNet_benchmark\examples`); measurement via the
  new `instanceStitchMetrics` helper decides against it:

  | set | config | out | falseMerge | falseSplit | oneToOne |
  |-----|--------|-----|-----------|-----------|----------|
  | easy | graph default | 33 | 0 | 0 | 33/33 |
  | hard | graph default | 206 | 14 | 54 | 62/131 |
  | hard | + `minObjectVoxels=50` | 125 | 14 | 10 | 95/131 |
  | hard | + `minObjectVoxels=200, zLookback=2` | 119 | 14 | 8 | 94/131 |

  Findings that redirect the plan:
  1. **Over-split, not over-merge, is the visible error** — and it is almost entirely single-slice
     noise fragments. `minObjectVoxels` cleanup (already implemented) drops false splits 54→10 and
     lifts one-to-one 62→95. This is the single biggest, cheapest lever.
  2. **The 14 false merges are threshold-invariant** (identical across every IoU/IoA/zLookback/aniso
     setting). Characterisation of their z-bridges: **13/14 are sustained overlaps (bridge 7–120
     slices)**; only 1 is a narrow 2-slice bridge to a 68-voxel noise fragment. Hysteresis edges can
     only cut *narrow* waists, so they would fix at most 1/14 — and that one is better removed as
     noise. No overlap-graph method can separate two objects that overlap across dozens of slices;
     that needs instance-level shape/appearance features or cleaner 2D input.
  - **Conclusion:** do not build hysteresis. Guidance instead: recommend `minObjectVoxels` (~50–200)
    as the default post-stitch cleanup.
  - Recorded as a regression guard: `StitchInstances2Dto3DTest` Integration cases
    (`easyBenchmarkReconstructsGroundTruth`, always-on; `hardBenchmarkBaseline`, opt-in via
    `MIB3_STITCH_BENCHMARK_HARD=1` due to ~10 GB RAM), plus `mibtest.helpers.stitchBenchmarkDir`.
- **Phase C′ (centroid-NN gap bridging) — implemented, off by default; benchmarks do not exercise it.**
  New `options.centroidLinkRadius` (+ `centroidSizeRatio`): for an object with **no** overlap partner
  on a compared slice pair (an orphan), add a link to the mutually-nearest orphan on the other slice
  within the radius (scaled by the slice gap) and of comparable size. Threaded through
  `MibModel.stitchModelInstances` (BatchOpt `CentroidLinkRadius` + dialog spinner). Correct and unit
  tested (drifting non-overlapping tube recovered to 1 object; two parallel tubes recovered to 2
  without cross-merge).
  - **Measured on hard set:** no benefit (FS stays 8; radius ≥40 adds 1 merge). **Root cause:** the
    residual 8 "false splits" are not bridgeable gaps at all — their two parts are **52–810 slices
    apart with zero z-overlap** (e.g. GT 186 at z=551–591 and z=1131–1260). These are GT objects made
    of z-disconnected components (reused IDs / biologically separate), which a slice-adjacency
    stitcher correctly keeps apart. Near-isotropic FIB-SEM benchmarks simply contain no NN-addressable
    gaps; the feature's value is for genuinely anisotropic / dropout-heavy data (proven synthetically).
    Left **off by default** — zero risk to existing behaviour.
- **Phase D (streaming)** — deferred per trigger condition.
- **Disconnected 2D labels (`splitDisconnected2D`) — found and fixed 2026-08-19.** Reported as
  "stitching merges most mitochondria into one object" on a real 1078×1380×101 salivary-gland
  stack. Root cause: `localCompact` keyed a node on the per-slice **index value**, so a 2D index
  covering several separate blobs welded all of their 3D chains together, unconditionally (the pair
  never reaches the IoU/IoA test). The welds chain transitively, so ~24 % of blobs sharing an index
  (7385 indices over 9746 blobs) collapsed 76.9 % of all labelled voxels into a single object.
  Fix: a node is now one connected component of an index. Same stack, default settings:
  354 objects / largest 76.9 % → **1481 objects / largest 4.6 %**, at +1.8 s (bbox-cropped
  `bwconncomp` per label). New `options.splitDisconnected2D` (default `true`) restores the old
  semantics when `false`; surfaced as a checkbox in both `MibModel.stitchModelInstances` and
  `MibDeep.mergeInstancesTo3D`. Tests: `sharedIndexDoesNotCascadeIntoOneObject`,
  `splitDisconnected2DOffKeepsOneLabelTogether`.
  - **Caveat:** the Phase C benchmark numbers recorded above predate this default and were measured
    with index-keyed nodes. The MitoNet benchmark data is no longer on this machine
    (`c:\MATLAB\Data\SOLOv2_Implementation\MitoNet_benchmark` is gone), so the Integration cases
    self-skipped and the baselines were not re-measured. Re-run them before citing those tables.
  - **Upstream follow-up (not done):** the shared indices are themselves wrong 2D instances. Worth
    checking whether they come from the SOLOv2 mask head firing at several locations (raise the
    prediction threshold) or from `deepmib.segmentImageInstancesIoUMerge` fusing detections across
    tile seams. Splitting at stitch time contains the damage but does not recover the correct 2D
    instances.
- **`minObjectSlices` noise filter — added 2026-08-19.** Follow-up from the same session: with the
  cascade fixed, the remaining spurious objects are 2D false positives that are *large in-plane*
  but present on one or two slices, which `minObjectVoxels` structurally cannot reach. New
  `options.minObjectSlices` removes objects occupying N or fewer slices (0 = keep all, 1 = drop
  single-slice); counts occupied slices, not first-to-last span, so `zLookback` bridges do not
  inflate it. Same stack: 1481 → 460 objects at N=1 while keeping 99.0 % of labelled voxels.
  Justification for it being a separate lever: single-slice objects had median 4 voxels but max
  2415, and genuine multi-slice objects went down to 16 voxels, so `minObjectVoxels = 2415` would
  have deleted 180 real objects. Surfaced in both dialogs; `stats.objectSliceCounts` added (empty
  unless the filter ran). Tests: `minObjectSlicesRemovesShallowObjects`,
  `minObjectSlicesCountsOccupiedSlicesNotSpan`.
- **`absOverlapPixels` link criterion — added 2026-08-19.** Reported as two objects staying apart
  despite a clear Z overlap (buffer-4 objects 105 and 136 at z27/28). Measured cause: IoU and IoA
  are both normalised by object area, which double-penalises a size-mismatched pair. 3795 px vs
  1689 px sharing **716 px** scores IoU 0.150 / IoA 0.424, under both defaults, so the pair is never
  linked. New `options.absOverlapPixels` (default `0` = off) links a pair on raw intersection alone
  - a *sufficient* condition, the mirror of `minOverlapPixels`' *necessary* guard; `maxCentroidShift`
  still vetoes. Sweep on the stack (460-object baseline): 300 → 458, 500-716 → 459, 900+ → no
  change; largest object unmoved at 4.7 % throughout, so no cascade risk. Value is in in-plane
  pixels and dataset-specific - no defensible default. Tests:
  `absOverlapPixelsLinksLargeAgainstSmall`, `absOverlapPixelsStillObeysCentroidGate`.
  - **Unresolved:** whether 105 and 136 *should* merge is a data question, not an algorithm one.
    They coexist as separate objects across z26-38 (13 slices, each 1500-3900 px) and touch across
    Z exactly once. That is equally consistent with one bent mitochondrion cut into two profiles and
    with two adjacent mitochondria. Left to the user's reading of the image.
- Suite after all three changes: **19/19 Unit green**.
- **`absorbFragmentVoxels` - added 2026-08-20.** Reported as "why was object 1299 at x=1072,y=600,
  z=90 not combined with the larger object 537 that surrounds it". Traced on the live buffers: the
  pixel is a **2-px island of 2D index 43** stranded inside index 68, 21 px from index 43's own
  492-px body. `splitDisconnected2D` correctly makes it its own node; it cannot merge in-plane (the
  stitcher only ever links across Z); and its one z-partner overlaps it by 2 px, under
  `minOverlapPixels = 5`, so it is rejected before IoU/IoA are consulted - its IoA would be 1.00.
  Result: a 2-voxel hole in an otherwise solid object. **545 of 1481 objects (37 %) on that stack
  are under 5 voxels** and structurally unlinkable, for 0.0175 % of the labelled voxels: 78 fully
  enclosed by one object, 304 on an object's rim, 1 touching several, 162 free-floating.
  - **Relaxing the guard was tried and rejected on measurement.** `minOverlapPixels = 1` (1064
    objects) and a prototype "full containment bypasses the guard" (1086) both absorb the dust *and*
    fuse the same four pairs of large objects. Traced mechanism: a 2-voxel speck on z=10 lies over
    object A (8503 vox, z=1..9) and under object B (66315 vox, z=1..32), so linking it to both welds
    them. A speck is a bad node to route a chain through - the `splitDisconnected2D` cascade again,
    in miniature.
  - **Built instead as a voxel post-pass** (`localAbsorbFragments`, runs after union-find, before the
    size filters): each (fragment, slice) group goes to the majority label among its 8-neighbours on
    that slice, counting only non-fragment objects so absorption cannot chain. No union happens, so
    no weld is possible. A fragment with no qualifying neighbour is left for `minObjectVoxels` /
    `minObjectSlices`. New `stats.numAbsorbedFragments` / `.numAbsorbedVoxels`.
  - **Measured on the same stack:** `=2` 1180 objects / 301 absorbed, `=4` 1098 / 383, `=5` 1094 /
    387, `=10` 1085 / 396; largest object unmoved at 4.62 % throughout, voxel support
    bit-identical, ~0.3 s. **Zero** groups fuse two objects of >= 5 voxels (vs 4 for
    `minOverlapPixels = 1`). `absorbFragmentVoxels` + `minObjectSlices = 1` gives the same 460
    objects as `minObjectSlices = 1` alone while keeping **~800 more voxels** - holes filled, not
    punched out.
  - **Default `5`, set 2026-08-20, deliberately equal to `minOverlapPixels`** - an object below
    that size cannot produce a large enough intersection to be linked on any slice pair, so the
    default reaches exactly the objects the linker structurally cannot and nothing else. The only
    cleanup parameter that is on by default, because unlike the two delete thresholds it removes
    nothing: it moves voxels between objects. Three unit tests now pass
    `absorbFragmentVoxels = 0` explicitly to assert the un-absorbed baseline.
  - Surfaced in `utils.dlgs.stitchInstancesSettingsDlg` (so both callers get it) and as
    `BatchOpt.AbsorbFragmentVoxels` in `MibModel.stitchModelInstances`; `MibDeep.mergeInstancesTo3D`
    needed no edit, which is the dedup paying off. Tests:
    `absorbFragmentVoxelsFillsEnclosedSpeck`, `absorbFragmentVoxelsDoesNotJoinObjectsAcrossZ`
    (asserts the `minOverlapPixels = 1` weld *and* that absorption avoids it),
    `absorbFragmentVoxelsWillNotAbsorbIntoAnotherFragment`. **22/22 Unit green.**
  - **Upstream, still open:** the 2-px island is a wrong 2D instance. Same root as the
    shared-index note above - worth checking the SOLOv2 prediction threshold and
    `deepmib.segmentImageInstancesIoUMerge`'s tile-seam fusion. Stitch-time absorption contains the
    damage; it does not recover correct 2D instances.
- **Score-guided gap bridging — proposed 2026-08-19, not built.** Idea: when a strong overlap spans
  a one-slice gap, consult prediction scores on the skipped slice to tell a detection dropout from a
  genuine object end. A **dense score map is the wrong tool** - not because of size (one uint8
  channel suffices; identity lives in the `.model`, so touching objects need no distinct indices)
  but because a map painted from accepted detections is **zero on the gap slice by construction**,
  and SOLOv2 exposes no per-pixel objectness to fall back on. The signal lives in **sub-threshold
  detections** instead: predict at a low recall threshold, keep the weak ones as *tentative* objects
  in a separate layer, and link `A(z)`/`B(z+2)` only when a tentative instance on `z+1` overlaps
  both - hysteresis at instance level, decided on geometry with no image access at stitch time.
  Gated on one measurement: for the pairs `zLookback = 2` already bridges, how many have a
  0.3-threshold detection on the skipped slice overlapping both. Phase C′ and the 52-810-slice
  separations of the residual false splits are evidence that gaps may not be the real failure mode
  here. Full write-up, including the per-object score export it depends on:
  [`potential_improvements.md`](potential_improvements.md#3-instance-scores-per-object-export-and-score-guided-gap-bridging).
  Note also that scores are already computed and discarded in both stitching modes
  (`segmentBlockedImageInstances.m:50`, `segmentImageInstancesIoUMerge.m:182`), and that the
  `P_ScoreFiles` dropdown stays enabled for `2D Instance` while being ignored by
  `startPredictionInstances` - a separate UI bug.
- **Settings dialog deduplicated — 2026-08-19.** Adding those three parameters meant editing the
  same 12-field dialog in `MibModel.stitchModelInstances` and `MibDeep.mergeInstancesTo3D` and
  renumbering `answer{n}` in both, three times, with nothing to catch a mismatch. Extracted to
  `utils.dlgs.stitchInstancesSettingsDlg` (returns a ready `stitchOptions` plus a `values` struct of
  raw widget values); the callers' only genuine difference, how Z anisotropy is obtained, is a
  `dlgOptions.anisotropyMode` of `'checkbox'` (MibModel, derives the ratio from `pixSize`) or
  `'ratio'` (MibDeep, raw prediction images have no pixel size). Everything else - input, output,
  undo, batch support, guards - stays in the callers. `MibModel` still rebuilds its options from
  `BatchOpt`, so the batch path is untouched. Details in
  [`stitchInstances2Dto3D.md`](stitchInstances2Dto3D.md#where-the-settings-dialog-lives).
