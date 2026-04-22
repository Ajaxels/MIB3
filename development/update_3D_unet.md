# Update: 3D U-Net — unet3dLayers → unet3d Migration + Anisotropic Refactor

**Date:** 2026-04-22
**Author:** Ilya Belevich / Claude Code

---

## Background

`unet3dLayers` was removed in MATLAB R2026a and replaced by `unet3d`. Both functions accept the same Name-Value parameters (`EncoderDepth`, `NumFirstEncoderFilters`, `FilterSize`, `ConvolutionPadding`) and both return `[network, outputPatchSize]`. The key difference is the return type:

| Function | Returns | Training engine |
|---|---|---|
| `unet3dLayers` (removed in R2026a) | `layerGraph` | `trainNetwork` |
| `unet3d` (introduced in R2026a) | `dlnetwork` | `trainnet` |

`startTraining.m` already dispatches automatically based on `isa(lgraph, 'dlnetwork')` (line 539), so no changes were needed there. `startPrediction3D.m` uses `semanticseg()` which supports both types.

The work also refactored the anisotropic 3D U-Net creation into a reusable utility function and generalized it to support **N configurable 2D downsampling blocks** (previously hardcoded to 1).

**Biological rationale for N anisotropic blocks:** For datasets where Z voxel spacing is coarser than XY by a factor of 2^N, N rounds of 2D-only downsampling bring the effective resolution to isotropic before the 3D convolution stages begin.

---

## Plan

### 1. New utility: `mib/+utils/+deepmib/createAnisotropic3dUnet.m`

Standalone function — no `obj` dependency, explicit parameters:

```
function [lgraph, outputPatchSize] = createAnisotropic3dUnet(
    inputPatchSize, numClasses, filterSize, numFirstFilters,
    convPadding, encoderDepth, numAnisotropicBlocks)
```

- `numAnisotropicBlocks` optional, default `1`
- Must satisfy `numAnisotropicBlocks < encoderDepth`
- Uses `isMATLABReleaseOlderThan('R2026a')` to choose `unet3d` vs `unet3dLayers`
- Loops over encoder stages 1..N: replaces Conv-1, Conv-2 with `[f f 1]` kernels; MaxPool with `[2 2 1]` stride
- Loops over the mirroring decoder stages (stage `encoderDepth - k + 1`): replaces UpConv, Conv-1, Conv-2 with 2D variants
- Reads `NumFilters` from existing layers — avoids manual recalculation

### 2. `mib/+controllers/@MibDeep/createNetwork.m`

- **`'3D Semantic'` / `'U-net'`**: wrap `unet3dLayers` in `else` branch; add `unet3d` for R2026a+
- **`'3D Semantic'` / `'U-net Anisotropic'`**: replace ~60 lines of inline layer-replacement code with a single call to `utils.deepmib.createAnisotropic3dUnet(...)`

### 3. `mib/+controllers/@MibDeep/MibDeep.m`

- Add `BatchOpt.T_NumAnisotropicBlocks` (default `1`, range `[1 Inf]`) alongside existing encoder parameters
- Add tooltip string

### Files requiring no changes

| File | Reason |
|---|---|
| `updateNetworkInputLayer.m` | ~~`replaceLayer` + `'ImageInputLayer'` name work on `dlnetwork`~~ **FIXED** — `unet3d` names the input layer differently; line 88 changed to use `lgraph.Layers(1).Name` |
| `updateActivationLayers.m` | `lgraph.Layers` + `replaceLayer` work on `dlnetwork` |
| `startTraining.m` | `isa(lgraph,'dlnetwork')` dispatch already present; `trainnet` path fully implemented |
| `startPrediction3D.m` | `semanticseg()` supports `dlnetwork` in R2026a+ |

---

## Changes Performed

### `mib/+utils/+deepmib/createAnisotropic3dUnet.m` — CREATED

New file. Key implementation notes:

- Version branch via `isMATLABReleaseOlderThan('R2026a')` (available since R2020b)
- Encoder loop: for each anisotropic stage `i`, replaces `Encoder-Stage-i-Conv-1`, `Encoder-Stage-i-Conv-2`, `Encoder-Stage-i-MaxPool`
- Decoder loop: for each anisotropic stage `i`, the mirror decoder stage is `encoderDepth - i + 1`; replaces `Decoder-Stage-X-UpConv`, `Decoder-Stage-X-Conv-1`, `Decoder-Stage-X-Conv-2`
- Filter counts preserved by reading `lgraph.Layers(layerId).NumFilters` from the existing layer
- `'valid'` padding: sets `outputPatchSize = []` as before

