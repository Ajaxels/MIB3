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
> `blockedImage/apply`) all confirmed working. The 3D section below is also **done** - only the
> deferred streaming phase (Phase D) remains, tracked in `instance_3d_plan.md`.
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
  `BatchOpt.P_OverlapInstancesMode` dropdown (`'IoU merge'` (**current default**, `MibDeep.m:447`)
  / `'Centroid in core'`); when IoU merge is chosen with `P_OverlappingTiles` off, a 5% overlap is
  forced with a warning.
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

## Known upstream limitation — stopping training early (`trainSOLOV2` / `images.dltrain`)

> **MathWorks bug, mitigated but not eliminated.** Report draft + runnable repro:
> [`../notes/mathworks_bugreport_dltrain_stop.md`](../notes/mathworks_bugreport_dltrain_stop.md)
> and [`../notes/dltrainStopRepro.m`](../notes/dltrainStopRepro.m).

### The bug

`trainSOLOV2` trains through `images.dltrain.internal.dltrain`. Its
`SerialTrainer/fit` (and `ParallelTrainer/fit`) honour a stop request by ending only the
inner per-iteration `while` loop — the outer `for epoch = 1:MaxEpochs` loop still runs to
completion:

```matlab
for epoch = 1:self.TrainingOptions.MaxEpochs      % <-- never exited early
    while keepTraining(self)                      % <-- only this loop is exited
        ... one training iteration ...
    end
    notify(self, 'EpochEnd', data);               % <-- checkpoint save, every idle epoch
    reset(self.DataQueue);
    shuffle(self.DataQueue);                      % when Shuffle == "every-epoch"
end
```

So the time to return scales with **`MaxEpochs` − epoch at which Stop was pressed**, not
with the training actually performed. Repro measurements (stop always at iteration 3):
`MaxEpochs` 5 → 15.7 s, 20 → 42.2 s, 400 → 765.5 s, with one duplicate checkpoint file per
idle epoch. Unmitigated, a real run stopped early blocked MATLAB for over an hour.

This affects **only the `2D Instance` workflow**. Semantic workflows use
`trainnet`/`trainNetwork`, which leave the training loop entirely on a stop request.

### Mitigations implemented

Each idle epoch costs a checkpoint save, a datastore prefetch, and augmentation of that
prefetch. All three are DeepMIB's own code and are short-circuited once a stop is under way,
gated on `mibDeepTrainingProgressStruct.spinDownActive`:

| Layer | File | What it does |
|-------|------|--------------|
| Checkpoint save | `mib/+deepmib/suspendCheckpointSaving.m` | Renames the checkpoint folder aside so `CheckpointSaver`'s save fails instantly (it only warns). Restored — with the warning state it suppresses — before finalisation; `'restoreOrphaned'` heals a folder stranded by Ctrl+C at the start of the next run. |
| Datastore prefetch | `mib/+deepmib/readInstancePatch.m` | `minibatchqueue` prefetches a mini-batch on every `reset`/`shuffle`, i.e. once per idle epoch. Returns a cached placeholder observation instead of loading and cropping a real image. |
| Augmentation | `mib/+deepmib/augmentInstanceData2D.m` | Passes that placeholder through unwarped. |

`spinDownActive` is set in the stop branch of `deepmib.customTrainingProgressDisplay` /
`deepmib.stopTrainingWithoutPlots` and cleared at the start of every run in
`startTrainingInstances.m` / `startTraining.m`.

**Why not key the short-circuit on `mibDeepStopTraining`:** the progress display reads
`stopState` *before* its `drawnow`, so a button press during that `drawnow` is seen only on
the following call — one genuine training iteration still follows the press. Keying on the
stop flag would feed that real iteration placeholder data and silently corrupt the weights.

### Emergency brake

