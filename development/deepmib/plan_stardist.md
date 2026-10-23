# DeepMIB: StarDist 2D as a native 2D Instance architecture

> **Status:** plan, 2026-10-23. Nothing implemented. Open questions at the end need an answer
> before phase 2.

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
| Grid | Outputs at `1/grid` resolution, targets subsampled by taking every `grid`-th pixel, offset `grid/2` | `config.grid`, e.g. `(2,2)` |
| Network | U-Net (depth 3, 32 base filters, 3x3 conv, ReLU, maxpool, upsampling + concat), then 3x3 conv with 128 filters, then two 1x1 heads: 1 channel sigmoid (prob), N channels linear (dist) | `StarDist2D` / `Config2D` defaults |
| Loss | `BCE(prob) + lambda * mean(abs(dist error) * prob_true)`, `lambda = 0.2` | `train_loss_weights=(1,0.2)`, `train_dist_loss='mae'` |
| Thresholds | Grid search of `prob_thresh` and `nms_thresh` on validation images, maximising mean matching accuracy over IoU thresholds | `optimize_thresholds`, stored in `thresholds.json` |
| Predict | Tiled forward pass -> prob map + dist map; candidates where prob > `prob_thresh`; greedy NMS by score with polygon IoU > `nms_thresh`; draw survivors into a label image, lowest score first | `predict_instances`, `non_maximum_suppression`, `polygons_to_label` |

The exact numbers above (layer counts, offsets, loss details) must be re-checked against the
StarDist source of the version whose pretrained weights are converted, in phase 0.

## What already exists (reuse, don't rewrite)

| Need | Existing code | Note |
|------|---------------|------|
| Workflow/architecture lists | `MibDeep.m:343-357` (`availableArchitectures`), `selectWorkflow.m`, `selectArchitecture.m` | Add `'StarDist'` to `architectureList{5}`; no encoder entry |
| Instance ground truth from MIB models | Preprocess tab -> instance label MAT files (`deepmib.saveInstanceLabelsParFor`, fields `imageFilename` + `instanceLabelMap`) | Architecture independent, reuse as-is. Verify in phase 2 |
| Patch sampling (object-seeded + random, seeded validation) | `deepmib.readInstancePatch` | Builds SOLOv2 GT and forces RGB; needs a label-map output mode |
| Instance augmentation | `deepmib.augmentInstanceData2D` | Works on `{image, boxes, labels, masks}`; needs a label-map mode (nearest interpolation for labels) |
| `trainnet` progress display, stop and emergency brake | `deepmib.customTrainingProgressDisplayTrainNet`, `deepmib.stopTrainingCallback`, semantic training path | StarDist trains with `trainnet`, not `trainSOLOV2`, so it follows the semantic path's stop handling |
| 2D -> 3D instance linking | `utils.instances.stitch2Dto3D` | Reuse for z-stacks |
| Prediction loop, file I/O, zarr input, output saving | `startPredictionInstances.m` | Add a StarDist branch where the slice is segmented; everything around it stays |
| Cross-tile instance stitching | `segmentBlockedImageInstances`, `segmentImageInstancesIoUMerge` | **Not used by StarDist**, see phase 3 |

## Design

### New package `mib/+deepmib/+stardist/`

Each function has at least two call sites (training, prediction, threshold search, tests),
so a package is justified.

| Function | Purpose |
|----------|---------|
| `createNetwork(config)` | `dlnetwork` for a config struct `.nRays .grid .nChannelIn .unetDepth .unetFilters .netConvAfterUnet`. Output: one `[H/g W/g 1+N]` tensor (prob + dist concatenated), so `trainnet` sees one output |
| `computeTargets(labelMap, config)` | `[H/g W/g 1+N]` single target: channel 1 = `edt_prob`, 2..N+1 = ray distances |
| `lossFunction(Y, T, lambda)` | BCE on channel 1 + prob-weighted MAE on distances; passed to `trainnet` as a function handle |
| `normalizeImage(img, pLow, pHigh)` | Percentile normalisation per channel, single precision |
| `predictMaps(net, img, config, tileOpt)` | Tiled forward pass with overlap, cores stitched into whole-image prob and dist maps |
| `nms(prob, dist, config, probThresh, nmsThresh)` | Candidates + greedy NMS. Calls the MEX when present, otherwise the raster fallback |
| `polygonsToLabel(points, dist, scores, imageSize, config)` | Draws kept polygons, lowest score first, `uint32` labels |
| `optimizeThresholds(net, valImages, valLabels, config)` | Grid search, cancelable, returns `[probThresh, nmsThresh]` |
| `loadPretrained(name)` | Loads a converted pretrained model (`.mat`: network, config, thresholds, licence text) |

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

