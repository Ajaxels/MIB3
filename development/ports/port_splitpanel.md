# Split-Panel Dataset ID Bug — Root Cause & Fix

**Status: DONE** (2026-03-24)

---

## Problem

In split-panel mode, `mibModel.id` was corrupted by mouse-motion events, causing:
- Double-clicking a file loaded it into the wrong dataset
- `loadModel` and all BatchOpt methods targeted the wrong dataset
- Panning broke; keyboard shortcuts stopped after first press

---

## Root Causes

1. **`gui_WinMouseMotionFcn` wrote `mibModel.id` on every mouse move** — needed for pixel readout but corrupted all downstream methods
2. **`BatchOpt.id = obj.id` in ~15 MibModel methods** — captured the corrupted value
3. **`drawnow` in `fileList_Callback`** processed AppContainer events mid-callback, re-triggering `listener_appStateChanged` → corrupting `Sets.selectedSet`
4. **0.4s rate limiter in `datasetsSetsOps`** blocked legitimate set switches

---

## Fixes Applied

### Fix 1: gui_WinMouseMotionFcn — no global state mutation

Mouse motion uses a local `localId` from `Sets.selectedDataset(setOfDatasetsIndex)`. Coordinate conversion logic inlined; no writes to `mibModel.id` or `Sets.selectedSet`.

**Rule: `gui_WinMouseMotionFcn` must NEVER write to `mibModel.id` or `Sets.selectedSet`.**

### Fix 2: getActiveId() helper

`+models/@MibModel/getActiveId.m` — computes id from `Sets.selectedSet` and `Sets.selectedDataset` (never corrupted by mouse motion):

```matlab
selSet = obj.Sets.selectedSet;
id = obj.Sets.selectedDataset(selSet) + (selSet - 1) * obj.Sets.datasetsInSet;
```

### Fix 3: All BatchOpt methods use getActiveId()

15 files updated — `BatchOpt.id = obj.id` → `BatchOpt.id = obj.getActiveId()`. See the list in `+models/@MibModel/`.

### Fix 4: fileList_Callback saves correct id before drawnow

Persistent variable saves `savedSelectedSet` before `drawnow`; `DoubleClicked` handler restores it before calling `loadImages`.

### Fix 5: listener_newDataset restores id after drawnow limitrate

After `drawnow limitrate`, restore intended set and id. Defer `DatasetsPanelUpdate` until after `UpdateDatasetAxes`.

### Fix 6: Rate limiter removed from datasetsSetsOps

The 0.4s limiter is removed; the `selectedSet == newSelectedSet` guard is sufficient.

---

## UI Chain (The Reliable Path for id Updates)

```
gui_WindowButtonDownFcn (click on document)
  -> listener_appStateChanged (AppContainer LastSelected change)
    -> setsOps_Callbacks
      -> datasetsSetsOps (validates, updates Sets.selectedSet)
        -> DatasetsPanelUpdate
          -> update_fromModel -> buffers_Callback (sets mibModel.id, fires UpdateGuiWidgets + ShowImage)
```

Code outside this chain must use `obj.getActiveId()` or compute from `Sets` directly.

---

## Remaining Concerns

- `fillSelectionOrMask.m` lines 62–63 use `obj.I{obj.id}` before `BatchOpt.id` is set (reads UI defaults only — cosmetic, not data-processing target)
- `syncActiveSet.m` declared in `MibImageDocument` but no longer called — can be removed
- Other `obj.I{obj.id}` patterns in `+models/@MibModel/` may still exist; grep `obj\.I\{obj\.id\}` to audit
