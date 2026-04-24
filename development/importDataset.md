# `MibModel.importDataset` — MIB2 → MIB3 Port

## Overview

`importDataset` imports an image, mask, or model layer from the MATLAB base workspace into the active MIB dataset.
It is the inverse of `exportDataset` and follows the same BatchOpt/interactive/batch architecture.

---

## Files Created

| MIB3 File | Role |
|-----------|------|
| `mib/+models/@MibModel/importDataset.m` | New method — all three layer types in one file |

## Files Modified

| File | Change |
|------|--------|
| `mib/+models/@MibModel/MibModel.m` | Added method signature after `exportDatasetToMib` |
| `mib/+controllers/@MibRibbon/homeImport_Callback.m` | Wired `'Import'` / `'MATLAB'` stubs → `importDataset('image')` |
| `mib/+controllers/@MibRibbon/maskImportSection_Callbacks.m` | Wired `'Import mask from MATLAB'` stub → `importDataset('mask')` |
| `mib/+controllers/@MibRibbon/modelImport_Callback.m` | Wired `sprintf('Import\nmodel')` stub → `importDataset('model')` |

---

## MIB2 Source Files

| MIB2 file (in `MIB2_RENAMED_FOR_MIB3\Classes\@mibController\`) | Used for |
|-----------------------------------------------------------------|---------|
| `menuFileImportImage_Callback.m` | Image import logic |
| `menuMaskImport_Callback.m` | Mask import logic (MATLAB workspace branch only) |
| `menuModelsImport_Callback.m` | Model import logic (MATLAB workspace branch only) |

---

## MIB2 → MIB3 Conversion Table

| MIB2 | MIB3 | Notes |
|------|------|-------|
| `clearContents(img, meta, enableSelection)` on `mibImage` | `obj.I{id}.initialize(img, meta, 'Standard', 'imageOnly', enableSelection)` on `MibDataset` | 4th arg `'imageOnly'` skips model/mask creation |
| `containers.Map` metadata | `dictionary(keys(m), values(m))` | Convert on import if input is `containers.Map` |
| `mibDoBackup('mask', 1, opts)` | `obj.backup('mask', 1, opts)` | |
| `setData3D('mask', mask, NaN, 4, NaN, opts)` | `setData3D(mask, 'mask', NaN, 3, NaN, opts)` | Data before type; orient 4→3 |
| `setData4D('mask', mask, 4, NaN, opts)` | `setData4D(mask, 'mask', 3, NaN, opts)` | Data before type; orient 4→3 |
| `setData2D('mask', mask, NaN, NaN, 0, opts)` | `setData2D(mask, 'mask', [], 3, NaN, opts)` | `[]` for current slice; orient 4→3 |
| `notify(obj.mibModel, 'newDataset')` | `notify(obj, 'NewDataset', core.ToggleEventData(id))` | Carries dataset id |
| `notify(obj.mibModel, 'plotImage')` | `notify(obj, 'ShowImage')` | |
| `obj.mibMaskShowCheck_Callback()` | `obj.showMask = true; notify(obj, 'ShowImage')` | |
| `obj.mibShowModelCheck_Callback()` | `obj.showModel = true; notify(obj, 'ShowImage')` | |
| `warndlg(msg, title)` | `inputUniversalDlg(..., MsgBoxOnly=true, Icon='puffin_error/warning')` | |
| `errordlg(msg)` | `utils.dlgs.showErrorDialog(obj.mibGUI, msg, title)` | |
| `mibInputMultiDlg({mibPath}, prompts, defAns, title)` | `utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defAns, title, opts)` | |
| `questdlg(msg, title, b1, b2, def)` | `utils.dlgs.inputQuestDlg(obj.mibGUI, msg, title, b1, b2, def)` | |
| `obj.mibModel.loadModel(model, opts)` from mibController | `obj.loadModel(model, opts)` from MibModel | Called as method on MibModel |
| `obj.mibModel.preferences.System.EnableSelection` | `obj.preferences.System.EnableSelection` | Already on MibModel |
| `obj.mibModel.I{id}.virtualImage` virtual check | `strcmp(obj.I{id}.datasetType, 'Virtual')` | |
| `obj.mibModel.I{id}.enableSelection == 0` | `obj.I{id}.enableSelection == 0` | |

---

## BatchOpt Fields

### Common
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `LayerType` | cell string | `{layerType, {'image','mask','model'}}` | Layer to import |
| `showWaitbar` | logical | `true` | Show progress dialog |
| `id` | double | `obj.getActiveId()` | Target dataset index (stripped before SyncBatch) |

### Image (`layerType = 'image'`)
| Field | Default | Description |
|-------|---------|-------------|
| `ImageVariable` | `'I'` | Workspace variable name (numeric array) |
| `MetaVariable` | `''` | Workspace variable name for metadata (containers.Map or dictionary); empty = skip |

### Mask (`layerType = 'mask'`)
| Field | Default | Description |
|-------|---------|-------------|
| `MaskVariable` | `'M'` | Workspace variable name (numeric or logical array) |

### Model (`layerType = 'model'`)
| Field | Default | Description |
|-------|---------|-------------|
| `ModelVariable` | `'O'` | Workspace variable name — numeric array, or struct with fields listed below |

Struct fields recognised for model import:
- `.model` (or `.modelVariable`) — the numeric array
- `.modelMaterialNames` — cell array of material names
- `.modelMaterialColors` — Nx3 RGB colour matrix
- `.modelType` — 63 or 255 (auto-detected from max value if absent)
- `.labelText` / `.labelPosition` / `.labelValue` — annotation fields

---

## Key Implementation Details

### Variable enumeration (interactive mode)
`evalin('base', 'whos')` retrieves the workspace variable list. It returns a struct array; fields used: `.name`, `.class`, `.size`.

Class filters:
- **image / mask**: `{'uint8','uint16','uint32','uint64','int8','int16','int32','int64','double','single','logical'}`
- **model**: `{'uint8','uint16','uint32','struct'}`

The filtered struct array must be captured before accessing per-element fields:
```matlab
filteredVars = availableVars(idxNum);          % capture first
imageVarsDetails{i} = sprintf('%s: %s [%s]', filteredVars(i).name, ...
    filteredVars(i).class, num2str(filteredVars(i).size));
