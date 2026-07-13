# BatchProcessing Controller — MIB2→MIB3 Port Plan

## Status

- **MIB2 refactoring: DONE** — all methods extracted to separate files
- **MIB3 port: NOT STARTED** — `@BatchProcessing/` folder exists but is empty

## Source Files (MIB2, refactored)

All methods are now in separate `.m` files under:
`C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\@mibBatchController\`

| File | Lines | Description |
|---|---|---|
| `mibBatchController.m` | 521 | classdef + properties + constructor (builds `Sections`) + static listener |
| `closeWindow.m` | 31 | Close controller window and delete listeners |
| `helpBtn_Callback.m` | 23 | Open help page in browser |
| `selectAction_Callback.m` | 60 | Section/action popup change handler |
| `updateSelectedActionTable.m` | 54 | Populate action table from BatchOpt |
| `displaySelectedActionTableItems.m` | 94 | Show edit widgets for selected table row |
| `selectedActionTableItem_Update.m` | 71 | Write edited value back to table/BatchOpt |
| `selectedActionTable_ContextCallback.m` | 200 | Context menu actions on action table |
| `deleteProtocol.m` | 27 | Delete current protocol |
| `saveProtocol.m` | 76 | Save protocol to .mat file |
| `loadProtocol.m` | 39 | Load protocol from .mat file |
| `protocolActions_Callback.m` | 96 | Add/insert/update/delete/move protocol steps |
| `protocolList_SelectionCallback.m` | 30 | Protocol list row selection handler |
| `updateProtocolList.m` | 28 | Refresh protocol list display |
| `BackupProtocol.m` | 28 | Save undo/redo snapshot |
| `BackupProtocolRestore.m` | 46 | Restore undo/redo snapshot |
| `runProtocolBtn_Callback.m` | 192 | Run protocol (complete/from/step/stepadvance) |
| `doSeriesLoop.m` | 67 | Loop over Bio-Formats series |
| `doFileLoop.m` | 59 | Loop over files in directory |
| `doBatchStep.m` | 167 | Execute a single protocol step |
| `obtainDirectoryForAction.m` | 80 | Resolve directory paths for batch steps |
| `DirectoryLoopAction_Callback.m` | 46 | Directory loop action handler |
| `FileLoopAction_Callback.m` | 47 | File loop action handler |
| `FileOperationsAction_Callback.m` | 55 | File operations handler |
| `DirectoryOperationsAction_Callback.m` | 48 | Directory operations handler |
| `updateWidgets.m` | 34 | Refresh section/action popups |
| `gui_WinMouseMotionFcn.m` | 33 | Cursor shape over separator panel |
| `gui_WindowButtonDownFcn.m` | 33 | Start panel resize on mouse down |
| `panelShiftBtnUpFcn.m` | 28 | Finish panel resize on mouse up |
| `sizeChangedFcn.m` | 43 | Main window resize function |
| `listenMIB_Callback.m` | 26 | Enable/disable MIB event listener |

**Total: 31 files, ~2075 lines**

## Target Structure (MIB3)

```
mib/+controllers/@BatchProcessing/
    BatchProcessing.m                     ← classdef + constructor + addCallbacks + createContextMenus + static listener
    closeWindow.m                         ← ported from MIB2
    helpBtn_Callback.m                    ← ported
    selectAction_Callback.m               ← ported
    updateSelectedActionTable.m           ← ported
    displaySelectedActionTableItems.m     ← ported
    selectedActionTableItem_Update.m      ← ported
    selectedActionTable_ContextCallback.m ← ported
    deleteProtocol.m                      ← ported
    saveProtocol.m                        ← ported
    loadProtocol.m                        ← ported
    protocolActions_Callback.m            ← ported
    protocolList_SelectionCallback.m      ← ported
    updateProtocolList.m                  ← ported
    BackupProtocol.m                      ← ported
    BackupProtocolRestore.m               ← ported
    runProtocolBtn_Callback.m             ← ported
    doSeriesLoop.m                        ← ported
    doFileLoop.m                          ← ported
    doBatchStep.m                         ← ported
    obtainDirectoryForAction.m            ← ported
    DirectoryLoopAction_Callback.m        ← ported
    FileLoopAction_Callback.m             ← ported
    FileOperationsAction_Callback.m       ← ported
    DirectoryOperationsAction_Callback.m  ← ported
    updateWidgets.m                       ← ported
    gui_WinMouseMotionFcn.m               ← ported
    gui_WindowButtonDownFcn.m             ← ported
    panelShiftBtnUpFcn.m                  ← ported
    sizeChangedFcn.m                      ← ported
    listenMIB_Callback.m                  ← ported

