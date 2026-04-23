# Performance Improvements for `getRGBimage.m`

## Context

`mib/+models/@MibModel/getRGBimage.m` is called on the display hot path — every pan, zoom, slice change, or frame change routes through `MibController.showImage` → `MibModel.getRGBimage`. Any latency here directly affects perceived UI responsiveness. The function is ~590 lines and performs many operations that have more efficient MATLAB equivalents (vectorization, avoiding `find()`, batching `imresize`/`imadjust` calls, reusing computed indices, using saturated arithmetic from the Image Processing Toolbox).

This plan enumerates concrete, low-risk optimizations with expected impact. Each change preserves the current behavior — pixel output should be bit-identical (or within rounding-equivalent) to the current implementation.

Target: reduce wall time on typical 2K×2K multichannel displays with model+mask+selection overlays. No new dependencies; all IPT functions used are already in regular use across MIB3.

---

## Optimizations (in priority order)

### 1. Cache subsampling indices (HIGH impact, trivial)

**Lines 138–139, 190–191, 207–208, 224–225, 471–472.** The expression `round(.51:magnificationFactor:end+.49)` is recomputed 4–5 times (image, model, mask, selection, final upscale). Each call materializes a full index vector.

Fix: compute once before the image-resize block:
```matlab
if magnificationFactor > 1
    rowIdx = round(.51:magnificationFactor:size(sImgIn,1)+.49);
    colIdx = round(.51:magnificationFactor:size(sImgIn,2)+.49);
end
```
and reuse `sImgIn(rowIdx, colIdx, :)` for all subsample branches. Separately cache the upscale indices (based on final H/W) for the `magnificationFactor < 1` block at line 471.

### 2. Preallocate the resized channel stack (LOW, trivial)

**Lines 142–148.** The per-channel `imresize` loop is intentional because the dataset may have any number of color channels (2, 4, 5+), not just 3. Keep the loop; only fix the growth pattern — `sImg` is currently allocated on `colCh == 1` via implicit assignment and then extended per channel.

Replace with a preallocation based on the first resize:
```matlab
first = imresize(sImgIn(:,:,1), 1/magnificationFactor, imageResizeMethod);
sImg = zeros([size(first,1), size(first,2), size(sImgIn,3)], 'like', sImgIn);
sImg(:,:,1) = first;
for colCh = 2:size(sImgIn,3)
    sImg(:,:,colCh) = imresize(sImgIn(:,:,colCh), 1/magnificationFactor, imageResizeMethod);
end
```
Minor win; mostly removes the array-growth hazard. Skip entirely if the benchmark shows no measurable effect.

### 3. Replace `stretchlim`+`imadjust` per-channel loop with single RGB call (MED)

**Lines 169–171 (live-stretch branch).** `stretchlim` and `imadjust` both accept H×W×C input natively and dispatch to optimized C for the RGB form.

Replace:
```matlab
for i = 1:size(sImg,3)
    sImg(:,:,i) = imadjust(sImg(:,:,i), stretchlim(sImg(:,:,i),[0 1]), []);
end
```
with:
```matlab
sImg = imadjust(sImg, stretchlim(sImg, [0 1]), []);
```

### 4. Single `imadjust` call for the 3-channel branches (MED)

**Lines 303–306, 310–313, 321–337.** The multichannel branches call `imadjust` three times on 2-D slices. `imadjust` accepts HxWx3 with 2×3 low/high matrices in one call:
```matlab
rgbIn  = [lowIn(:)'; highIn(:)'];       % 2×3
rgbOut = [lowOut(:)'; highOut(:)'];     % 2×3
adjRGB = imadjust(sImg(:,:,1:3), rgbIn, rgbOut, currViewPort.gamma(slices{4}(1:3)));
R = adjRGB(:,:,1); G = adjRGB(:,:,2); B = adjRGB(:,:,3);
```
Keep separate paths only for the <3-channel cases where RGB zero-fill is needed; in those cases a single 2-channel `imadjust` call can still replace two scalar calls.

### 5. Use saturated arithmetic for LUT grayscale blend (MED)

