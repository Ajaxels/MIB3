# moveLayers Conversion: MIB2 → MIB3

## Overview

Ported `mibModel.moveLayers` and 6 fast-path helper methods from MIB2 to MIB3. This is the core function for moving segmentation data between selection, mask, and model layers.

## Files Created

| MIB3 File | MIB2 Source | Class |
|-----------|-------------|-------|
| `+models/@MibModel/moveLayers.m` | `@mibModel/moveLayers.m` | MibModel |
| `+core/@MibDataset/moveMaskToSelectionDataset.m` | `@mibImage/moveMaskToSelectionDataset.m` | MibDataset |
| `+core/@MibDataset/moveMaskToModelDataset.m` | `@mibImage/moveMaskToModelDataset.m` | MibDataset |
| `+core/@MibDataset/moveModelToSelectionDataset.m` | `@mibImage/moveModelToSelectionDataset.m` | MibDataset |
| `+core/@MibDataset/moveModelToMaskDataset.m` | `@mibImage/moveModelToMaskDataset.m` | MibDataset |
| `+core/@MibDataset/moveSelectionToMaskDataset.m` | `@mibImage/moveSelectionToMaskDataset.m` | MibDataset |
| `+core/@MibDataset/moveSelectionToModelDataset.m` | `@mibImage/moveSelectionToModelDataset.m` | MibDataset |

## Files Modified

- `+core/@MibDataset/MibDataset.m` — added 6 method declarations
- `+models/@MibModel/MibModel.m` — added `moveLayers` declaration

## Property Mapping (MibDataset Helpers)

| MIB2 (`mibImage`) | MIB3 (`MibDataset`) |
|--------------------|---------------------|
| `obj.model{level}` | `obj.labels.data{level}` |
| `obj.selection{level}` | `obj.selection.data{level}` |
| `obj.maskImg{level}` | `obj.mask.data{level}` |
| `obj.modelType == 63` | `isa(obj.labels, 'core.MibLabels63')` |
| `obj.getData('labels', 4, idx)` | `uint8(obj.labels.data{1} == idx)` |

## API Mapping (moveLayers in MibModel)

| MIB2 | MIB3 |
|------|------|
| `obj.I{id}.modelType == 63` | `isa(obj.I{id}.labels, 'core.MibLabels63')` |
| `obj.I{id}.time` / `.depth` / `.height` / `.width` | `obj.I{id}.image.time` / `.depth` / `.height` / `.width` |
| `obj.getData4D(type, orient, col, opt)` | `obj.I{id}.getData4D(type, orient, col, opt)` |
| `obj.getData2D(type, slc, ori, col, opt)` | `obj.I{id}.getData2D(type, slc, ori, col, opt)` |
| `obj.setData4D(type, data, orient, col, opt)` | `obj.I{id}.setData4D(data, type, orient, col, opt)` — **data before type** |
| `obj.I{id}.clearSelection('3D', ...)` | `obj.I{id}.clearLayer('selection', '3D')` |
| `obj.mibDoBackup(...)` | commented out (not yet implemented) |
| `warndlg(msg, title)` | `utils.dlgs.inputUniversalDlg` with `MsgBoxOnly=true`, `Icon='puffin_warning'` |
| `msgbox(msg, title, 'error')` | same with `Icon='puffin_error'` |
| `waitbar(0, msg, 'Name', title)` | `uiprogressdlg(obj.mibGUI, ...)` |
| `ToggleEventData(1)` | `core.ToggleEventData(1)` |
| `notify(obj, 'plotImage')` | `notify(obj, 'ShowImage')` |
| `notify(obj, 'showModel', eventdata)` | `obj.showModel = true` |
| `notify(obj, 'showMask', eventdata)` + `obj.mibMaskShowCheck = 1` | `obj.showMask = true` |
| `BatchOpt.mibBatchSectionName = 'Menu -> ...'` | `'Ribbon -> ...'` |
| `doNotTranspose = 4` (no block mode) | `orient = 3` (YX, non-transposed) |
| `doNotTranspose = 0` (block mode) | `orient = []` (current orientation) |

## Performance Optimizations

### P1. Local variable for data arrays (high impact)
MIB2 repeatedly accessed `obj.model{options.level}` (4–6 property chain lookups per operation). MIB3 reads once into a local `D`, performs all bit operations, then writes back once:
```matlab
D = obj.labels.data{level};      % single read
D = bitor(D, bitand(D, 64)*2);   % pure array ops
obj.labels.data{level} = D;      % single write
```

### P2. Boolean flag instead of NaN sentinel (cleaner code)
MIB2 used `imgTemp = NaN` then `isnan(imgTemp(1))` in every branch. MIB3 uses `useFiltered` boolean and `filteredImg` array.

### P3. Strip x/y/z/t once in moveLayers (less code)
MIB2 helpers each started with 4 `isfield`/`rmfield` calls. MIB3 strips these fields once in `moveLayers` before calling helpers.

### P4. Reduced data passes for type-63 (medium impact)
Combined `bitset(D, 8, 0)` + `bitor(D, M)` into `bitand(D, 63)` + `bitor(D, M)` — clears selection and mask in one pass instead of two.

### P5. In-place clear instead of zeros allocation (low impact)
```matlab
% MIB2: obj.selection{level} = zeros(size(obj.selection{level}), class(obj.selection{level}));
% MIB3: selD(:) = 0;
```

## Architecture Notes

- **Fast path**: Full-dataset operations (no ROI/block mode) dispatch directly to the 6 `MibDataset` helper methods which manipulate packed data arrays
- **Slow path**: 2D/3D operations with ROI/block mode use `getData2D`/`getData4D` + modify + `setData2D`/`setData4D`
- `mibDoBackup` is not yet implemented in MIB3 — backup calls are commented out (consistent with `MibModel.clearLayer`)
- The MIB2 check `modelType == 128` (reject binary models) was removed; MIB3 `getData`/`setData` handles all model types

## Date
2026-03-22
