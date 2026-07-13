# Plan: Linked-View Propagation (MIB3)

## Context

Two buffer containers can be "linked" via the right-click context menu (already implemented in `buffers_ContextMenu.m`). The link state is stored in `MibModel.linkedPairs` (n×2 double array of global dataset ID pairs) and also mirrored as text in each button's context menu.

When two datasets are linked, they always show the same position (slice, frame, zoom, pan), dynamically — similar to `sync_xyz` but persistent and bidirectional.

---

## Implementation Status

### DONE — Core infrastructure

| File | Change | Status |
|------|--------|--------|
| `+models/@MibModel/MibModel.m` | Added `linkedPairs = zeros(0,2)` property + method declarations for `imageDeepCopy`, `getLinkedDataset` | ✅ |
| `+models/@MibModel/initialize.m` | `obj.linkedPairs = zeros(0, 2)` | ✅ |
| `+models/@MibModel/getLinkedDataset.m` | NEW — returns partner global ID or `[]` | ✅ |
| `+models/@MibModel/imageDeepCopy.m` | NEW — deep-copies a MibDataset (all handle sub-properties) | ✅ |
| `+controllers/@MibController/MibController.m` | Added `propagatingLinkedView = false` property | ✅ |
| `+controllers/@MibController/showImage.m` | Added linked-view propagation block at end (copies slices/axes/magFactor to partner, re-renders partner set if active) | ✅ |
| `+controllers/@MibActiveDataset/buffers_ContextMenu.m` | `link` adds to `linkedPairs`; `unlink` removes; `close`/`closeSet` clean up pairs and reset partner menu text; `sync_xy/xyz/xyzt` and `link_views` use set+buffer dialog format | ✅ |
| `+controllers/@MibActiveDataset/buffers_Callback.m` | On buffer switch TO a linked buffer, copies previous buffer's view state before `notify(ShowImage)` | ✅ |

### DONE — Split-panel pan fix

| File | Change | Status |
|------|--------|--------|
| `+controllers/@MibImageDocument/gui_WindowButtonUpFcn.m` | Changed `showImage()` → `showImage(true, obj.setOfDatasetsIndex)` so pan always re-renders the panel that was panned (not whichever set is currently "selected") | ✅ |

### DONE — Keyboard zoom applies to hovered panel

| File | Change | Status |
|------|--------|--------|
| `+controllers/@MibController/gui_WindowKeyPressFcn.m` | Detect which `cImageDoc` has `isInsideAxes = true` → use as `cImageDoc` (and `hoverDocIdx`). In zoom branch: sync `mibModel.Sets.selectedSet` + `mibModel.id` to `hoverDocIdx` before calling `zoomEdit_Callback` | ✅ |

---

### DONE — White-panel / dead-propagation fix (2026-07-11)

**Symptom**: after linking two sets in split view, moving one view stopped updating the other; the partner panel turned into an empty white background.

**Root cause (two bugs in the propagation block of `showImage.m`)**:
1. The slice-copy loop treated `slices{4}` as a `[min max]` range and clamped it with `min(src.slices{4}, [maxVal maxVal])`. `slices{4}` is a **list of shown color channels** — a scalar `1` (grayscale) became `[1 1]`, so `getRGBimage` rendered channel 1 twice and produced a 6-channel `Ishown`, which `image()` rejects ("Color data must be m-by-n or m-by-n-by-3").
2. That error was thrown between `propagatingLinkedView = true` and `= false`, so the guard stuck at `true` and **permanently disabled all propagation** for the session. The failed render also left `imageHandle.CData = []` → the white panel.

**Fix**: the slice-copy loop now iterates `[1 2 3 5]` only (channel selection is not view position), and the nested partner `showImage` call is wrapped in try/catch that releases the guard before rethrowing.

The **same buggy slice-copy loop existed in `buffers_Callback.m` (~line 74)** — the buffer-switch sync path — corrupting `slices{4}` when switching TO a linked buffer (surfaced as the same CData error via `update_fromModel` → `buffers_Callback` → `ShowImage`). Fixed identically. If this pattern is ever copied again: **never clamp `slices{4}` with `min(..., [maxVal maxVal])`.**

**Follow-on symptom — brush cursor hidden in split view**: when `showImage` *recreates* the image object (its CData was left empty by a failed render, dataset reload, etc.), the new `image()` is prepended to the axes children and covers the persistent `brushCursor` line, which is created once and survives re-renders. The cursor still tracked the mouse — it was just underneath the image. Fix: `uistack(imageHandle, 'bottom')` right after creation in `showImage.m`. Diagnosis note: java.awt.Robot mouse moves do NOT generate motion events in the CEF web figures — instrument the callback and let a human move the mouse instead.

## Remaining / Pending

### 1. Keyboard zoom cursor repositioning in split view

