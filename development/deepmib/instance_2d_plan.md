# DeepMIB — Finish 2D Instance Segmentation (SOLOv2)

> **Step 0 (on approval):** copy this file to `development/deepmib/instance_2d_plan.md`
> (repo-tracked location the user requested; plan-mode restrictions prevent creating it now).

## Context

MIB3's DeepMIB tool (`mib/+controllers/@MibDeep/`) is gaining a 5th workflow — **2D Instance
segmentation** via MathWorks **SOLOv2** (`solov2` / `trainSOLOV2` / `segmentObjects`,
following the R2026a "Perform Instance Segmentation Using SOLOv2" example). The UI flow is:
`selectWorkflow('2D Instance')` → Preprocess tab (`PreprocessButton`) converts MIB models into
SOLOv2 annotation MAT files → Train tab → Predict tab. Settings persist via `.mibCfg`
(`saveConfig`/`loadConfig`). A ready test project exists at
`d:\CNN\SOLOv2_Implementation\DeepMIB\solov2-RN18.mibCfg`.

The scaffolding is ~50% done but **non-functional end to end**: a hard blocker stops all
instance actions, preprocessing has bugs, training omits augmentation and has undefined
variables, and prediction/evaluation are entirely missing. This plan audits and completes the
preprocess → train → predict → evaluate → config chain.

### Verified data contract (confirmed against the test project)
- Training models are **uint16 label maps, one unique integer index per instance**, bg = 0
  (test file `1_Train/Labels/00001.model`: 720×1280, values 0–8). `regionprops(labelMatrix)`
  correctly yields one region per index (8), whereas `bwconncomp(M>0)` merges touching objects
  (7) — so unique-index labelling is the intended encoding. Single class `"object"`.
- **SOLOv2 datastore contract** (per observation): `1×4` cell `{image HxWx3 uint8,
  boxes Mx4 [x y w h], labels Mx1 categorical, masks HxWxM logical}`.
  `deepmib.matReadInstanceLabels` already returns exactly this (image path reconstructed from
  the stored `imageFilename` + Train/Validation folder). So `trainSOLOV2(labelsDS, net, opts)`
  passing the label datastore alone is correct — it yields all four elements.
- **API:** `net = solov2("light-resnet18-coco"|"resnet50-coco","object",InputSize=[H W 3])`;
  `net = trainSOLOV2(trainDS, net, options, 'FreezeSubNetwork','backbone')`;
  `[masks,labels,scores] = segmentObjects(net, ds, Threshold=..., MinSize=...)` →
  masks `HxWxN` logical; `evaluateInstanceSegmentation(resultsDS, gtDS, 0.5)` for metrics.

## Decisions (confirmed with user)
- **Augmentation:** full — geometric (reflections, 90°/arbitrary rotation, scale, shear)
  applied to image+masks together, **boxes recomputed from warped masks**; plus intensity/color
  jitter on the image only. Reuse `obj.AugOpt2D` / `obj.Aug2DFuncNames` / probabilities.
- **Validation:** attempt to enable `ValidationData` in `trainSOLOV2` on R2026a; fall back to
  disabled with a warning if it errors.

## Current-state summary (audit result)

| File | State |
|------|-------|
| `start.m:13-18` | **BLOCKER** — unconditional "Coming soon…" dialog + `return` for `2D Instance`. Also PredictButton has no instance branch. |
| `processImagesForInstanceSegmentation.m` | Training path implemented but buggy; prediction path is a stub. |
| `startPreprocessing.m:39-50` | Split logic routes `LabelsInstances` correctly (`splitForInstanceSegmentation` set but unused — harmless). OK. |
| `startTrainingInstances.m` | Datastores + `solov2()` + `trainSOLOV2()` present; **augmentation fully commented out**; `classNames`/`classColors` **undefined** at save/checkpoint; checkpoint-resume `error()` stub; validation force-disabled. |
| `preprareTrainingOptionsInstances.m` | Functional. Custom-progress `OutputFcn` + end-of-run `info.*Accuracy` fields need verifying against `trainSOLOV2` output. |
| `deepmib.matReadInstanceLabels` / `saveInstanceLabelsParFor` | Correct 1×4 contract; save stores `imageFilename`. OK. |
| `createNetwork.m`, `checkNetwork.m` | No `2D Instance` case → "Check network" preview would fail. |
| `startPrediction2D.m` / `startPredictionBlockedImage.m` / `previewModels.m` / `evaluateSegmentation.m` | **No instance support.** |

