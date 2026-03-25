# Fixing Dataset Selection in Split-Panel Mode

## Date: 2026-03-24

## Problem Summary

In split-panel mode (two documents visible side-by-side), `mibModel.id` — the global index into
`obj.I{}` identifying the active dataset — was frequently corrupted. This caused:

1. **Double-clicking a file in Directory Contents** loaded the image into Set 1 instead of Set 2
2. **Loading a model** (`loadModel.m`) targeted the wrong dataset
3. **All MibModel BatchOpt-based methods** (dilate, erode, clear, save, etc.) could silently
   operate on the wrong dataset
4. **Panning became unreliable** and **keyboard shortcuts** (e.g., `w` for zoom) stopped working
   after the first press unless the mouse moved

## Root Causes

### 1. `gui_WinMouseMotionFcn` wrote to `mibModel.id` on every mouse move

The mouse motion handler updated `mibModel.id` to match whichever document the cursor hovered
over. This was needed for pixel readout but had severe side effects:

- Any MibModel method called between mouse moves would read the wrong `obj.id`
- Panning and keyboard shortcuts broke because the id kept flipping between documents
- `gui_WindowButtonDownFcn`'s guard (`Sets.selectedSet != setOfDatasetsIndex`) was defeated
  when `syncActiveSet()` had already updated `selectedSet` during mouse motion

### 2. `BatchOpt.id = obj.id` pattern in ~15 MibModel methods

Every BatchOpt-compatible method captured `obj.id` as a default during initialization. Since
`obj.id` was corrupted by mouse motion, the wrong dataset was targeted.

### 3. `drawnow` in `fileList_Callback` processed AppContainer events mid-callback

The `Clicked` handler in `fileList_Callback` calls `drawnow` (required for Shift+click
multi-select). This `drawnow` processes the UI event queue, which can:
- Fire `AppContainer PropertyChanged` events that trigger `listener_appStateChanged` →
  `setsOps_Callbacks` → `datasetsSetsOps`, corrupting `Sets.selectedSet` and `mibModel.id`
- Fire the `DoubleClicked` callback INSIDE the `Clicked` handler's `drawnow`

### 4. Rate limiter in `datasetsSetsOps` blocked legitimate set switches

A 0.4-second rate limiter prevented rapid calls, but also blocked legitimate set-switch
calls from `listener_appStateChanged` when quickly clicking between documents.

## Fixes Applied

### Fix 1: `gui_WinMouseMotionFcn` — no global state mutation

**File**: `+controllers/@MibImageDocument/gui_WinMouseMotionFcn.m`

Mouse motion now uses a local `localId` computed from `Sets.selectedDataset(setOfDatasetsIndex)`
for pixel readout. It reads `dataset.magFactor`, `dataset.axesX`, `dataset.axesY` directly
instead of going through MibModel wrappers (`getMagFactor()`, `getAxesLimits()`,
`convertMouseToDataCoordinates()`) that internally read `obj.id`. The coordinate conversion
logic from `convertMouseToDataCoordinates` is inlined.

**Rule**: `gui_WinMouseMotionFcn` must NEVER write to `mibModel.id` or `Sets.selectedSet`.

### Fix 2: `getActiveId()` helper method

**New file**: `+models/@MibModel/getActiveId.m`

Computes the correct dataset index from `Sets.selectedSet` and `Sets.selectedDataset`:
```matlab
selSet = obj.Sets.selectedSet;
id = obj.Sets.selectedDataset(selSet) + (selSet - 1) * obj.Sets.datasetsInSet;
```

These properties are only changed through the full UI chain and are immune to mouse-motion
corruption.

### Fix 3: All BatchOpt methods use `getActiveId()`

**15 files updated** — replaced `BatchOpt.id = obj.id` with `BatchOpt.id = obj.getActiveId()`:

- `addMaterial.m`
- `clearLayer.m`
- `clearSelection.m`
- `createModel.m`
- `dilateImage.m`
- `erodeImage.m`
- `fillSelectionOrMask.m`
- `interpolateImage.m`
- `loadImages.m`
- `loadModel.m`
- `materialsActions.m`
- `moveLayers.m`
- `removeMaterial.m`
- `renameMaterial.m`
- `saveImage.m`

### Fix 4: `fileList_Callback` — persistent variable saves correct id

**File**: `+controllers/@MibDirContents/fileList_Callback.m`