mib/+views/
    BatchProcessingGUI.mlapp              ← user creates manually in App Designer
```

---

## Conversion Rules (Quick Reference)

Apply these rules when porting each file. **Read only the MIB2 file being ported + this table — do not re-read other files.**

### Naming

| MIB2 | MIB3 |
|---|---|
| `mibBatchController` | `controllers.BatchProcessing` |
| `mibBatchGUI` (.fig/.m) | `views.BatchProcessingGUI` (.mlapp) |
| `obj.View` | `obj.view` |
| `mibChildView(obj, guiName)` | `core.ChildView(obj, guiName)` |
| `ToggleEventData(...)` | `core.ToggleEventData(...)` |

### GUIDE → AppDesigner Widget Syntax

| GUIDE | AppDesigner |
|---|---|
| `widget.String` (popup/listbox) | `widget.Items` |
| `widget.Value` (popup → numeric index) | `widget.Value` (→ actual string item) |
| `popup.String{popup.Value}` | `popup.Value` directly |
| `widget.String` (button) | `widget.Text` |
| `widget.String` (edit box) | `widget.Value` |
| `widget.String` (label/text) | `widget.Text` |
| `.TooltipString` | `.Tooltip` |
| `.BackgroundColor = 'g'` | `.BackgroundColor = [0 1 0]` |
| `.CData` (button icon) | `.Icon` |
| `.Visible = 'on'/'off'` | `.Visible = 'on'/'off'` (both work) |

### Listbox/Popup Index→String Conversion

MIB2 popup `Value` is a numeric index; MIB3 dropdown `Value` is the string. When porting code that reads a popup index and uses it to index into `String`, replace with direct `Value` usage:
```matlab
% MIB2: idx = obj.View.handles.sectionPopup.Value;
%        name = obj.View.handles.sectionPopup.String{idx};
% MIB3: name = obj.view.handles.sectionPopup.Value;
```

When setting a popup by index, find the item string and set `Value`:
```matlab
% MIB2: obj.View.handles.sectionPopup.Value = 3;
% MIB3: items = obj.view.handles.sectionPopup.Items;
%        obj.view.handles.sectionPopup.Value = items{3};
```

### Global Variable Replacement

| MIB2 | MIB3 |
|---|---|
| `global Font;` | `obj.mibModel.preferences.System.Font` |
| `global mibPath;` | `obj.mibModel.mibPath` |

### Utility Function Replacement

| MIB2 | MIB3 |
|---|---|
| `moveWindowOutside(gui, 'left')` | `utils.moveWindowOutside(gui, obj.mibModel.mibGUI, 'left')` |
| `mibRescaleWidgets(gui)` | Remove (not needed in AppDesigner) |
| `mibUpdateFontSize(gui, Font)` | `utils.fontSizeUpdate(gui, Font)` |
| `mibInputMultiDlg({mibPath}, ...)` | `utils.dlgs.mibInputMultiDlg(...)` |
| `errordlg(...)` | `utils.dlgs.showErrorDialog(...)` or keep `errordlg` |
| `findjobj(...)` | Remove — use native uitable `ColumnWidth`/`scroll()` |

### Java Table Removal

Remove properties: `jSelectedActionTable`, `jSelectedActionTableScroll`.
Remove `findjobj(...)` init code. Replace with:
```matlab
obj.view.handles.selectedActionTable.ColumnWidth = {'fit', 'auto'};
```
Use `scroll(uitableHandle, 'row', rowIndex)` (R2021a+) if programmatic scrolling needed.

### Context Menus

Create programmatically in `createContextMenus()`:
```matlab
cm = uicontextmenu(obj.view.gui);
uimenu(cm, 'Label', 'Action', 'MenuSelectedFcn', @(~,~) obj.callback());
obj.view.handles.widget.ContextMenu = cm;
```

### Callback Wiring

Wire in `addCallbacks()` (not in .mlapp or external GUI file):
```matlab
h.dropdown.ValueChangedFcn = @(src,~) obj.method(src);
h.button.ButtonPushedFcn = @(~,~) obj.method();
h.checkbox.ValueChangedFcn = @(~,~) obj.method();
```

---

## Step-by-Step Conversion Plan

Each step reads only the specific MIB2 source file + this conversion rules table. This minimizes token usage by never loading the full codebase.

### Phase 1: Main classdef skeleton

**Step 1.1 — Create `BatchProcessing.m`**
- **Read:** MIB2 `mibBatchController.m` (521 lines — properties, constructor, static listener)
- **Write:** `mib/+controllers/@BatchProcessing/BatchProcessing.m`
- **Actions:**
  - Copy `properties` block; rename `View` → `view`; remove `jSelectedActionTable`, `jSelectedActionTableScroll`
  - Copy `events` block as-is
  - Copy `methods (Static)` block (`ViewListner_Callback2`) — update guard to check `obj.view`
  - Create `methods` block with all 30 external method declarations (same signatures as MIB2 `mibBatchController.m` lines 117–147)
  - Port constructor: `mibChildView` → `core.ChildView`; remove `findjobj` block; remove `mibRescaleWidgets`; replace `global` usage; add calls to `obj.addCallbacks()` and `obj.createContextMenus()`; replace `moveWindowOutside` and `mibUpdateFontSize`
  - Add `addCallbacks()` inline — wire all widget callbacks (see Callback Wiring section above)
  - Add `createContextMenus()` inline — port context menus from `mibBatchGUI.m`

### Phase 2: Simple methods (≤50 lines each, minimal GUIDE syntax)

Port each file one-at-a-time. For each: read MIB2 file → apply conversion rules → write MIB3 file.

**Step 2.1** — `closeWindow.m` (31 lines) — `obj.View` → `obj.view`
**Step 2.2** — `helpBtn_Callback.m` (23 lines) — `global mibPath` → `obj.mibModel.mibPath`
**Step 2.3** — `deleteProtocol.m` (27 lines) — `obj.View` → `obj.view`
**Step 2.4** — `updateProtocolList.m` (28 lines) — listbox `.String` → `.Items`
**Step 2.5** — `BackupProtocol.m` (28 lines) — minimal changes
**Step 2.6** — `BackupProtocolRestore.m` (46 lines) — minimal changes + updateProtocolList call
**Step 2.7** — `updateWidgets.m` (34 lines) — popup `.String`/`.Value` index→string conversion
**Step 2.8** — `listenMIB_Callback.m` (26 lines) — `obj.View` → `obj.view`
**Step 2.9** — `panelShiftBtnUpFcn.m` (28 lines) — `obj.View` → `obj.view`
**Step 2.10** — `protocolList_SelectionCallback.m` (30 lines) — listbox `.Value` index→string

### Phase 3: Medium methods (50–100 lines, moderate GUIDE syntax)

**Step 3.1** — `selectAction_Callback.m` (60 lines) — popup index→string throughout
**Step 3.2** — `updateSelectedActionTable.m` (54 lines) — table `.Data`, popup syntax
**Step 3.3** — `selectedActionTableItem_Update.m` (71 lines) — popup/edit/checkbox syntax
**Step 3.4** — `displaySelectedActionTableItems.m` (94 lines) — heavy widget manipulation
**Step 3.5** — `protocolActions_Callback.m` (96 lines) — listbox index→string, protocol ops
**Step 3.6** — `saveProtocol.m` (76 lines) — `global mibPath`, file dialogs
**Step 3.7** — `loadProtocol.m` (39 lines) — `global mibPath`, file dialogs
**Step 3.8** — `obtainDirectoryForAction.m` (80 lines) — `obj.View` → `obj.view`, minimal
**Step 3.9** — `gui_WinMouseMotionFcn.m` (33 lines) — `obj.View` → `obj.view`, cursor logic
**Step 3.10** — `gui_WindowButtonDownFcn.m` (33 lines) — `obj.View` → `obj.view`
**Step 3.11** — `sizeChangedFcn.m` (43 lines) — panel position logic, `obj.View` → `obj.view`

### Phase 4: Complex methods (100+ lines, protocol execution)

**Step 4.1** — `doFileLoop.m` (59 lines) — loop logic, `obj.View` → `obj.view`
**Step 4.2** — `doSeriesLoop.m` (67 lines) — loop logic, `obj.View` → `obj.view`
**Step 4.3** — `doBatchStep.m` (167 lines) — eval dispatch, `global mibPath`, error handling
**Step 4.4** — `runProtocolBtn_Callback.m` (192 lines) — button `.String` → `.Text`, protocol execution loop
**Step 4.5** — `selectedActionTable_ContextCallback.m` (200 lines) — heavy GUIDE syntax, dialogs

### Phase 5: Action callbacks (simple wrappers, ~50 lines each)

**Step 5.1** — `DirectoryLoopAction_Callback.m` (46 lines)
**Step 5.2** — `FileLoopAction_Callback.m` (47 lines)
**Step 5.3** — `FileOperationsAction_Callback.m` (55 lines)
**Step 5.4** — `DirectoryOperationsAction_Callback.m` (48 lines)

### Phase 6: Verification

**Step 6.1** — Run MATLAB Code Analyzer on all files in `@BatchProcessing/`
**Step 6.2** — Verify all method signatures in `BatchProcessing.m` match external files
**Step 6.3** — Smoke test: instantiate class (requires `.mlapp` to exist)

---

## Key Widget List for `.mlapp`

The user must create `mib/+views/BatchProcessingGUI.mlapp` with these named components:

### Dropdowns
- `sectionPopup` — section selector
- `actionPopup` — action selector

### Listbox
- `protocolList` — protocol steps list

### Table
- `selectedActionTable` — 2-column uitable (Parameter, Value)

### Buttons
- `runProtocolBtn`, `runStepBtn`, `runStepAdvanceBtn`, `runFromBtn`
- `helpBtn`, `loadProtocolBtn`, `saveProtocolBtn`, `deleteProtocolBtn`
- `undoBtn`, `redoBtn`
- `addToListButton`, `insertToListButton`, `updateListButton`

### Checkboxes
- `autoAddToProtocol`, `showOptionsCheck`, `listenMIB`
- `selectedActionTableCellCheck` — for editing boolean parameters

### Edit Fields
- `selectedActionTableCellEdit` — string parameter editing
- `selectedActionTableCellNumericEdit` — numeric parameter editing
- `selectedActionTableCellPopup` — dropdown parameter editing

### Labels
- `sectionNameText`, `selectedActionTableCellText`, `ParametersText`, `TooltipText`

### Panels
- `actionListPanel`, `selectActionPanel`, `separatingPanel`
- `StepsSubpanelUp`, `StepsSubpanelRight`

---

## Notes

- Command strings in `Sections.Actions.Command` use MIB2 controller names (e.g. `mibAlignmentController`). Update later as those controllers are ported.
- The `.mlapp` file is NOT created by this plan — user creates it in App Designer.
- External callback targets (e.g. `obj.mibController.mibFilesListbox_cm_Callback(...)`) kept as-is; ported separately.
- `uigetfile_n_dir` (multi-directory selection) kept as-is if available in MIB3 external tools.
