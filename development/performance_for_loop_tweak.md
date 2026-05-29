# Performance Fix: Copy-on-Write in Per-Slice Loops

## Summary

A 15–200× slowdown in MIB3 vs MIB2 for image-processing operations was traced to copy-on-write triggered by an extra handle-class hop in the MIB3 data chain. The fix is to cache `obj.data{1}` in a local variable before per-slice loops, then write back once.

Measured impact:
- `DisplayAdjust.applyBtn_Callback` (imadjust per slice): **2.36 s → 0.16 s** (~15×)
- `convertImage` multichannel → grayscale (rgb2gray per slice): **3.17 s → ~16 ms** (~200×)

---

## Root Cause

### The chain difference

| | MIB2 chain | MIB3 chain |
|-|------------|------------|
| Path | `obj.mibModel.I{Id}.img{1}(...)` | `obj.mibModel.I{id}.image.data{1}(...)` |
| Handle hops before cell | **one** (`mibImage` handle from `I{Id}`) | **two** (`MibDataset` from `I{id}`, then `.image` → `MibImage`) |

Visually the chains look the same length, but MIB3 inserted a `MibDataset` wrapper between `I{id}` and the image data. That extra `.image` dereference crosses a second handle-class boundary.

### Why two hops break in-place modification

When MATLAB compiles `chain{1}(idx) = value`, it tries to mutate the cell's stored numeric array in place. In-place mutation is only valid if MATLAB can prove the cell array has a single reference. The proof traverses the assignment chain back through every `subsref/subsasgn` dispatch.

- **One handle in front** (MIB2): `mibImage.img{1}(idx) = val` — MATLAB resolves `img` as single-ref on the handle, mutates in place. No allocation per iteration.
- **Two handles in front** (MIB3): `MibDataset.image.data{1}(idx) = val` — analysis crosses an extra class boundary, MATLAB conservatively treats the cell content as shared, and triggers **copy-on-write of the entire array on every slice**. For a 512×512×100×3 uint8 dataset that's ~75 MB allocated and freed per slice.

### Why the local-variable fix works

```matlab
imageData = obj.mibModel.I{id}.image.data{1};   % shallow ref (cheap)
for z = 1:depth
    imageData(:,:,z,ch,t) = process(imageData(:,:,z,ch,t));
end
obj.mibModel.I{id}.image.data{1} = imageData;   % shallow ref back
```

Once `imageData` is a plain workspace variable, the LHS chain has **zero handles** in front of it. MATLAB sees a unique reference and mutates in place every iteration. The single read at the start and single write at the end each cost ~one reference bump.

### Why MIB2 wasn't affected

MIB2 stored `mibImage` handles directly in `obj.mibModel.I{Id}`. The cell array `img` was a property of that single handle — one hop, MATLAB's single-reference proof succeeded, in-place mutation kicked in. The visual length of the chain (`obj.mibModel.I{Id}.img{1}`) was identical to MIB3 but contained one less handle-class deref.

---

## The Fix Pattern

```matlab
% WRONG — triggers COW on every iteration
for z = 1:depth
    obj.mibModel.I{id}.image.data{1}(:,:,z,ch,t) = process(...);
end

% CORRECT — one read, one write
imageData = obj.mibModel.I{id}.image.data{1};
for z = 1:depth
    imageData(:,:,z,ch,t) = process(imageData(:,:,z,ch,t));
end
obj.mibModel.I{id}.image.data{1} = imageData;
```

### When this rule applies

| Caller location | Chain depth | At risk? |
|-----------------|-------------|----------|
| Controller / other class | `mibModel.I{id}.image.data{1}` — 2 handle hops | **YES** — always cache |
| Inside `MibImage` methods | `obj.data{1}` — 0 handle hops | Safe, but cache for very large loops to avoid future regression if refactored |
| Inside `MibLabels` / `MibLabels63` methods | `obj.data{1}` — 0 handle hops | Same — safe but cache for hot loops |

### Cancel-path handling

If a loop can return early on user cancel, flush the local back to the model before returning so partial work isn't lost:

```matlab
if pwb.getCancelState()
    obj.mibModel.I{id}.image.data{1} = imageData;
    pwb.deletePoolWaitbar();
    return;
end
```

---

## Files Changed

### `+controllers/@DisplayAdjust/DisplayAdjust.m` — `applyBtn_Callback`
- Cached `obj.mibModel.I{id}.image.data{1}` into `imageData` before nested t/z imadjust loop.
- Hoisted `viewPort.gamma(channel)` out of the loop.
- Cancel path flushes `imageData` back before return.
- **Result:** 2.361 s → 0.160 s

### `+core/@MibImage/convertImage.m`
Seven per-slice loops rewritten to use `imageData` local + single write-back. Some loops already used a local `I` cache for *reads*; the LHS writes still went through `obj.data{1}(...)` and triggered COW because `data` is a cell-array property (one hop within MibImage, not the two-hop case, but still measurably slow for tight loops).

Paths fixed:
- multichannel → grayscale (≤3 channels) — rgb2gray per slice
- indexed → grayscale — ind2gray per slice
- hsvcolor → multichannel — hsv2rgb per slice
- indexed → multichannel — ind2rgb per slice
- multichannel → hsvcolor — rgb2hsv per slice
- grayscale → indexed — gray2ind per slice
- multichannel (≤3) → indexed — rgb2ind per slice
- uint16 → uint16 (with viewport stretch) — imadjust per slice
- uint8 → uint16 (with viewport stretch) — imadjust per slice

Paths that were already safe (built local `I` or `img`, wrote `obj.data{1} = img` once):
- multichannel (>3) → grayscale (LUT blending)
- multichannel (>3) → indexed (LUT blending)
- uint16 → uint8, uint32 → uint8, uint32 → uint16 (already used local `img`)

**Result for the multichannel→grayscale path:** 3.168 s → ~0.016 s (~200×)

### `+core/@MibImage/rotateColorChannel.m`
Cached `obj.data{1}` before the nested t/slice `rot90` loop.

### `+core/@MibImage/replaceMaskedArea.m`
Cached `obj.data{1}` before the color-channel loop, even though only 1–3 channels — same pattern for consistency.

### `CLAUDE.md`
Added a `Copy-on-write in per-slice loops` subsection under MATLAB Coding Rules documenting the rule and a before/after example.

---

## Not Changed (Already Safe)

These were flagged in the audit but already use the correct pattern (read one z/t slab into a local `img`, modify, write back):

- `+core/@MibLabels/insertMaterial.m`
- `+core/@MibLabels63/insertMaterial.m`
- `+core/@MibLabels/squeezeMaterialLabels.m`

These iterate per time-point and pull one 3D `(:,:,:,1,t)` block into a local variable each iteration. That's the correct trade-off for large datasets: avoids holding two full 5D copies in memory while still mutating each block in place.

---

## Audit Methodology

To find similar hotspots in future work, search for the pattern:

```
obj.data{1}(...) = ...    inside a for loop
mibModel.I{*}.image.data{1}(...) = ...   inside a for loop
```

The `+core/@MibImage/*.m` and `+core/@MibLabels*/*.m` methods are the primary candidates because they own the bulk array operations. Any controller writing into the data chain inside a loop is also at risk.

Diagnostic check in MATLAB: wrap the loop with `tic/toc`. If per-iteration time is dominated by allocation rather than the actual processing function, copy-on-write is the cause. Confirm by caching to a local and re-timing.