```
Directly indexing `availableVars(idxNum)(i).class` with a logical index expands to a comma-separated list and breaks `sprintf` ("Too many input arguments").

### Dropdown `defAns` format
`inputUniversalDlg` expects a **row** cell array ending with the default index:
```matlab
defAns = {[imageVarsDetails(:)', {defaultImgIdx}], [metaVars(:)', {defaultMetaIdx}]};
```
The `(:)'` transpose ensures row orientation regardless of how the cell was built. Forgetting this causes "Dimensions of arrays being concatenated are not consistent".

### Meta-variable list (image import)
The 'Do not import' sentinel must be a **cell**, not a bare char, when concatenating with the variables cell array:
```matlab
metaVars = [{'Do not import'}; {availableVars(idxMeta).name}'];  % cell concat
```
Using `['Do not import'; {cell}]` coerces the result to a char array and breaks the subsequent `[metaVars(:)', {idx}]` concatenation.

### double → integer conversion (image import)
Prompted with `inputQuestDlg` before converting. Smallest fitting type selected:
`uint8` (≤255) → `uint16` (≤65535) → `uint32` (≤4294967295). Values beyond uint32 abort with an error dialog.

### Missing colour-channel reshape (image import)
3-D arrays where dim 3 > 3 likely have Z stacked as the third dimension with no colour channel.
User is asked via `inputQuestDlg`; answering Yes reshapes `[H,W,Z]` → `[H,W,1,Z]`.

### Smart mask routing (mask import)
```matlab
if size(maskData,3) == 1          → setData2D  (single slice)
elseif size(maskData,4) == 1      → setData3D  (full Z stack, single time)
else                              → setData4D  (full 4D)
```
Uses orient `3` (XY native) and `blockModeSwitch = 0`.

### Model: struct vs numeric
`isstruct(varIn)` branches:
- **struct** — extracts `.model` field (or `.modelVariable` override), reads optional metadata fields into `loadOpts`
- **numeric** — used directly; `modelType` inferred from `max(array(:))` (63 if < 64, else 255)

Delegates entirely to `obj.loadModel(modelArray, loadOpts)`.

---

## Bugs Found and Fixed During Implementation

| Error | Location | Cause | Fix |
|-------|----------|-------|-----|
| `Too many input arguments` | line ~118 | Logical-indexed struct array expanded to CSL before accessing `.class` inside `sprintf` | Capture filtered struct first: `filteredVars = availableVars(idxNum)` |
| `Dimensions of arrays being concatenated are not consistent` (1st) | line ~132 | `imageVarsDetails` / `maskVarsDetails` / `modelVarsDetails` were Nx1 (column); `{defaultIdx}` is 1×1; horizontal concat failed | Added `(:)'` transpose: `[xxxDetails(:)', {defaultIdx}]` for all three defAns |
| `Dimensions of arrays being concatenated are not consistent` (2nd, latent) | line ~127 | `metaVars` built by `['Do not import'; cell]` — bare char + cell → MATLAB produces char array, which then fails in the row-concat on line 132 | Changed to `[{'Do not import'}; cell]` so result is a proper cell array |

---

## Current Status (2026-04-25)

| Feature | Status |
|---------|--------|
| Image import — interactive dialog | Implemented; three known runtime bugs fixed |
| Image import — batch mode | Implemented |
| Mask import — interactive dialog | Implemented |
| Mask import — batch mode | Implemented |
| Model import — interactive dialog | Implemented |
| Model import — batch mode | Implemented |
| Ribbon wiring (Home / Mask / Model) | Done |

**Not yet tested end-to-end** — the three runtime bugs were fixed progressively during the session. The function has not been confirmed to run to completion in all three paths. The following manual tests from the verification checklist should be run next:

1. `I = uint16(rand(100,100,3,20)*1000)` → Ribbon → Home → Import → MATLAB → select `I`
2. Double conversion: `I2 = rand(100,100)` → import → confirm uint8 conversion dialog → verify dataset
3. Reshape prompt: `I3 = rand(100,100,10)` → import → Yes → verify 4-D `[100,100,1,10]`
4. `M = zeros(100,100,20,'uint8'); M(40:60,40:60,:)=1;` → Ribbon → Mask → Import mask from MATLAB
5. Mask mismatch: `M3 = zeros(50,50,'uint8')` → import → verify error dialog
6. Model (struct): `O = struct('model',uint8(zeros(100,100,20)),'modelMaterialNames',{{'mat1'}},'modelType',63)` → Ribbon → Model → Import model
7. Model (raw): `O2 = uint8(zeros(100,100,20))` → import → verify model created
8. Batch discovery: `obj.mibModel.importDataset('mask', NaN)` → verify SyncBatch fires
