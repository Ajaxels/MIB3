# Plan: ContrastNormalization Controller (MIB2 → MIB3)

## Problem Statement
Port `mibModel.contrastNormalization()` from MIB2 into a dedicated MIB3 controller
(`controllers.ContrastNormalization`) following the AppDesigner+BatchOpt conventions
established by `Alignment` and `ResampleDataset`.

---

## Key Decisions / Notes

| Topic | Decision |
|---|---|
| BatchOpt field `Exculude` | Keep the MIB2 typo to preserve backward-compatibility with saved batch scripts |
| `sessionSettings.ContNorm` | Store **all** BatchOpt user-facing fields (not only Mean/Std), so the dialog reopens exactly as the user left it |
| GUI modality | Non-modal (same as Alignment, ResampleDataset) |
| `getData2D` orient arg | `[]` (current orient), not `NaN` (MIB3 convention) |
| `setData2D` arg order | `(dataset, type, ...)` – data first, then type (MIB3 convention; MIB2 had type first) |
| `getData`/`setData` type `'model'` | → `'labels'` — irrelevant here (image only), but noted |
| `notify(obj, 'plotImage')` | → `notify(obj.mibModel, 'ShowImage')` |
| `notify(obj, 'syncBatch')` | → `notify(obj.mibModel, 'SyncBatch', eventdata)` |
| Waitbar | `uiprogressdlg(obj.mibModel.mibGUI, ...)` – no parfor used, so PoolWaitbar not needed |
| `getActiveId()` | Use in all default `BatchOpt.id` assignments |

---

## Files to Create

```
mib/+controllers/@ContrastNormalization/
    ContrastNormalization.m                         (class definition + constructor)
    gui_Callbacks.m                                 (central dispatcher)
    continueBtn_Callback.m                          (validate → backup → dispatch to target method)
    normalizeZStack_ContrastNormalization.m         (Z stack mode)
    normalizeTimeSeries_ContrastNormalization.m     (Time series mode)
    normalizeMaskedArea_ContrastNormalization.m     (Masked area mode)
    normalizeBackground_ContrastNormalization.m     (Background mode)
    collectSliceStats_ContrastNormalization.m       (shared low-level: per-z-slice mean/std)
```

---

## Class Structure – `ContrastNormalization.m`

### Properties
```
mibModel     handle to MibModel
view         handle to ContrastNormalizationGUI .mlapp (empty in batch mode)
listener     cell of listener handles
BatchOpt     structure compatible with batch processing
```

### Events
```
CloseEvent
```

### Static Methods
- `ViewListner_Callback2` — standard guard listener routing `UpdateGuiWidgets` / `NewDataset` → `updateWidgets`

### Public Methods (in class file)
- **Constructor** `ContrastNormalization(mibModel, varargin)`
  - Initialise `sessionSettings.ContNorm` if absent (defaults below)
  - Build `BatchOpt` defaults; restore from `sessionSettings.ContNorm` if present
  - **Batch path** (nargin==3): combine fields, call `continueBtn_Callback(true)`, return
  - **GUI path**: create `core.ChildView`, `addCallbacks()`, `updateWidgets()`, set listeners, show window
- **`closeWindow`** — save current BatchOpt to `sessionSettings.ContNorm`, delete view, delete listeners, `notify CloseEvent`
- **`returnBatchOpt`** — `notify(obj.mibModel, 'SyncBatch', ...)`
- **`updateBatchOptFromGUI`** — `utils.updateBatchOptFromGUI_Shared`
- **`updateWidgets`** — rebuild `ColChannel` dropdown items, enable/disable context-sensitive widgets (Mode→Mean/Std/ReferenceSliceNo, Target→MaskLayer/TimeSeriesNormalization panels), populate from `obj.BatchOpt`
- **`addCallbacks`** — wire all widget tags through the `gui_Callbacks` dispatcher

### Method Declarations (external files)
```matlab
gui_Callbacks(obj, source, event)
continueBtn_Callback(obj, useBatchMode)
normalizeZStack_ContrastNormalization(obj, colorChannel, options)
normalizeTimeSeries_ContrastNormalization(obj, colorChannel, options)
normalizeMaskedArea_ContrastNormalization(obj, colorChannel, options)
normalizeBackground_ContrastNormalization(obj, colorChannel, options)
[mean_val, std_val] = collectSliceStats_ContrastNormalization(obj, z1, z2, t, colorCh, useMask, options)
```