Work in `development/deepmib/stardist_poc/`, outside `mib/`.

1. **Python reference (developer only).** In a separate env (`stardist`, TF CPU is enough):
   - export the `2D_versatile_fluo` weights, `config.json` and `thresholds.json`;
   - run `predict_instances` on 3-5 test images (dense, touching nuclei, one large image
     that needs tiling) and save `prob`, `dist`, final labels, polygon points and scores;
   - run `star_dist` and `edt_prob` on 2-3 label images and save the targets.
2. **Weight conversion.** Two candidate routes; try A first:
   - A: build the network with `createNetwork`, copy the weights layer by layer from the
     Keras `.h5` (`h5read`), keeping Keras HWIO kernel layout -> MATLAB `[h w in out]`.
   - B: `tf2onnx` in Python, then `importNetworkFromONNX` (the ONNX converter support
     package is installed). Faster to get running, but the imported graph is harder to
     fine-tune and to reconfigure.
3. **Raster NMS** in MATLAB.
4. **Compare** on the test images:
   - prob and dist maps: max abs difference < 1e-3 (float32 rounding between frameworks);
   - final labels: matching F1 at IoU 0.5 >= 0.98 against the Python labels;
   - NMS time per 2048x2048 image.

**Gate:** if the maps match but NMS is too slow, phase 4 (MEX) moves before phase 2. If the
maps do not match, stop and resolve before any DeepMIB work.

### Phase 1: core library (about 1 week)

Implement `+deepmib/+stardist/` from the PoC code, with full RST docblocks.

- `computeTargets`: the ray-stepping loop is vectorised over pixels per ray (N passes over
  the foreground pixels, each a stepped lookup into the label map). Check speed on a
  512x512 patch with ~200 objects; a MEX is only worth it if target generation stalls the
  GPU during training.
- `nms` (raster fallback):
  1. candidates = grid positions with prob > `probThresh`, sorted by score descending;
  2. polygon vertices from centre + rays (scaled by `grid`);
  3. for each candidate: bounding box, `poly2mask` inside the box only, overlap with the
     already accepted pixels, IoU approximated from pixel counts against the accepted object
     it overlaps most; accept if IoU <= `nmsThresh` and paint it;
  4. a quick rejection first: skip the mask if the candidate centre already lies deep inside
     an accepted object (StarDist does a similar radius check).
  The approximation is documented in the docblock; phase 0 measures how far it is from the
  exact result.
- `predictMaps`: tiling is done on the **dense maps**, not on instances. Overlap must cover the
  network's receptive field; cores are written into whole-slice maps, and NMS runs once on
  the whole slice. This removes the cross-tile instance stitching that SOLOv2 needs.
- Every loop that can run long (`optimizeThresholds`, tiling of large images) takes a
  progress handle and checks cancel, per the CLAUDE.md rule.

### Phase 2: DeepMIB training integration (about 1-1.5 weeks)

- `MibDeep.m`: `architectureList{5} = {'SOLOv2', 'StarDist'}`.
- `selectArchitecture.m`: StarDist case. Hide the encoder; show StarDist settings: pretrained
  model (`None`, `2D_versatile_fluo`, `2D_versatile_he`), number of rays and grid (locked when
  a pretrained model is chosen), input channels. Patch size must be divisible by
  `grid * 2^unetDepth`.
- BatchOpt fields for the new widgets, named exactly as the widgets
  (`utils.updateBatchOptFromGUI_Shared` rule).
- `readInstancePatch`: add `options.outputFormat` (`'solov2'` default, `'labelMap'` returns
  `{image, labelPatch}` at native channel count). Sampling logic stays shared.
- `augmentInstanceData2D`: add the label-map mode (same geometric transform, nearest
  interpolation and no intensity changes for the label map). Targets are computed **after**
  augmentation, because rotation changes the ray distances.
- New `startTrainingStarDist.m` instead of more branches in the 1341-line
  `startTrainingInstances.m`, which is SOLOv2-specific (`trainSOLOV2`, freeze phases,
  checkpoint recovery). Pipeline: `fileDatastore` + `readInstancePatch('labelMap')` ->
  `transform` (augmentation, normalisation, `computeTargets`) -> `trainnet(ds, net,
  @lossFunction, options)`. Fine-tuning a pretrained model uses a lower default learning rate.
- `start.m`: route `2D Instance` + `StarDist` to the new training method.
- After training: run `optimizeThresholds` on the validation set (cancelable), store the
  thresholds in the network file, and report them in the training summary.
- `checkNetwork.m`: StarDist preview via `analyzeNetwork` on `createNetwork(config)`.
- `findBestMinibatchSize.m`: StarDist cost depends on patch size, not object count, so use
  the semantic-workflow probe, not the SOLOv2 one.
