# UIFigure & Icon Caching for MIB3 Dialogs

**Status**: Implemented (2026-05-27)

---

## Problem

Compiled MIB has noticeable lag when opening dialogs. `uifigure()` creation in compiled MATLAB apps costs ~200-400ms due to web engine initialization. Icon loading (`imread` + alpha blend + `imresize`) adds ~30-80ms per call.

## Files Modified

| File | Figure cache | Icon cache | Notes |
|------|:-----------:|:----------:|-------|
| `+utils/+dlgs/inputUniversalDlg.m` | Yes | Yes (alpha-composite) | 401 call sites; most-used dialog |
| `+utils/+dlgs/inputQuestDlg.m` | Yes | Yes (alpha-composite) | Question dialogs with 2-3 buttons |
| `+utils/+dlgs/inputSingleDlg.m` | Yes | No (uses file path) | Single text/spinner input |
| `+utils/+dlgs/showErrorDialog.m` | Yes | No (uses file path) | Error display with copy button |
| `+utils/+dlgs/showMilestoneDialog.m` | Yes | No (special media) | Celebration dialog with video/image |

Each dialog has its **own** persistent `cachedFigure` — they don't share figures.

## Design Decisions

| Option | Verdict | Reason |
|--------|---------|--------|
| **A: Persistent uifigure + `uiwait`/`uiresume`** | **Chosen** | Saves ~200-400ms per dialog (compiled); proven pattern |
| B: Pool of pre-created uifigures | Rejected | No concurrent dialogs observed — overkill |
| C: Pre-create at app startup | Rejected | Adds to startup time; lazy caching achieves the same |
| D: Lazy background timer | Rejected | Over-engineered; persistent variable gives lazy caching naturally |
| **E: Icon caching** | **Chosen** | Saves ~30-80ms per call; applied to dialogs that alpha-composite icons |

### Concurrent dialog safety

- All dialog calls are sequential blocking — no concurrent/nested calls observed
- Safety guard: only reuse if `cachedFigure.Visible == 'off'`; otherwise create fresh figure
- If cached figure is externally deleted, `isvalid()` fails → fresh figure created

---

## Common Pattern

All five dialogs follow the same caching pattern:

### Figure creation

```matlab
persistent cachedFigure;

if ~isempty(cachedFigure) && isvalid(cachedFigure) && strcmp(cachedFigure.Visible, 'off')
    fig = cachedFigure;
    delete(fig.Children);          % clear old widgets
    fig.Name = dlgTitle;
    fig.WindowKeyPressFcn = '';    % reset callbacks defensively
    fig.CloseRequestFcn = 'closereq';
else
    fig = uifigure('Name', dlgTitle, 'Visible', 'off');
    fig.Tag = 'dialogTagName';
    cachedFigure = fig;
end
fig.WindowStyle = ...;             % set after cache check
fig.Position(3:4) = [...];
```

### Blocking mechanism

| Before | After |
|--------|-------|
| `waitfor(fig)` | `uiwait(fig)` |
| `delete(fig)` in callbacks | `fig.Visible = 'off'; uiresume(fig)` |

Widget values are read BEFORE hiding — widgets are still valid at that point.

### drawnow ordering

```matlab
fig.Visible = 'on';   % was after drawnow — caused focus warnings
drawnow;
focus(targetWidget);
```

### CloseRequestFcn

Set **after** layout is built (callbacks reference nested functions):
```matlab
fig.CloseRequestFcn = @(~,~) onCancel();  % or onClose()
```

---

## Icon Caching (inputUniversalDlg, inputQuestDlg)

These dialogs alpha-composite PNG icons against the figure background color. The composited images are cached in a persistent `configureDictionary("string", "cell")`.

```matlab
persistent iconCompositeCache;   % dictionary: cacheKey -> composited uint8
persistent iconCacheBgColor;     % RGB triplet used for compositing

% Initialize
if isempty(iconCompositeCache)
    iconCompositeCache = configureDictionary("string", "cell");
    iconCacheBgColor = figBgColor;
end
% Invalidate on theme/bg change
if ~isequal(iconCacheBgColor, figBgColor)
    iconCompositeCache = configureDictionary("string", "cell");
    iconCacheBgColor = figBgColor;
end

cacheKey = string(sprintf('%s_%d', iconFilename, iconWidth));
if isKey(iconCompositeCache, cacheKey)
    iconImg = iconCompositeCache{cacheKey};       % retrieve (cell extraction)
else
    % ... imread + alpha blend + imresize ...
    iconCompositeCache(cacheKey) = {iconImg};     % store (cell-wrapped)
end
```