---

## BatchOpt Structure

| Field | Type | Default | Tooltip |
|---|---|---|---|
| `Target` | cell-string dropdown | `'Z stack'` | Normalization target |
| `Mode` | cell-string dropdown | `'Automatic'` | Automatic / Manual / BasedOnSlice |
| `Mean` | string | `'30000'` | Destination mean (Manual mode) |
| `Std` | string | `'3000'` | Destination std (Manual mode) |
| `ColChannel` | cell-string dropdown | `'All channels'` | Color channel(s) to process |
| `Exculude` | cell-string dropdown | `'Whole range'` | Outlier exclusion policy |
| `MaskLayer` | cell-string dropdown | `'selection'` | Source layer for mask (Masked area / Background) |
| `ReferenceSliceNo` | string | current slice | Reference slice for BasedOnSlice mode |
| `TimeSeriesNormalization` | cell-string dropdown | `'Based on current 2D slice'` | Per-frame vs. per-stack stats (Time series) |
| `showWaitbar` | logical | `true` | Show progress bar |
| `mibBatchSectionName` | string | `'Menu -> Image'` | Batch panel section |
| `mibBatchActionName` | string | `'Contrast -> Normalize layers'` | Batch action label |
| `mibBatchTooltip.*` | struct | (per-field strings) | Tooltips for batch UI |
| `id` | int | `getActiveId()` | Dataset index (removed before SyncBatch) |

---

## sessionSettings.ContNorm (persists across dialog open/close)

Initialised in constructor if absent:
```
sessionSettings.ContNorm.Target                  = 'Z stack'
sessionSettings.ContNorm.Mode                    = 'Automatic'
sessionSettings.ContNorm.Mean                    = '30000'
sessionSettings.ContNorm.Std                     = '3000'
sessionSettings.ContNorm.ColChannel              = 'All channels'
sessionSettings.ContNorm.Exculude                = 'Whole range'
sessionSettings.ContNorm.MaskLayer               = 'selection'
sessionSettings.ContNorm.ReferenceSliceNo        = '1'
sessionSettings.ContNorm.TimeSeriesNormalization = 'Based on current 2D slice'
sessionSettings.ContNorm.showWaitbar             = true
```
Saved in `closeWindow`; restored in constructor before building BatchOpt defaults.

---

## Execution Flow (`continueBtn_Callback`)

1. Resolve `parentFig` (view.gui in GUI mode, mibGUI in batch mode)
2. Check virtual mode → error + return
3. Check `'indexed'` color type → error + return
4. Check mask exists when Target ∈ {Masked area, Background} and MaskLayer == 'mask'
5. Backup: `obj.mibModel.mibDoBackup('image', 1, BatchOpt)` for single time point
6. Resolve `colorChannel` vector from `BatchOpt.ColChannel`
7. Resolve `outliers` from `BatchOpt.Exculude`
8. Resolve `[t1, t2, z1, z2]` ranges
9. Open `uiprogressdlg`
10. **Dispatch** to per-target method:
    - `'Z stack'`     → `normalizeZStack_ContrastNormalization`
    - `'Time series'` → `normalizeTimeSeries_ContrastNormalization`
    - `'Masked area'` → `normalizeMaskedArea_ContrastNormalization`
    - `'Background'`  → `normalizeBackground_ContrastNormalization`
11. Log to `updateImgInfo`
12. Close waitbar; `notify(obj.mibModel, 'SyncBatch', ...)` + `notify(obj.mibModel, 'ShowImage')`

---

## Low-Level Function Hierarchy

```
continueBtn_Callback
 ├── normalizeZStack_ContrastNormalization
 │    └── collectSliceStats_ContrastNormalization   (full-slice stats, no mask)
 ├── normalizeMaskedArea_ContrastNormalization
 │    └── collectSliceStats_ContrastNormalization   (masked stats)
 ├── normalizeBackground_ContrastNormalization
 │    └── collectSliceStats_ContrastNormalization   (masked stats)
 └── normalizeTimeSeries_ContrastNormalization
      (computes stats inline – getData2D for 2D slice or getData3D for full stack)
```

