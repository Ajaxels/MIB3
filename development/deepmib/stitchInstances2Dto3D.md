# 2D→3D Instance Stitching — `utils.stitchInstances2Dto3D`

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

**Options:** `method`, `iouThreshold` (0.25), `ioaThreshold` (0.50), `minOverlapPixels` (5),
`zLookback` (1 = adjacent only), `minObjectVoxels` (0), `bidirectional` (true, hungarian only),
`showWaitbar`, `verbose`. Returns `[labelVol, stats]` where `stats` carries
`numInput2DObjects`, `numOutput3DObjects`, `objectVoxelCounts`, `method`, `options`.

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
- Anisotropic Z (large slice spacing) — may need IoU thresholds relaxed or `zLookback` tuned.
- Memory for whole-slide 3D volumes — current version materialises the output volume in RAM;
  blocked/streaming variant is future work (union-find core is already streaming-friendly).
