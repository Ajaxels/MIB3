# ActionLog Controller — Design Spec
Date: 2026-05-22

## Overview

Port MIB2's `mibLogListController` / `mibLogListGUI` to MIB3 as `controllers.ActionLog` with `views.ActionLogGUI`. Replaces the three push-buttons (insert, modify, delete) with a context menu on the log listbox.

## Data Source

MIB3 stores the action log in `MibImage.actionLog` — a plain `cell array` of timestamped strings, e.g.:

```
'MIB(2601041823): MIB demo dataset, Huh7 SBEM'
'MIB(2603131934): ImFilter: Gaussian, HSize:3 3, Sigma:0.6'
```

Populated at load time by `core.MibImage.splitImageDescription`; appended by model operations via `MibImage.updateActionLog`. **No pipe-parsing needed in the controller.** No "protected entry 1" — `boundingBox` is a separate property in MIB3.

Mutations go through `obj.mibModel.I{id}.image.updateActionLog(text, action, index)`.

## Files

| File | Role |
|------|------|
| `+controllers/@ActionLog/ActionLog.m` | Class definition, constructor, `closeWindow`, `addCallbacks` |
| `+controllers/@ActionLog/updateWidgets.m` | Populate `logList.Items` from `image.actionLog` |
| `+views/ActionLogGUI.mlapp` | View — created by user |

Launched via: `obj.mibController.startController('controllers.ActionLog')`

## Widget Names (`ActionLogGUI.mlapp`)

| Widget | Type | Purpose |
|--------|------|---------|
| `logList` | UIListBox | Displays action log entries; multi-select |
| `refreshButton` | UIButton | Refresh display |
| `logPrintButton` | UIButton | Print log to MATLAB console |
| `clipboardButton` | UIButton | Copy log to system clipboard |
| `closeButton` | UIButton | Close window |

`insertBtn`, `modifyBtn`, `deleteBtn` do **not** exist as widgets — replaced by context menu.

## Callbacks & Behavior

### `updateWidgets`
- Reads `obj.mibModel.I{id}.image.actionLog`
- Sets `logList.Items` to the cell array (empty cell `{}` → `{'No log entries'}`)
- Preserves current `logList.Value` if it still exists; otherwise resets to first item

### Context Menu (on `logList`)

**Insert**
- Gets last selected index; insert position = selected + 1 (or append if nothing selected)
- Prompts user via `utils.dlgs.inputUniversalDlg` for entry text
- Calls `image.updateActionLog(text, 'insert', pos)`
- Refreshes widgets; sets `logList.Value` to newly inserted item

**Modify** (single selection only)
- Strips `MIB(YYMMDDHHNN): ` prefix from the selected entry to expose the editable description
- Prompts user via `utils.dlgs.inputUniversalDlg` with pre-filled text
- Calls `image.updateActionLog(text, 'modify', pos)` — entry gets a new timestamp
- Refreshes widgets

**Delete** (multi-select supported)
- Shows confirmation dialog via `utils.dlgs.inputQuestDlg`
- Deletes entries in reverse index order via `image.updateActionLog('', 'delete', pos)`
- Resets `logList.Value` to first item; refreshes widgets

### Buttons

| Button | Action |
|--------|--------|
| `refreshButton` | `obj.updateWidgets()` |
| `logPrintButton` | `disp` each entry in `logList.Items` to MATLAB console |
| `clipboardButton` | `strjoin(logList.Items, '\n')` → `clipboard('copy', ...)` |
| `closeButton` | `obj.closeWindow()` |

### Key Press
Forward `KeyPressFcn` events to `mibModel` as `keyPressEvent` (same pattern as other MIB3 child windows).

### Listeners
Both `UpdateGuiWidgets` and `NewDataset` events → call `obj.updateWidgets()`.
Guarded by the standard `ViewListner_Callback2` static method.

## Constructor Pattern

Follows `DatasetInfo` / standard MIB3 child controller pattern:

```matlab
obj.mibModel = mibModel;
obj.view = core.ChildView(obj, 'views.ActionLogGUI');
obj.addCallbacks();
utils.fontSizeUpdate(obj.view.gui, Font);
obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'right');
obj.updateWidgets();
obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...);
obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...);
obj.view.gui.Visible = 'on';
```

## What Changes vs MIB2

| MIB2 | MIB3 |
|------|------|
| Log in `meta('ImageDescription')` (pipe string) | `image.actionLog` (cell array) |
| `updateImgInfo` call | `image.updateActionLog(text, action, index)` |
| Entry 1 protected (BoundingBox) | No restriction — any entry editable |
| Three push-buttons | Context menu on `logList` |
| `global mibPath` | `obj.mibModel.mibPath` |
| `global Font` | `obj.mibModel.preferences.System.Font` |
| `moveWindowOutside(h, 'right', 'bottom')` | `utils.moveWindowOutside(gui, mibGUI, 'right')` |