**Important**: Must use `configureDictionary("string", "cell")`, not `dictionary(string.empty, cell.empty(1,0))` — the latter crashes on dimension mismatch when storing matrices.

Dialogs that use `uiimage(..., 'ImageSource', iconPath)` (file path directly) don't need icon caching — MATLAB handles loading internally.

---

## Per-File Details

### inputUniversalDlg.m

- **Persistent vars**: `cachedFigure`, `iconCompositeCache`, `iconCacheBgColor`
- **Figure tag**: `'inputUniversalDlg'`
- **Blocking**: `waitfor` → `uiwait`; `delete` → hide+uiresume in `onOK`/`onCancel`
- **Bug fixes**: Added `CloseRequestFcn` (was missing — X button returned stale answer); `drawnow` reorder

### inputQuestDlg.m

- **Persistent vars**: `cachedFigure`, `iconCompositeCache`, `iconCacheBgColor`
- **Figure tag**: `'inputQuestDlg'`
- **Blocking**: `waitfor` → `uiwait`; `delete` → hide+uiresume in `onButton`/`doCancel`
- **Callbacks**: `WindowKeyPressFcn` and `CloseRequestFcn` wired after layout (were set at creation before)
- Already had `CloseRequestFcn` → `onClose` → `doCancel`

### inputSingleDlg.m

- **Persistent vars**: `cachedFigure`
- **Figure tag**: `'inputSingleDlg'`
- **No icon cache**: uses `uiimage('ImageSource', iconPath)` — file path, no alpha compositing
- **Blocking**: `waitfor` → `uiwait`; `delete` → hide+uiresume in `onOK`/`onCancel`
- **Bug fix**: Added `CloseRequestFcn = @(~,~) onCancel()` (was missing)

### showErrorDialog.m

- **Persistent vars**: `cachedFigure`
- **Figure tag**: `'showErrorDialog'`
- **No icon cache**: uses `uiimage('ImageSource', iconPath)` — file path, no alpha compositing
- **Blocking**: already used `uiwait`; changed `uiresume+delete` → `hide+uiresume` in `onClose`
- `CloseRequestFcn` set after layout build
- **Note**: `ParentFigure=[]` triggers legacy `errordlg()` fallback (line ~148) — bypasses cached figure entirely

### showMilestoneDialog.m

- **Persistent vars**: `cachedFigure`
- **Figure tag**: `'showMilestoneDialog'`
- **No icon cache**: uses video/image media, not standard puffin icons
- **Blocking**: already used `uiwait`; changed `uiresume+delete` → `hide+uiresume` in `onOK`/`onClose`
- **Video timer**: `stopTimer()` called before hiding — timer is stopped and deleted before figure is hidden
- `CloseRequestFcn` set after layout build (was set at creation before)
- VideoReader and timer are local variables — cleaned up when function returns after `uiresume`

---

## Verification

Tested in MATLAB (2026-05-27):

### inputUniversalDlg
1. Fresh call — numeric + text fields, puffin icon loaded
2. Cached reuse — different widget count/types, figure recycled
3. MsgBoxOnly mode — reused figure switches layout
4. Back to normal — dropdown after MsgBox, figure reused
5. Figure persistence — 1 hidden valid figure cached

### inputQuestDlg
1. Fresh call — 2-button question, icon displayed
2. Cached reuse — different buttons/title, figure recycled
3. Figure persistence — 1 hidden valid figure cached

### inputSingleDlg
1. Fresh call — text editfield
2. Cached reuse — spinner widget (different type), figure recycled
3. Figure persistence — 1 hidden valid figure cached

### showErrorDialog
1. Tested with ParentFigure=[] (legacy fallback)
2. Figure caching active when ParentFigure is provided

### showMilestoneDialog
- Not tested interactively (requires `userPrefs.Tiers` struct)
- Code analysis clean; follows same proven pattern

### Still to verify
- Modal dialogs across all four dialog types
- Compiled standalone build — measure actual latency improvement
- Sequential rapid opens (10+ dialogs) for each type
- showMilestoneDialog with video playback + figure reuse
