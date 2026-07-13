# Port Log: menuImageMode_Callback + convertImage → MIB3

## Summary

Ported MIB2's image format/bit-depth conversion pipeline to MIB3.  Three code
units were created or modified; two class declaration files were updated.

---

## Files Changed

| File | Action |
|------|--------|
| `mib/+core/@MibImage/convertImage.m` | **New** — low-level pixel converter |
| `mib/+models/@MibModel/changeImageMode.m` | **New** — batch-compatible orchestrator |
| `mib/+controllers/@MibRibbon/imageMode_Callback.m` | **Modified** — implement stub |
| `mib/+core/@MibImage/MibImage.m` | **Modified** — add `convertImage` to methods block |
| `mib/+models/@MibModel/MibModel.m` | **Modified** — add `changeImageMode` to methods block |

---

## MIB2 Sources

| MIB2 file | Role |
|-----------|------|
| `Classes/@mibImage/convertImage.m` | Pixel conversion logic — ported to `core.MibImage.convertImage` |
| `Classes/@mibController/menuImageMode_Callback.m` | Orchestration logic — ported to `models.MibModel.changeImageMode` |

---

## Data Layout Change (Critical)

MIB2 stored pixel data as **`[H, W, C, Z, T]`**.  MIB3 uses **`[H, W, Z, C, T]`**.
Every indexed access to `obj.img{1}` was mechanically transposed:

| Access | MIB2 | MIB3 |
|--------|------|------|
| Variable name | `obj.img{1}` | `obj.data{1}` |
| Slice at channel c, depth z, time t | `(:,:,c,z,t)` | `(:,:,z,c,t)` |
| Color dimension | `size(...,3)` | `size(...,4)` |
| Depth dimension | `size(...,4)` | `size(...,3)` |
| Allocate `[H,W,C,Z,T]` | `zeros([H,W,C,Z,T], cls)` | `zeros([H,W,Z,C,T], cls)` |

For functions that require `[H,W,3]` input (`rgb2gray`, `rgb2hsv`, `hsv2rgb`,
`rgb2ind`, `ind2rgb`), slices are assembled channel-by-channel:

```matlab
sliceRGB = zeros(H, W, 3, class(I));
sliceRGB(:,:,1) = obj.data{1}(:,:,i,1,t);
sliceRGB(:,:,2) = obj.data{1}(:,:,i,2,t);
sliceRGB(:,:,3) = obj.data{1}(:,:,i,3,t);
```

Results are written back the same way to avoid dimension-mismatch errors.

---

## Property Renames (`MibImage`)

| MIB2 | MIB3 |
|------|------|
| `obj.img{1}` | `obj.data{1}` |
| `obj.meta('ColorType')` | `obj.colorType` |
| `obj.meta('imgClass')` | `obj.dataClass` |
| `obj.meta('MaxInt')` | `obj.maxInt` |
| `obj.meta('Colormap')` | `obj.colormap` |
| `obj.meta('Colors')` | *(not needed; `obj.colors` is a direct property)* |
| `'truecolor'` color type | `'multichannel'` |
| `obj.slices{3}` (selected color channels on mibImage) | `options.selectedColorChannels` (passed in from MibDataset) |
| `obj.updateDisplayParameters()` | `obj.getDefaultViewPort()` |
| `obj.updateImgInfo(text)` | `obj.updateActionLog(text)` |

---

## `slices{}` Index Correction (MibDataset)

MIB2 stored selected color channels at `slices{3}`; MIB3 uses **`slices{4}`**
(because `slices{3}` is depth in MIB3):

| Index | MIB2 | MIB3 |
|-------|------|------|
| `slices{1}` | height range | height range |
| `slices{2}` | width range | width range |
| `slices{3}` | **color channels** | depth range |
| `slices{4}` | depth range | **color channels** |
| `slices{5}` | time point | time point |

The plan document erroneously listed `slices{3}` — corrected to `slices{4}` in
both `changeImageMode.m` (read) and the post-conversion sync (write).

---

## Dialog / UI Renames

