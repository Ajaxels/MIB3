# BatchProcessing Controller — Port Plan

**Status: NOT STARTED**

MIB2 source refactored into 31 separate files. MIB3 `@BatchProcessing/` folder exists but is empty. The `.mlapp` must be created manually in App Designer.

---

## Source Files (MIB2, refactored)

All methods are in separate `.m` files under:
`C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\@mibBatchController\`

| File | Lines | Description |
|------|-------|-------------|
| `mibBatchController.m` | 521 | classdef + properties + constructor + static listener |
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

---

## Target Structure (MIB3)

```
mib/+controllers/@BatchProcessing/
    BatchProcessing.m
    closeWindow.m
    helpBtn_Callback.m
    selectAction_Callback.m
    updateSelectedActionTable.m
    displaySelectedActionTableItems.m
    selectedActionTableItem_Update.m
    selectedActionTable_ContextCallback.m
    deleteProtocol.m / saveProtocol.m / loadProtocol.m
    protocolActions_Callback.m / protocolList_SelectionCallback.m
    updateProtocolList.m / BackupProtocol.m / BackupProtocolRestore.m
    runProtocolBtn_Callback.m
    doSeriesLoop.m / doFileLoop.m / doBatchStep.m
    obtainDirectoryForAction.m
    DirectoryLoopAction_Callback.m / FileLoopAction_Callback.m
    FileOperationsAction_Callback.m / DirectoryOperationsAction_Callback.m
    updateWidgets.m / listenMIB_Callback.m
    gui_WinMouseMotionFcn.m / gui_WindowButtonDownFcn.m
    panelShiftBtnUpFcn.m / sizeChangedFcn.m

mib/+views/
    BatchProcessingGUI.mlapp    ← user creates manually in App Designer
