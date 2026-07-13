# Mouse cursor recentering after zoom / view-move

How MIB moves the OS mouse cursor to the centre of a document's image axes after a
zoom step, a middle-click `moveView`, or an orientation switch — and how it copes
with docked vs. undocked windows, multiple monitors, and OS display scaling.

## The problem

After a zoom in/out, MIB recenters the OS cursor onto the centre of the active
document's image axes so the next zoom keeps zooming around the same image point.
The original implementation computed the target screen pixel purely from the
**main AppContainer window** geometry (`mibView.gui.WindowBounds` + panel widths +
split offsets). That is only valid while the document is **docked** inside the main
window. When a document is **undocked** into its own floating window, the cursor
jumped to a wrong position derived from the main window. Multi-monitor and OS
display-scaling cases were also fragile.

## Key entry points

| File | Role |
|------|------|
| `+controllers/@MibImageDocument/centerCursorInAxes.m` | thin wrapper: gets the target and assigns `groot().PointerLocation` |
| `+controllers/@MibImageDocument/axesCenterPointerLocation.m` | computes the target screen-pixel location (all the logic) |
| `+controllers/@MibStatusBar/zoomEdit_Callback.m` | zoom recenter; also picks which document the cursor is over (multi-doc) |
| `+controllers/@MibImageDocument/gui_WindowButtonDownFcn.m` | middle-click / click `moveView` recenter (×3 call sites) |
| `+controllers/@MibQuickAccessBar/orientationChange.m` | orientation switch recenter (ribbon-triggered) |
| `+controllers/@MibImageDocument/gui_WinMouseMotionFcn.m` | maintains the per-doc `isInsideAxes` flag used to pick the hovered document |

`centerCursorInAxes(cursorOverAxes)` and
`axesCenterPointerLocation(cursorOverAxes)` take an optional logical flag telling
them whether the OS cursor is currently over this document's axes.

## Solution: two strategies

### 1. Runtime self-calibration — *preferred* (`cursorOverAxes = true`)

Used by the zoom and middle-click/click recenters, where the cursor is provably
over the axes (the code has just read `imViewAxes.CurrentPoint` / the user just
clicked). At that instant the figure-client cursor position corresponds to the
live pointer location, so we only need to shift the cursor by the small **in-axes
displacement** to the axes centre:

```matlab
axCentre = ax.Position(1:2) + ax.Position(3:4)/2;     % axes centre, figure-client px
cpFig    = fig.CurrentPoint;                          % cursor, figure-client px (logical)
target   = groot().PointerLocation + (axCentre - cpFig) * scaling;
```

Why this is robust:
- **No window/monitor/chrome geometry** — no `WindowBounds`, no monitor lookup, no
  hardcoded chrome insets. Works identically docked, floating, and on any monitor.
- The only quantity converted is a *small displacement within one axes*, so any
  error is proportional to that displacement (and tiny when the cursor is already
  near centre) — unlike absolute-coordinate math where scaling/offset errors scale
  with the full multi-thousand-pixel coordinate.

Guard: `fig.CurrentPoint` is bounds-checked against `fig.Position(3:4)` (the client
size, reliable in any dock state). If the cursor is not actually inside the figure,
it falls through to the geometric path.

### 2. Geometric reconstruction — *fallback* (`cursorOverAxes = false`)

Used only when the cursor is **not** over the axes — currently just the
ribbon-triggered orientation switch. Reconstructs the absolute screen position.

**Floating document** — from `figureDoc.WindowBounds`:
```matlab
winBounds  = figureDoc.WindowBounds;          % [left bottom width height]
borderSide = (winBounds(3) - figureDoc.Figure.Position(3)) / 2;   % auto-derived chrome
m          = monitor containing winBounds(1)  % via MonitorPositions
clientLeft   = winBounds(1) + borderSide;                 % global X
clientBottom = monPos(m,2) + winBounds(2) + borderSide;   % global Y (monitor offset + local)
pointerX = (clientLeft   + axCentre(1)) * scaling;
pointerY = (clientBottom + axCentre(2)) * scaling;
```

**Docked document** — `figureDoc.WindowBounds` is `[-1 -1 -1 -1]` and
`figureDoc.Figure.Position` is `[1 1 w h]`, so the docked client's screen position
cannot be read from any property. It is reconstructed from the main window:
```matlab
screenX = mainWB(1) + leftPanel + splitOffsetX + axCentre(1);
screenY = mainWB(2) + mainWB(4) - bottomPanel - axCentre(2);
idx        = monitor containing screenX;
monitorTop = monPos(idx,2) + monPos(idx,4) - 1;
pointerX = (screenX + 9) * scaling;
pointerY = (monitorTop - (screenY - monPos(idx,2)) + 31) * scaling;
```

## Picking which document the cursor is over (multiple sets)

With more than one open set the recenter must act on the document the cursor is
**physically over** — otherwise the wrong set is zoomed/moved and the cursor is
recentered using a *hidden* document's stale `fig.CurrentPoint`, flinging it out of
the window. `zoomEdit_Callback` selects the target document like this:

```matlab
detectedDocIdx = obj.mibModel.Sets.selectedSet;
for iDoc = 1:numDocs
    if obj.mibController.cImageDoc{iDoc}.isInsideAxes
        detectedDocIdx = iDoc;  break;
    end
end
% then sync Sets.selectedSet / id to detectedDocIdx
```

