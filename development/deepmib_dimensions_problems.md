# DeepMIB Dimension Problems

## Background

MIB2 stored images in `[Y, X, C, Z, T]` axis order (color = dim 3, depth = dim 4).
MIB3 stores images in `[Y, X, Z, C, T]` axis order (depth = dim 3, color = dim 4).

The DeepMIB prediction pipeline was ported to MIB3 but several places still
assumed the MIB2 axis order, causing dimension mismatches.

---

## Bug 1 — FIXED: `rgb2gray:invalidInputSize` in 2D prediction

**File:** `mib/+controllers/@MibDeep/processBlocksBlockedImage.m`

**Symptom:** `Error using rgb2gray — Invalid input image size` when running 2D
prediction on a grayscale or multi-channel image.

**Root cause:**
In MIB3, a 2D image arrives as `vol = [Y, X, Z=1, C]`.  Without squeezing,
`size(vol, 3) = 1` (the Z singleton), not C.  The check

```matlab
if dataDimension == 2 && size(vol, 3) ~= inputPatchSize(4)
    vol = repmat(vol, [1, 1, 3]);
end
```

compared Z (1) against the expected color count and incorrectly replicated vol
along dim 3, giving `[Y, X, 3, C]`.  `noColors` then computed to 3, which
triggered `rgb2gray` on a wrongly-shaped volume.

**Fix applied (lines 19–21):**
```matlab
if dataDimension == 2
    vol = squeeze(vol);  % MIB3 stores 2D images as [Y,X,1,C]; squeeze to [Y,X,C]
end
```

After squeezing, `size(vol, 3) = C` and the color-count check works correctly.

---

## Bug 2 — FIXED: `Index in position 3 exceeds array bounds` when displaying a
loaded model

**Files involved:**
- `mib/+core/@MibImage/MibImage.m` — constructor (`MibImage`, inherited by `MibLabels63`)
- `mib/+core/@MibDataset/loadModel.m`
- `mib/+core/@MibDataset/createModel.m`
- `mib/+core/@MibLabels63/getData63.m`
- `mib/+core/@MibImage/getData.m`
- `mib/+models/@MibModel/getRGBimage.m`

**Symptom:**
```
Index in position 3 exceeds array bounds.
Error in models.MibModel/getRGBimage (line 350)
if ~isnan(sOver1(1,1,1))
```
`sOver1` returned by `getData2D('labels', sliceNo≥2, ...)` has size `254×378×0`.

**Root cause — two interacting issues:**

### 2a. `MibImage` constructor misidentifies depth-3 label data as 3-channel image

`MibImage` constructor (lines 169–171) has a permute guard:
```matlab
if ndims(data)==3 && size(data, 3) < 4
    data = permute(data, [1 2 4 3]);   % [H,W,C] → [H,W,1,C]
end
```
This was designed for RGB images stored as `[H,W,3]` (color in dim 3).  For
label models, dim 3 is **depth**, not color.

MATLAB silently drops trailing singleton dimensions from `reshape`:
```matlab
reshape(rawModel, [H, W, 3, 1, 1])  % → [H,W,3]  (3D, NOT 5D)
```
So `ndims=3`, `size(data,3)=3 < 4` → the permute fires → data becomes `[H,W,1,3]`
→ `depth=1, colors=3`.

### 2b. Stale dim properties in the `bitand` fast path of `createModel`

When `createModel(63)` reuses the existing `MibLabels63` object (fast path), it
modifies `data{1}` in-place but never calls `initialize()`, leaving `depth`,
`width`, `height`, `time`, `colors`, and `dim_yxzct` at whatever values they had
before.

**Fixes applied:**

### Fix 1 — `MibImage.m` constructor (primary)

Added `&& strcmp(obj.type, 'image')` to the permute guard:
```matlab
% Before:
if ndims(data)==3 && size(data, 3) < 4
    data = permute(data, [1 2 4 3]);
end

% After:
if ndims(data)==3 && size(data, 3) < 4 && strcmp(obj.type, 'image')
    data = permute(data, [1 2 4 3]);
end
```
`obj.type` is set by the `switch class(obj)` block immediately above, so the check
is always valid.  Labels (`'labels'`, `'labels63'`) now pass 3D data through
untouched; dim 3 remains depth.

### Fix 2 — `loadModel.m` (use constructor instead of direct assignment)

Replaced:
```matlab
obj.createModel(modelType);
obj.labels.data{1} = rawModel;
```
with a fresh constructor call so ALL dimension properties derive from the actual data:
```matlab
obj.createModel(modelType);
modelMeta = core.MibImage.initializeImgInfo( ...
    'pixSize', obj.image.pixSize, ...
    'Height', modelH, 'Width', modelW, 'Depth', modelD, 'Time', modelT, 'Colors', 1);
if modelType == 63
    obj.labels = core.MibLabels63(rawModel, modelMeta);
else
    obj.labels = core.MibLabels(rawModel, modelMeta);
    obj.labels.maxMaterials = modelType;
end
```

### Fix 3 — `createModel.m` fast path dim sync

After the `bitand` in-place reuse, sync all six dimension properties:
```matlab
obj.labels.data{1} = bitand(obj.labels.data{1}, uint8(192));
[h, w, d, ~, t] = size(obj.labels.data{1});
obj.labels.height    = h;
obj.labels.width     = w;
obj.labels.depth     = d;
obj.labels.colors    = 1;
obj.labels.time      = t;
obj.labels.dim_yxzct = [h, w, d, 1, t];
```

### Fix 4 — Defensive clamping in `getData63.m` and `getData.m`

The Zlim (and Xlim/Ylim/Tlim) clamping now uses `size(obj.data{1},N)` instead of
the scalar properties, so a stale `depth` can never produce an empty range:
```matlab
% Before:
Zlim = [max([Zlim(1) 1]) min([Zlim(2) obj.depth])];
% After:
Zlim = [max([Zlim(1) 1]) min([Zlim(2) size(obj.data{1}, 3)])];
```

### Fix 5 — Empty-overlay guard in `getRGBimage.m`

```matlab
% Before:
if ~isnan(sOver1(1,1,1))
% After:
if ~isempty(sOver1) && ~isnan(sOver1(1,1,1))
```
Prevents a crash if `getData` ever returns a `[H,W,0]` array for any reason.

---

