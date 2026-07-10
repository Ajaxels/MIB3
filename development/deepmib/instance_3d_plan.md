# 3D Instance Stitching — Improvement Plan (`utils.stitchInstances2Dto3D`)

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
- **DeepMIB auto-feed** (2D prediction stack → stitcher) is the only integration still pending.
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