Raised from `deepmib.readInstancePatch` as `error('DeepMIB:userEmergencyStop', …)`, caught
in `startTrainingInstances.m`, which rebuilds the network from the newest checkpoint via the
local `iRecoverNetworkFromCheckpoint` (synthesising `info` from the progress window's curve).

**Critical gotcha:** it cannot be raised from the training `OutputFcn`. `images.dltrain`
invokes the `OutputFcn` from a `notify()` listener, and **`notify` catches listener errors
and downgrades them to a warning** — so the abort is swallowed *and* `stop(trainer)` is
never reached, leaving training unstoppable by either button. The datastore `ReadFcn` is the
only DeepMIB code `trainSOLOV2` calls directly from its loop (`next(DataQueue)`), where
errors propagate normally.

Emergency brake needs `T_SaveProgress` on; the recovered network is up to
`CheckpointFrequency` epochs stale, so a low frequency (1–2) is worth recommending.

Also fixed here: `deepmib.stopTrainingCallback` compared the button text against
`'Emergency Brake'` while both progress displays label it `'Emergency brake'` — the brake had
**never** engaged, in any workflow. Now `strcmpi`. Exposing it then surfaced a second latent
bug: `Workflow`/`Architecture` were only ever set on the local `trainingProgressOptions`,
never on the global struct the callback reads; both displays now populate them.

### Residual limitation

Measured on a 1000-epoch run stopped at epoch 11: 450 s (checkpoint suspension only) → 128 s
(+ placeholder read) → **59 s** (+ augmentation passthrough), i.e. ~0.06 s per idle epoch —
roughly **a minute per 1000 remaining epochs**. What is left is `minibatchqueue` batching the
placeholder into a `dlarray` and moving it to the GPU once per idle epoch; shrinking the
placeholder to dodge that would risk the shape contract `trainSOLOV2` expects and turn a
graceful stop into an error dialog. Only the upstream `break` removes it.

Stated in the pre-training confirmation dialog (`startTrainingInstances.m`) and in
`docs/docs/user-interface/deepmib/deepmib-train.md`.

## 3D instance segmentation - DONE (steps 1-3 implemented and wired into DeepMIB)

> Open design questions and the remaining work moved to
> [`instance_3d_plan.md`](instance_3d_plan.md); the algorithm, a critique of the empanada/MitoNet
> source spec and the benchmark validation live in
> [`stitchInstances2Dto3D.md`](stitchInstances2Dto3D.md).

The goal was to extend 2D instance results to **3D objects**. Delivered:

1. **Per-slice 2D prediction** - the patch/tiled 2D pipeline above already writes one `*.model` per
   prediction image into `ResultingImagesDir/PredictionImages/ResultsModels`, so a volume exported
   as a 2D image sequence yields the per-slice instance label maps directly.
2. **Cross-slice merging** - `mib/+utils/stitchInstances2Dto3D.m` links 2D instances across
   adjacent slices via IoU/IoA of masks between `z` and `z+1`, resolved globally through an
   undirected overlap graph + union-find (`'graph'`, default) or strict per-pair 1-to-1 matching
   (`'hungarian'`, kept for paper-faithful comparison).
3. **Real-world topology** - appearing/disappearing objects, one-to-many splits and many-to-one
   merges are handled; `zLookback` bridges single-slice dropouts, `minObjectVoxels` removes noise
   fragments, and `anisotropyZ` / `maxCentroidShift` / `centroidLinkRadius` guard against over- and
   under-merging. Regression-tested by `tests/utils/StitchInstances2Dto3DTest.m` (11 Unit cases +
   benchmark Integration cases).

### DeepMIB entry points (all three verified present and enabled for `2D Instance`)

| Widget (Tag) | Wiring | Purpose |
|--------------|--------|---------|
| `P_mergeInstancesTo3D` | `MibDeepGUI.mlapp` → `MibDeep.mergeInstancesTo3D` | Predict tab → *Instance segmentation* → "Merge 2D to 3D": loads the per-slice `ResultsModels/*.model` in alphabetical (= Z) order, asks for the 9 stitching settings, stitches, then saves via `io.SaverFactory` as a single 3D file or a 2D sequence. |
| `P_OverlapInstancesMode` | `BatchOpt` dropdown, read in `startPredictionInstances.m:120` | Cross-**tile** stitching within one slice: `'IoU merge'` (default) / `'Centroid in core'`. |
| `P_OverlapInstancesSettings` | `MibDeepGUI.mlapp` → `MibDeep.updateOverlapInstancesSettings` | Edits `obj.OverlapInstancesOpt`: `.DetectionThreshold` (both modes), `.MergeIoU` / `.MergeIoA` (IoU-merge mode). |

All three are disabled by default and switched on only for the `2D Instance` workflow
(`selectArchitecture.m:27-29` and `:122-124`). The two levels of stitching are independent:
`P_OverlapInstancesMode` merges **tiles inside one slice**, `P_mergeInstancesTo3D` merges
**slices into a volume**.

Docs: `docs/docs/user-interface/deepmib/deepmib-instance.md` ("Merging 2D predictions into a 3D
model") and `deepmib-predict.md` (subpanel). The stitcher is also reachable outside DeepMIB via
Ribbon → Model → `MibModel.stitchModelInstances` for a model already open in MIB.

### 2D images and z-stacks as prediction input (added 2026-08-13)

Instance prediction and merging originally required **2D files only**. Both now accept z-stacks,
matching the `2D Semantic` behaviour:

- `startPredictionInstances.m` reads `read(imgDS)` **unsqueezed** as `[H W Z C T]` (the documented
  `io.loadImagesWrapper` contract) instead of `squeeze(...)`. The old squeeze made a grayscale
  z-stack `[H W Z]` indistinguishable from an RGB 2D image `[H W 3]`, which is exactly why stacks
  could not be supported before. Depth now comes from `size(vol,3)` and colour from `size(vol,4)`.
  Each z-slice is segmented separately (same tiling / stitching mode) and written into
  `outputLabels(:,:,z)`; a depth-1 file still saves a 2D model, so the 2D path is byte-identical.
  More than one time point raises a warning and only `t=1` is predicted (as in the semantic path).
- Instance indices stay **contiguous `1..N` per slice**, deliberately *not* unique across the
  stack: `utils.stitchInstances2Dto3D` relabels every slice internally, and a per-slice range keeps
  `modelType` at 65535 instead of overflowing into uint32 on deep stacks. `modelType` /
  `numMaterials` are driven by `maxInstancesPerSlice`.
- `mergeInstancesTo3D.m` detects the layout from the depth of the **first** `*.model` file:
  depth 1 = the legacy "one file per Z-slice, one merged output" path; depth > 1 = each file is an
  independent stack, stitched separately into one output per file. A mixed folder errors out in
  both directions (`MibDeep:mergeInstancesTo3D:mixedDimensions`). Multi-output runs ask for a
  folder + a format dropdown (instead of `uiputfile`) and save with `silent = true` so the
  TIF/model savers do not ask the 3D-stack/2D-sequence question once per file; outputs are named
  `<inputModelName>_stitched3D.<ext>`. Loading a model file moved into a local `iLoadLabels`
  subfunction (used by both the layout peek and the two loading paths).
- Verified in MATLAB against real files: 2D grayscale → `[64 48 1 1 1]`, 2D RGB → `[64 48 1 3 1]`,
  5-page TIF → `[64 48 5 1 1]`, per-slice extraction always yields `[H W 3]`, slice order
  preserved, and a synthetic 3D instance model round-trips through save → `iLoadLabels` → stitch
  (10 2D objects → 2 3D instances).

### What is still open
- **Phase D (streaming to a BigData sink)** - deferred; the trigger is a single-timepoint labels
  volume that no longer fits in RAM. `mergeInstancesTo3D` currently builds the whole `H×W×Z`
  volume in memory.
- Phase C (hysteresis edges) was **measured and rejected**; Phase C′ (centroid-NN gap bridging) is
  implemented but **off by default** (no benefit on near-isotropic benchmarks). Numbers behind both
  decisions are in `instance_3d_plan.md`.