## Implementation phases

### Phase 1 — Unblock + fix preprocessing bugs  *(model: Sonnet — mechanical)*
- `start.m`: **delete** the `2D Instance` blocker (lines 13-18). In the `PredictButton` case,
  route `2D Instance` to the new `obj.startPredictionInstances()` (Phase 4) for both prediction
  modes (bypass the `Blocked-image`/`Legacy` branch for instances).
- `processImagesForInstanceSegmentation.m`:
  - Line 202: replace `reshape([stats.BoundingBox], [4, 8])'` with `[4, numObjects]`
    (`numObjects = numel(stats)`), computed *before* the reshape.
  - Guard against non-contiguous / empty regions: after `regionprops`, drop entries with empty
    `PixelIdxList` (remap so boxes/masks/names stay aligned); handle `numObjects == 0`
    (skip file or write empty annotation with a warning).
  - Line 192 (single-model path): `imgFilelist.Files{imgId}` → `imgFilelist(imgId).name`
    (it's a `dir` struct, not a datastore).
  - Implement the **prediction** branch (currently the `not yet implemented` stub, lines 33-41):
    for prediction only images are needed, so just validate the `Images` folder exists and
    return cleanly (no label MATs). SOLOv2 `segmentObjects` reads raw images directly.

### Phase 2 — Instance augmentation  *(model: Opus — new algorithm, box/mask sync)*
- New `mib/+deepmib/augmentInstanceData2D.m` (transform fcn, `IncludeInfo` style) mirroring
  `augmentAndCrop2dPatchMultiGPU.m` but operating on the `{image,boxes,labels,masks}` cell:
  - Honour `AugOpt2D.Fraction` gate and each augmentation's `Enable`+probability via
    `Aug2DFuncNames`/`Aug2DFuncProbability` (built by `obj.setAugFuncHandles('2D')`).
  - **Geometric** (`randomAffine2d`/`rot90`/`fliplr`/`flipud`): apply the *same* transform to
    `image` (`imwarp`, cubic) and every mask slice (`imwarp`, nearest), then **recompute boxes
    from the warped masks** (reuse the example's `getBoxFromMask` logic → add
    `mib/+deepmib/getBoxFromMask.m`); drop instances whose mask vanishes after warp.
  - **Intensity/color** (`jitterColorHSV`, `imnoise`, `imgaussfilt`, brightness/contrast):
    image only — masks/boxes untouched.
  - Rotation90 square-shape guard already exists in `startTrainingInstances.m:53-65`.
- `startTrainingInstances.m`: replace the commented block (lines ~322-451) with, when
  `T_augmentation` is true: `labelsDS = transform(labelsDS, @(d)deepmib.augmentInstanceData2D(d, augOpt))`
  (and same for `valLabelsDS` if validation is on — validation gets identity/no aug).

### Phase 3 — Fix training core  *(model: Opus — correctness-critical)*
- `startTrainingInstances.m`:
  - Define `classNames = categorical("object")` (or from a single-class list) and
    `classColors = obj.modelMaterialColors(1,:)` **before** the `save(...)` (line ~624) and
    before the checkpoint class-mismatch block (lines ~513-527); remove/guard the semantic-only
    checkpoint code that assumes `lgraph.Layers`/`Classes` (not applicable to `solov2`).
  - Implement checkpoint **resume** (replace `error()` at line 304): load the `net` from the
    checkpoint `.mat` and pass to `trainSOLOV2` (SOLOv2 checkpoints save the detector object;
    verify field name).
  - **Validation:** remove the forced `valLabelsDS = []` (lines 462-476); pass `valLabelsDS`
    through to `preprareTrainingOptionsInstances`. Wrap the `trainSOLOV2` call so a
    validation-related error retries once with validation disabled + warning.
  - Keep `inputPatchSize = [H W 3]` (matReadInstanceLabels converts grayscale→RGB, so the net is
    always 3-channel) — leave as-is but add a comment.
- `preprareTrainingOptionsInstances.m`: verify `trainSOLOV2` calls the `OutputFcn`
  (`deepmib.customTrainingProgressDisplay`) with a compatible `info`; if `info` lacks
  `TrainingAccuracy`/`Validation*`/`OutputNetworkIteration`, guard those reads in
  `startTrainingInstances.m` end-of-run + SendReports blocks (`isfield` checks).

### Phase 4 — Prediction + evaluation  *(model: Opus — new integration)*
- New `mib/+controllers/@MibDeep/startPredictionInstances.m` (+ signature line in `MibDeep.m`):
  - Build an `imageDatastore`/`fileDatastore` over `OriginalPredictionImagesDir\Images`
    (reuse `deepmib.storeLoadImages`; convert grayscale→RGB to match the 3-channel net).
  - Load `net` from `BatchOpt.NetworkFilename`; call `segmentObjects(net, ds, Threshold=…,
    MinSize=…, ExecutionEnvironment=…)` per image.
  - Convert `masks HxWxN` → a MIB **uint16 instance label map** (index per instance, matching
    the input encoding) and save under `ResultingImagesDir\PredictionModels` as `.model`
    (reuse the model-save path used by semantic prediction / `deepmib.storeLoadModel` sibling);
    optionally write score info. Add a progress dialog + user-score bump like other predictions.
- `checkNetwork.m` / `createNetwork.m`: add a `2D Instance` case so "Check network" builds a
  `solov2` preview instead of failing (low priority; can stub with an informative dialog first).
- Optional: instance branch in `evaluateSegmentation.m` using
  `evaluateInstanceSegmentation` (GT from `GroundTruthLabelsInstances`). Mark optional.

### Phase 5 — Config round-trip + docs  *(model: Sonnet — mechanical)*
- Verify `saveConfig`/`loadConfig` + `correctBatchOpt` round-trip the `2D Instance` workflow
  (Workflow/Architecture/T_EncoderNetwork switch path in `loadConfig.m:81-104`). Load the test
  `.mibCfg` and confirm widgets populate without error.
- Update API docs (`docs_api/`) for the new/changed public methods and the user docs
  (`docs/`) for the 2D Instance workflow, per the repo doc rules.

## Verification (end-to-end, via MATLAB MCP with the `mib` handle)
1. **Preprocess:** load `solov2-RN18.mibCfg`; run Preprocess (Split for training/validation) on
   `1_Train`; assert `TrainLabels\*.mat` each contain `instanceBoxes (Mx4)`, `instanceNames`,
   `instanceMasks (HxWxM)` with `M == numel(unique(model))-1` and no `8`-hardcoded truncation.
   Test a model with a non-contiguous index to confirm empty-region filtering.
2. **Datastore + aug:** `preview(labelsDS)` returns a valid 1×4 cell; run
   `augmentInstanceData2D` on one observation and assert boxes still match `regionprops` of the
   warped masks and mask count is preserved (minus vanished instances).
3. **Train:** short run (MaxEpochs=1–2, MiniBatchSize small) with validation on — confirm
   `trainSOLOV2` completes, `.mibDeep` saves with `classNames`/`classColors`, and the custom
   progress window updates without `info.*` field errors. Confirm validation-fallback path.
4. **Predict:** run `startPredictionInstances` on `2_Predict\Images`; open a result `.model` in
   MIB and confirm distinct instance indices; sanity-check with `evaluateInstanceSegmentation`.
5. **Config:** save then reload `.mibCfg`; confirm workflow/architecture/encoder restore.
6. Run `buildtool check` on changed files; run `python development/graphify/run_all.py` after
   code changes to refresh the graph.

## Key files
- Edit: `start.m`, `processImagesForInstanceSegmentation.m`, `startTrainingInstances.m`,
  `preprareTrainingOptionsInstances.m`, `checkNetwork.m`/`createNetwork.m`, `MibDeep.m` (signatures).
- New: `mib/+controllers/@MibDeep/startPredictionInstances.m`,
  `mib/+deepmib/augmentInstanceData2D.m`, `mib/+deepmib/getBoxFromMask.m`.
- Reuse: `deepmib.matReadInstanceLabels`, `deepmib.saveInstanceLabelsParFor`,
  `deepmib.storeLoadImages`, `deepmib.storeLoadModel`, `obj.setAugFuncHandles`, `obj.AugOpt2D`.

---

> **Status:** Phases 1–6 are implemented and verified end-to-end on the test project (GPU): patch
> cropping (`deepmib.readInstancePatch`), `Patches per image` replication, `trainSOLOV2` on patch
> datastore, and tiled centroid-in-core prediction (`deepmib.segmentBlockedImageInstances` via
> `blockedImage/apply`) all confirmed working. The 3D roadmap below is future.
>
> Phase 6 implementation notes: preprocessing now stores a lightweight 2D `instanceLabelMap`
> (uint16) per image instead of full `H×W×N` mask stacks; training crops native-resolution patches
> from it on-the-fly; prediction reuses the blocked-image machinery with `BorderSize` = overlap and
> a global unique-ID counter (`mibInstanceIdCounter`), relabelled to contiguous IDs after gather.

## Phase 6 — Patch-based training & tiled prediction (large / whole-slide images)  *(model: Opus — new datastore + tiling logic)*

### Motivation
In microscopy, source rasters can be huge (slide-scanner / whole-slide images) with many
objects. The initial implementation feeds the **whole image** to SOLOv2, which resizes it to the
network input (e.g. 800×800) — this destroys resolution, distorts aspect ratio, and makes small
objects undetectable. Instance segmentation must operate on **native-resolution patches**, both
for training and prediction.

### Decisions (confirmed with user)
- **Training patch source:** crop the label **model on-the-fly** (not from pre-generated
  full-image masks — full `H×W×N` mask stacks are memory-prohibitive for whole slides).
- **Training patch sampling:** a **mix** — ~90 % object-seeded patches + ~10 % uniform-random
  patches. Object-seeded patches must use **coordinate jitter**: pick a random object, then place
  the patch window at a random offset so the object appears *anywhere* in the patch, never forced
  to the center (centering would teach the network the false prior "an object is always at the
  patch center").
- **Prediction stitching:** **centroid-in-core**, reusing the existing `blockedImage/apply`
  machinery (starter approach — see limitations below).

### Training design
- Build a combined datastore: `imageDatastore(TrainImages)` + `fileDatastore(TrainLabels *.model)`,
  `combine`d and `transform`ed. Preprocessing for training then reduces to **splitting** the
  image+model pairs into `Train*/Validation*` — the full-image `instanceMasks.mat` generation is
  no longer needed for patch training (keep it only if the whole-image path is retained).
- Per read: choose a patch window (90/10 object-seeded-with-jitter / uniform), crop the **image**
  and the **label model** at native resolution, then `regionprops` on the *cropped* label →
  `{boxes, names, masks}` for that patch. Border objects are naturally truncated with recomputed
  boxes; drop remnants below a minimum pixel area.
- Re-enable `Patches per image`: replicate the file list ×N so each image yields N different
  random patches per epoch; include N in the `maxNoIter`/`iterPerEpoch` calculation
  (currently `T_PatchesPerImage` is inert for instances — see the "Patches per image" note).
- `deepmib.augmentInstanceData2D` runs after the crop, unchanged.
- "Tons of objects" is handled by construction: per-patch object count is bounded by patch area;
  seeding just picks a random index from the label map's unique values (cheap for thousands).

### Prediction design (centroid-in-core)
- New `deepmib.segmentBlockedImageInstances(block, blockInfo, net, ...)` per-block function, routed
  through `blockedImage/apply` like `processBlocksBlockedImage`, with **`BorderSize` = overlap**
  (from `P_OverlappingTiles` / `P_OverlappingTilesPercentage`):
  - Run `segmentObjects` on the bordered tile → local instance masks.
  - Keep only instances whose **centroid lies in the tile core** (not the border); assign each a
    **globally unique ID** (offset by the tile's linear index). `apply` reassembles the cores.
  - Because the border supplies context, each object is fully seen by exactly the tile owning its
    centroid → no duplicates and no seam-splitting. After `gather`, relabel IDs to a contiguous
    `1..N` uint16/uint32 MIB model.
- Whole-image (resize) path retained only for images ≤ input patch size.

### Limitations & possible future improvements
- **Centroid-in-core requires `overlap ≥ largest object radius`.** Objects larger than the overlap
  band are truncated (seen partially by every tile, so no tile fully contains them). Document this;
  expose/validate the overlap setting accordingly.
- **Two distinct objects sharing a centroid tile-core edge case:** extremely close centroids near a
  core boundary could, in rare cases, be mis-assigned; negligible when overlap is adequate.
- **IoU-merge stitching — IMPLEMENTED:** `deepmib.segmentImageInstancesIoUMerge` keeps all
  per-tile detections (stored memory-light as bbox + cropped mask) and links detections of
  neighbouring tiles whose masks agree **inside the shared overlap band** (in-band IoU ≥ 0.5 or
  IoA ≥ 0.8, min 5 px intersection), resolved globally via union-find; merged groups are painted
  low-score-first so stronger groups win pixel conflicts. Selected at prediction time via the new
  `BatchOpt.P_OverlapInstancesMode` dropdown (`'Centroid in core'` (default) / `'IoU merge'`);
  when IoU merge is chosen with `P_OverlappingTiles` off, a 5% overlap is forced with a warning.
  Validated with a synthetic fake-`segmentFcn` test (injectable `options.segmentFcn` hook): exact
  6/6 GT partition reconstruction incl. an object far larger than the overlap band, plus
  zero-border and empty-image edge cases. Old configs load fine (missing field falls back to the
  default via `updateBatchOptCombineFields_Shared`). GUI: "Instance segmentation" subpanel on the
  Predict tab with the "Overlap mode" dropdown (Tag `P_OverlapInstancesMode`) and a Settings
  button (Tag `P_OverlapInstancesSettings` → `updateOverlapInstancesSettings`); both enabled only
  for the `2D Instance` workflow (`selectArchitecture.m`). Tunable settings live in
  `obj.OverlapInstancesOpt` (`.DetectionThreshold` — `segmentObjects` confidence, both modes;
  `.MergeIoU` / `.MergeIoA` — in-band merge thresholds, IoU-merge mode), persisted via
  `preferences.Deep.OverlapInstancesOpt` (`generatePreferences`/`closeWindow`), the `.mibCfg`
  (`saveConfig`/`loadConfig`) and the trained `.mibDeep` (`startTrainingInstances`).
- **Future improvement — object-density-aware sampling:** adapt the 90/10 object/uniform ratio to
  local object density so sparse regions still get background exposure.

## Future roadmap — 3D instance segmentation (to be planned)

> **Step 2 prototype done:** the cross-slice merging algorithm is implemented and validated as a
> standalone utility — `mib/+utils/stitchInstances2Dto3D.m`. See
> [`stitchInstances2Dto3D.md`](stitchInstances2Dto3D.md) for the algorithm, a critique of the
> empanada/MitoNet source spec, validation on the easy/hard test sets (perfect 33/33 reconstruction
> on the easy 3D ground truth), and the MIB/DeepMIB integration path. It is **not yet wired into
> DeepMIB** (pure `[H×W×Z]` label volume in/out).

The **ultimate goal** is to extend 2D instance results to **3D objects**. Planned approach:

1. Run 2D instance segmentation slice-by-slice over the volume (reusing the patch/tiled 2D pipeline
   above), producing a per-slice instance label map.
2. Run a dedicated **3D merging algorithm** (implemented — see `stitchInstances2Dto3D.md`) that
   links 2D instances across adjacent slices into consistent 3D object IDs via IoU/IoA of masks
   between slice `z` and `z+1` (assign the same 3D ID when overlap exceeds a threshold), resolved
   globally through an undirected overlap graph + union-find.
3. The merging must handle real-world topology: objects appearing/disappearing across slices,
   one-to-many **splits** and many-to-one **merges** between consecutive slices, and an IoU/overlap
   threshold (plus optional size/centroid constraints) to avoid over- or under-merging.
4. Open design questions for that phase: greedy slice-pairwise linking vs. global optimization
   (e.g. tracking-by-assignment), anisotropic Z handling, and memory strategy for whole-slide 3D
   volumes (blocked/streaming). The IoU-merge stitching from Phase 6's future improvements is a
   natural building block to share here.