`isInsideAxes` is the right primitive — each document's own `gui_WinMouseMotionFcn`
sets it from the axes `CurrentPoint` vs `XLim/YLim`, so it is correct regardless of
docked/floating and **tabbed/split** layout. (The earlier `figureDoc.Figure
.Position(3)` width-accumulation heuristic was wrong: new sets are added as **stacked
tabs** — same `Tile`, identical `Figure.Position`, only one `Showing` — so the
width walk always selected doc 1.) The keyboard zoom handler
(`gui_WindowKeyPressFcn`) already uses the same `isInsideAxes` loop to set
`Sets.selectedSet` before calling the zoom.

### `isInsideAxes` staleness fix (split view)

`isInsideAxes` is only updated by the figure currently receiving motion events; it
was **never reset when the cursor left** a document. In split view that left *both*
documents with `isInsideAxes = 1`, and the first-match loop picked doc 1 — so zooming
the right panel zoomed the left one. Fix: since only one figure can hold the cursor,
`gui_WinMouseMotionFcn` now clears the *other* documents' flags on every motion
event:

```matlab
cImageDocs = obj.mibController.cImageDoc;
if numel(cImageDocs) > 1
    for iOtherDoc = 1:numel(cImageDocs)
        if cImageDocs{iOtherDoc} ~= obj
            cImageDocs{iOtherDoc}.isInsideAxes = false;
        end
    end
end
```

This makes `isInsideAxes` single-valued, fixing both the zoom detection and the
keyboard handler's `hoverDocIdx` in split view.

## Coordinate-system facts discovered (live probing of `FigureDocument`)

The `matlab.ui.internal.FigureDocument` docked/floating API is undocumented; these
were established by probing a running MIB and calibrating against the real cursor
(`offset = groot().PointerLocation - fig.CurrentPoint`):

- **`figureDoc.Docked`** — logical: `1` docked, `0` floating. (`~figureDoc.Docked`
  is the floating test.)
- **`figureDoc.WindowBounds`** — `[left bottom width height]` of the floating
  window; `[-1 -1 -1 -1]` while docked. **Asymmetric:** `left` is a GLOBAL desktop
  X, but `bottom` is relative to the BOTTOM of the window's monitor → add
  `monPos(m,2)` to get a global bottom-left `PointerLocation` Y. (On the primary
  monitor `monPos(m,2)≈1`, so the bug only appears on a vertically-offset second
  monitor — e.g. a 241 px offset showed up as a 241 px error.)
- **`figureDoc.Figure.Position`** — gives only the client *size* `[1 1 w h]`, never
  a usable desktop position. Window chrome = `WindowBounds(3:4) - Position(3:4)`
  (equal left/right/bottom borders; the larger height remainder is the title bar).
- **Main window `mibView.gui.WindowBounds`** uses a *different* convention from the
  floating one; for the docked Y-flip the `monitorTop` and vertical offset
  `monPos(idx,2)` must both come from the monitor **containing the axes** — using
  the *primary* monitor instead introduces a ~240 px error on a vertically-offset
  second monitor.
- The docked chrome insets `+9` (X) and `+31` (Y) were calibrated against the real
  cursor (the original code used `+8`/`+26`, ~5 px off).

## OS display scaling (125% / 150%)

`preferences.System.GUI.systemscaling` is a **manual** preference (default `1`),
entered in Preferences → System scaling. It is **not** auto-detected from the OS, so
at Windows 125%/150% the user must set it to `1.25`/`1.5`.

The runtime formula multiplies the in-axes displacement by `systemscaling`, which is
correct because `groot().PointerLocation` is reported in physical px while
`fig.CurrentPoint` / `ax.Position` are logical px, differing by exactly the OS
scaling. **Verified working at 1.0 and 1.25.** Because the converted quantity is a
small displacement, the approach also degrades gracefully if the pref is slightly
off, rather than failing badly like absolute-coordinate math.

## Validation performed

Real-cursor calibration (`offset = PointerLocation - fig.CurrentPoint`) on a running
MIB, all confirmed pixel-accurate:

| Case | Result |
|------|--------|
| Docked, primary monitor | ✅ |
| Docked, second monitor | ✅ (after fixing the containing-monitor Y-flip) |
| Floating, primary monitor | ✅ |
| Floating, second monitor | ✅ (after adding the `monPos(m,2)` Y-offset) |
| OS scaling 1.25 (pref set to 1.25) | ✅ |
| Multiple sets, tabbed (stacked) | ✅ (after switching detection to `isInsideAxes`) |
| Multiple sets, split (side-by-side) | ✅ (after the `isInsideAxes` staleness fix) |

## Known residual (left as-is)

At extreme zoom (~3584%) a ~1 *image*-pixel "up" jump remains. This is the
pre-existing pixel-snap in the recenter path, not the cursor math:

```matlab
[xy2(1),xy2(2)] = obj.mibModel.convertMouseToDataCoordinates(...);
xy2 = ceil(xy2);     % rounds the data coordinate UP by up to 1 image pixel
```

`ceil` biases the recenter target up/left by up to one image pixel; visible only at
very high magnification. Shared by docked and floating. Changing `ceil` → `round`
would centre and halve the bias, but it is a behaviour change to the shared recenter
path and was intentionally left unchanged.
