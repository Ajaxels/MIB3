# MIB2 → MIB3 Segmentation Tool Conversion Guide

Reference case: `mibSegmentationSpot` → `segmentationSpot`
(MIB2: `Classes/@mibController/mibSegmentationSpot.m` → MIB3: `+controllers/@MibImageDocument/segmentationSpot.m`)

---

## 1. File location and naming

| Aspect | MIB2 | MIB3 |
|--------|------|------|
| Location | `Classes/@mibController/mibSegmentationXxx.m` | `mib/+controllers/@MibImageDocument/segmentationXxx.m` |
| Method name | `mibSegmentationXxx` | `segmentationXxx` (drop `mib` prefix) |
| Class file declaration | not needed (all methods in `@mibController`) | add one line in `MibImageDocument.m` methods block |

### Register in MibImageDocument.m

Add a declaration line in the `methods` block of `MibImageDocument.m` (alphabetically near other `segmentation*` entries):

```matlab
segmentationXxx(obj, y, x, modifier, BatchOptIn)   % One-line description
```

### Update call sites

Search `gui_WindowButtonDownFcn.m` for the old `mibSegmentationXxx` call and rename:

```matlab
% old
obj.mibSegmentationXxx(ceil(h), ceil(w), modifier);
% new
obj.segmentationXxx(ceil(h), ceil(w), modifier);
```

---

## 2. Substitution table

### Core API

| MIB2 | MIB3 |
|------|------|
| `obj.mibModel.id` (default id) | `obj.mibModel.getActiveId()` |
| `obj.mibModel.mibDoBackup(type, sw, opts)` | `obj.mibModel.backup(type, sw, opts)` |
| `obj.mibModel.getData2D(type, z, orient, ch, opts)` | same — **type is first arg** (unchanged) |
| `obj.mibModel.setData2D(type, data, z, orient, ch, opts)` | `obj.mibModel.setData2D(data, type, z, orient, ch, opts)` — **data first, type second** |
| `obj.mibModel.getData3D(type, t, orient, ch, opts)` | same — **type is first arg** (unchanged) |
| `obj.mibModel.setData3D(type, data, t, orient, ch, opts)` | `obj.mibModel.setData3D(data, type, t, orient, ch, opts)` — **data first, type second** |
| `obj.plotImage()` | `obj.mibController.showImage()` |
| `notify(obj.mibModel, 'plotImage')` | `notify(obj.mibModel, 'ShowImage')` |
| `notify(obj.mibModel, 'updateUserScore')` | `notify(obj.mibModel, 'UpdateUserScore')` |

### UI handles

| MIB2 | MIB3 |
|------|------|
| `obj.mibView.handles.mibSegmSpotSizeEdit.String` | `obj.mibController.cSegmentation.handles.brushRadius.Value` |
| `obj.mibView.handles.mibActions3dCheck.Value` | `obj.mibModel.applySegmentationIn3D` |
| `obj.mibView.handles.mibSegmObjectPickerPanelSub2Width.String` | `obj.mibController.cSegmentation.handles.<widgetName>.String` |

> **Rule:** never use `obj.mibController.cSelection.handles.applySegmentationIn3D.Value` — use `obj.mibModel.applySegmentationIn3D` instead.

### Dialogs

| MIB2 | MIB3 |
|------|------|
| `errordlg(msg, title)` | `dlgOpt.MsgBoxOnly=true; dlgOpt.Icon='puffin_error'; dlgOpt.Header=msg; dlgOpt.HeaderLines=1; utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, title, dlgOpt)` |
| `waitbar(0, 'msg', 'Name', title)` + `waitbar(v,wb)` + `delete(wb)` | `wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', msg, 'Title', title); wb.Value = v; delete(wb)` |

### Batch boilerplate

| MIB2 | MIB3 |
|------|------|
| `BatchOpt.id = obj.mibModel.id` | `BatchOpt.id = obj.mibModel.getActiveId()` |
| `BatchOpt.mibBatchSectionName = 'Panel -> Segmentation'` | `BatchOpt.mibBatchSectionName = 'Ribbon -> Segmentation'` |
| `eventdata = ToggleEventData(BatchOpt)` | `eventdata = core.ToggleEventData(BatchOpt)` |
| `utils.updateBatchOptCombineFields_Shared` | same — exists in MIB3 |

---

## 3. Radius / size formula

Both spot and brush read from the same `brushRadius` spinner. Apply the same `-1` offset:

```matlab
radius = obj.mibController.cSegmentation.handles.brushRadius.Value - 1;
if radius < 1; radius = 0.5; end
radius = round(radius);
```

This gives `diameter = 2*radius + 1` in dataset pixels, matching the brush structural element at `magFactor = 1`.

> **Note:** the brush additionally divides by `magFactor` because it rasterises into the *displayed* image. The spot operates in full-resolution dataset coordinates, so no `magFactor` correction is needed.

---

## 4. Dispatch in gui_WindowButtonDownFcn

Every tool must have a `case` in the `switch tool` block of `gui_WindowButtonDownFcn.m`. Coordinates are converted with `convertMouseToDataCoordinates` before the call:

```matlab
case 'MyTool'
    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
    obj.segmentationMyTool(ceil(h), ceil(w), modifier);
    return;
```

Use `'shown'` mode with `round_flag=1` for 2D tools and `round_flag=0` for 3D tools.

---

## 5. User score

At the end of the method, increment the relevant counter and fire the event:

```matlab
obj.mibModel.preferences.Users.Tiers.numberOfXxx = obj.mibModel.preferences.Users.Tiers.numberOfXxx + 1;
notify(obj.mibModel, 'UpdateUserScore');
```

Counter names are defined in `+utils/+defaults/generatePreferences.m`. Add a new entry there if the tool is new.

---

## 6. Checklist

- [ ] Create `mib/+controllers/@MibImageDocument/segmentationXxx.m`
- [ ] Add method declaration in `MibImageDocument.m`
- [ ] Update `gui_WindowButtonDownFcn.m`: rename `mibSegmentationXxx` → `segmentationXxx`
- [ ] Use `getActiveId()` for default `BatchOpt.id`
- [ ] Use `obj.mibModel.applySegmentationIn3D` for the 3D checkbox
- [ ] `setData2D` / `setData3D`: data first, type second
- [ ] `getData2D` / `getData3D`: type first (unchanged from MIB2)
- [ ] Replace `waitbar` with `uiprogressdlg`
- [ ] Replace `errordlg` / `warndlg` with `utils.dlgs.inputUniversalDlg`
- [ ] Replace `obj.plotImage()` with `obj.mibController.showImage()`
- [ ] Batch section name: `'Ribbon -> ...'` not `'Panel -> ...'`
- [ ] Run `buildtool check` (or MATLAB Code Analyzer) on the new file