### `collectSliceStats_ContrastNormalization`
- Inputs: `z1, z2, t, colorCh, useMask, options`
  - `useMask = false` → full-slice stats (respecting `outliers`)
  - `useMask = true`  → stats only from `BatchOpt.MaskLayer` pixels
- Outputs: `mean_val(maxZ)`, `std_val(maxZ)` (NaN where mask is empty)
- Called with same `options` struct (contains `.id`, `.t`)

---

## GUI Widget List for `ContrastNormalizationGUI.mlapp`

All Tags must match exactly (used in `addCallbacks` and `gui_Callbacks`).

### Controls
| Tag | Type | Label | Notes |
|---|---|---|---|
| `Target` | DropDown | "Target" | Items: `{'Z stack','Time series','Masked area','Background'}` |
| `Mode` | DropDown | "Mode" | Items: `{'Automatic','Manual','BasedOnSlice'}` |
| `Mean` | EditField (text) | "Mean" | Enabled when Mode = Manual |
| `Std` | EditField (text) | "Std" | Enabled when Mode = Manual |
| `ReferenceSliceNo` | EditField (text) | "Reference slice No" | Enabled when Mode = BasedOnSlice |
| `ColChannel` | DropDown | "Color channel" | Items populated from dataset at runtime |
| `Exculude` | DropDown | "Exclude intensities" | Items: `{'Whole range','Excude blacks','Excude whites'}` (keep typo for batch compat) |
| `MaskLayer` | DropDown | "Mask layer" | Items: `{'selection','mask'}` — panel Enable = Target ∈ {Masked area,Background} |
| `TimeSeriesNormalization` | DropDown | "Time normalization" | Items: `{'Based on current 2D slice','Based on complete 3D stack'}` — panel Enable = Target == Time series |
| `showWaitbar` | CheckBox | "Show waitbar" | |

### Buttons
| Tag | Type | Label |
|---|---|---|
| `continueBtn` | Button | "Normalize" |
| `closeBtn` | Button | "Close" |
| `helpBtn` | Button | "Help" |

### Recommended Layout (for reference)
```
┌──────────────────────────────────────────┐
│ Target:       [Z stack ▾]                │
├──────────────────────────────────────────┤
│ Mode:         [Automatic ▾]              │
│ Mean:         [30000     ]  (grayed out) │
│ Std:          [3000      ]  (grayed out) │
│ Ref slice No: [1         ]  (grayed out) │
├──────────────────────────────────────────┤
│ Color channel: [All channels ▾]          │
│ Exclude:       [Whole range  ▾]          │
├─── Mask settings (enabled/disabled) ─────┤
│ Mask layer:   [selection ▾]              │
├─── Time series settings ──────────────── │
│ Time normalization: [Based on current ▾] │
├──────────────────────────────────────────┤
│ ☑ Show waitbar                           │
├──────────────────────────────────────────┤
│ [Normalize]  [Close]  [Help]             │
└──────────────────────────────────────────┘
```

---

## `gui_Callbacks` Dispatch Logic

```matlab
switch source.Tag
    case 'continueBtn'    → obj.continueBtn_Callback()
    case 'closeBtn'       → obj.closeWindow()
    case 'helpBtn'        → web(helpUrl, '-browser')
    case 'Target'         → update enable state of MaskLayer / TimeSeriesNormalization panels
                            obj.updateBatchOptFromGUI(source)
    case 'Mode'           → update enable state of Mean / Std / ReferenceSliceNo
                            obj.updateBatchOptFromGUI(source)
    otherwise             → obj.updateBatchOptFromGUI(source)
end
```

---

## Todos (Implementation Order)

1. Create `@ContrastNormalization/` folder structure
2. Write `ContrastNormalization.m` (class, constructor, closeWindow, returnBatchOpt, updateBatchOptFromGUI, updateWidgets, addCallbacks)
3. Write `gui_Callbacks.m`
4. Write `collectSliceStats_ContrastNormalization.m`
5. Write `normalizeZStack_ContrastNormalization.m`
6. Write `normalizeMaskedArea_ContrastNormalization.m`
7. Write `normalizeBackground_ContrastNormalization.m`
8. Write `normalizeTimeSeries_ContrastNormalization.m`
9. Write `continueBtn_Callback.m`
10. Verify with `buildtool check`
