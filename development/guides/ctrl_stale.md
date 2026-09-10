# Stale modifier keys (the "Ctrl is stuck" bug)

> Symptom the user sees: the mouse wheel over the image resizes the brush instead of changing
> the slice, and the brush cursor is stuck at eraser size. Tapping Ctrl over the image clears it.

## Why MIB keeps its own note of the modifier keys

MIB cannot ask MATLAB "is Ctrl down right now?" - `UIFigure.CurrentModifier` and
`UIFigure.SelectionType` both go stale after a blocking call and cannot be trusted
(`gui_ScrollWheelFcn.m:39-44`, `gui_WindowButtonDownFcn.m:561-570`). Instead the state is
tracked from the key events:

| State | Set by | Cleared by | Meaning |
|-------|--------|------------|---------|
| `MibController.currentModifier` | `gui_WindowKeyPressFcn.m:29` | `gui_WindowKeyReleaseFcn.m:31` | `{}` / `{'control'}` / `{'shift','control'}` ... |
| `MibController.view.ctrlPressed` | `gui_WindowKeyPressFcn.m:473` (`case 'control'`) | `gui_WindowKeyReleaseFcn.m:33-38` | how much the brush radius was enlarged for eraser mode |

Both are read all over MIB: `gui_ScrollWheelFcn.m:46`, `gui_WindowButtonDownFcn.m:30` and
`:570`, `MibSelection/*`, `MibRoi/roiToSelection`, `InstanceEditor/imageButtonDown`, etc.

**The whole bug is that the "key released" message sometimes never arrives, so the note is
never erased.** MIB then acts on a key the user let go of minutes ago.
`gui_WindowKeyReleaseFcn` is the only code that undoes *both* pieces of state - clearing
`currentModifier` alone leaves the brush enlarged.

## Two failure modes, and they need different fixes

They are frequently confused; the fix for one does nothing for the other.

### A. The event is delivered, but to the wrong window

A child window opened while a modifier is held takes the keyboard focus, so the release goes
to *it*. A child that registers no `WindowKeyReleaseFcn` silently drops it.

Reproduce: hold Ctrl over the image, click **Display** in the Selection panel to open
DisplayAdjust, release Ctrl while that window has focus. Scrolling is now broken.
`DisplayAdjust.m:298` registers a `WindowKeyPressFcn` and no release handler; before the fix
only `MibActiveDataset`, `MibDirContents` and `MibFijiConnect` registered one at all.

**This mode is fixable portably** - the event exists, it just needs re-routing.

### B. No event is delivered at all

MATLAB is blocked and its event loop is not running, so the release is lost rather than
misdelivered. Three sources:

- `pyrun` into SAM (`segmentationSAM`, `segmentationSAM2`)
- native OS modals - `uiputfile` (`saveImage.m:305`)
- long compute with a progress dialog - DeepMIB training, `invertImage`

**Nothing can re-route an event that was never sent.** Either the code clears the state
itself on the way out, or it asks the operating system what is really held.

## How it is handled now

### Mode A - one fix, all platforms, every dialog

`utils/startController.m:131` (`iWireKeyReleaseToMib`, `:145`). Every child window in MIB is
constructed through this one funnel, so wiring the child figure's `WindowKeyReleaseFcn` back
to `mibController.gui_WindowKeyReleaseFcn` there covers all of them at once - including
plugin windows, which reach it through the same `parentObj.mibController` path.

Guarded: an existing handler is never overwritten (a dialog that manages key releases itself
is assumed to know better), non-`matlab.ui.Figure` views (AppContainer) are skipped, and the
whole thing is in a `try`/`catch` so a window that cannot be wired still opens.

Verified against a real DisplayAdjust opened through `startController`: `WindowKeyReleaseFcn`
present where it was empty before, and firing it clears both `currentModifier` and
`ctrlPressed`.

### Mode B - per-site, because each site is its own blocking call

| Site | File | What it does |
|------|------|--------------|
| Ctrl+S "Save image as..." | `gui_WindowKeyPressFcn.m:299` | calls `gui_WindowKeyReleaseFcn` before `uiputfile` |
| Ctrl+I "Invert image" | `gui_WindowKeyPressFcn.m:162` | same, before the progress dialog |
| DeepMIB preprocess / train / predict | `MibDeep/start.m:20` | `onCleanup` -> `iReleaseModifierKeys` (`:119`), so every exit path including errors |
| SAM click | `gui_WindowButtonDownFcn.m:813` | re-synchronises against the real keyboard, see below |
| add-to-material, Ctrl+V, Ctrl+Shift+V, Ctrl+Z | `gui_WindowKeyPressFcn.m:210, 306, 310, 368` | pre-existing, clear `currentModifier` only |
| keypress from a panel with no release handler | `gui_WindowKeyPressFcn.m:491` | pre-existing fallback |

**Known gap:** the four pre-existing sites clear `currentModifier` but not `ctrlPressed`, so
after Ctrl+V the scroll wheel works while the brush stays enlarged. Only visible when
Preferences -> Segmentation tools -> Brush -> *Eraser radius factor* is not `1`. Switching
them to `gui_WindowKeyReleaseFcn` would close it; left alone as working code that predates
this work.

### SAM is a special case, and why it cannot just clear

Ctrl and Shift are SAM's own refinement modifiers - Ctrl-click adds a negative point, Shift a
positive one (`gui_WindowButtonDownFcn.m:687-700`). A blanket clear after each SAM call would
make the next held-key refinement click fall into the `isempty(modifier)` branch and **start a
new object** instead of refining the current one. The interactive session has no end event to
hook either: `SAMsegmenter.Points.Value` is only reset when the segmentation tool changes
(`MibSegmentation/segmentationTool_Callback.m:102`).