| MIB2 | MIB3 |
|------|------|
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(parentFig, msg, title)` |
| `questdlg(msg,title,b1,b2,def)` | `utils.dlgs.inputQuestDlg(parentFig, msg, title, b1, b2, def)` |
| `mibInputDlg({mibPath}, prompt, title, def)` | `utils.dlgs.inputUniversalDlg(parentFig, '', {prompt}, {def}, title, struct())` |
| `msgbox(msg,'Error','error')` | `utils.dlgs.showErrorDialog(parentFig, msg, 'Error')` |
| `waitbar(v, wb, msg)` + `delete(wb)` | `uiprogressdlg(parentFig, ...)` + `delete(waitbar)` |
| `warndlg(msg, title)` | `utils.dlgs.inputUniversalDlg` with `MsgBoxOnly=true`, `Icon='puffin_warning'` |

`convertImage` falls back to the native MATLAB dialogs (`errordlg`, `questdlg`,
`inputdlg`) when `options.parentFigure` is empty, keeping the function usable
standalone without a GUI parent.

---

## `changeImageMode` vs MIB2 `menuImageMode_Callback`

| Aspect | MIB2 | MIB3 |
|--------|------|------|
| Owner class | `mibController` | `MibModel` |
| `id` default | `obj.mibModel.Id` | `obj.getActiveId()` |
| Virtual guard | `I{id}.Virtual.virtual == 1` | `I{id}.image.type == 'virtual'` |
| Color type access | `I{id}.meta('ColorType')` | `I{id}.image.colorType` |
| Colors count | `I{id}.colors` | `I{id}.image.colors` |
| LUT checkbox clear | `obj.View.handles.mibLutCheckbox.Value = 0` | `notify(obj,'UpdateGuiWidgets', ToggleEventData({'selectionPanel'}))` |
| Format map | `switch get(hObject,'tag')` | `dictionary(...)` |
| Selected channels | `obj.mibModel.I{id}.slices{3}` | `obj.I{id}.slices{4}` |
| Post-conversion sync | `obj.mibModel.I{id}.slices{3} = 1:colors` | `obj.I{id}.slices{4} = 1:colors` |
| SyncBatch | `notify(obj.mibModel, 'syncBatch', ...)` | `notify(obj, 'SyncBatch', ...)` |
| Redraw | `obj.updateGuiWidgets(); obj.plotImage()` | `notify(obj,'UpdateGuiWidgets',...); notify(obj,'ShowImage')` |

The LUT dialog check was refactored: MIB2 repeated it in both `'Grayscale'` and
`'Indexed'` switch arms; MIB3 runs it once before the format map with an
`ismember` guard.

---

## `imageMode_Callback` Stub → Implementation

The ribbon stub dispatched on `hWidget.Text` with empty `case` bodies.
Replaced with a single consolidated `case` that builds a minimal `BatchOpt` and
calls `obj.mibModel.changeImageMode(BatchOpt)`:

```matlab
switch mode
    case {'Grayscale', 'Multi-channel', 'HSV color', 'Indexed', '8 bit', '16 bit', '32 bit'}
        BatchOpt.Target = {mode};
        obj.mibModel.changeImageMode(BatchOpt);
    otherwise
        return;
end
```

The ribbon widget text strings match the `BatchOpt.Target` allowed values
directly, so no intermediate mapping is needed.

---

## Bug Fix vs MIB2

MIB2 `uint32 → uint16` (no viewport adjustment) used `uint8(...)` — clearly
wrong.  Fixed to `uint16(...)` in MIB3:

```matlab
% MIB2 (bug):
obj.img{1} = uint8(obj.img{1} / (maxIntValue/double(intmax('uint16'))));

% MIB3 (fixed):
obj.data{1} = uint16(obj.data{1} / (maxIntValue / double(intmax('uint16'))));
```

---

## Bit-Depth Loop Order

MIB2 inner loops iterated `t → c → z` which maps to `(5) → (3) → (4)` in its
`[H,W,C,Z,T]` layout.  MIB3 keeps the same logical order `t → c → z` but the
array indices change to `(5) → (4) → (3)` in `[H,W,Z,C,T]`:

```matlab
% MIB3 inner loops for uint8/uint16/uint32 conversions
for t = 1:obj.time
    for c = 1:obj.colors           % dim 4 in data{1}
        for z = 1:obj.depth        % dim 3 in data{1}
            img(:,:,z,c,t) = ...process obj.data{1}(:,:,z,c,t)...
        end
    end
end
```

---

## Post-Conversion Block (`convertImage`)

After every successful conversion the following properties are updated in order:

```matlab
obj.colors = size(obj.data{1}, 4);
obj.dim_yxzct = [obj.height obj.width obj.depth obj.colors obj.time];
% extend lutColors if new channels were added
numLutColors = size(obj.lutColors, 1);
if numLutColors < obj.colors
    obj.lutColors(numLutColors+1:obj.colors, :) = ...
        repmat(obj.lutColors(numLutColors,:), [obj.colors-numLutColors, 1]);
