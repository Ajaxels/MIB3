# File Drag-and-Drop in MATLAB uifigure / AppContainer Apps

How to accept OS-level file drops into a MATLAB app and dispatch the filenames
to your own callback, without the Chromium engine hijacking the drop with its
own behaviour (navigate to file, Save-As prompt, red "no-parking" cursor).

**Reusable helper:** `utils.attachFileDnD` (see `mib/+utils/attachFileDnD.m`) —
wraps the whole bridge into a single call. Most users should only need the
[quick-start](#quick-start). The [internals](#internals) section documents how
the helper works for anyone who needs to modify it.

Reference call site: `mib/+views/@MibView/doPostInitializationTasks.m`.

> **⚠️ Status on MATLAB R2026a (preview): this helper intermittently crashes
> MATLAB.** Dropping a file onto the image-document figure canvas can corrupt
> the process heap (`STATUS_HEAP_CORRUPTION`, `ntdll.dll`) inside CEF's native
> drag handler — before any code here runs, so it cannot be caught or worked
> around in MATLAB. See [R2026a native drop crash](#r2026a-native-drop-crash-status_heap_corruption--unresolved)
> below. A `uihtml`-based drop zone is the intended replacement (not yet
> implemented). Repro + bug report: `development/dnd_bug_repro/`.

---

## Quick start

Three arguments: the webwindow, a `uifigure` living inside it, and your open
callback.

```matlab
obj.controller.dndBridgeButton = utils.attachFileDnD( ...
    obj.controller.mibWebWindow, ...                          % matlab.internal.webwindow
    obj.handles.panels.selectionPanel.Figure, ...             % any uifigure in the same webwindow
    @(params) obj.controller.dragNdrop_Callback(params));     % your open handler
```

> The callback **must** be wrapped in `@(params) ...`. MATLAB's `@` syntax
> cannot create a method handle from chained property access —
> `@obj.controller.dragNdrop_Callback` fails at invocation time with
> *"Undefined function 'obj.controller.dragNdrop_Callback' for input
> arguments of type 'cell'"*. The explicit anonymous-function wrapper
> captures `obj.controller` correctly.

Your callback receives a cell `params = {webwin, filenames}` — identical to
the shape MATLAB's native `FileDragDropCallback` produces:

```matlab
function dragNdrop_Callback(obj, parameterIn)
    % parameterIn{1}: webwindow handle (usually unused)
    % parameterIn{2}: char array of filenames, one per row, space-padded
    filenameList = cell(size(parameterIn{2},1), 1);
    for k = 1:size(parameterIn{2}, 1)
        filenameList{k} = cellstr(parameterIn{2}(k,:));
    end
    % ... open each file ...
end
```

Keep the returned button handle alive (e.g. on your controller): deleting it
detaches the bridge. The helper itself is stateless — the drop-state for each
attachment lives in that button's `UserData`.

### Where to call it

- **After the webwindow is visible.** `enableDragAndDropAll` needs the window
  grabbed. In MIB3 this is done from `doPostInitializationTasks` after the
  initial `drawnow; pause(2)`.
- **With a uifigure that lives in the same Chromium document as the drop
  target.** For an `AppContainer` app, pass the `.Figure` of any `FigurePanel`
  you've added to the container. A standalone `uifigure(...)` gets its own
  separate webwindow, so you can either pass that figure and *its* webwindow,
  or skip it entirely — but you cannot mix a main-window webwindow with a
  child-dialog figure.

### Alternative: route via the main window's existing bridge

Child dialogs that use `DivFigurePlatformHost` (undocked AppContainer documents,
URL port 31515) cannot host a bridge because their Chromium window is not
registered in any MATLAB webwindow manager and cannot be reached by
`attachFileDnD`. For these windows the practical fallback is to **intercept the
extension in the main window's drop callback and forward to the child
controller**.

In `MibController.dragNdrop_Callback` add a guard at the top of the
extension-routing block:

```matlab
% Route .mibcfg to DeepMIB if it is open; always intercept so the extension
% never falls through to the image loader (which would error on unknown ext).
if strcmpi(extLower, '.mibcfg')
    deepMibIdx = find(strcmp(obj.childControllersIds, 'controllers.MibDeep'), 1);
    if ~isempty(deepMibIdx) && isvalid(obj.childControllers{deepMibIdx})
        obj.childControllers{deepMibIdx}.loadConfig(filenameList{1});
        status = true;
    else
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            'DeepMIB window must be open to load a *.mibCfg config file.', ...
            {}, {}, 'Drag and Drop', dlgOpt);
    end
    return;   % always return — never fall through
end
```

Key rules for this pattern:
- **Always `return` unconditionally** — even when DeepMIB is closed. Letting an
  unrecognised extension fall through to `loadImages` triggers an extension-
  registry error.
- **Show a warning when the child is not open.** The user dropped a file with a
  purposeful intent; a silent no-op is confusing.
- The child controller is found via `obj.childControllersIds` (populated by
  `startController`) using the exact string passed to `startController`, e.g.
  `'controllers.MibDeep'`.

### Child windows need their own bridge

Each child dialog opened via `obj.startController(...)` (or anything that
creates its own `uifigure`) gets its own Chromium document. The main window's
bridge does not cover it. Call `utils.attachFileDnD` again from the child's
initialization, passing **that** child's webwindow and a figure inside it.

### Finding the webwindow

**Two webwindow managers exist in R2025+:**

| Window type | Manager | URL port |
|-------------|---------|----------|
| AppContainer app (main MIB window) | `matlab.internal.webwindowmanager` | 31516 |
| Standalone mlapp / undocked figure | `matlab.internal.cef.webwindowmanager` | 31515 |

Match by **URL**, not title, using `matlab.ui.internal.FigureServices.getFigureURL(fig)`:

```matlab
figUrl = matlab.ui.internal.FigureServices.getFigureURL(fig);

% Primary: CEF manager for standalone mlapp windows
cefWW = matlab.internal.cef.webwindowmanager.instance.windowList;
matchIdx = find(strcmp(figUrl, {cefWW.URL}), 1);
if ~isempty(matchIdx)
    childWebwin = cefWW(matchIdx);
end

% Fallback: AppContainer manager
if isempty(childWebwin)
    wwList = matlab.internal.webwindowmanager.instance.windowList;
    matchIdx = find(strcmp(figUrl, {wwList.URL}), 1);
    if ~isempty(matchIdx)
        childWebwin = wwList(matchIdx);
    end
end
```

`utils.attachFileDnD` accepts both `matlab.internal.webwindow` and `matlab.internal.cef.webwindow` — both expose `enableDragAndDropAll`, `FileDragDropCallback`, and `executeJS`.

---

## Handling the drop

The mechanism delivers filenames; the callback decides what to do with them.
Reference implementation: `mib/+controllers/@MibController/dragNdrop_Callback.m`.

### Parse `parameterIn`

`parameterIn{2}` is a **char array**, one filename per row, right-padded with
spaces. Convert to a clean cellstr list before using:

```matlab
filenameList = cell(size(parameterIn{2},1), 1);
for k = 1:size(parameterIn{2}, 1)
    filenameList(k) = cellstr(parameterIn{2}(k,:));   % trims trailing spaces
end
[path, fn, ext] = fileparts(filenameList{1});
extLower = lower(ext);                                % always normalise case
```

### Ambiguous extensions: ask the user

In MIB3 many formats (`.tif`, `.am`, `.h5`, `.mat`, `.nrrd`, `.mrc`, …) can be
either an image or a segmentation model. Rules:

1. **Unambiguous model-only formats** (`.model`, `.mibcat`) always go to
   `mibModel.loadModel`.
2. **Ambiguous formats**: if no dataset is loaded yet
   (`strcmp(obj.mibModel.I{activeId}.image.filename, 'none.tif')`) load as
   image — there is nothing to attach a model to. Otherwise prompt the user:

```matlab
answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
    sprintf('Load the dropped file as an image or as a segmentation model?\n\n%s', ...
            filenameList{1}), ...
    'Drag-and-drop', 'Image', 'Model', 'Cancel', 'Image');
if strcmp(answer, 'Cancel'); return; end
loadAsModel = strcmp(answer, 'Model');
```

Use the 3-button form (`Image`, `Model`, `Cancel`, default `Image`) so the
user can back out of a mistaken drop. `inputQuestDlg` also returns `''` if the
dialog is closed via the window X — guard for both.

### Split-panel safety: use `getActiveId()`

`obj.mibModel.id` can be stale between clicks in split-panel mode. Always
use the accessor:

```matlab
activeId = obj.mibModel.getActiveId();      % not obj.mibModel.id
```

### Loading a specific model file

`loadModel` normally scans a directory by filename pattern. To force it to
load one exact file, pass the **full path** in `BatchOpt.FilenameFilter` —
`loadModel.m:226-227` detects this via `isfile(filterExpanded)` and takes
that file directly:

```matlab
BatchOpt = struct();
BatchOpt.DirectoryName  = {path};
BatchOpt.FilenameFilter = filenameList{1};   % full path triggers isfile branch
obj.mibModel.loadModel([], BatchOpt);
```

### Why not route by drop location?

Tempting idea: detect the panel under the mouse (image axes vs materials
table vs a specific split-view pane) and route accordingly. **It does not
work reliably in AppContainer.** `getpixelposition(h, true)` returns
coordinates relative to the widget's host uifigure, not the screen; the host
figure itself is docked inside a Chromium document whose screen position
isn't exposed by any public API. `get(0, 'PointerLocation')` gives screen
pixels, but you can't convert them into the docked figure's frame. Extension-
based routing + a confirmation dialog is the robust fallback.

---

## R2026a native drop crash (STATUS_HEAP_CORRUPTION) — UNRESOLVED

On MATLAB R2026a (preview, `26.1.0.x`), the native drag-and-drop path this
helper relies on (`webwindow.enableDragAndDropAll` + `FileDragDropCallback`)
**intermittently crashes MATLAB** when a file is dropped onto a docked
figure-document **canvas** (the image document):

```
Exception code : 0xc0000374   (STATUS_HEAP_CORRUPTION)
Faulting module: ntdll.dll
```

### Characteristics

- **Intermittent and cumulative** — often crashes on a later drop, sometimes
  after earlier drops succeeded; a whole run may not crash at all. This is the
  signature of heap corruption: the damage is *planted* during the drop but the
  visible crash lags until some later allocation hits the poisoned region.
- **Real HDF5 files (MATLAB v7.3 / MIB `*.model`) trigger it more readily** than
  freshly-saved samples or text-ish files — suspected (not confirmed) to involve
  Chromium content-sniffing the `\x89HDF…` signature, which is near-identical to
  PNG's `\x89PNG…`, and invoking a buggy native image decoder. Not deterministic.
- **The crash precedes `FileDragDropCallback`.** With crash-survivable logging
  (open→write→close at each stage), a crashing drop logs *nothing at all* — not
  even the first line of the callback. The corruption is entirely inside CEF's
  native handler, so it cannot be caught, deferred, or guarded from MATLAB.

### What does NOT fix it (all confirmed ineffective)

These were all tried and have no effect on canvas drops, because they run
*after* the crash point:

- `allowNavigation(false)` (permanent or bracketed per-drag) and `stopDownload()`
- leaving `FileDragDropCallback` unset (the corruption is upstream of it)
- deferring the load off the drop event with a timer
- capture-phase DOM `addEventListener` listeners

### Why the canvas can't be selectively excluded

- `enableDragAndDropAll` is **required** for *any* drop to reach the web layer.
  With it off — or with plain `enableDragAndDrop` — the DOM receives zero drag
  events and the cursor shows the no-drop sign over the entire window.
- With it on, CEF routes drops over the figure canvas to a **native surface that
  bypasses the DOM**. A live probe confirmed capture-phase `document` listeners
  receive **no** drag events over the canvas (only over the surrounding HTML
  panels), so the canvas drop cannot be intercepted in JS either.

### Workaround direction (uihtml — not yet implemented)

A `uihtml` component with custom HTML5 drag-and-drop is **crash-free**: it does
not use `enableDragAndDropAll` and never touches the native canvas surface
(verified — dropping the same `.model`/`.am` files onto a `uihtml` zone does not
crash). The catch: **MATLAB's CEF does not expose `File.path`** on dropped files
— only `name`, `size`, and the file **bytes** (via `FileReader`) are available.
MathWorks' own R2026a file-drop example (`dragdrop.html`) likewise works from
content, not a path.

So a `uihtml` drop zone must: read bytes via `FileReader` → send to MATLAB
(`sendEventToMATLAB` / `HTMLEventReceivedFcn`) → write a temp file → call
`loadImages` / `loadModel` on it, with a **size guard** that redirects very
large datasets to File ▸ Open (byte transfer through the data channel is
base64-encoded and impractical for multi-GB files). This is the planned MIB
replacement for `attachFileDnD`.

### Reproduction, report, and MathWorks contact

Self-contained material lives in **`development/dnd_bug_repro/`**:

| File | Purpose |
|------|---------|
| `dndCrashRepro.m` | Minimal AppContainer + figure-canvas repro; generates v7 and v7.3 (`.model`) samples to drop |
| `BUG_REPORT.md` | Full write-up: environment, repro steps, crash signature, findings, and **deterministic** reproduction under a heap verifier (`gflags /p /enable MATLAB.exe /full` or Application Verifier) |
| `email_to_ken.txt` | Summary sent to the MathWorks contact (crash + the `File.path` gap) |

Because the crash is intermittent, reproduce it **deterministically** under page
heap / Application Verifier — that faults at the corrupting drop instead of a
later random allocation.

---

## Gotchas

| Symptom | Cause | Fix |
|---------|-------|-----|
| File opens while still dragging, before mouse release | You wired `webwindow.FileDragDropCallback` directly instead of using the helper | Use `utils.attachFileDnD` |
| Dropped text file replaces the whole app UI | DOM defaults not cancelled | Use `utils.attachFileDnD` |
| Save-As dialog appears after a binary drop | Chromium's default for binaries | Use `utils.attachFileDnD` |
| **MATLAB hard-crashes (ntdll.dll `STATUS_HEAP_CORRUPTION`) when dropping files** | CEF's native drag handler corrupts the process heap; originally seen with JPEG/PNG (image decoder), and on **R2026a** also with HDF5 `*.model`/v7.3 files dropped on the figure canvas | **Partially mitigated, NOT fully fixed.** `allowNavigation(false)` reduced the image-decoder case, but on R2026a the corruption happens *before* any MATLAB callback and cannot be guarded — see [R2026a native drop crash](#r2026a-native-drop-crash-status_heap_corruption--unresolved). The intended fix is a `uihtml` drop zone. |
| Red no-parking 🚫 cursor while dragging | `dropEffect` not set (you modified the helper's JS and removed `dropEffect = 'copy'`) | Set it on **both** `ondragenter` and `ondragover` |
| Drop does nothing, no error | JS can't find the bridge button | Button must be a child of a `uifigure` rendered in the **same** Chromium document as the webwindow. Open DevTools (`webwin.openDevTools()`) and run the `querySelectorAll` line by hand to confirm. |
| Works in development, not deployed | `enableDragAndDropAll` called before webwindow is visible | Move the `attachFileDnD` call into a post-init hook, after `drawnow; pause(...)` |
| Linux, older than R2021a | `enableDragAndDropAll` was a no-op | Require R2021a+ |

### DevTools

`webwin.openDevTools()` opens Chromium's inspector on your app. Useful for:
- verifying the injected `document.ondrop` handler is in place
- finding the hidden bridge button in the DOM
- testing the `textContent`-based selector interactively

---

## Internals

This section is only relevant if you need to modify `attachFileDnD` itself.

### The three problems the helper solves

1. **Chromium renders the dropped file inside your app.** Default behaviour
   when a file is dropped on a Chromium page: text-ish payloads (`.txt`,
   `.am`, `.json`, …) cause a *navigation* — the file content replaces the
   page; binary payloads (`.tif`, `.png` in some versions) open a *Save-As*
   dialog. Both must be cancelled at the DOM level by `preventDefault()` on
   `dragenter`, `dragover`, and `drop`. `enableDragAndDropAll` hooks CEF
   above the DOM and does **not** cancel these defaults.

2. **`FileDragDropCallback` fires on drag-*enter*, not on drop.** The OS
   hands filenames to CEF at drag-enter, before the user releases the mouse.
   Acting on them there opens the file while the drag is still in progress.
   Deferring to the real drop requires a JS → MATLAB bridge: capture
   filenames on drag-enter, open only after the DOM `drop` event fires.

3. **Red no-parking cursor.** `preventDefault()` on `dragover` alone tells
   Chromium "don't navigate", but it also needs
   `e.dataTransfer.dropEffect = 'copy'` to mean "I accept the drop". Set on
   `ondragenter` **and** `ondragover`, otherwise the cursor shows 🚫.

4. **CEF heap corruption on browser-renderable file types (JPEG, PNG, …).**
   In some MATLAB/CEF versions, when a JPEG is dropped Chromium starts its
   native image decoder at the C++ level *before* JS `preventDefault()` can
   stop the navigation. If MATLAB's `imread` opens the same file
   concurrently, the JPEG decoder corrupts the native heap — producing an
   `ntdll.dll STATUS_HEAP_CORRUPTION` crash. `webwin.allowNavigation(false)`
   (called from `FileDragDropCallback` / drag-enter) blocks the CEF-level
   navigation before the decoder starts; `allowNavigation(true)` is restored
   after the user callback returns.  A `cancelBridge` path (triggered by
   `ondragleave` when the drag leaves without a drop) also restores
   `allowNavigation(true)` so help links and other in-app navigations keep
   working.

### Bridge pattern

```
┌──────────┐ dragenter  ┌──────────────────────────────────────────┐
│ Chromium │ ─────────▶ │ FileDragDropCallback                     │
│  (CEF)   │ filenames  │ → stash in btn.UserData                  │
└──────────┘            │ → allowNavigation(false)  ← JPEG fix     │
                        └──────────────────────────────────────────┘

   user releases mouse
   ▼
┌──────────┐ document.  ┌─────────────────────────┐
│ Chromium │ ondrop ──▶ │ JS: click bridge button │
│  (CEF)   │            │ by textContent lookup   │
└──────────┘            └────────────┬────────────┘
                                     │
                                     ▼
                        ┌─────────────────────────────────────────┐
                        │ ButtonPushedFcn (fireBridge)            │
                        │ → user callback(params)                 │
                        │ → allowNavigation(true)   ← JPEG fix   │
                        └─────────────────────────────────────────┘

   OR: drag leaves window without drop
   ▼
┌──────────┐ document.     ┌───────────────────────────────────────┐
│ Chromium │ ondragleave ▶ │ JS: click cancel button (debounced    │
│  (CEF)   │               │ with setTimeout to skip intra-doc     │
└──────────┘               │ element transitions)                  │
                           └──────────────┬────────────────────────┘
                                          │
                                          ▼
                           ┌─────────────────────────────────────────┐
                           │ cancelButton ButtonPushedFcn            │
                           │ → allowNavigation(true)   ← JPEG fix   │
                           └─────────────────────────────────────────┘
```

Components:
- **Hidden bridge `uibutton`** with unique `Text` (`mibDnDBridge_<n>`); state lives
  in its `UserData` as `struct('pendingFiles', {{}}, 'callback', fcn, 'webwin', ww)`.
- **Hidden cancel `uibutton`** with unique `Text` (`mibDnDBridgeCancel_<n>`); kept
  alive by `parentFigure`. Clicked by `ondragleave` when drag leaves the window.
- **`FileDragDropCallback`** on the webwindow — writes into `UserData.pendingFiles`
  and calls `allowNavigation(false)`.
- **`DownloadCallback`** on the webwindow — calls `stopDownload()` as a
  belt-and-braces against any download prompt that slips through.
- **Four DOM handlers** injected via `executeJS`: `ondragenter` (increments
  `_mibDragCount`, `preventDefault`, `dropEffect = 'copy'`); `ondragover`
  (`preventDefault`, `dropEffect = 'copy'`); `ondrop` (resets `_mibDragCount` to 0,
  `preventDefault`, clicks bridge button); `ondragleave` (decrements
  `_mibDragCount`, defers zero-check via `setTimeout(0)`, clicks cancel button
  when count reaches 0).

### Why the button's `UserData`, not a class property?

Keeps the helper reusable — any caller can call it from any class without
adding properties or methods. The button's lifetime is tied to its parent
figure, so state cleans up automatically. Deleting the returned button
handle is a clean "detach".

### Editing the injected JS

The `sprintf` escape rules get tricky: MATLAB's `'` inside a char literal
is `''`, and the JS strings inside also need to use `''` (so a JS string
literal `'copy'` becomes `''copy''` in the MATLAB source). If you want to
change the JS, easiest workflow: write and test it in DevTools first, then
paste into the `sprintf` and double every single quote.

### Multiple bridges in one document

Each `attachFileDnD` call bumps a persistent counter and gets a unique
`bridgeId`, so the button lookup is unambiguous. But `document.ondragenter /
ondragover / ondrop` are **singleton properties** — a second call in the
same document overwrites the first. This is fine across separate webwindows
(each has its own `document`), but attaching twice to the same webwindow is
not supported. If you ever need that, switch to `addEventListener` and track
a list of bridge buttons in a JS-side registry.

### Historical note

MIB2 (GUIDE-based) used `Tools/DnD_uifigure.m`, a larger `dojo.query`-based
JS helper with per-widget drop rectangles. `utils.attachFileDnD` is the MIB3
port of that idea, updated for modern MATLAB (AppContainer, web-based
uifigure components, `querySelectorAll`) and simplified to one drop zone
per webwindow. The behavioural contract is the same: capture filenames on
drag-enter, process them on drop, cancel Chromium's defaults.