```

---

## Naming Conversions

| MIB2 | MIB3 |
|------|------|
| `mibBatchController` | `controllers.BatchProcessing` |
| `mibBatchGUI` (.fig/.m) | `views.BatchProcessingGUI` (.mlapp) |
| `obj.View` | `obj.view` |
| `mibChildView(obj, guiName)` | `core.ChildView(obj, guiName)` |
| `ToggleEventData(...)` | `core.ToggleEventData(...)` |

---

## Step-by-Step Plan

Each step: read only the specific MIB2 source file + the naming table above. See `.claude/appdesigner_guide.md` for widget syntax.

### Phase 1: Main classdef skeleton

**Step 1.1 — Create `BatchProcessing.m`**
- Read: MIB2 `mibBatchController.m` (521 lines)
- Copy `properties` block; rename `View` → `view`; remove `jSelectedActionTable`, `jSelectedActionTableScroll`
- Copy `events` block as-is
- Copy `methods (Static)` block (`ViewListner_Callback2`) — update guard to check `obj.view`
- Create `methods` block with all 30 external method declarations
- Port constructor: `mibChildView` → `core.ChildView`; remove `findjobj`; replace globals; add `obj.addCallbacks()` and `obj.createContextMenus()` calls
- Add `addCallbacks()` inline — wire all widget callbacks
- Add `createContextMenus()` inline

### Phase 2: Simple methods (≤50 lines)

**2.1** `closeWindow.m` — `obj.View` → `obj.view`
**2.2** `helpBtn_Callback.m` — `global mibPath` → `obj.mibModel.mibPath`
**2.3** `deleteProtocol.m` — `obj.View` → `obj.view`
**2.4** `updateProtocolList.m` — listbox `.String` → `.Items`
**2.5** `BackupProtocol.m` — minimal changes
**2.6** `BackupProtocolRestore.m` — minimal + updateProtocolList call
**2.7** `updateWidgets.m` — popup `.String`/`.Value` index→string
**2.8** `listenMIB_Callback.m` — `obj.View` → `obj.view`
**2.9** `panelShiftBtnUpFcn.m` — `obj.View` → `obj.view`
**2.10** `protocolList_SelectionCallback.m` — listbox `.Value` index→string

### Phase 3: Medium methods (50–100 lines)

**3.1** `selectAction_Callback.m` — popup index→string throughout
**3.2** `updateSelectedActionTable.m` — table `.Data`, popup syntax
**3.3** `selectedActionTableItem_Update.m` — popup/edit/checkbox syntax
**3.4** `displaySelectedActionTableItems.m` — heavy widget manipulation
**3.5** `protocolActions_Callback.m` — listbox index→string, protocol ops
**3.6** `saveProtocol.m` — `global mibPath`, file dialogs
**3.7** `loadProtocol.m` — `global mibPath`, file dialogs
**3.8** `obtainDirectoryForAction.m` — `obj.View` → `obj.view`
**3.9** `gui_WinMouseMotionFcn.m` — cursor logic
**3.10** `gui_WindowButtonDownFcn.m` — panel resize start
**3.11** `sizeChangedFcn.m` — panel position logic

### Phase 4: Complex methods (100+ lines)

**4.1** `doFileLoop.m` — loop logic
**4.2** `doSeriesLoop.m` — loop logic
**4.3** `doBatchStep.m` (167 lines) — eval dispatch, `global mibPath`, error handling
**4.4** `runProtocolBtn_Callback.m` (192 lines) — button `.String` → `.Text`, protocol execution loop
**4.5** `selectedActionTable_ContextCallback.m` (200 lines) — heavy GUIDE syntax, dialogs

### Phase 5: Action callbacks (~50 lines each)

**5.1** `DirectoryLoopAction_Callback.m`
**5.2** `FileLoopAction_Callback.m`
**5.3** `FileOperationsAction_Callback.m`
**5.4** `DirectoryOperationsAction_Callback.m`

### Phase 6: Verification

**6.1** Run MATLAB Code Analyzer on all files in `@BatchProcessing/`
**6.2** Verify all method signatures in `BatchProcessing.m` match external files
**6.3** Smoke test: instantiate class (requires `.mlapp` to exist)

---

## Widget List for BatchProcessingGUI.mlapp

User must create `mib/+views/BatchProcessingGUI.mlapp` with these named components:

| Tag | Type | Purpose |
|-----|------|---------|
| `sectionPopup` | DropDown | Section selector |
| `actionPopup` | DropDown | Action selector |
| `protocolList` | ListBox | Protocol steps |
| `selectedActionTable` | UITable | 2-column: Parameter, Value |
| `runProtocolBtn`, `runStepBtn`, `runStepAdvanceBtn`, `runFromBtn` | Button | Run controls |
| `helpBtn`, `loadProtocolBtn`, `saveProtocolBtn`, `deleteProtocolBtn` | Button | Protocol I/O |
| `undoBtn`, `redoBtn` | Button | Undo/redo |
| `addToListButton`, `insertToListButton`, `updateListButton` | Button | List editing |
| `autoAddToProtocol`, `showOptionsCheck`, `listenMIB` | CheckBox | Options |
| `selectedActionTableCellCheck` | CheckBox | Edit boolean parameters |
| `selectedActionTableCellEdit` | EditField | Edit string parameters |
| `selectedActionTableCellNumericEdit` | NumericEditField | Edit numeric parameters |
| `selectedActionTableCellPopup` | DropDown | Edit dropdown parameters |
| `sectionNameText`, `selectedActionTableCellText`, `ParametersText`, `TooltipText` | Label | Labels |
| `actionListPanel`, `selectActionPanel`, `separatingPanel` | Panel | Layout |
| `StepsSubpanelUp`, `StepsSubpanelRight` | Panel | Resizable subpanels |

---

## Notes

- Command strings in `Sections.Actions.Command` use MIB2 controller names (e.g. `mibAlignmentController`). Update as those controllers are ported.
- External callback targets (e.g. `obj.mibController.mibFilesListbox_cm_Callback(...)`) kept as-is; ported separately.
- `uigetfile_n_dir` (multi-directory selection) kept as-is if available in MIB3 external tools.