end
obj.getDefaultViewPort();       % resets obj.viewPort to defaults for new depth/class
obj.updateActionLog(['Converted from ' from ' to ' format]);
```

MIB2 also reset `obj.slices{3} = 1:obj.colors` here (on `mibImage`).  In MIB3
`slices` lives on `MibDataset`, so the reset is done in `changeImageMode` after
the call returns:

```matlab
obj.I{BatchOpt.id}.slices{4} = 1:obj.I{BatchOpt.id}.image.colors;
```

---

## Conversion Matrix (all 24 paths)

### Color-space conversions

| From → To | Behaviour |
|-----------|-----------|
| grayscale → grayscale | no-op, return 1 |
| multichannel (≤3 ch) → grayscale | pad to 3 ch, `rgb2gray` slice-by-slice |
| multichannel (>3 ch) → grayscale | LUT blend selected channels → RGB → `rgb2gray` |
| hsvcolor → grayscale | **error**: convert to RGB first |
| indexed → grayscale | `ind2gray` slice-by-slice; clear `obj.colormap` |
| grayscale → multichannel | replicate channel × 3 |
| multichannel → multichannel | no-op, return 1 |
| hsvcolor → multichannel | `hsv2rgb` slice-by-slice (uint8 only) |
| indexed → multichannel | `ind2rgb` × maxInt, cast to original class |
| grayscale → hsvcolor | **error**: convert to RGB first |
| multichannel (≠3 ch) → hsvcolor | **error**: must be exactly 3 channels |
| multichannel (=3 ch) → hsvcolor | `rgb2hsv` slice-by-slice (uint8 only) |
| hsvcolor → hsvcolor | no-op, return 1 |
| indexed → hsvcolor | **error**: convert to RGB first |
| grayscale → indexed | prompt gray levels → `gray2ind` |
| multichannel (≤3 ch) → indexed | prompt gray levels → `rgb2ind` |
| multichannel (>3 ch) → indexed | LUT blend → RGB → prompt levels → `rgb2ind` |
| hsvcolor → indexed | **error**: convert to RGB first |
| indexed → indexed | no-op, return 1 |

### Bit-depth conversions

| From → To | Behaviour |
|-----------|-----------|
| uint8 → uint8 | no-op, return 1 |
| uint8 → uint16 | viewport-adjusted `imadjust` stretch, or simple `× 257` |
| uint8 → uint32 | simple `× (2³²−1)/(2⁸−1)` |
| uint16 → uint8 | viewport-adjusted `imadjust / 255`, or simple `÷ 257` |
| uint16 → uint16 | viewport-adjusted `imadjust` in-place, or no-op return 1 |
| uint16 → uint32 | simple `× (2³²−1)/(2¹⁶−1)` |
| uint32 → uint8 | viewport-adjusted linear stretch, or simple `÷ (2³²−1)/(2⁸−1)` |
| uint32 → uint16 | viewport-adjusted linear stretch, or simple `÷ (2³²−1)/(2¹⁶−1)` |
| uint32 → uint32 | no-op, return 1 |

Gamma is not implemented for uint32 sources; a confirmation dialog is shown.
Indexed images block all bit-depth conversions with an error.

---

## Verification Checklist

1. `cd C:\Matlab\MIB3\mib; mib3` — app starts without errors
2. Open a dataset → Image ribbon → Mode → **Grayscale**: multichannel converts; ribbon checkbox updates
3. Mode → **Multi-channel**: grayscale → 3-channel; HSV option enables
4. Mode → **HSV color**: 3-ch multichannel converts; grayscale/indexed disable
5. Mode → **Indexed**: gray-levels dialog appears; conversion happens
6. Mode → **8 bit** / **16 bit** / **32 bit**: bit-depth cast; ribbon depth checkboxes update
7. Multichannel >3ch → Grayscale: LUT blending dialog; LUT checkbox disables after
8. Virtual dataset: conversion blocked with warning
9. Batch mode: `obj.mibModel.changeImageMode(NaN)` triggers `SyncBatch` with defaults
10. Undo (Ctrl+Z): image restored (backup taken before conversion)
11. `buildtool check` — no new code issues
