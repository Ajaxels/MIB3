# MIB3 UI-Specific Patterns

---

## Modifier Key Handling

MATLAB's AppContainer splits the app into independent sub-figures. `obj.UIFigure.CurrentModifier` is **unreliable** — it only reflects events that targeted that exact sub-figure and returns `{}` for button clicks from other panels.

**Solution:** `MibController` stores modifier state explicitly:

| Location | What it does |
|----------|--------------|
| `MibController.currentModifier` | `{}` property; single source of truth |
| `gui_WindowKeyPressFcn.m` | Stores `obj.currentModifier = modifier` on every key-press |
| `gui_WindowKeyReleaseFcn.m` | Clears `obj.currentModifier = {}` on every key-release |

```matlab
% CORRECT — read from MibController
modifier = obj.mibController.currentModifier;

% WRONG — returns {} from button callbacks in other sub-figures
modifier = obj.UIFigure.CurrentModifier;
```

**Standard modifier → scope mapping:**

```matlab
modifier = obj.mibController.currentModifier;
if sum(ismember({'alt', 'shift'}, modifier)) == 2
    DatasetType = (obj.mibModel.I{id}.image.time == 1) ? '3D, Stack' : '4D, Dataset';
elseif sum(ismember({'alt', 'shift'}, modifier)) == 1
    DatasetType = '3D, Stack';
else
    DatasetType = '2D, Slice';
end
```

---

## Image Display Coordinate Systems

MIB3 stretches the X axis for anisotropic voxels. Stretch factor `coef_z` by orientation:

| Orientation | Plane | coef_z |
|-------------|-------|--------|
| 3 (default) | XY | `pixSize.x / pixSize.y` |
| 1 | ZX | `pixSize.z / pixSize.x` |
| 2 | ZY | `pixSize.z / pixSize.y` |

`imageHandle.XData = [1, shownW * coef_z]` — Y is never stretched.

**Data coords → CData pixel index** (brush/segmentation tools):

```matlab
XData = obj.imageHandle.XData;
YData = obj.imageHandle.YData;
xc = round((x - XData(1)) / (XData(end) - XData(1)) * (shownW - 1)) + 1;
xc = max(1, min(shownW, xc));
yc = round((y - YData(1)) / (YData(end) - YData(1)) * (shownH - 1)) + 1;
yc = max(1, min(shownH, yc));
```

**Brush cursor**: use `updateBrushCursorOffset()` — derives `coef_z` from `imageHandle.XData`, draws an ellipse (X radius × coef_z, Y radius × 1). Store `brushPrevXY` in **data/axes coords**; convert to CData indices only for rasterizing.

---

## Child Dialog Keyboard Shortcuts

Child dialog controllers (Quantification, Annotations, CropObjects, etc.) are separate windows launched via `startController`. They do **not** receive `MibController` and cannot use `gui_WindowKeyPressFcn` directly.

**Solution:** `utils.childWindowKeyPressFcn` — a shared handler that reads the same `KeyShortcuts` table as the main window but only handles a whitelisted set of actions.

| Action | Shortcut | What it does |
|--------|----------|--------------|
| Undo | Ctrl+Z (from KeyShortcuts) | `mibModel.undo()` + `notify(mibModel, 'ShowImage')` |
| Escape | Escape key | Calls `controller.closeWindow()` |

**Wiring (one line in `addCallbacks.m`):**

```matlab
obj.view.gui.WindowKeyPressFcn = @(h,d) utils.childWindowKeyPressFcn(obj, h, d);
```

**Key design points:**
- `mibModel.undo()` is standalone — no MibController dependency needed
- `notify(mibModel, 'ShowImage')` triggers main-window refresh via existing listener
- Edit fields / text areas are skipped (same guard as main handler)
- Extensible: add more `case` entries in the switch block for additional actions
- First adopter: `controllers.Quantification` (in `addCallbacks.m`)

**Do NOT pass `MibController` into child dialogs** just for keyboard shortcuts — the shared utility handles it through `mibModel` alone.

---

## Orientation Switching (Alt+1/2/3)

Use `'resize'` mode (not `'fitToScreen'`) to preserve magnification:

```matlab
% in MibQuickAccessBar.orientationChange:
savedMag = dataset.magFactor;
dataset.transpose(newOrient);
dataset.setAxesLimits([newW/2 - halfW, newW/2 + halfW], [newH/2 - halfH, newH/2 + halfH]);
dataset.magFactor = savedMag;
Options.mode = 'resize';   % keeps magFactor; fitToScreen would reset zoom
notify(obj.mibModel, 'UpdateDatasetAxes', core.ToggleEventData(Options));
```
