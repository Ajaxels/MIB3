# Plan: Port mibSnapshotController to MIB3 Snapshot

## Context

MIB2's `mibSnapshotController` (GUIDE-based) ported to MIB3 as `+controllers/@Snapshot/Snapshot.m`. The `.mlapp` view (`+views/SnapshotGUI.mlapp`) already exists. The controller supports BatchOpt, the extraController path for volume viewer snapshots, and a new `AxesLimitsChanged` event replacing the old `modelNotify` approach.

**Key differences from MIB2:**
- Panels (`tifPanel`, `jpgPanel`, `bmpPanel`, `pngPanel`) replaced by `TabGroup` with tabs (`tifTab`, `jpgTab`, `bmpTab`, `pngTab`)
- `TargetButtonGroup` and `CropButtonGroup` are `uibuttongroup` (radio button groups)
- All widget access via `obj.view.handles.<Tag>` (lowercase `view`)
- AppDesigner dropdowns return string `.Value` directly (not numeric index)
- Spinners/NumericEditFields return numeric `.Value` (not string)

---

## Files Created/Modified

### 1. CREATED: `mib/+controllers/@Snapshot/Snapshot.m` ✅
Full controller port from MIB2 `mibSnapshotController.m`.

### 2. CREATED: `mib/+utils/addScaleBar.m` ✅
Port from `MIB2\Tools\mibAddScaleBar.m` with orientation 4→3 fix and removed legacy path.

### 3. MODIFIED: `mib/+models/@MibModel/MibModel.m` ✅
Added `AxesLimitsChanged` event to the `events` block.

### 4. MODIFIED: `mib/+controllers/@MibImageDocument/gui_ScrollWheelFcn.m` ✅
Uncommented and simplified to: `notify(obj.mibModel, 'AxesLimitsChanged');`

### 5. MODIFIED: `mib/+controllers/@MibController/listener_updateDatasetAxes.m` ✅
Uncommented and simplified to: `notify(obj.mibModel, 'AxesLimitsChanged');`

### 6. MODIFIED: `mib/+utils/mibImWrite.m` ✅
Updated docblock to RST format.

---

## Implementation Details

### AxesLimitsChanged Event
- Added to MibModel events block (after `UpdateUserScore`)
- Fired from `gui_ScrollWheelFcn.m` (zoom via mouse wheel) and `listener_updateDatasetAxes.m` (pan/resize)
- Listened by Snapshot controller to update dimensions when "Shown Area" crop is selected

### addScaleBar.m
- Function: `utils.addScaleBar(I, pixSize, scale, Options)`
- Orientation default: `3` (XY) instead of MIB2's `4`
- Removed `global DejaVuSansMono` and legacy `mibAddText2Img_Legacy` path
- Uses only `insertText` from Computer Vision Toolbox
- RST docblock

### Snapshot Controller
- `mibBatchSectionName = 'Ribbon -> Home'` (user corrected from 'Ribbon -> File')
- Constructor handles 3 modes: GUI, batch struct, NaN (return defaults)
- `addCallbacks()` only sets `CloseRequestFcn` — user wires other callbacks in `.mlapp`
- Listeners: `UpdateGuiWidgets`, `NewDataset`, `AxesLimitsChanged`
- All MIB2→MIB3 conversions applied:
  - `.String` → `.Value` for edit fields
  - Popup `.Value` (numeric index) → Dropdown `.Value` (string)
  - Spinner/NumericEditField `.Value` returns number directly
  - `orientation == 4` → `orientation == 3`
  - `notify(obj, 'updateId')` → `notify(obj, 'UpdateGuiWidgets')`
  - `waitbar` → `uiprogressdlg`
  - `questdlg` → `utils.dlgs.inputQuestDlg`
  - `warndlg` → `utils.dlgs.showErrorDialog`
  - `mibImWrite` → `utils.mibImWrite`
  - `mibAddScaleBar` → `utils.addScaleBar`
  - `ToggleEventData` → `core.ToggleEventData`
  - `BackgroundColor = 'g'` → `[0.149 0.902 0.1804]`
  - `BackgroundColor = 'r'` → `[1 0 0]`

---

## Widget Tag → BatchOpt Mapping

| Widget Tag | Type | BatchOpt Field | Notes |
|---|---|---|---|
| `TargetButtonGroup` | uibuttongroup | `Target` | Children: `File`, `Clipboard` |
| `CropButtonGroup` | uibuttongroup | `Crop` | Children: `FullImage`, `ShownArea`, `ROI` |
| `ROIIndex` | uidropdown | `ROIIndex` | |
| `Width` | uieditfield(text) | `Width` | |
| `Height` | uieditfield(text) | `Height` | |
| `ResizeMethod` | uidropdown | `ResizeMethod` | |
| `Scalebar` | uicheckbox | `Scalebar` | |
| `Measurements` | uicheckbox | `Measurements` | |
| `WhiteBackground` | uicheckbox | `WhiteBackground` | |
| `SplitChannels` | uicheckbox | `SplitChannels` | |
| `Grayscale` | uicheckbox | `Grayscale` | |
| `ColsNumber` | uispinner | `ColsNumber` | string in BatchOpt, numeric in widget |
| `RowsNumber` | uispinner | `RowsNumber` | string in BatchOpt, numeric in widget |
| `Margin` | uispinner | `Margin` | string in BatchOpt, numeric in widget |
| `FileFormat` | uidropdown | `FileFormat` | |
| `TIFcompression` | uidropdown | `TIFcompression` | |
| `JPGmode` | uidropdown | `JPGmode` | |
| `JPGquality` | uinumericeditfield | `JPGquality` | string in BatchOpt |
| `outputDir` | uieditfield(text) | — | not in BatchOpt |
| `jpgBitdepth` | uidropdown | — | not in BatchOpt |
| `jpgComment` | uieditfield(text) | — | not in BatchOpt |
| `tifColor` | uidropdown | — | not in BatchOpt |
| `tifResolution` | uinumericeditfield | — | not in BatchOpt |
| `tifRowsPerStrip` | uinumericeditfield | — | not in BatchOpt |
| `tifDescription` | uieditfield(text) | — | not in BatchOpt |
| `binCheck` | uicheckbox | — | local only |

---

## Verification Checklist

- [x] MATLAB code analyzer passes (only expected warnings remain)
- [ ] Launch MIB3 and open Snapshot dialog
- [ ] Clipboard snapshot (Full Image)
- [ ] File snapshot (TIF with lzw)
- [ ] File snapshot (JPG, PNG, BMP) — format switching updates TabGroup and extension
- [ ] Shown Area crop — zoom in, verify dimensions update
- [ ] ROI crop — add ROI, select it, verify crop
- [ ] Split channels — enable, verify montage output
- [ ] Scale bar — enable, verify bar appears on snapshot
- [ ] Width/Height change — verify aspect ratio lock
- [ ] Bin x2/x4/x8 buttons — verify dimension halving
- [ ] Volume viewer snapshot (if extraController is available)
- [ ] Batch mode via BatchProcessing with a BatchOpt struct