**Problem**: When using `q`/`w` zoom keys while hovering over the **right** panel (set 2), the cursor is moved to the **wrong position** (set 1's panel center) after the zoom. The cursor repositioning code in `zoomEdit_Callback.m` computes `screenX` as:

```matlab
screenX = winBounds(1) + leftPanelW + posAxes(1) + posAxes(3)/2;
```

This assumes the axes is always at `winBounds(1) + leftPanelW + ...`, which is only true for the **leftmost** panel. The right panel has an additional horizontal offset equal to the width of the left document panel.

**Diagnostic data** (from zooming in set 2):
```
winBounds: [1118, 41, 1416, 1019]
posAxes: [47, 11, 512, 618]
leftPanelW=271, bottomPanelH=181
screenX=1692 (WRONG — this is set 1's axes center)
pointerX=1700 (cursor moved to set 1)
current PointerLocation before set: [2286, 889] (actual cursor over set 2)
scaling=1.000, monitor: primary 3440x1440
```

Document area width = `1416 - 271 = 1145`. With two panels, each ≈ 572.5 px. The missing offset for set 2 is ~594 px (2286 - 1692).

**Attempted fix 1** (reverted — broke single-panel zoom):
```matlab
docFigX = activeDoc.figureDoc.Figure.Position(1);
screenX = docFigX + posAxes(1) + posAxes(3)/2;
```
`figureDoc.Figure.Position` is in MATLAB logical pixels, not compatible with the `winBounds` CSS/web logical pixel space. Broke single-panel zoom (cursor outside GUI).

**Attempted fix 2** (reverted — did not take effect, needs investigation):
Computed `panelOffset` from proportional axes widths within `winBounds` coordinate system:
```matlab
panelOffset = docAreaWidth * axWidths(1) / totalAxWidth;  % ≈ 572.5
screenX = winBounds(1) + leftPanelW + panelOffset + posAxes(1) + posAxes(3)/2;
```
Theoretically gives `screenX ≈ 2264.5` (close to actual 2286), but user reported cursor still moved to set 1 center. Possible causes:
- `obj.mibModel.Sets.selectedSet` might not be 2 when the recenter block executes (needs diagnostic verification with `selectedSet` printed)
- MATLAB function caching — user may need `clear classes` after code edit
- The proportional approach may not accurately reflect panel widths (dividers, tab bars, padding)

**Next steps**:
1. Uncomment diagnostic block in `zoomEdit_Callback.m` (lines ~143-157) — it now also prints `selectedSet` and `numDocs`
2. Additionally uncomment the `figureDoc.Figure.Position` loop (lines ~158-161) to see figure positions for both panels
3. Verify `selectedSet` is actually 2 when zooming in set 2
4. Use figure position difference (`fig2.Position(1) - fig1.Position(1)`) as the panel offset instead of proportional axes widths — this gives the exact relative offset in MATLAB logical pixels
5. Investigate coordinate system relationship: does `winBounds` = MATLAB logical pixels when `scaling=1.0`?

**State of `zoomEdit_Callback.m`**: reverted to original formula. Diagnostic block is commented out, ready to uncomment.

### 2. Linked-view zoom propagation (set 1 → set 2)

**Problem**: Zooming in set 1 with `q`/`w` keys does NOT propagate the zoom to set 2 via linked views.

**Expected flow**:
1. `gui_WindowKeyPressFcn` detects zoom key → calls `zoomEdit_Callback`
2. `zoomEdit_Callback` fires `notify(mibModel, 'UpdateDatasetAxes')` → updates `I{datasetId}.axesX/Y/magFactor`
3. `zoomEdit_Callback` fires `notify(mibModel, 'ShowImage')` → `listener_showImage` → `showImage(true, [])`
4. `showImage` renders set 1, then linked-view propagation block copies state to partner and re-renders set 2

**Propagation block** (end of `showImage.m`, lines 241-275) looks correct: copies `slices`, `axesX/Y`, `magFactor` to partner, then calls `showImage(resizeToMagnification, partnerSetIdx)` with `propagatingLinkedView` guard.

**Needs investigation**:
- Verify `linkedPairs` is populated when the issue occurs (add `fprintf` showing `linkedPairs` in the propagation block)
- Verify `getLinkedDataset(datasetId)` returns the correct partner
- Check if `partnerSetIdx ~= selectedSet` condition is met
- Slice/pan propagation reportedly works — this may be zoom-specific (maybe `UpdateDatasetAxes` modifies state that the propagation block doesn't copy correctly?)

---

## Key Design Decisions

- `linkedPairs` uses **global** dataset IDs (not local buffer IDs) so cross-set links work.
- `propagatingLinkedView` guard on `MibController` prevents infinite recursion when `showImage` re-renders the partner panel.
- `showImage` is the universal hook — it covers ALL navigation paths (slice, frame, pan, zoom, buffer switch) because all paths eventually call it.
- Partner panel is only re-rendered if it is the **active** buffer in its set AND belongs to a different set than the one just rendered.

---

## Verification Steps

1. `cd C:\Matlab\MIB3\mib; mib3`
2. Load dataset A into buffer 1, dataset B (same dims, same orientation) into buffer 2.
3. Right-click buffer 1 → "Link view" → pick buffer 2. Confirm menu text changes to `[Linked: 1 <-> 2]`.
4. Navigate slice slider in buffer 1 → verify buffer 2 shows the same slice (same-set, single panel — buffer 2 state updated but not rendered until switched).
5. Switch to buffer 2 → verify it is already at the same slice/position as buffer 1.
6. Open a second set in split panel. Link buffer 1 set 1 to buffer 1 set 2. Navigate slice in set 1 → verify set 2 panel updates in real time.
7. Zoom/pan in set 1 → verify set 2 follows. Pan set 1 → set 2 follows (fixed). Pan set 2 → set 1 follows (was already working).
8. Zoom with `q`/`w` keys over set 2 → zoom applies to set 2 (fixed), but cursor repositioning still moves to wrong position (pending fix). Linked-view zoom propagation from set 1 to set 2 also pending.
9. Close buffer 1 → verify `linkedPairs` is emptied, context menu text on buffer 2 resets to `[Unlinked]`.
