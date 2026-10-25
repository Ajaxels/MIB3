# DeepMIB: StarDist 2D as a native 2D Instance architecture

> **Status:** phase 0 done 2026-10-23: maps and labels match the Python reference, raster
> NMS is 7-16x slower than C++, so the MEX NMS moved to phase 2. Results:
> [`stardist_poc/phase0_results.md`](../private/deepmib/stardist_poc/phase0_results.md). Phase 1 (core library
> `mib/+deepmib/+stardist/`) and phase 2 (MEX `mib/external/stardist/stardistMex`, results
> identical to StarDist) done 2026-10-23. Phase 3 (training integration) code done, GUI test
> pending. Phase 4 (prediction) code done 2026-10-23, GUI test pending. Phase 5 done
> 2026-10-23. Phase 6 (tests, docs) done 2026-10-23. Training and prediction ran in the
> DeepMIB window 2026-10-24 (pretrained and random weights); the rest of the GUI checklists of
> phases 3 and 4 remains. Phase 7 (a trained example project, random weights) planned
> 2026-10-24; a 300-epoch run reached F1 0.887 / 0.753 (target 0.88 / 0.75), the same run
> with a piecewise learning-rate schedule 0.873 / 0.721, and with 4x more weight updates
> (batch 8, L2 0) 0.908 / 0.816 (pretrained 0.914 / 0.844), accepted; example project zipped and
> added to Home -> Example datasets 2026-10-24, upload pending. Phase 8 (use the pretrained model without
> training) code done 2026-10-24, GUI test pending.
> Open questions answered 2026-10-23, see [Decisions](#decisions).

## Context

StarDist (Schmidt et al. 2018, Weigert et al. 2020) segments star-convex objects (nuclei,
round cells, vesicles) by predicting, for every pixel, an object probability and the distances
to the object boundary along N fixed rays. The overlapping candidate polygons are reduced to
one per object by non-maximum suppression (NMS). Touching objects separate without a watershed
step, and the pretrained `2D_versatile_fluo` / `2D_versatile_he` models fine-tune well from a
few annotated images.

The reference implementation is Python + TensorFlow. Python integration (the SAM2
pattern) was considered and not chosen for the main path:

- TensorFlow GPU on native Windows stopped at TF 2.10 (Python 3.10, CUDA 11.2).
- MATLAB loads one interpreter per session, which clashes with the PyTorch env used by SAM.
- Users would have to install a conda env, and the compiled MIB would depend on it.

A native implementation keeps StarDist Python-free, works in the compiled app, uses MATLAB's
own GPU stack, and fits the DeepMIB training/prediction UI the users already know.

**Decision:** add `StarDist` as a second architecture of the existing `2D Instance` workflow
(`MibDeep.m:356`, currently `{'SOLOv2'}`). Python is used only by the developer, once, to
convert the pretrained weights and to produce reference outputs for the tests.

**Out of scope:** StarDist 3D (polyhedron NMS, no general pretrained model), multi-class
StarDist (`n_classes`), and the Python route.

## How StarDist works (summary for implementers)

| Step | What happens | Reference behaviour to match |
|------|--------------|------------------------------|
| Normalise | Per image, stretch intensities between percentiles | `csbdeep.utils.normalize(img, 1, 99.8)`, float32 |
| Targets: probability | Inside each object, the Euclidean distance to the nearest edge, normalised per object to max 1; background 0 | `stardist.geometry.edt_prob` |
| Targets: distances | For each foreground pixel, step along each of N rays (angles `2*pi*k/N`) until leaving that pixel's label | `stardist.geometry.star_dist` (sub-pixel step, see its C code) |
| Grid | Outputs at `1/grid` resolution, targets taken at every `grid`-th pixel starting at pixel 0 (no offset); the prob target is the EDT of the subsampled label map | `config.grid`, e.g. `(2,2)` |
| Network | For `grid > 1` a pre-stage (2 convs of 32 filters + maxpool per factor 2), then U-Net (depth 3, 32 base filters, 3x3 conv, ReLU, maxpool, nearest upsampling + concat `[up, skip]`), then 3x3 conv with 128 filters, then two 1x1 heads: 1 channel sigmoid (prob), N channels linear (dist) | `StarDist2D` / `Config2D`; values from the model's `config.json` |
| Loss | `BCE(prob, soft edt target) + 0.2 * [mean(mask .* abs(dist error)) / mean(mask) + 1e-4 * mean((1-mask) .* abs(dist pred))]`, `mask` = prob target; 90% of patches forced to contain foreground | `train_loss_weights=(1,0.2)`, `train_dist_loss='mae'`, `train_background_reg`, `train_foreground_only` |
| Thresholds | Grid search of `prob_thresh` and `nms_thresh` on validation images, maximising mean matching accuracy over IoU thresholds | `optimize_thresholds`, stored in `thresholds.json` |
| Predict | Tiled forward pass -> prob map + dist map; candidates where prob > `prob_thresh`; greedy NMS by score, suppressing when intersection / smaller area > `nms_thresh`; draw survivors into a label image, lowest score first | `predict_instances`, `non_maximum_suppression`, `polygons_to_label` |

The exact numbers above (layer counts, offsets, loss details) must be re-checked against the
StarDist source of the version whose pretrained weights are converted, in phase 0. The Grid,
Network, Loss and Predict rows were corrected against StarDist 0.9.2 on 2026-10-23; details
with file and line in [`stardist_poc/source_notes.md`](../private/deepmib/stardist_poc/source_notes.md).

## What already exists (reuse, don't rewrite)

| Need | Existing code | Note |
|------|---------------|------|
| Workflow/architecture lists | `MibDeep.m:343-357` (`availableArchitectures`), `selectWorkflow.m`, `selectArchitecture.m` | Add `'StarDist'` to `architectureList{5}`; no encoder entry |
| Instance ground truth from MIB models | Preprocess tab -> instance label MAT files (`deepmib.saveInstanceLabelsParFor`, fields `imageFilename` + `instanceLabelMap`) | Architecture independent, reuse as-is. Verify in phase 3 |
| Patch sampling (object-seeded + random, seeded validation) | `deepmib.readInstancePatch` | Builds SOLOv2 GT and forces RGB; needs a label-map output mode |
| Instance augmentation | `deepmib.augmentInstanceData2D` | Works on `{image, boxes, labels, masks}`; needs a label-map mode (nearest interpolation for labels) |
| `trainnet` progress display, stop and emergency brake | `deepmib.customTrainingProgressDisplayTrainNet`, `deepmib.stopTrainingCallback`, semantic training path | StarDist trains with `trainnet`, not `trainSOLOV2`, so it follows the semantic path's stop handling |
| 2D -> 3D instance linking | `utils.instances.stitch2Dto3D` | Reuse for z-stacks |
| Prediction loop, file I/O, zarr input, output saving | `startPredictionInstances.m` | Add a StarDist branch where the slice is segmented; everything around it stays |
| Cross-tile instance stitching | `segmentBlockedImageInstances`, `segmentImageInstancesIoUMerge` | **Not used by StarDist**, see phase 4 |

## Design

### New package `mib/+deepmib/+stardist/`

Each function has at least two call sites (training, prediction, threshold search, tests),
so a package is justified. Implemented in phase 1; signatures as built:

| Function | Purpose |
|----------|---------|
| `defaultConfig(config)` | Config struct shared by all functions (`nRays grid nChannelIn patchSize unet* netConvAfterUnet normalizePercentiles probThresh nmsThresh train*`); fills missing fields, so old network files keep working |
| `createNetwork(config, weights)` | `dlnetwork` with Keras layer names, `imageInputLayer` of `[patchSize nChannelIn]` (predict accepts other sizes). Output: one `[H/g W/g 1+N]` tensor (prob + dist concatenated), so `trainnet` sees one output |
| `computeTargets(labelMap, config, method)` | `[H/g W/g 1+N]` single target: channel 1 = `edt_prob`, 2..N+1 = ray distances (`stardistMex` when present) |
| `lossFunction(Y, T, config)` | Keras-exact BCE on channel 1 + masked MAE with background regulariser; `@(Y,T) lossFunction(Y,T,config)` for `trainnet` |
| `normalizeImage(img, percentiles)` | Percentile normalisation per channel (numpy percentile definition), single precision |
| `predictMaps(net, img, config, options)` | Tiled forward pass (`.tileSize .executionEnvironment .progressDlg`), whole-image prob and dist maps, cancelable |
| `nms(prob, dist, grid, probThresh, nmsThresh, options)` | Candidates + greedy NMS (`stardistMex` when present, raster fallback), returns kept `points scores rayDist`, cancelable |
| `starPolygonMask(centre, rayDist, rowRange, colRange)` | Rasterises one star-convex polygon (used by `nms` and `polygonsToLabel`) |
| `polygonsToLabel(points, rayDist, scores, imageSize)` | Draws kept polygons, lowest score first, `uint32` labels |
| `optimizeThresholds(net, images, labels, config, options)` | StarDist's search (scipy bracket + golden ported), cancelable, returns `[probThresh, nmsThresh, accuracy, cancelled]` |
| `loadPretrained(modelName, folder, progressDlg)` | Loads `<folder>/<name>.mat` written by `convert_pretrained.py`, downloads the zip on first use |

### Network file

`.mibDeep` keeps the usual fields and adds a `StarDistConfig` struct: `nRays`, `grid`,
`nChannelIn`, `normalizePercentiles`, `probThresh`, `nmsThresh`, `pretrainedSource`.
`startPredictionInstances` branches on `res.BatchOpt.Architecture{1}`.

### Channels

SOLOv2 needs RGB and the instance path expands grayscale to 3 channels in several places
(`readInstancePatch`, `startPredictionInstances.m:232`, `segmentBlockedImageInstances.m:44`).
StarDist takes the native channel count (`versatile_fluo` = 1, `versatile_he` = 3). Every
RGB expansion must be skipped for StarDist, and a channel-count mismatch with the chosen
pretrained model must be refused with a clear message before training starts.

## Phases

### Phase 0: proof of concept, go/no-go (about 3-5 days)

Work in `development/private/deepmib/stardist_poc/`, outside `mib/`.

1. **Python reference (developer only).** In a separate env (`stardist`, TF CPU is enough):
   - export the `2D_versatile_fluo` weights, `config.json` and `thresholds.json`;
   - run `predict_instances` on 3-5 test images (dense, touching nuclei, one large image
     that needs tiling) and save `prob`, `dist`, final labels, polygon points and scores;
   - run `star_dist` and `edt_prob` on 2-3 label images and save the targets.
2. **Source check.** Read the StarDist source of the installed version (the one whose
   weights are converted) and settle these points, which the summary table above states
   from memory and may get wrong. Record each answer, with file and line, in
   `development/private/deepmib/stardist_poc/source_notes.md` and correct the table:
   - **NMS overlap measure.** Is the overlap tested against `nms_thresh` the IoU, or the
     intersection divided by the *smaller* polygon area (expected in `stardist2d.cpp`)? The
     raster NMS, the MEX wrapper and the meaning of the stored `nms_thresh` must all use the
     same definition, or thresholds from `thresholds.json` behave differently in MIB.
   - **Loss terms beyond BCE + MAE.** `train_background_reg` (a small penalty on predicted
     distances in the background) and `train_foreground_only` (fraction of patches forced to
     contain foreground) - their defaults, their values in the `versatile_fluo` config, and
     exactly how the regulariser enters the loss. Both go into `lossFunction` and the patch
     sampler of phase 3.
   - **Grid offset.** Whether the targets are subsampled starting at pixel `0` or at
     `grid/2` (`ss_grid` in the data generator), and how prediction maps a grid cell back to
     pixel coordinates (`points * grid`, with or without an offset). A wrong offset shifts
     every predicted polygon by up to `grid-1` pixels.
   - **Config defaults.** Base `Config2D` uses `grid=(1,1)`, the pretrained models use
     `(2,2)`, and other fields may differ too (`n_rays`, U-Net depth and filters,
     `net_conv_after_unet`, upsampling mode, padding). `createNetwork` must take every value
     from the model's `config.json` and use the `Config2D` defaults only for a model trained
     from scratch.
   - **Accepted polygons may overlap.** Confirm that StarDist accepts a candidate whose
     overlap with each earlier accepted polygon stays below `nms_thresh`, so accepted
     polygons can overlap one another. Step 5 measures what this costs the raster NMS.
3. **Weight conversion.** Two candidate routes; try A first:
   - A: build the network with `createNetwork`, copy the weights layer by layer from the
     Keras `.h5` (`h5read`), keeping Keras HWIO kernel layout -> MATLAB `[h w in out]`.
   - B: `tf2onnx` in Python, then `importNetworkFromONNX` (the ONNX converter support
     package is installed). Faster to get running, but the imported graph is harder to
     fine-tune and to reconfigure.
4. **Raster NMS** in MATLAB, using the overlap measure found in step 2.
5. **Compare** on the test images:
   - prob and dist maps: max abs difference < 1e-3 (float32 rounding between frameworks);
   - final labels: matching F1 at IoU 0.5 >= 0.98 against the Python labels;
   - NMS decisions: raster vs Python kept candidates on identical prob/dist input, so map
     differences don't hide NMS differences. The raster version paints accepted objects into
     one label raster, where later objects overwrite earlier ones in overlap zones, so a new
     candidate's overlap with an earlier object is underestimated. Report how many candidates
     differ, and whether they cluster on the densest image;
   - NMS time per 2048x2048 image.

**Gate:** if the maps match but NMS is too slow, or the raster NMS disagrees with Python on
too many candidates in dense images, the MEX phase moves before the DeepMIB integration. If the
maps do not match, stop and resolve before any DeepMIB work.

**Outcome (2026-10-23):** maps and labels match; NMS too slow. The MEX is now phase 2, and the
training and prediction integrations are phases 3 and 4.

### Phase 1: core library (about 1 week)

**Done 2026-10-23.** 11 functions in `mib/+deepmib/+stardist/` with RST docblocks, API page
`docs_api/source/api/deepmib/stardist.rst` (builds without warnings), code analyzer clean.
Checked against the Python reference by `stardist_poc/verify_phase1.m`:

| Function | Result against StarDist 0.9.2 |
|----------|-------------------------------|
| `computeTargets` | prob and dist equal to 1e-6 (float rounding) on 3 label images, grid 1 and 2 |
| `normalizeImage` | exact |
| `createNetwork` + `predictMaps` | maps within 3e-6 (CPU) / 6e-4 (GPU); tiled = untiled to 1e-6 |
| `nms` + `polygonsToLabel` | DSB images pixel-identical labels; mosaic F1 0.9994 |
| `lossFunction` | equal to Keras in double (0.426100); 7e-5 relative in single |
| `optimizeThresholds` | same thresholds and accuracy as StarDist (0.4782 / 0.30 / 0.8753), 59 s vs 10 s |
| `loadPretrained` | converted `2D_versatile_fluo` loads and predicts; download path untested until the zip is hosted |

Cancel returns cleanly from `predictMaps`, `nms` and `optimizeThresholds`.

**Target speed:** `computeTargets` takes 0.4-0.7 s per whole DSB image at grid 2 (single
thread), about 0.1-0.2 s per 256x256 training patch; at batch 8 that is about 1 s of CPU per
iteration and would stall the GPU. `star_dist` is in the same `stardist2d.cpp`, so phase 2 wraps
it too.

Implementation notes kept from the plan:

- `computeTargets`: vectorised over all (pixel, ray) pairs, compacting the moving rays each
  step; single precision and round-half-even as the C code.
- `nms` (raster fallback, from `poc_nms.m` / `poc_starPolygonMask.m`):
  1. candidates = grid cells with prob > `probThresh` outside a 2-cell border, sorted by score
     descending, centre `(gridIndex-1)*grid`;
  2. polygon vertices, bounding boxes and shoelace areas for all candidates at once;
  3. for each candidate: kept polygons whose bounding box intersects, nearest centre first;
     the candidate is rasterised once on its box (sector test on pixel centres), kept polygons'
     masks are cached; suppress when intersection / smaller area > `nmsThresh`.
  Phase 0 measured 0-2 decisions differing from the C++ NMS, but 7-16x slower, which is why
  phase 2 adds the MEX before any DeepMIB integration. The raster version stays as the fallback
  when the MEX is missing.
- `predictMaps`: tiling is done on the **dense maps**, not on instances. Overlap must cover the
  network's receptive field; cores are written into whole-slice maps, and NMS runs once on
  the whole slice. This removes the cross-tile instance stitching that SOLOv2 needs.
- Every loop that can run long (`optimizeThresholds`, tiling of large images) takes a
  progress handle and checks cancel, per the CLAUDE.md rule.

### Phase 2: MEX NMS and ray distances (about 1 week)

Moved ahead of the DeepMIB integration on 2026-10-23 after the phase 0 timing (raster NMS
7.1 s vs C++ 0.59 s on a 2048x2048 slice; NMS is >95% of prediction time, and
`optimizeThresholds` in phase 3 runs it for every threshold pair on every validation image).

**Done 2026-10-23.** As built (differences from the original plan in bold):

- `mib/external/stardist/stardistMex.cpp`: one MEX file with two commands,
  `stardistMex('nms', dist, points, nmsThresh, useKdtree, useBbox)` (`c_non_max_suppression_inds`)
  and `stardistMex('starDist', labelMap, nRays, gridRow, gridCol)` (`c_star_dist`), from
  `stardist2d.cpp` of the 0.9.2 tag (the wheel ships only the `.pyd`). Python C-API replaced by
  the MEX API, column-major arrays, `uint32` labels instead of `uint16`, `utIsInterruptPending`
  for Ctrl+C. Clipper 6.4.2 and nanoflann 1.3.2 are StarDist's own copies, in the same folder.
- **The MEX file sits next to its source, `mib/external/stardist/stardistMex.mexw64`, called as
  global `stardistMex`** (as the other MIB MEX files); the folder is on the path via `mib3.m`
  and the MATLAB project. `nms` and `computeTargets` use it when
  `exist('stardistMex', 'file') == 3`, otherwise the MATLAB code; a `method` option forces
  either.
- **Built by `deployment/mib3_compile_c_files.m`** (new `StarDist` target, `-lut`), not a
  separate `build_mex.m`. **Single-threaded, no OpenMP**: it is already as fast as StarDist's
  own build, and OpenMP would add `libgomp-1.dll` (MinGW) or `vcomp140.dll` (MSVC) to the
  dependencies. The MinGW build imports only `libmex`, `libmx`, `libut` and the Windows C
  runtime. Deployment ships `mib/external` and gathers its `*license*` files, so no change to
  the deployment script was needed.
- Licences: `stardist_license.txt` (BSD 3-Clause), `clipper_license.txt` (Boost),
  `nanoflann_license.txt` (BSD) next to the source; listed in
  `docs/docs/getting-started/licenses/licenses-ext.md` and `acknowledgements.md`.
- Compiler on this workstation: MATLAB's MinGW-w64 add-on (GCC 14.2) after an AppLocker rule
  `C:\ProgramData\MATLAB\*`.

Results (`stardist_poc/verify_phase1.m`, check `mex`):

| Check | Result |
|-------|--------|
| NMS decisions on Python's candidates, 5 cases, 63 713 candidates | **0 differ** from StarDist |
| NMS time, mosaic 48 208 candidates | 0.62-0.66 s (StarDist C++ 0.60 s); dense 0.12 s (0.12 s) |
| `nms()` + `polygonsToLabel` vs Python labels | identical objects in all 5 cases; 3 border pixels differ on the mosaic (polygon drawing) |
| `starDist` targets vs `ref/targets_*.mat` | **max diff 0** (bit-identical) |
| `computeTargets` time, dense image grid 2 | 0.13 s (MATLAB fallback 0.72 s) |
| `optimizeThresholds`, 4 validation images | same result as StarDist (0.4782 / 0.30 / 0.8753) in 8.8 s (StarDist 9.9 s, raster 59 s) |

### Phase 3: DeepMIB training integration (about 1-1.5 weeks)

**Code done 2026-10-23; the GUI flow in the DeepMIB window is not yet tested** (it needs the
window and its confirmation dialogs; see "Still to test" below). As built (differences from the
original plan in bold):

- `MibDeep.m`: `architectureList{5} = {'SOLOv2', 'StarDist'}`; **new property `StarDistOpt`**
  (`NRays 32`, `Grid 2`, `NormalizePercentiles [1 99.8]`, `OptimizeThresholds true`,
  `RayCheckFiles 20`), kept in preferences (`closeWindow`), saved in `.mibCfg` (`saveConfig`)
  and merged on load (`loadConfig`). **No new BatchOpt fields and no `.mlapp` change.**
- **Pretrained model choice reuses "Starting weights"** (`updateStartingWeightsList`):
  `2D_versatile_fluo` (default) or `None (random)`.
- **StarDist settings reuse the settings button next to "Starting weights"** (decided with the
  user): `setStartingWeightsSettings` hands over to the new `setStarDistSettings` (rays and grid
  for a new network, normalisation percentiles, threshold tuning, ray reconstruction check); the
  button's tooltip is switched per architecture.
- `selectArchitecture.m`: StarDist disables the encoder, "Calculate accuracy for instance 2D" and
  the stitching mode, and sets `TrainEngine = 'trainnet'`.
- `readInstancePatch`: `options.outputFormat = 'labelMap'` returns `{image, labelPatch,
  normValues}`: native channel count, and **the whole-image normalisation percentiles (cached
  per file)**, because the intensity augmentations work on raw values, so normalisation must
  come after augmentation. `objectFraction = config.trainForegroundOnly` (0.9).
- `augmentInstanceData2D`: label-map mode for the 1x3 cell (geometric transforms with nearest
  interpolation, no boxes).
- New `startTrainingStarDist.m`: start from the pretrained model, from random weights, or
  **continue the existing network file**; one patch is read up front to report a channel
  mismatch clearly; datastore chain read -> augment -> normalise + `computeTargets`; validation
  with fixed per-observation seeds as SOLOv2; `trainnet` with `deepmib.stardist.lossFunction`
  and the semantic training options (**without the accuracy metric**,
  `TargetDataFormats "SSCB"`); threshold tuning on the whole validation images (cancelable);
  network file with `StarDistConfig` (incl. `probThresh`, `nmsThresh`, `pretrainedModel`) and
  `StarDistOpt`.
- `start.m` routes 2D Instance + StarDist to it.
- `checkNetwork.m`: StarDist shown in `analyzeNetwork` (pretrained model loaded, downloaded on
  first use).
- `findBestMinibatchSize.m`: StarDist probed with random images and targets of the output size
  and the StarDist loss; a pretrained model is represented by its design, not downloaded.
- **`customTrainingProgressDisplayTrainNet`: missing accuracy now defaults to NaN and shows
  "-"**; before, a run without the accuracy metric would have deleted vector elements on
  every validation.
- **Training metric "Core IoU"** (`deepmib.stardist.trainingMetrics`, added after the first GUI
  run showed empty gauges): IoU of predicted vs target object cores (probability > 0.5 on both
  sides), shown on the accuracy gauges with the panel titled "Core IoU". A package function
  handle cannot be a trainnet metric (its name must be a valid variable name), so the metric is a
  local function returned by handle; trainnet reports it as `TrainingcoreIoU` /
  `ValidationcoreIoU`. A first version compared predicted cores with all object pixels
  (target > 0) and scored even the pretrained model low:

  | Image (`2D_versatile_fluo` maps) | pred > 0.5 vs target > 0 | soft IoU | core IoU |
  |---|---|---|---|
  | dense | 29.0% | 72.9% | 69.4% |
  | large_objects | 33.2% | 87.5% | 85.2% |
  | medium | 35.0% | 67.6% | 69.8% |
- **New `deepmib.stardist.matchInstances`** (matching moved out of `optimizeThresholds`, now
  shared with the ray check).
- **Patch preview in the progress window** (added 2026-10-24 after the GUI run showed two empty
  boxes): the semantic preview lives in `augmentAndCrop2dPatchMultiGPU`, which StarDist does not
  use, so `localTrainingPair` of `startTrainingStarDist` shows a fraction of the augmented
  training patches and their label maps.
- User docs: StarDist section in `docs/docs/deepmib/deepmib-instance.md`.

Verified headless (`stardist_poc/verify_phase3.m`, mini project of 40 + 10 DSB2018 images;
`verify_phase1.m` checks `raycheck` and `thresholds`):

| Check | Result |
|-------|--------|
| label-map patch | native channels; normalisation values equal the whole image's |
| label-map augmentation | ids survive (subset), `normValues` kept |
| training pair | 128x128 image -> 64x64x33 targets |
| fine-tuning `2D_versatile_fluo`, 3 epochs | 60 iterations, 0.46 s/iteration (GPU, batch 8); validation loss 0.259 -> 0.225 |
| threshold tuning after training | runs; accuracy 0.855 -> 0.856 (the model already knows DSB2018) |
| ray reconstruction score | equal to StarDist `relabel_image_stardist` + `mean_true_score` to 1e-7, 8-128 rays |
| `optimizeThresholds` after the matching refactor | still StarDist's result (0.4782 / 0.30 / 0.8753) |

**GUI runs 2026-10-23/24 (user):** training and prediction from `2D_versatile_fluo` and from
random weights work in the DeepMIB window (`C:\temp\DeepMIB_Stardist`, 402 training + 45
validation images and 50 test images of `ref/dsb2018`). Matching against the 50 test labels:

| Network | F1 at IoU 0.5 | F1 at IoU 0.7 |
|---------|---------------|---------------|
| `2D_versatile_fluo` as downloaded | 0.914 | 0.844 |
| random weights, 30 + 10 epochs (about 480 iterations at batch 32, LR 0.003 and 0.0001) | 0.786 | 0.433 |

The random run is under-trained: validation loss still falling (0.74 at the end, pretrained
0.27-0.33), and Core IoU jumping between 0 and 50% from one validation to the next. StarDist's
own default is 400 epochs x 100 steps at batch 4 (about 160k patches, 10x this run) with Adam
at LR 3e-4 and ReduceLROnPlateau. In the fine-tuning runs at LR 0.003 the validation loss rose
from 0.27-0.34 to 0.52-0.58 at the first validation and at best returned to its starting value
(0.338 -> 0.333 in one run), so fine-tuning gained nothing; on DSB2018, the pretrained
model's own training data, there is little left to gain.

Still to test in the DeepMIB window: switching to StarDist and back to SOLOv2 (widget states,
starting weights list, button tooltip), the settings dialog and the ray check, Check network,
Find best mini-batch size, a full Train run with the progress window (Stop training, threshold
tuning dialog, saved network and config), and loading a saved StarDist config.

### Phase 4: prediction integration (about 3-5 days)

**Code done 2026-10-23; the GUI flow in the DeepMIB window is not yet tested.** As built
(differences from the original plan in bold):

- `startPredictionInstances.m`: **the network file decides** (`StarDistConfig` present), not
  the Architecture selected in the GUI. Per slice: `normalizeImage` (percentiles of the slice)
  -> `predictMaps` -> `nms` on the whole slice -> `polygonsToLabel`; no RGB expansion; no
  stitching and no `splitDisconnected` (as StarDist). A channel-count mismatch with the
  network is reported before any slice is processed. File reading, `.model` / zarr output,
  progress and cancel are shared with SOLOv2.
- **Thresholds are not mapped to SOLOv2's `DetectionThreshold`**: that is a fixed confidence
  (0.5) of another network, while the StarDist thresholds are tuned per network and stored in it.
  New `StarDistOpt` fields: `PredictThresholds` (`'From the network'` default or `'Custom'`),
  `ProbThresh`, `NmsThresh`, `PredictTileSize` (1024).
- **The Predict-tab settings button opens "StarDist prediction settings"** for StarDist
  (`updateOverlapInstancesSettings` hands over to a local dialog that also shows the
  thresholds of the selected network); its tooltip is switched per architecture in
  `selectArchitecture`, which also disables the overlap mode, "Overlapping tiles" and
  "Overlap, %" for StarDist (the overlap follows from the receptive field).
- Z-stacks: per slice, then "Merge 2D to 3D" as for SOLOv2 (unchanged, reads `.model` files).
- Very large slices: whole-slice maps in RAM (about 0.5 GB for 16k x 16k, 32 rays, grid 2);
  block-wise NMS deferred.
- User docs: StarDist paragraph in the Prediction section of `deepmib-instance.md`.

Verified headless (`stardist_poc/verify_phase4.m`, the same call sequence on raw images):
pixel-identical labels to StarDist on the four DSB2018 cases with tiles of 256 and 1024 px;
three identical slices of a z-stack give identical labels.

Still to test in the DeepMIB window: Predict with a StarDist network (2D images, a z-stack,
ZARR input and "Zarr3 (BigData model)" output), the StarDist prediction settings (network
thresholds shown, Custom thresholds used), the disabled overlap widgets and tooltip after
switching architectures, a channel-mismatch image, Cancel during prediction, and "Merge 2D
to 3D" on a StarDist z-stack prediction.

### Phase 5: pretrained models (about 2-3 days, can run in parallel with phase 3)

**`2D_versatile_fluo` done 2026-10-23.** The regenerated zip is on the server: checked
2026-10-24, the downloaded file is byte-identical (SHA-256) to `pretrained/2D_versatile_fluo.zip`
and contains the `.mat` and `2D_versatile_fluo_LICENSE.txt`.

- Conversion script `development/private/deepmib/stardist_poc/convert_pretrained.py` (developer,
  one-off) -> `.mat` per model (weights, config, thresholds, source URL, licence) and a zip
  with the `.mat` and `<name>_LICENSE.txt`. It refuses a model whose training-data licence is
  not recorded in its `TRAINING_DATA` table.
- Distribution: download on first use, the same way as the DeepMIB encoders
  (`generateUnet2DwithEncoder.m`). One zip per model on
  `http(s)://mib.helsinki.fi/web-update/stardist/<name>.zip`, fetched by `loadPretrained` with
  `core.DownloadProgressMonitor` (HTTP first, HTTPS on failure, cancelable) into
  `ExternalDirs.DeepMIBDir` and unzipped there. Nothing is bundled with the installer. The
  download was verified 2026-10-23 (1.4 s, identical file).
- Licences, checked 2026-10-23:

  | Model | Weights | Training data | Status |
  |-------|---------|---------------|--------|
  | `2D_versatile_fluo` | BSD 3-Clause, (c) 2018-2020 Martin Weigert, Uwe Schmidt ([stardist-models](https://github.com/stardist/stardist-models)) | DSB2018 subset = BBBC038v1, CC0, citation requested (Caicedo et al., Nature Methods 2019) | cleared |
  | `2D_versatile_he` | BSD 3-Clause (same) | MoNuSeg 2018 (CC BY-NC-SA 4.0, non-commercial, share-alike) + TNBC, Naylor et al. 2018 (CC BY 4.0) | **not offered** (decided 2026-10-23) |

  The first zip carried the StarDist **code** licence; the regenerated one carries the
  `stardist-models` licence plus the training-data provenance and citation, in the `.mat`
  (`model.licence` of `loadPretrained`) and as `2D_versatile_fluo_LICENSE.txt` next to it after
  unzipping. Weights unchanged; uploaded (verified 2026-10-24). MIB installations that already
  downloaded the first zip keep working (identical weights).
  Listed in `docs/docs/getting-started/licenses/licenses-ext.md`; BBBC038 citation in
  `acknowledgements.md`.
- Models: only `2D_versatile_fluo`. `2D_versatile_he` is not offered (decision 6): part of its
  training data is non-commercial. Histology users fine-tune `2D_versatile_fluo` or train from
  scratch.

### Phase 6: tests and documentation (about 3-4 days)

**Done 2026-10-23.**

Tests in `tests/deepmib/` (self-contained: expected values derived analytically, so the
git-ignored Python reference files are not needed; the comparisons against StarDist itself stay
in `stardist_poc/verify_phase1/3/4.m`):

- `StarDistTest.m`, 22 `Unit` tests, 3.9 s: config defaults; ray lengths of a rectangle
  (n - 1 + 0.5) and the normalised EDT, MATLAB and MEX; grid sampling from pixel 0; MEX = MATLAB
  targets on random touching labels; label ids above 65535; numpy percentiles of 1..100;
  diamond area; `starPolygonMask` on one-column/one-row/one-pixel windows (regression); drawing
  order; NMS suppression, border and grid (raster and MEX), MEX vs raster on random maps;
  network output sizes and the patch-size error; weights loaded by layer name; tiled = untiled
  maps and the distance clamp; cancel of `predictMaps`; loss of an exact prediction (entropy +
  regulariser); core IoU metric; matching at IoU 0 / 0.5 / 0.7; label-map patch and
  augmentation; unknown pretrained model refused. MEX tests self-skip when the MEX is not built.
- `StarDistIntegrationTest.m`, `Integration` + `RequiresNetwork`, 1.8 s: downloads
  `2D_versatile_fluo` (and its licence file) into a temporary folder and finds all 9 disks of a
  synthetic image at IoU 0.5; self-skips offline.
- Full Unit suite (`buildtool test` in a separate `matlab -batch`): **Build Successful, 0
  failed**, 5 tests filtered by their own assumptions (none in DeepMIB). That MATLAB then
  crashed **at exit** in `zarrMex.mexw64_unloaded`, the same fault that killed the user's MIB
  session when the suite was run through MCP; unrelated to StarDist, to be investigated next.

Running the tests corrected one docblock: the background regulariser of `lossFunction` weighs
the distances by `1 - mask` everywhere, so it also acts inside objects (the soft mask is below 1
except at the centre).

Documentation:
- `docs/docs/deepmib/deepmib-instance.md`: StarDist section (when to choose it, starting
  weights, patch size, settings, ray check, the Core IoU gauges) and its prediction paragraph;
  `deepmib-predict.md` points to it. Licences and acknowledgements updated in phases 2 and 5.
- RST docblocks for every `deepmib.stardist` function, `trainingMetrics`, the new controller
  methods and the changed DeepMIB functions; `docs_api/source/api/deepmib/stardist.rst`. The API
  build shows no warnings in these files; all 13 package functions and the new `MibDeep` members
  render.
- `development/private/deepmib/stardist_poc/`: `phase0_results.md` (measurements, raster vs C++ NMS),
  `source_notes.md` (StarDist 0.9.2 behaviour with file and line), conversion and reference
  scripts.
- `development/INDEX.md` links this plan and the proof-of-concept folder.

Still open (not phase 6): the GUI runs of phases 3 and 4 in the DeepMIB window.

### Phase 7: trained example project (future)

A DeepMIB example project for StarDist, as the other DeepMIB projects in **Ribbon -> Home ->
Example datasets -> DeepMIB projects** (Zenodo record, entry in
`docs/docs/user-interface/ribbon/home/index.md`). Based on the test project
`C:\temp\DeepMIB_Stardist` (`01_train`: 402 training + 45 validation images, `02_predict`: 50
test images with labels, all from `ref/dsb2018`).

**Data licence:** `ref/dsb2018` is StarDist's `dsb2018.zip` (release 0.1.0), a subset of the
Kaggle DSB2018 `stage1_train` set = BBBC038v1, **CC0** ("the various contributors of the imagesets
have waived all copyright and related or neighboring rights"). Redistribution, modification and
commercial use are allowed. Credit in the record and the docs: the BBBC038v1 citation requested
by the Broad ("We used image set BBBC038v1, available from the Broad Bioimage Benchmark Collection
[Caicedo et al., Nature Methods, 2019]") and the StarDist subset (Schmidt et al. 2018). Not
confirmed: whether StarDist also corrected labels in the subset; their zip carries no licence of
its own, so this does not change the terms.

**The example trains from random weights.** `2D_versatile_fluo` was trained on this data, so
fine-tuning it here shows no gain (threshold-tuned accuracy 0.855 -> 0.856, validation loss
never below its start); a fine-tuning example would need a different nuclei dataset.

**Suggested settings for the next random-weights run** (changes from the 2026-10-24 run in bold;
longer training with a steadily dropping learning rate, patches per image unchanged):

| Setting | 2026-10-24 run | Suggested | Why |
|---------|----------------|-----------|-----|
| Network filename | `stardist.mibDeep` | **`stardist_random.mibDeep`** | keeps the current network for comparison; answer "Start new training" |
| Starting weights | None (random) | None (random) | |
| StarDist settings | 32 rays, grid 2, percentiles 1-99.8, tune thresholds | same | StarDist defaults |
| Input patch size | 256 256 1 1 | same | |
| Mini-batch size | 32 | same | |
| Patches per image | 1 | same | 402 / 32 = 12 iterations per epoch |
| Max epochs | 30 (+10 continued) | **300** | 3600 iterations, about 115k patches; StarDist's default is about 160k (400 epochs x 100 steps x batch 4) |
| Initial learning rate | 0.003 | same | fastest early progress of the runs so far (validation loss 1.83 -> 0.74 in 360 iterations; 3.19 -> 1.81 in 120 at 0.0001) |
| Learning rate schedule | none | **piecewise, drop period 50, drop factor 0.5** | 3e-3, 1.5e-3, 7.5e-4, 3.8e-4, 1.9e-4, 9.4e-5; reaches StarDist's 3e-4 around epoch 150 and calms the Core IoU, which jumped between 0 and 50% at a constant 0.003 |
| Validation frequency (per epoch) | 2 | same | |
| Output network | best-validation-loss | same | |
| L2 regularization | 1e-4 | same | StarDist has none; small enough to keep |
| Augmentation FillValue | 255 | **0** | see below |
| Augmentations | all enabled, as listed in the window | same | |
| Random seeds | 3 / 1 | same | |

Expected time: 30 epochs took 8 min, so about 80 min for 300 epochs.

**FillValue, measured 2026-10-24** on a training patch with the project's augmentation settings
(500 draws): 90% of the patches are changed by augmentation, 77% geometrically. 25% contain
fill pixels from rotation or shear, median 3% and up to 7.6% of the patch (a 10 degree rotation
fills 7.7%, a 10 degree shear 4.6%). The fill is **not masked from the loss**: the label map is
warped with fill 0 = background, and the StarDist loss covers every pixel (BCE on the
probability, background regulariser on the distances). On this image 255 normalises to 3.2,
while objects reach 1, so the network is taught that very bright corners are background. Small
effect, but 0 (dark, as the background of fluorescence images) is the right value here.

**Fill avoided, 2026-10-25** (SOLOv2 and StarDist): with augmentation, `readInstancePatch` reads
the training patch with a margin of real image (`.margin`, `.fillValue`; the window itself is
picked as before), `augmentInstanceData2D` warps the larger patch and crops its centre back
(`.patchSize`, `.minObjectArea` for SOLOv2), so fill remains only beyond the image border.
Validation keeps no margin. The margin, `deepmib.instanceAugmentationMargin`, is the worst case
over all combinations of the enabled geometric augmentations at the ends of their ranges, in
their application order (patch corners traced back through the inverse maps, convex hull kept
per step), + 2 px for the cubic kernel; it is conservative: for the test augmentations (rotation
45, scale 0.7-1.3, x/y scale 0.8-1.2, x/y shear 20, rot90) it gives 60 px on a 32 x 48 patch, and
50 px already showed no fill in 300 worst-case draws; without a margin all 300 had fill.
Measured with the example project's settings (FillValue 255 as a marker, 300 patches per row,
margin 53 px, so 362 x 362 is read for a 256 x 256 patch):

| Training images | Margin | Patches with fill | Fill pixels | ms / patch |
|---|---|---|---|---|
| larger than the patch (155 of 402) | 0 | 88 | 0.93% | 13.0 |
| | 53 | 47 | 0.20% | 15.5 |
| exactly 256 x 256 (247 of 402) | 0 | 123 | 1.13% | 11.1 |
| | 53 | 98 | 0.78% | 12.7 |

The patch-sized DSB images have no image around the window, so the example project gains
little; the remaining fill of the larger images comes from windows at the image border.
Tests: `tests/deepmib/InstanceAugmentationTest.m` (7 Unit tests, constant image: any fill pixel
in a cropped patch fails). Side effect: a 90-degree rotation of a non-square patch is now cropped
back to the patch orientation. The semantic workflows (`augmentAndCrop2dPatchMultiGPU`) still
fill their corners.

**Judging the run:** Evaluate segmentation in the Predict tab against `02_predict/Labels`. The
semantic evaluation could not do this (`pixelLabelDatastore` takes uint8 only, and every object
id would be a class), so on 2026-10-24 the 2D Instance workflow got its own,
`evaluateSegmentationInstances` (StarDist-style one-to-one matching at IoU thresholds, F1 /
precision / recall / panoptic quality per threshold, per-image tables, MATLAB / MAT / Excel / CSV
export). Checked on the 50 test predictions: the same TP / FP / FN as the independent matching
script used for the phase 3 table (2177 / 119 / 283 at IoU 0.5), 2.9 s. Reference:
`2D_versatile_fluo` F1 0.914 at IoU 0.5 and 0.844 at IoU 0.7; the 2026-10-24 random run
0.786 / 0.433. Suggested target for the example: at least 0.88 / 0.75.

**Run 2026-10-24, `stardist_random.mibDeep`** (300 epochs, patches per image 1, batch 32,
FillValue 0, validation every 4 epochs): **F1 0.887 at IoU 0.5 and 0.753 at IoU 0.7** on the
50 test images (pretrained 0.914 / 0.844), so it meets the target. Validation loss 0.431 at its
best (iteration 3120 of 3600), thresholds tuned to 0.469 / 0.40. **The learning rate stayed at
0.003 for the whole run**: drop period 50 and factor 0.5 were set, but "Learning rate schedule"
was left at `none`, so the training history shows 0.003 throughout. Next run: the same with the
schedule set to `piecewise`.

**Run 2026-10-24 evening, piecewise schedule** (same settings, `piecewise` 50 / 0.5, so the rate
fell from 0.003 to 9.4e-5; same file `stardist_random.mibDeep`, the previous one is gone; plots
`Training_stardist_random.png` and `Training_stardist_random_fixed_LR.png`): **F1 0.873 at IoU 0.5
and 0.721 at IoU 0.7** (TP 2022 / FP 151 / FN 438), thresholds 0.482 / 0.30. Slightly worse than the
constant rate, within run-to-run noise at 0.5. In both runs the validation loss levels off at
about 0.45 by iteration 1500 and the training loss sits at the same level, so the network
under-fits: the schedule only smooths the curve. The random network has the same design as
`2D_versatile_fluo` (same `StarDistConfig` apart from the thresholds, 1 425 185 learnables), and
the pretrained model reaches a validation loss of 0.27-0.33 on the same data, so the limit is the
training recipe, not the network. Differences from StarDist's own training: 3600 weight updates at
batch 32 against 40 000 at batch 4 (the same number of patches), L2 1e-4 against none, and
stronger geometric augmentation (rotation, shear) against flips and 90-degree rotations.

**Run 2026-10-24 night, more weight updates** (`stardist_random_updated.mibDeep`, plot
`Training_stardist_random_updated.png`): batch 8, 4 patches per image, 75 epochs (the same 120 600
patches as before, but 15 075 updates instead of 3600), piecewise with drop period 15 and factor
0.5 (4 drops, the rate ended at 1.9e-4), L2 0, validation once per epoch; 1 h 36 min. **F1 0.908
at IoU 0.5 and 0.816 at IoU 0.7** (TP 2160 / FP 138 / FN 300), thresholds 0.479 / 0.30, validation
loss about 0.37. Objects are found almost as well as by `2D_versatile_fluo` (FN 300 against 294);
what remains is outline accuracy at IoU 0.7 (0.816 against 0.844). Accepted for the example
project: it meets the target, and closing the last gap would need about 4x longer training.

**Packaged 2026-10-24:** `C:\temp\2D_Nuclei_StarDist.zip` (60 MB, top folder
`2D_Nuclei_StarDist`; the user's project folder with `stardist_random.mibDeep/.mibCfg` = the batch 8
network, a `README.md` with data origin, licences and citations; project files checked
pixel-identical to the sorted `dsb2018.zip` files). To be uploaded as
`http://mib.helsinki.fi/tutorials/deepmib/2D_Nuclei_StarDist.zip`, the URL used by the new ribbon
item **Home -> Example datasets -> DeepMIB projects -> 2D LM Nuclei, StarDist** (`addRibbonHome`,
`MibRibbon`, `homeExamples_Callback`, icon `examples_stardist_24px.png`) and its entry in
`docs/docs/user-interface/ribbon/home/index.md`. No Zenodo record yet. Decided with the user: no
StarDist training defaults in DeepMIB; the recommended settings for a new network are in
`deepmib-instance.md`, section "Training a new StarDist network".

**Network replaced 2026-10-25:** the project now ships the run with the rotation fix (same
settings, 1 h 39 min; F1 0.906 / 0.809, thresholds 0.472 / 0.30, validation loss about 0.39
against 0.37 of the earlier run), as it represents the current code. Against the earlier network
(0.908 / 0.816) the difference is within run-to-run variation: per image better on 17 and worse
on 14 of the 50 test images, mean per-image F1 +0.005 (95% bootstrap interval -0.003 to +0.013).
The README was updated; the zip has to be rebuilt and uploaded again.

**Original plan:** put the settings into the StarDist section of
`docs/docs/deepmib/deepmib-instance.md` (training from random weights needs many more
iterations than fine-tuning, with a dropping learning rate), consider a StarDist default for
the learning rate and schedule when the architecture is selected (not decided), then package
the project (images, labels, network, `.mibCfg`) for Zenodo and add the Home -> Example datasets
entry.

### Phase 8: pretrained model without training

**Code done 2026-10-24, GUI test pending.** Until now a `.mibDeep` file was written only at the
end of training, so even the pretrained model needed preprocessed labels and a training run before
it could predict. Prediction itself needs only `net`, `inputPatchSize` and `StarDistConfig` from
the file, which `loadPretrained` already provides.

- New `createStarDistFromPretrained.m`: asks for the filename (default
  `2D_versatile_fluo.mibDeep` in the folder of the current network), loads the model with
  `loadPretrained` (cancelable, downloads on first use) and writes `.mibDeep` + `.mibCfg`. The
  `StarDistConfig` is the model's own, with the `thresholds.json` thresholds and the
  normalisation percentiles of `StarDistOpt`; the file then becomes the Network filename.
- New `saveStarDistNetwork.m`: the save block of `startTrainingStarDist`, now shared by both
  call sites, so a pretrained file and a trained one are identical in layout (Check network,
  custom thresholds, "Continue training" all work on it).
- Two places to reach it (decided with the user): a `uiconfirm` in `selectArchitecture` when
  the user picks StarDist in the dropdown (only with the dropdown's event, so `loadConfig` and
  `selectWorkflow` never show it; skipped when the current network file already holds
  `StarDistConfig`), and a checkbox "Create a network file from the pretrained model" in
  `setStarDistSettings` (`inputUniversalDlg` has no buttons; runs after OK, as the ray check).
- Rejected: choosing a pretrained model by name in the Predict tab (the filename is assumed by
  `selectNetwork`, the config sync, Check network, preview and evaluation, and there is no place
  for re-tuned thresholds), and training with 0 epochs (`trainnet` needs at least one, and the
  labels would still be required).
- User docs: section "StarDist: prediction without training" in `deepmib-instance.md`, linked
  from its intro, overview and settings list, and from `deepmib-networks.md`.

Still to test in the DeepMIB window: the dropdown dialog (shown on picking StarDist, not on
loading a config or a StarDist network), the settings checkbox, cancel at the save dialog and
during the download, prediction with the created file (expected: F1 0.914 / 0.844 on the 50
test images, as `2D_versatile_fluo` as downloaded in the phase 3 table), and "Downsample factor
for images" with StarDist (enabled, accepts 0.1-1, StarDist tooltip; disabled for SOLOv2; back to
`[1 Inf]` and the semantic tooltip after switching to a semantic workflow; state kept when the
prediction mode changes in 2D Instance).

**Scale factor (added 2026-10-24).** A pretrained model works only for nuclei of a size similar
to its training data. StarDist reuses the Predict-tab field "Downsample factor for images"
(`BatchOpt.P_ImageDownsamplingFactor`, until now read only by the semantic
`startPredictionBlockedImage` and silently ignored by 2D Instance although enabled): scale
`s = 1 / factor`. Decided with the user after a first version with its own `StarDistOpt.PredictScale`
spinner in two dialogs: one visible prediction setting instead of a hidden one next to an existing
field that does the same. For StarDist `selectArchitecture` lowers the limit to 0.1 (enlarging
for small nuclei), sets a StarDist tooltip and enables the field regardless of the prediction
mode; for SOLOv2 the field is disabled. Each slice is zoomed before detection, as StarDist
`predict_instances(img, scale=s)`: `scipy.ndimage.zoom` order 1 (reimplemented with
`griddedInterpolant`, corner pixels aligned, no antialiasing), then the kept centres and ray
lengths are divided by `s` and the polygons drawn at the original size (not a nearest-neighbour
resize of the label image). Checked by `verify_phase4.m` (check `scale`) against
`export_scale_reference.py` on three cases at 0.5 / 0.75 / 1.5 / 2: zoomed image equal to scipy
(max diff 3e-8), labels identical except 1 pixel in one case. The reference must use
`sparse=False`: with StarDist's default sparse candidates the dense image gave 246 objects at
scale 0.5 against 240 from StarDist's own dense NMS (= MIB).

Nucleus size of `2D_versatile_fluo`, measured on StarDist's DSB2018 subset (equivalent diameter
`sqrt(4*area/pi)`): training 447 images, 19 372 nuclei, median 21.1 px, quartiles 12.6 / 28.4,
5-95% 7.2-50 px; per-image medians 9.6-49 px (5-95%); test set median 22.5 px. The dialogs and
docs therefore say "about 20 pixels, most between 10 and 50" and suggest factor = diameter / 20;
the offer in `selectArchitecture` and the final message of `createStarDistFromPretrained` say so.

**Total estimate:** about 5-7 weeks of focused work, of which phase 0 decides whether the
rest is realistic.

## Risks

| Risk | Mitigation |
|------|------------|
| Keras -> MATLAB differences (padding, upsampling mode, kernel layout) silently shift outputs | Phase 0 compares maps numerically before anything is built on them |
| Raster NMS differs from the C++ NMS near the threshold | Measured in phase 0: 0-2 decisions in 48k candidates; the phase 2 MEX is the C++ itself |
| `trainnet` with one concatenated output and custom loss: GPU memory with 33 output channels at full patch size | Grid 2 reduces outputs 4x; reuse `findBestMinibatchSize` |
| Target generation slows training | Phase 1: MATLAB 0.1-0.2 s per 256x256 patch; phase 2 MEX about 5x faster, bit-identical |
| Users try StarDist on non-star-convex objects | Docs say when to use SOLOv2 instead; optional preprocessing check reporting how well N rays reconstruct the training labels (StarDist's own sanity check) |
| Pretrained licence restrictions | Check each model's licence before shipping; ship only what is permitted |

## Decisions

Answered 2026-10-23.

1. **Pretrained model distribution:** download on first use from `mib.helsinki.fi`, following
   the DeepMIB encoder pattern (`core.DownloadProgressMonitor` into `ExternalDirs.DeepMIBDir`).
   Not bundled. Details in phase 5.
2. **Which pretrained models:** `2D_versatile_fluo` now; `2D_versatile_he` after a licence
   check of the model and its training data (checked: not offered, see decision 6).
   `2D_paper_dsb2018` is not offered (it adds little over `versatile_fluo`).
3. **When the MEX NMS comes in:** first answered "raster first, MEX later". Revised
   2026-10-23 after phase 0 measured the raster NMS at 7-16x slower than C++: the MEX is now
   phase 2, before the DeepMIB integration. The raster NMS stays as the fallback.
4. **Ray reconstruction sanity check:** included in phase 3 (training integration).
5. **Where the StarDist settings live in the GUI** (2026-10-23): no `.mlapp` change; the
   settings button next to "Starting weights" opens the StarDist settings when StarDist is
   selected, and "Starting weights" lists the pretrained models.
6. **`2D_versatile_he`** (2026-10-23): not offered, because part of its training data (MoNuSeg
   2018) is CC BY-NC-SA 4.0; only `2D_versatile_fluo` (training data CC0) is shipped.