- Config save/load: new BatchOpt fields go into `.mibCfg`; `loadConfig` defaults them for
  old configs.

### Phase 3: prediction integration (about 3-5 days)

- `startPredictionInstances.m`: when the network is StarDist, segment each slice with
  `normalizeImage` -> `predictMaps` -> `nms` -> `polygonsToLabel`, skip the RGB expansion,
  and disable the stitching-mode widgets (`P_OverlapInstancesMode`) in the GUI, since dense
  tiling has no instance seams.
- Thresholds: default from the network file; the existing `DetectionThreshold` setting in
  `OverlapInstancesOpt` maps to `probThresh`, and an NMS threshold field is added.
- Z-stacks: per slice, then `utils.instances.stitch2Dto3D` as for SOLOv2.
- Very large slices (whole-slide): phase 3 keeps whole-slice maps in RAM (`(1+N)` single
  channels at `1/grid^2` size, about 0.5 GB for 32 rays on a 16k x 16k slice at grid 2).
  Block-wise NMS for larger slices is deferred.

### Phase 4: MEX NMS (about 1 week)

- Compile StarDist's 2D NMS C++ (`stardist/lib/stardist2d.cpp` + Clipper) into
  `deepmib.stardist.nms_mex`, wrapping only the NMS entry point. Keep its OpenMP build if
  MSVC builds it cleanly.
- `nms` dispatches to the MEX when it exists, otherwise falls back to raster.
- Build script in `development/deepmib/stardist_poc/build_mex.m`; check that
  `deploymentScript.m` packs the `.mexw64`.
- Licences: StarDist BSD-3-Clause and Clipper (Boost) texts shipped next to the MEX and
  listed in MIB's third-party licences.
- Test: MEX vs raster vs exact `polyshape` IoU on synthetic polygons.

### Phase 5: pretrained models (about 2-3 days, can run in parallel with phase 2)

- Conversion script `development/deepmib/stardist_poc/convert_pretrained.py` (developer,
  one-off) -> `.mat` per model: weights, config, thresholds, source URL, licence.
- Distribution, see open questions.

### Phase 6: tests and documentation (about 3-4 days)

Tests (in the existing DeepMIB test location):
- `computeTargets` vs Python fixtures (exact prob, distances within 0.1 px);
- `nms`: synthetic overlapping polygons with a known correct result, MEX and raster;
- `polygonsToLabel` drawing order (higher score wins on overlap);
- `createNetwork` output size for several patch sizes and grids;
- end to end: converted `versatile_fluo` on a fixture image vs the Python labels (F1 at IoU 0.5).

Documentation:
- `docs/docs/deepmib/deepmib-instance.md`: StarDist section covering when to choose it over
  SOLOv2 (star-convex, dense, touching objects), pretrained models and fine-tuning, and the
  two thresholds. Behaviour only, per the CLAUDE.md audience table.
- RST docblocks for every `+stardist` function and the new controller method; `docs_api`
  entries.
- `development/deepmib/`: PoC measurements, raster-vs-exact NMS comparison, conversion notes.
- `development/INDEX.md`: link this plan.

**Total estimate:** about 5-7 weeks of focused work, of which phase 0 decides whether the
rest is realistic.

## Risks

| Risk | Mitigation |
|------|------------|
| Keras -> MATLAB differences (padding, upsampling mode, kernel layout) silently shift outputs | Phase 0 compares maps numerically before anything is built on them |
| Raster NMS differs from exact IoU near the threshold | Measured in phase 0; MEX in phase 4 is exact |
| `trainnet` with one concatenated output and custom loss: GPU memory with 33 output channels at full patch size | Grid 2 reduces outputs 4x; reuse `findBestMinibatchSize` |
| Target generation slows training | Measure in phase 1; MEX or precompute targets for non-augmented geometry if needed |
| Users try StarDist on non-star-convex objects | Docs say when to use SOLOv2 instead; optional preprocessing check reporting how well N rays reconstruct the training labels (StarDist's own sanity check) |
| Pretrained licence restrictions | Check each model's licence before shipping; ship only what is permitted |

## Open questions for the user

1. **Pretrained model distribution:** bundle the converted `.mat` files with MIB, or download
   on first use (from where)?
2. **Which pretrained models:** `2D_versatile_fluo` only, or also `2D_versatile_he` (RGB
   histology)? `2D_paper_dsb2018` adds little over `versatile_fluo`.
3. **Order of phases 2 and 4:** ship with raster NMS first and add the MEX later (current
   plan), or require the MEX from the start?
4. **Preprocessing sanity check** (ray reconstruction score of the training labels): include
   in phase 2 or defer?