The `Clicked` handler saves `savedSelectedSet` and computes `savedId` from it (NOT from
`mibModel.id` which is already corrupted by mouse motion). The `DoubleClicked` handler
restores both before calling `loadImages`.

### Fix 5: `listener_newDataset` — restore id after `drawnow limitrate`

**File**: `+controllers/@MibController/listener_newDataset.m`

After `drawnow limitrate` (which can process AppContainer events and corrupt `selectedSet`/`id`),
the intended set and id are restored. `DatasetsPanelUpdate` is deferred until AFTER
`UpdateDatasetAxes` to prevent `ShowImage` firing before axes are initialized.

### Fix 6: Rate limiter removed from `datasetsSetsOps`

**File**: `+models/@MibModel/datasetsSetsOps.m`

The 0.4s rate limiter was removed. The existing `selectedSet == newSelectedSet` guard already
prevents redundant processing.

### Fix 7: `gui_WindowButtonDownFcn` guard preserved

**File**: `+controllers/@MibImageDocument/gui_WindowButtonDownFcn.m`

The guard `Sets.selectedSet != setOfDatasetsIndex` correctly detects set changes and triggers
the full UI chain (`UpdateGuiWidgets` + `ShowImage`). This works because mouse motion no longer
updates `selectedSet`.

## Key Architectural Insight

In split-panel mode, `mibModel.id` is a **mutable global** that multiple callbacks compete to
update. The reliable source of truth is `Sets.selectedSet` + `Sets.selectedDataset(selectedSet)`,
which are only changed through the full UI chain:

```
gui_WindowButtonDownFcn (click on document)
  -> listener_appStateChanged (AppContainer LastSelected change)
    -> setsOps_Callbacks
      -> datasetsSetsOps (validates, updates Sets.selectedSet)
        -> DatasetsPanelUpdate event
          -> update_fromModel -> buffers_Callback (sets mibModel.id, fires UpdateGuiWidgets + ShowImage)
```

Any code that needs the "correct" dataset index outside this chain should use
`obj.getActiveId()` (MibModel methods) or compute it locally from `Sets` (callbacks on
MibImageDocument that know their `setOfDatasetsIndex`).

## Files Modified (complete list)

| File | Change |
|------|--------|
| `+models/@MibModel/MibModel.m` | Added `getActiveId` method declaration |
| `+models/@MibModel/getActiveId.m` | **NEW** — helper to compute id from Sets |
| `+models/@MibModel/addMaterial.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/clearLayer.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/clearSelection.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/createModel.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/dilateImage.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/erodeImage.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/fillSelectionOrMask.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/interpolateImage.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/loadImages.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/loadModel.m` | Inline id computation -> `obj.getActiveId()` |
| `+models/@MibModel/materialsActions.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/moveLayers.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/removeMaterial.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/renameMaterial.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/saveImage.m` | `obj.id` -> `obj.getActiveId()` |
| `+models/@MibModel/datasetsSetsOps.m` | Removed 0.4s rate limiter |
| `+controllers/@MibImageDocument/gui_WinMouseMotionFcn.m` | Stopped writing `mibModel.id`; uses local id + inlined coordinate conversion |
| `+controllers/@MibImageDocument/gui_WindowButtonDownFcn.m` | Removed `syncActiveSet()` before guard |
| `+controllers/@MibDirContents/fileList_Callback.m` | Persistent vars save id from `selectedSet`; removed debug fprintf |
| `+controllers/@MibController/listener_newDataset.m` | Restore id/selectedSet after drawnow; defer DatasetsPanelUpdate |
| `CLAUDE.md` | Documented `getActiveId()` rule and mouse-motion constraint |

## Remaining Concerns

- **`fillSelectionOrMask.m` lines 62-63** use `obj.I{obj.id}` before `BatchOpt.id` is set, to
  read UI defaults (`getSelectedMaterialIndex`, `restrictSelectionToMaterial`). These are only
  cosmetic defaults for the dialog, not data-processing targets, but could show wrong defaults.
- **`syncActiveSet.m`** is declared in `MibImageDocument` but no longer called from anywhere.
  Can be removed in a future cleanup.
- **Other `obj.I{obj.id}` patterns** in MibModel methods (outside BatchOpt initialization) may
  still exist and could be vulnerable. A grep for `obj\.I\{obj\.id\}` in `+models/@MibModel/`
  would identify them.