So SAM does not clear - it **re-synchronises**:

```matlab
[realModifier, modifierIsKnown] = utils.trueModifierKeys();
if modifierIsKnown
    if ~any(strcmp(realModifier, 'control'))
        obj.mibController.gui_WindowKeyReleaseFcn([], []);   % also restores the brush radius
    end
    obj.mibController.currentModifier = realModifier;
elseif samMethodVal == 2 && isequal(obj.mibController.currentModifier, {'shift'})
    obj.mibController.currentModifier = {};      % the historical narrow rule
end
```

Ctrl genuinely still down -> stays `{'control'}` and refinement keeps working; released ->
`{}` and scrolling works.

`mib/+utils/trueModifierKeys.m` reads the live keyboard through .NET
`System.Windows.Forms.Control.ModifierKeys`. Measured: **0.055 ms** per raw query, **0.28 ms**
through the function with the assembly cached in a persistent - negligible against a SAM click
that spends hundreds of ms in Python. Bit decoding verified against all seven combinations of
`Keys.Shift` (65536) / `Control` (131072) / `Alt` (262144).

Its contract has two outputs on purpose: an empty `modifier` means "nothing held" **only**
when `available` is true. On a platform where the OS cannot be asked it returns empty *and*
`available = false`, and the caller decides.

## Platform coverage today

| Situation | Windows | Linux / macOS |
|-----------|---------|---------------|
| Any child dialog (mode A) | fixed | **fixed** - pure MATLAB |
| Ctrl+S, Ctrl+I | fixed | **fixed** - targeted resets, no OS call |
| DeepMIB train / predict | fixed | **fixed** - same |
| SAM click (mode B, `pyrun`) | exact | **not fixed** |

On Linux and macOS `ispc` is false, `trueModifierKeys` returns `available = false`
immediately, and the SAM branch falls back to the historical narrow rule
(*Interactive 3D* + Shift alone). That is deliberate: a wider reset there would be a guess
that could break held-key refinement, so those platforms are left **exactly as they were**
rather than trading one bug for a worse one. MIB is compiled for all three platforms, so this
is a real gap, not a theoretical one.

## Possible future fixes for macOS and Linux

Only mode B is open, and only for SAM. In rough order of how promising they look.

### 1. A Python backend for `trueModifierKeys` (most promising)

SAM users already have a working Python environment, so the marginal cost is one package.
`pynput` exposes the live keyboard state on Windows, macOS and Linux:

```python
from pynput import keyboard
# a non-blocking Listener keeps a set of currently pressed keys
```

`trueModifierKeys` is already shaped for this - add the backend behind the same
`available` flag and no call site changes. Caveats to check before committing:

- **macOS requires Accessibility permission** for any process reading global input. MATLAB (or
  the compiled MIB app) would have to be granted it in System Settings, and the failure mode
  when it is not granted must degrade to `available = false`, not an error dialog.
- **Linux/Wayland** blocks global input capture by design; `pynput` works on X11 and is
  unreliable under Wayland. Expect `available = false` on modern desktops.
- A `pyrun` round trip costs far more than 0.06 ms - measure before putting it on the click
  path, and consider a persistent listener rather than a per-call query.

### 2. `drawnow` after the Python call (cheapest, worth testing first)

The premise of mode B is that the release is *lost*. If it is in fact only *queued* while
MATLAB is blocked, a `drawnow` on return would deliver it and `gui_WindowKeyReleaseFcn` would
fire by itself - portable, no dependency, no OS call.

There is direct evidence for this: `segmentationSAM.m:566-567` already does

```matlab
% this pause is required to clear the sticky key modifier states
pause(0.1);
```

and the comment claims it works. **`segmentationSAM2` has no equivalent.** So the first
experiment is simply: does adding the same yield to the SAM2 path fix it on Windows without
`trueModifierKeys`? If yes, the same line fixes Linux and macOS for free.

Risk to weigh: re-entering the event loop inside a mouse-down handler can let another click or
callback run before the current one finishes. `pause(0.1)` also costs a tenth of a second per
click.

### 3. Java AWT - investigated and rejected

MATLAB ships a JVM on every platform, but AWT has **no API to poll global keyboard state**.
`Toolkit.getLockingKeyState` covers only CapsLock / NumLock / ScrollLock. Modifier state can
only be read off an event you already received - which is precisely the channel that is broken
here. `addAWTEventListener` sees only events in Java windows, and MIB's uifigures are
CEF/web-based, so it sees nothing.

### 4. Shelling out to the window system - rejected

`xset q` / `xinput query-state` on X11, and nothing sane on macOS short of a compiled helper.
Fragile, slow, and X11-only, so it dies under Wayland. Not worth it.

### 5. Do nothing on those platforms

Defensible: mode A is fixed everywhere and covers most of the real-world reports, mode B on
SAM leaves an annoyance that one tap of Ctrl clears. Document it in the user docs rather than
carrying a fragile dependency.

## Reproducing

The general recipe, for any of the sites:

1. Hold Ctrl over the image view
2. Trigger something that opens a blocking window **while still holding it**
3. Release Ctrl while that window is on screen

Releasing before the window appears does not reproduce it - the release has to land while
another window owns the keyboard.

Check the state directly rather than by feel:

```matlab
fprintf('modifier=[%s]  ctrlPressed=%d\n', ...
    strjoin(cellstr(mib.currentModifier), ','), mib.view.ctrlPressed);
```

Healthy is `modifier=[]  ctrlPressed=0`. Anything else once the keyboard is untouched is the
bug. And to check what the OS reports (Windows):

```matlab
disp('hold Ctrl now...'); pause(3);
[m, a] = utils.trueModifierKeys();
fprintf('available=%d  held={%s}\n', a, strjoin(m, ','));
```