### `mib/+controllers/@MibDeep/createNetwork.m` — MODIFIED

**`'U-net'` case (was lines 154–157):**
```matlab
% Before:
[lgraph, outputPatchSize] = unet3dLayers(inputPatchSize, numClasses, ...);

% After:
if ~isMATLABReleaseOlderThan('R2026a')
    [lgraph, outputPatchSize] = unet3d(inputPatchSize, numClasses, ...);
else
    [lgraph, outputPatchSize] = unet3dLayers(inputPatchSize, numClasses, ...);
end
```

**`'U-net Anisotropic'` case (was lines 158–218, ~60 lines):**
```matlab
% Before: full inline layer-replacement block

% After:
[lgraph, outputPatchSize] = utils.deepmib.createAnisotropic3dUnet(...
    inputPatchSize, obj.BatchOpt.T_NumberOfClasses{1}, ...
    obj.BatchOpt.T_FilterSize{1}, obj.BatchOpt.T_NumFirstEncoderFilters{1}, ...
    obj.BatchOpt.T_ConvolutionPadding{1}, obj.BatchOpt.T_EncoderDepth{1}, ...
    obj.BatchOpt.T_NumAnisotropicBlocks{1});
```

### `mib/+controllers/@MibDeep/MibDeep.m` — MODIFIED

Added after `T_FilterSize` (line ~424):
```matlab
obj.BatchOpt.T_NumAnisotropicBlocks{1} = 1;
obj.BatchOpt.T_NumAnisotropicBlocks{2} = [1 Inf];
```

Added tooltip:
```matlab
obj.BatchOpt.mibBatchTooltip.T_NumAnisotropicBlocks = ...
    'Number of initial 2D-only downsampling blocks before full 3D convolutions; ...
     for anisotropic datasets where Z spacing is coarser than XY (U-net Anisotropic only)';
```

---

## Current Status

### Done
- [x] `createAnisotropic3dUnet.m` created with N-block generalization and R2026a version branch
- [x] `createNetwork.m` — `'U-net'` case updated with `unet3d` / `unet3dLayers` version branch
- [x] `createNetwork.m` — `'U-net Anisotropic'` case replaced with utility function call
- [x] `MibDeep.m` — `T_NumAnisotropicBlocks` BatchOpt field and tooltip added

### Pending / To Verify
- [x] **Input layer name differs in `unet3d`** — confirmed that `unet3d` does NOT name the input layer `'ImageInputLayer'`; fixed in `updateNetworkInputLayer.m` line 88 by using `lgraph.Layers(1).Name` instead of the hardcoded string.
- [ ] **Encoder/decoder layer names in `unet3d`** — verify that `'Encoder-Stage-N-Conv-1'`, `'Encoder-Stage-N-MaxPool'`, `'Decoder-Stage-N-UpConv'` etc. are unchanged; used by `createAnisotropic3dUnet.m`.
- [ ] **Decoder stage numbering** for `encoderDepth > 2` — the assumption `Decoder-Stage-encoderDepth` mirrors `Encoder-Stage-1` was confirmed for `encoderDepth=2` from the existing code comment. Needs verification for depth 3 and 4.
- [ ] **UI widget for `T_NumAnisotropicBlocks`** — the field is accessible via BatchOpt (programmatic / batch processing) but no spinner has been added to the Deep MIB training panel. Add as follow-on task.
- [ ] **Test training** — 1 epoch with `pixelClassificationLayer` and `dicePixelCustomClassificationLayer` loss on R2026a, confirm `trainnet` is selected automatically.
- [ ] **Test prediction** — `startPrediction3D` on a small volume with a network trained via `unet3d`.

---

## Risks

1. **Layer names** — `unet3d` documentation does not explicitly guarantee the same layer name strings as `unet3dLayers`. Verify empirically.
2. **`updateSegmentationLayer` guard** — already present at `createNetwork.m` line 296: `if ~isa(lgraph, 'dlnetwork')`. Correctly skips adding a loss layer to the `dlnetwork` returned by `unet3d`.
3. **`'valid'` padding with anisotropic network** — `outputPatchSize = []` path still handled correctly in `createAnisotropic3dUnet.m`.