**Lines 262–264.** `sImg * selectedColorsLUT(1, 1)` where `sImg` is `uint8/16/32` promotes to double and back. `immultiply` does the same operation with native saturation and avoids the double temporary:
```matlab
R = immultiply(sImg, selectedColorsLUT(1,1));
G = immultiply(sImg, selectedColorsLUT(1,2));
B = immultiply(sImg, selectedColorsLUT(1,3));
```
Same pattern applies to the multichannel LUT loop (lines 285–296) — accumulate with `imadd(R, immultiply(adjImg, selectedColorsLUT(i,1)))` etc., which is saturated and single-pass.

### 6. Replace `find()` + per-channel indexed blend with whole-image `imlincomb` blend (HIGH)

**Lines 383–405 (model all-materials), 413–417 (selected material), 449–454 (mask), 459–463 (selection).** Current pattern:
```matlab
idx = find(M == k);   % or M ~= 0
R(idx) = R(idx) * T + color(1) * (1-T);
G(idx) = ...
B(idx) = ...
```
Problems: `find` materializes a full int64 index array; `R(idx)*T` promotes uint→double and back (3 temporaries × RGB); the same index vector is used for three near-identical operations.

Better pattern (pure logical indexing, in-place, no double cast):
```matlab
mask = M == k;
R(mask) = imlincomb(T, R(mask), (1-T)*color(1), 'uint8');
```
Or, when blending only a single color over many pixels, precompute the scalar once and use `imlincomb`, which is optimized for this exact operation.

