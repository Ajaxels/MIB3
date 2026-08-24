# 2D→3D Instance Stitching — `utils.stitchInstances2Dto3D`

> Deferred DeepMIB ideas (checkpoint weight averaging, two-phase freeze/unfreeze training) are
> collected in [`potential_improvements.md`](potential_improvements.md).

First building block of the **3D instance segmentation** roadmap in
[`instance_2d_plan.md`](instance_2d_plan.md) ("Future roadmap — 3D instance segmentation").
Implements step 2 of that roadmap: linking independently-segmented 2D instance masks across
adjacent slices into consistent 3D object IDs.

- **Function:** `mib/+utils/stitchInstances2Dto3D.m` (standalone utility, **not yet wired into
  MIB/DeepMIB** — pure `[H×W×Z]` label-volume in, relabelled `[H×W×Z]` volume out).
- **Source spec:** `d:\CNN\SOLOv2_Implementation\MitoNet_benchmark\examples\2Dto3D_stitching_algorithm_spec.md`
  (empanada / MitoNet — Conrad & Narayan, 2023).
- **Test data:** `…\MitoNet_benchmark\examples\{easy,hard}` — each has a 3D TIFF plus a
  `slices_2d_objects\` folder of per-slice 2D label TIFFs simulating 2D instance output.

## What it does

Takes a stack of per-slice 2D instance label maps whose IDs are **not** consistent across slices
and returns a single 3D instance volume with one ID per object through the whole stack. The input
ID *values* are ignored — every slice is internally relabelled to globally-unique nodes, so the
routine is correct on genuinely independent per-slice segmentations.

Two strategies:

| method | how | when |
|--------|-----|------|
| `'graph'` *(default)* | undirected overlap graph across all slices (edge when a pair passes IoU **or** IoA) → connected components via union-find | splits/merges handled natively; no reverse pass needed |
| `'hungarian'` | empanada-style: 1-to-1 IoU matching per pair (`matchpairs`) + IoA merge-in of unmatched, forward **and** reverse passes | faithful reproduction of the paper for comparison |

**Options:** `method`, `splitDisconnected2D` (true), `iouThreshold` (0.25), `ioaThreshold` (0.50),
`minOverlapPixels` (5), `absOverlapPixels` (0), `zLookback` (1 = adjacent only), `minObjectVoxels`
(0), `minObjectSlices` (0), `absorbFragmentVoxels` (5), `bidirectional` (true, hungarian only),
`showWaitbar`, `verbose`. Returns `[labelVol, stats]` where `stats` carries `numInput2DObjects`,
`numOutput3DObjects`, `objectVoxelCounts`, `objectSliceCounts`, `numAbsorbedFragments`,
`numAbsorbedVoxels`, `method`, `options`.

### `absOverlapPixels` — the ratio tests are blind to size mismatch

IoU and IoA are both normalised by object area, which double-penalises a pair whose two
cross-sections differ a lot in size. A real miss on the mitochondria stack: 3795 px on z=27 against
1689 px on z=28, sharing **716 px** — IoU 0.150, IoA 0.424, under both defaults, so no link.
`absOverlapPixels` adds a *sufficient* condition on the raw intersection (`inter >= N` links the
pair regardless of the ratios). It is the mirror image of `minOverlapPixels`, which is a *necessary*
guard; the `maxCentroidShift` gate still applies to both.

Sweep on the same stack (`splitDisconnected2D` on, `minObjectSlices=1`, 460 objects at baseline):

| `absOverlapPixels` | objects | largest object | the 716 px pair joined |
|---|---|---|---|
| 0 (off) | 460 | 4.7 % | no |
| 300 | 458 | 4.7 % | yes |
| 500 | 459 | 4.7 % | yes |
| 716 | 459 | 4.7 % | yes |
| 900+ | 460 | 4.7 % | no |

The effect is local, not a cascade — the largest object is unmoved. That is expected: unlike a
shared 2D index, an absolute-overlap link still has to be earned pair by pair. The value is in
in-plane pixels and so is dataset-specific; there is no defensible default, hence `0` = off.

### `minObjectSlices` — depth is a better noise discriminator than area

`minObjectVoxels` assumes noise is *small*. It often is not: a 2D false positive can be a large,
confident, well-formed blob that simply does not exist on the neighbouring slices.
`minObjectSlices` removes objects occupying **N or fewer slices** (`0` = keep all, `1` = drop
single-slice objects). It counts occupied slices rather than the first-to-last span, so an object
bridged by `zLookback` across a dropout is judged on the slices it is actually on.

Measured on the same 1078×1380×101 mitochondria stack (`splitDisconnected2D` on, no other cleanup):

| `minObjectSlices` | objects | labelled voxels kept |
|---|---|---|
| 0 | 1481 | 100 % |
| 1 | 460 | 99.0 % |
| 2 | 360 | 98.2 % |
| 3 | 310 | 97.2 % |
| 5 | 268 | 95.7 % |

The 1021 single-slice objects had a median size of 4 voxels but a **maximum of 2415**, while genuine
multi-slice objects went down to 16 voxels. Setting `minObjectVoxels = 2415` to catch that one blob
would have deleted 180 real objects — the two thresholds are not substitutes.

### `absorbFragmentVoxels` - dust is a voxel problem, not a linking problem

An object smaller than `minOverlapPixels` can never reach the guard, whatever it overlaps: a 2-voxel
speck has at most a 2 px intersection, so the pair is rejected before IoU or IoA is consulted (its
IoA would be 1.00 — full containment). Such specks therefore survive stitching as unlinkable
objects, and because `splitDisconnected2D` correctly splits a stray blob off its index, there are a
lot of them. On the mitochondria stack, **545 of 1481 objects (37 %) are under 5 voxels**, while
accounting for 0.0175 % of the labelled voxels. Classified by their in-plane surroundings:

| where the speck sits | count |
|---|---|
| fully enclosed by one object (a hole punched in it) | 78 |
| touching one object plus background (a rim nibble) | 304 |
| touching several objects | 1 |
| free-floating in background | 162 |

**Relaxing the guard is the wrong fix, and this was measured, not assumed.** Both `minOverlapPixels
= 1` and a prototype "full containment bypasses the guard" rule absorb the dust *and* fuse the same
four pairs of large objects. The mechanism, traced on one of them: a 2-voxel speck on z=10 lies over
object A (8503 voxels, z=1..9) and under object B (66315 voxels, z=1..32), so linking it to both
welds A and B into one 74818-voxel object. It is the `splitDisconnected2D` cascade in miniature - a
speck is a terrible node to route a 3D chain through.

`absorbFragmentVoxels` instead runs **after** the union-find, as a voxel operation: each
(fragment, slice) group is given to the majority label among its 8-neighbours *on that slice*,
counting only objects that are not themselves fragments (so absorption cannot chain). Nothing is
unioned, so nothing can weld. A fragment with no qualifying neighbour keeps its voxels and is left
for `minObjectVoxels` / `minObjectSlices`.

Same stack, `absorbFragmentVoxels` alone:

| value | objects | fragments absorbed | voxels moved | largest object |
|---|---|---|---|---|
| 0 (off) | 1481 | - | - | 4.62 % |
| 2 | 1180 | 301 | 504 | 4.62 % |
| 4 | 1098 | 383 | 801 | 4.62 % |
| **5 (default)** | **1094** | **387** | **821** | 4.62 % |
| 10 | 1085 | 396 | 886 | 4.62 % |

**Default is `5`, deliberately equal to `minOverlapPixels`.** That is not a tuned number: an object
of fewer voxels than `minOverlapPixels` cannot produce a large enough intersection to be linked on
any slice pair, so the default absorbs exactly the objects the linker is structurally unable to
reach and nothing else. It is the only one of the cleanup parameters that is on out of the box,
because unlike the two delete thresholds it cannot remove anything - it moves voxels between
objects. Above `minOverlapPixels` the value becomes a judgement about what counts as noise, which
is why the curve keeps improving slowly but the default stops there.

At `4`, **zero** groups fuse two objects of 5 voxels or more (against 4 such fusions for
`minOverlapPixels = 1`), the voxel support is bit-identical, and the largest object does not move.
Cost is ~0.3 s on that stack. Combined with the recommended cleanup, `absorbFragmentVoxels` +
`minObjectSlices = 1` gives the same 460 objects as `minObjectSlices = 1` alone but keeps ~800 more
voxels - the holes are filled rather than punched out.

### `splitDisconnected2D` — why a node is a blob, not an index

A node is one **connected component** of a per-slice index, not the index itself. 2D instance
predictors routinely give a single index to several spatially separate blobs (a SOLOv2 mask head
firing at more than one location; a tile merge fusing two detections). Keyed on the index alone,
such a label is an unconditional weld between all of its blobs' 3D chains — no threshold can
reject it, because the pairing never enters the IoU/IoA test in the first place. The welds then
chain transitively, and a small fraction of them collapses most of the stack into one object.

Measured on a real 1078×1380×101 salivary-gland mitochondria stack (2D SOLOv2 prediction, 7385
per-slice indices covering 9746 blobs, so ~24 % of blobs shared an index):

| `splitDisconnected2D` | 2D nodes | 3D objects | largest object |
|---|---|---|---|
| `false` (index-keyed, pre-2026-08 behaviour) | 7385 | 354 | **76.9 % of all labelled voxels** |
| `true` (default) | 9746 | 1481 | 4.6 % |

Cost is one `bwconncomp` per label, cropped to its bounding box: +1.8 s on that stack (2.2 s → 4.0 s).

The trade going the other way is small: a genuine instance the network split into two blobs on one
slice becomes two nodes, but they rejoin through their shared neighbour on the adjacent slice
whenever the object really is 3D-connected. `false` is kept for inputs whose indices are trusted.

## Where the settings dialog lives

The utility has two entry points - `MibModel.stitchModelInstances` (active labels layer) and
`MibDeep.mergeInstancesTo3D` (predicted `*.model` files on disk). They differ in everything around
the call (input, output, undo, batch support, guards) but presented the *same* settings dialog
(12 fields at the time, 13 now), duplicated line for line. Adding a parameter meant editing two
prompt lists and renumbering `answer{n}` in both, with nothing to catch a mismatched index.

That dialog is now a single function, `utils.dlgs.stitchInstancesSettingsDlg`, returning both a
ready `stitchOptions` struct and a `values` struct of raw widget values keyed by parameter name.
The one real difference between the callers is handled by `dlgOptions.anisotropyMode`:

| mode | widget | who uses it | `anisotropyZ` |
|---|---|---|---|
| `'checkbox'` | yes/no toggle | `MibModel` - has a dataset | left unset; the caller derives it from `pixSize.z / pixSize.x` |
| `'ratio'` | numeric spinner | `MibDeep` - raw prediction images have no pixel size | set from the entered ratio when > 1 |

`MibModel` uses only the `values` output and rebuilds its options from `BatchOpt`, so the batch path
(which never opens the dialog) goes through exactly the same code as before.

Two conveniences for parameter trials, both added because a run is otherwise unreproducible from the
log and every trial means re-entering a dozen fields:

- **Console echo.** On acceptance the dialog prints one line naming every option it is passing.
  It is built by walking the returned `stitchOptions` struct, not from a hand-written list, so a new
  parameter appears without a second edit. Disabled gates are absent from the line rather than
  printed as zero - that is what actually reaches the utility.
- **Per-session memory.** The dialog itself stays stateless; the callers store the returned `values`
  and hand it back as `defaults` next time. The key is not preseeded in
  `utils.defaults.generateSessionSettings` - the same convention already used for
  `sessionSettings.stitching`, so the defaults live in one place and cannot drift. `MibModel`
  validates a restored value against its own `BatchOpt` limits before applying it (the batch path can
  consume it without the dialog ever running); the shared dialog independently clamps any seeded
  numeric into the widget's range and ignores a field it does not know, since it seeds from its own
  field list rather than from what it is handed.
- **One key, both entry points - fixed 2026-08-24.** The two callers originally stored under
  `sessionSettings.stitchModelInstances` and `.mergeInstancesTo3D`, so a threshold trialled from the
  ribbon was not offered by DeepMIB's *Merge 2D to 3D* and vice versa - reported as "it does not
  respect options stored in sessionSettings". They now share
  `sessionSettings.stitchInstances2Dto3D`. Same dialog, same algorithm, so the settings should
  follow the user rather than the button.
  - **Anisotropy is the one field that cannot be shared,** because the two modes ask different
    questions: `'checkbox'` (MibModel) stores a yes/no under `UseAnisotropy` and derives the ratio
    from `pixSize.z/pixSize.x`; `'ratio'` (MibDeep) stores the raw number under `Anisotropy`, raw
    prediction images having no pixel size. A checkbox cannot be converted into a ratio, so the two
    live side by side under separate names.
  - Consequently both callers write **field by field into whatever is already stored** rather than
    replacing the struct - otherwise a run from one side would silently reset the other side's
    anisotropy answer. The extra field each leaves behind is harmless: `MibModel` reads an explicit
    list of names, and the dialog seeds from its own.
  - Regression cases in `tests/core/StitchModelInstancesTest.m` (MibModel level, batch mode so no
    dialog opens): key name, read-back, explicit-argument precedence, cross-entry-point anisotropy
    survival, and out-of-range rejection. MibDeep's half of the round trip needs a live controller
    and a modal dialog, so it is covered only by the contract those cases pin down.

## Critique of the source spec (and what changed here)

1. **Median-filtering the probability maps (spec Step 4) is out of scope for a label-stitcher** and
   omitted. It operates on the semantic logit volume *before* instance extraction — that
   information is gone once you have discrete label maps. Its correct home is DeepMIB inference,
   not this utility. The label-space substitute for single-slice dropouts is `zLookback`.
2. **Strict 1-to-1 Hungarian is the *cause* of the oversplitting the spec then patches** (Steps 3
   and 5 exist to repair chains a one-to-one assignment structurally cannot represent). Modelling
   the problem as an undirected overlap graph + union-find handles splits/merges in a single pass.
   `'graph'` is therefore the default; `'hungarian'` is kept only as the paper-faithful path.
3. **Reverse pass (spec Step 5) is redundant under the graph formulation** (an undirected graph
   gives the same components either direction) and its "reconcile/merge" step was unspecified.
   Retained behind `bidirectional` for the Hungarian method, where it does matter.
4. **Global ID bookkeeping** (disjoint-set across the whole stack + final compaction to 1..K) was
   unaddressed in the spec; added.
5. **Robustness guards added:** absolute `minOverlapPixels` (spurious 1–2 px links),
   `zLookback` (objects skipping a slice), `minObjectVoxels` (drop noise fragments).
6. **RLE storage (spec) deferred** — full-volume-in-RAM handled 3.3 GB in ~23 s; union-find only
   needs an array over the 2D-object count plus two slices at a time.
7. **Ortho-plane / isotropic consensus (spec optional extension) not attempted here** — it requires
   re-running 2D segmentation on the xz/yz stacks (raw volume + model), unreachable from xy labels
   alone. Belongs in a separate module.

## Validation

Per-slice IDs were randomly scrambled first (to simulate genuinely independent 2D segmentation),
then stitched:

| dataset | dims | 2D objects in | 3D objects out | time | check |
|---------|------|---------------|----------------|------|-------|
| easy | 165×768×1024 | 2707 | 33 | 2.5 s | **median IoU = 1.000 vs 3D ground truth, 33/33 one-to-one** |
| hard | 1260×1081×1200 | 13923 | 206 (125 after `minObjectVoxels=200`) | 23 s | large objects span median 87 slices; 81 removed fragments are single-slice noise |

`easy/lucchi_pp_mito.tif` is a true 3D instance ground truth — the stitcher reconstructs it
perfectly despite scrambled input IDs. `zLookback=2` on hard bridges dropouts (206 → 198).

## Integration path

1. **Done** — pure label-stitching utility, validated above.
2. **Done — MIB ribbon integration.** Wired into **Ribbon → Model → Convert type → Indexed objects
   → "Stitch 2D instances to 3D"** (a separate entry after the connected-component items, since its
   input is a model that is *already* per-slice 2D instances, not a semantic model). Chain:
   - `mib/+views/@MibView/addRibbonModel.m` — new `stitchInstances2Dto3D` `ListItem` in the
     "Indexed objects" submenu.
   - `mib/+controllers/@MibRibbon/MibRibbon.m` + `model_Callbacks.m` — callback wiring + dispatch
     case → `obj.mibModel.stitchModelInstances()`.
   - `mib/+models/@MibModel/stitchModelInstances.m` — BatchOpt wrapper (Method, IoUThreshold,
     IoAThreshold, MinOverlapPixels, ZLookback, MinObjectVoxels, showWaitbar, id), guards
     (virtual/enableSelection/modelExist), `SyncBatch`/`UpdateGuiWidgets`/`ShowImage`
     notifications — mirrors `convertModel.m`. Adds: an interactive `inputUniversalDlg`
     settings dialog (method dropdown + IoU/IoA/overlap/lookback/min-size spinners) shown when
     launched from the ribbon; an **undo backup** (`obj.backup('labels', 1, …)`, skipped in batch
     protocols; verified that Ctrl+Z restores the exact pre-stitch model); and an **indeterminate**
     progress dialog (the graph-building pass has no fine-grained progress to report).
   - `mib/+core/@MibDataset/stitchModelInstances.m` — per-timepoint read (`getData3D('labels',…)`)
     → `utils.stitchInstances2Dto3D` → rebuild `core.MibLabels` at 65535/4294967295 capacity
     (mirrors the indexed-object branch of `convertModel`).

   Verified end-to-end headless (via `buildSyntheticModel`-style harness): a 60-slice easy subset
   with **scrambled** per-slice IDs → 28 coherent 3D instances (median z-extent 54, zero
   single-slice fragments), model preserved as uint16/65535. *Note: the ribbon widget only appears
   after a MIB restart, since the Model tab is built at startup.*
3. **DeepMIB** *(not yet done)* — feed the per-slice instance stack from 2D inference (Phase 6 tiled
   prediction) straight in. If the semantic probability volume is retained there, add optional
   z-median smoothing at *that* stage (the correct home for the spec's Step 4).
4. **Optional later** — ortho-plane consensus as a separate util (raw volume + 3× inference +
   clique fusion).

## Open questions for the wider 3D phase (from `instance_2d_plan.md`)

- Greedy slice-pairwise vs. global tracking-by-assignment — `'graph'` union-find already gives a
  global connected-components solution rather than pure greedy chaining.
- Anisotropic Z (large slice spacing) — **addressed** (see `instance_3d_plan.md` Phase B):
  `options.anisotropyZ` lowers the effective IoU threshold to
  `max(iouThreshold/anisotropyZ, iouFloor)`; `options.maxCentroidShift` gates far-apart links so
  the relaxation cannot over-merge. For continuations that do not overlap at all (large drift /
  brief dropout), `options.centroidLinkRadius` adds mutual-nearest-neighbour gap bridging between
  orphan objects (off by default). All wired from the dataset pixel size via the ribbon dialog's
  "Anisotropic Z" checkbox + "Max centroid shift" / "Centroid link radius" spinners.
- Memory for whole-slide 3D volumes — current version materialises the output volume in RAM;
  blocked/streaming variant is future work (union-find core is already streaming-friendly).