For the "all materials" case (lines 383–405), the cleanest win is to build HxW per-pixel R/G/B target color maps via LUT lookup and use `imlincomb` once per channel:
```matlab
nz = M ~= 0;
% modColors lookup produces per-pixel target color
tgtR = zeros(size(R), 'like', R); tgtG = tgtR; tgtB = tgtR;
if dataset.labels.maxMaterials <= 65535
    tgtR(nz) = modColors(M(nz),1);
    tgtG(nz) = modColors(M(nz),2);
    tgtB(nz) = modColors(M(nz),3);
else
    cid = mod(M(nz)-1, 65535) + 1;
    tgtR(nz) = modColors(cid,1);
    % ...
end
R(nz) = imlincomb(T, R(nz), 1-T, tgtR(nz));
G(nz) = imlincomb(T, G(nz), 1-T, tgtG(nz));
B(nz) = imlincomb(T, B(nz), 1-T, tgtB(nz));
```
This is still one temporary per channel but with saturated native arithmetic and no double cast. Benchmark against both the current code and the `labeloverlay` alternative (see #7).

### 7. Evaluate `labeloverlay` for model/mask overlay (HIGH potential, needs verification)

**Lines 382–406 and 433–455.** `labeloverlay` (IPT, R2019a+) performs exactly the operation in the "all materials" block — blends a categorical label image into an RGB/grayscale image using a colormap and transparency, with optimized C implementation:
```matlab
% After building R,G,B, assemble preliminary imgRGB
imgRGB = cat(3, R, G, B);
imgRGB = labeloverlay(imgRGB, M, ...
    'Colormap', dataset.labels.materialColors, ...
    'Transparency', T);
```
This would replace 25+ lines per overlay with a single call. Caveats to verify before adopting:
- `labeloverlay` only outputs uint8 RGB — may require pre-converting uint16/uint32 paths (the existing grayscale/multichannel paths already produce `uint8` in most practical cases; need to confirm).
- Contour mode (the `M - imerode(M, strel)` path at line 366/371/377) still needs to run first; `labeloverlay` just replaces the blend.

Recommended: try `labeloverlay` behind a class-check guard (`if isa(R,'uint8')`) and fall back to #6 for uint16/uint32. If benchmarks show significant wins, promote it; otherwise keep #6.

### 8. Fix `max(max(sOver1))` → `max(sOver1, [], 'all')` (LOW, trivial)

**Line 421.** Nested `max(max(...))` allocates a 1×W intermediate; `'all'` dim is single-pass.

### 9. Use `'like'` class cloning and in-place zero-fill (LOW, trivial)

**Lines 162, 321, 326, 331, 336, 362, 364, 375, 423, 425.** Replace `zeros(size(X), class(X))` with `zeros(size(X), 'like', X)` (idiomatic, no class-name string eval). For `obj.hideImage`, `sImg(:) = 0` is faster than allocating a fresh array.

### 10. Contour-mode per-material loop is O(N_materials × H × W) (MED, nontrivial)

**Lines 360–369.** The "quality" contour mode creates a fresh mask and calls `imerode` for each material. For 30 materials on a 2K×2K image this is ~120 Mpix erosions. Alternative: use `boundarymask(M)` (IPT, R2018a+) to compute all label boundaries in a single optimized pass, then use the original labels' IDs where the boundary is true:
```matlab
bnd = boundarymask(M);
M2 = zeros(size(M), 'uint8');
M2(bnd) = M(bnd);
M = M2;
```
This loses the per-material thickness control (single-pixel boundary only). If thickness > 1 is required, dilate the boundary once:
```matlab
bnd = imdilate(boundarymask(M), strel('disk', thickness-1));
```
Verify visually against current output before replacing — this changes the "thickness" rendering slightly.

### 11. Minor: preallocate `pos` in the annotations block (LOW)

**Lines 546–562.** `pos` is grown column-wise without preallocation. Preallocate:
```matlab
pos = zeros(size(labelPos,1), 2);
```
before the branch. Negligible time, but removes an `mlint` warning.

---

## Critical Files to Modify

- `C:\Matlab\MIB3\mib\+models\@MibModel\getRGBimage.m` — the only file touched.

No API changes; the function signature, options struct, and return values stay identical.

## Reuse of Existing Utilities

All suggested replacements use functions already used elsewhere in MIB3:
- `imresize`, `imadjust`, `stretchlim` — used throughout `+core`, `+io`, `+controllers`.
- `imlincomb`, `immultiply`, `imadd` — used in `+core/@MibImage` and various filters.
- `labeloverlay`, `boundarymask` — new to this file; verify IPT availability (toolbox is already a hard dependency; R2019a+ is already required by MIB3's AppContainer usage).

## Verification

### Correctness (before any change)

1. Launch MIB3 (`cd C:\Matlab\MIB3\mib; mib3`), open a typical multichannel dataset with a model and a mask, and capture reference screenshots for each display mode:
   - grayscale, grayscale+LUT, multichannel 2/3/>3 channels, indexed
   - with/without model overlay (all materials + single selected)
   - with/without mask, with/without selection
   - contour mode on/off
   - zoomed in (magnificationFactor < 1), 1:1, zoomed out (>1)
   - virtual stacking dataset

2. Expose a test harness that calls `getRGBimage` with a saved `options` struct and checksums the result: `typecast(imgRGB(:), 'uint8')` → `DataHash` or SHA1. Run before and after each change.

### Performance (benchmark)

Create a small script that loads a 2K×2K, 3-channel, multi-material dataset and times 100 calls:
```matlab
options.blockModeSwitch = 0;
options.resizeToMagnification = true;
tic;
for k = 1:100
    imgRGB = obj.mibModel.getRGBimage(options);
end
t = toc/100;
fprintf('mean %0.2f ms\n', t*1000);
```
Record baseline, then apply changes incrementally (in the order above) and re-benchmark. Stop applying an optimization if its delta is < 2% and the code-clarity cost is high.

### End-to-end

- Run `buildtool check` (linter) after each edit — the file must not introduce new `mlint` warnings.
- Run `buildtool test` if any existing tests cover display.
- Manual UI smoke: open the target dataset, pan/zoom/slice through it; confirm no flicker, no color shift, overlays match the pre-change screenshots pixel-for-pixel (or within rounding for `imlincomb` vs manual promotion — tolerance ±1 LSB is acceptable).

## Out of Scope

- Changing `getData2D` return types (the `cell2mat` unwrap is an interface issue, not local to this function).
- Parallelizing with `parfor` (overhead dominates at single-slice sizes).
- GPU acceleration via `gpuArray` (adds install-time dependency risk).
- Refactoring R/G/B into a single HxWx3 working array throughout (large structural change; attempt only after #1–#6 land and measure).
