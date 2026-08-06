# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

MIB3 (Microscopy Image Browser 3) is a MATLAB application for image processing, segmentation, and visualization of multidimensional (2D-4D) microscopy datasets. Runs as a MATLAB script or compiled standalone Windows app.

- Entry point: `mib/mib3.m`
- Version string format: `'ver. 2025.12 / 05.12.2025'`
- Author: Ilya Belevich, University of Helsinki

## Documentation Map

This file holds the always-needed essentials. Everything deeper lives behind one contents page:

- **[`development/INDEX.md`](development/INDEX.md)** — contents page for all development docs: how-to guides (AppDesigner porting, dialogs, PoolWaitbar, drag-and-drop, RST docblocks…), completed port logs, subsystem folders (`bigdata/`, `deepmib/`, `stitching/`, `graphify/`), notes. **Open it whenever this file is not enough.**
- [`docs/CLAUDE.md`](docs/CLAUDE.md) — user docs (Zensical/MkDocs): nav editing, custom elements, build commands
- [`docs_api/CLAUDE.md`](docs_api/CLAUDE.md) — API reference (Sphinx/RST): docblock format, build steps
- [`mib/plugins/plugins_instructions.md`](mib/plugins/plugins_instructions.md) — standalone, self-contained guide for plugin development tasks

**Rule:** whenever you add, rename, or significantly change a public method or UI feature, update the corresponding documentation (`docs/` and/or `docs_api/`).

### Documentation and tooltip style

**Never use the long dash.** Use a plain hyphen `-` (U+002D) in all documentation, code comments,
docblocks, tooltips and dialog text. Em dash `—` (U+2014) and en dash `–` (U+2013) are banned: they
render inconsistently in MATLAB tooltips and the compiled standalone app, and they are awkward to
type and to search for. Write `Feather - weighted blend`, not `Feather — weighted blend`.

**This is the rule that gets broken most often**, because an em dash is what a model reaches for
when writing English prose and nothing in the editor flags it. Before finishing any task that
touched `.m` files, run the check and fix what it reports:

```bash
# must return nothing - strings, comments and RST docblocks alike
grep -rn --include=*.m "—\|–" . | grep -v "^./deployed/"
```

**Every `.m` file in the repo is dash-free**, RST docblocks included: the docblock parameter
separator is a plain hyphen (`**name** - description`), and
[`docs_api/CLAUDE.md`](docs_api/CLAUDE.md) / [`development/guides/docs_api_sphinx.md`](development/guides/docs_api_sphinx.md)
were updated to match. Nothing in Sphinx parses that separator, so it is purely a glyph choice.

`deployed/` is excluded because it is untracked build output, regenerated from `mib/` by
`deploymentScript.m` - editing it there would be undone on the next build. The `.md` documentation
under `docs/`, `docs_api/` and `development/` has **not** been swept and still contains em dashes.

**Tooltips stay short; detail lives in `docs/`.** A widget tooltip is a reminder, not a manual: name
each option and give the one fact that decides between them. Anything longer - trade-offs, measured
numbers, failure modes - belongs in the matching `docs/docs/user-interface/...` page, which the
tooltip can point at.

### MIB2 → MIB3 Migration

Active port of MIB2 to MIB3. MIB3 uses MATLAB's **AppContainer framework** (ribbon UI, `.mlapp` panel components, docked documents). MIB2 uses GUIDE-based `.fig`/`.m` with a flat `Classes/` structure.

| | MIB2 | MIB3 |
|-|------|------|
| Class location | `Classes/@mibController` (no packages) | `+controllers/@MibController` (packages) |
| Naming | `mibController`, `mibModel` (lowercase prefix) | `MibController`, `MibModel` (PascalCase) |
| GUI | `GuiTools/*.fig` + `*.m` | `+views/*.mlapp` |

Two MIB2 reference copies exist with different roles:

| Path | State | Use for |
|------|-------|---------|
| `C:\Matlab\MIB2\` | Original, fully working | **Verifying behavior** — run it, debug it, confirm what the code actually does |
| `C:\Matlab\MIB2_RENAMED_FOR_MIB3\` | Partial rename to MIB3 style, may not run | **Copying logic** — some variables/methods pre-renamed, reduces transformation work |

**Porting workflow:**
1. Copy the method from `MIB2_RENAMED_FOR_MIB3\Classes\` or `GuiTools\` as the starting point
2. When behavior is unclear or needs verification, check the same method in `MIB2\` (runs correctly)
3. Apply the conversion rules below regardless — `MIB2_RENAMED_FOR_MIB3` renaming is incomplete and inconsistent
4. For a full GUI controller port, read `development/guides/appdesigner_guide.md` first (file layout, checklist)

---

## Common Commands

```matlab
% Run MIB
cd C:\Matlab\MIB3\mib; mib3

% Build checks and tests
cd C:\Matlab\MIB3
buildtool          % default: check + test
buildtool check    % code issues only
buildtool test     % tests only

% Compile standalone
run('C:\Matlab\MIB3\deploymentScript.m')
```

---

## Architecture

MVC pattern with MATLAB packages under `mib/`:

```
mib/
  mib3.m          % entry point: creates MibModel → MibController
  +controllers/   % UI controllers
  +models/        % application model
  +views/         % .mlapp components + MibView
  +core/          % core data classes
  +io/            % image I/O (factory pattern)
  +utils/         % dialogs, defaults, utilities
```

**Model** (`+models/@MibModel`): Central state. Holds `I{}` array of `MibDataset` instances. Fires events (`NewDataset`, `ShowImage`, `SliceChanged`, …) that controllers listen to.

**Controller** (`+controllers/@MibController`): Owns sub-controllers — `cRibbon`, `cSegmentation`, `cDirContents`, `cActiveDataset`, `cImageDoc{}`, `cSelection`, `cRoi`, `cStatus`, `cQuickAccessBar`, `childControllers{}`.

**View** (`+views/@MibView`): Builds the main app window. Ribbon tabs added by `addRibbonHome.m`, etc. Panel components are `.mlapp` files in `+views/+components/`.

### Core Data (`+core/`)

- **`MibDataset`** — one open dataset; layers: `image` (MibImage), `labels` (MibLabels/MibLabels63), `mask`, `selection`, `annotations`, `lines3D`
- **`MibImage`** — pixel data as `data` (plain numeric array) with dims `[height, width, depth, colors, time]`; types: `'Standard'`, `'Virtual'`, `'BigData'`
- **`MibBackup`** — undo history; **`ChildView`** — base class for child dialog views

### I/O Layer (`+io/`)

`ExtensionRegistryLoad` → `LoaderFactory.create()` → loader (`loadMetadata` + `loadImages`). Loaders in `+loaders/`: AmiraMesh, BioFormats, HDF5, Imod, Imread, MibImg, Nrrd, VideoReader, MatModel.

### Key Conventions

- Package namespace: `controllers.MibController`, `models.MibModel`, `core.MibImage`, `io.LoaderFactory`, `utils.dlgs.showErrorDialog`, etc.
- Methods split into separate `.m` files in `@ClassName/`; constructor + signatures in main class file.
- Event-driven: `events`/`notify`/`addlistener`. Listener naming: `listner1_Standard`, `listenerNewDataset`, etc.
- `.asv` files are MATLAB autosave backups — ignore them.
- Pixel/voxel size: `MibDataset.pixSize` struct — `.x .y .z .t .units .tunits`.
- Image orientation: `3` = XY (default), `1` = ZX, `2` = ZY.

---

## MIB2 → MIB3 Conversion Quick Reference

Full tables: `development/guides/conversion_reference.md` (data structures, backup, clearing, bit packing, PoolWaitbar) and `development/guides/conversion_ui.md` (modifier keys, display coords, child dialog keyboard shortcuts, orientation switching).

### Naming
- Classes: `mibXxxController` → `Xxx` (PascalCase, no `mib` prefix), in `+controllers/@Xxx/`
- Views: `mibXxxGUI.fig` → `+views/XxxGUI.mlapp`; accessed as `obj.view` (lowercase)
- Orientation XY: `4` → `3`; layer `'model'` → `'labels'`

### Dialogs

| MIB2 | MIB3 |
|------|------|
| `warndlg(msg, title)` | `dlgOpt.MsgBoxOnly=true; dlgOpt.Icon='puffin_warning'; dlgOpt.HeaderLines=N;` + `utils.dlgs.inputUniversalDlg(obj.mibGUI, msg, {}, {}, title, dlgOpt)` |
| `warndlg` with body text | same but pass body in prompts/defAns: `utils.dlgs.inputUniversalDlg(obj.mibGUI, '!!! Warning !!!', {''}, {'body text'}, title, dlgOpt)` |
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.mibGUI, msg, title)` |
| `questdlg(msg,title,b1,b2,def)` | `utils.dlgs.inputQuestDlg(obj.mibGUI, msg, title, b1, b2, def)` |
| `waitbar` | `wb = uiprogressdlg(obj.mibGUI,'Value',v,'Message',msg,'Title',title)` |
| `inputdlg` / `mibInputMultiDlg` | `utils.dlgs.inputUniversalDlg(obj.mibGUI, header, prompts, defAns, title, options)` |

**`inputUniversalDlg` signature:** `(ParentFigure, header, prompts, defAns, dlgTitle, options)` — `header` is a bold label shown above the content; pass `''` when not needed. Icons: `'puffin_question'` (default), `'puffin_warning'`, `'puffin_error'`, `'puffin_info'`.

- **Dropdown `defAns`:** `{'item1', 'item2', 'item3', 2}` — items followed by a **numeric default index** as last element. `answer{i}` returns the selected item string.
- **Spinner (numeric) `defAns`:** pass `struct('Spinner', true, 'Value', 5, 'Limits', [1 100], 'Step', 1, 'Round', true)`. `answer{i}` returns the numeric value directly — no `str2double`, assign as `BatchOpt.MyParam{1} = answer{i}`.

**Numeric BatchOpt fields** — store as a 3-element cell: `BatchOpt.MyParam = {value, [minLim maxLim], 'on'}` (`{2}` = spinner limits, `{3}` `'on'` = integer rounding, `'off'`/omit = float). Read with `BatchOpt.MyParam{1}`, **not** `str2double`. After `utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn)`, refresh the limits from the actual dataset dims:
```matlab
maxSlice = obj.I{BatchOpt.id}.dim_yxzct(dimOrient);
BatchOpt.MyParam{2} = [1, maxSlice];
```

### Events & Notifications

| MIB2 | MIB3 |
|------|------|
| `notify(obj, 'plotImage')` | `notify(obj, 'ShowImage')` |
| `notify(obj, 'updateGuiWidgets')` / `'updateId'` | `notify(obj, 'UpdateGuiWidgets')` |
| `notify(obj, 'showModel', evd)` | `obj.showModel=true; notify(obj,'ShowImage')` |
| `notify(obj, 'showMask')` | `obj.showMask=true; notify(obj,'ShowImage')` |
| `notify(obj, 'updateLayerSlider', evd)` | update `slices{orient}` then `notify('SliceChanged')` |
| `notify(obj, 'updateTimeSlider', evd)` | update `slices{5}` then `notify('FrameChanged')` |
| `notify(obj, 'updatedAnnotations')` | `notify(obj, 'UpdateAnnotations')` |
| `ToggleEventData(x)` | `core.ToggleEventData(x)` |

### MibModel Data Accessors

```matlab
% Reading (options.id defaults to obj.getActiveId())
dataset = obj.mibModel.getData2D(type, slice_no, orient, col_channel, options)
dataset = obj.mibModel.getData3D(type, time, orient, col_channel, options)
dataset = obj.mibModel.getData4D(type, orient, col_channel, options)

% Writing — MIB3: data BEFORE type (MIB2 had type before data!)
obj.mibModel.setData2D(dataset, type, slice_no, orient, col_channel, options)
obj.mibModel.setData3D(dataset, type, time, orient, col_channel, options)
obj.mibModel.setData4D(dataset, type, orient, col_channel, options)
```

- **`setData` argument order swapped:** MIB2 `(type, dataset, ...)` → MIB3 `(dataset, type, ...)`. `getData` (type first) is unchanged.
- Use `[]` (not `NaN`) for `slice_no` and `orient` to get current slice/orientation.
- **Orient values:** MIB2 used `4` for native YX; MIB3 uses `3` — convert all orient arguments `4` → `3`.
- **Type renamed:** MIB2 `'model'` → MIB3 `'labels'`.

### obj.id vs obj.getActiveId() — Split-Panel Safety

**`obj.id` can be stale** between user clicks in split-panel mode.

```matlab
BatchOpt.id = obj.id;             % WRONG — may point at wrong dataset
BatchOpt.id = obj.getActiveId();  % CORRECT — always uses Sets.selectedSet
```

**Rule:** Every MibModel method that initializes `BatchOpt.id` as a default must use `obj.getActiveId()`. Direct `obj.id` is fine after it was explicitly set by the caller.

**`gui_WinMouseMotionFcn` must NEVER write to `mibModel.id` or `Sets.selectedSet`** — doing so breaks panning and keyboard shortcuts. See `development/ports/port_splitpanel.md`.

### Modifier Keys (CRITICAL)
`UIFigure.CurrentModifier` is **unreliable** — stale after `pyrun()`, wrong in sub-figures.
```matlab
modifier = obj.mibController.currentModifier;  % CORRECT
modifier = hFig.CurrentModifier;               % WRONG
```

### AppDesigner Widget Syntax

| GUIDE | AppDesigner |
|-------|-------------|
| `.String` (edit box) | `.Value` |
| `.String` (label / button) | `.Text` |
| `popup.String` (item list) | `popup.Items` |
| `popup.String{popup.Value}` | `popup.Value` (string directly) |
| set popup by index | `popup.Value = popup.Items{3}` |
| `.TooltipString` | `.Tooltip` |
| `.BackgroundColor = 'g'` | `.BackgroundColor = [0 1 0]` |
| `.CData` (button icon) | `.Icon` |
| `findjobj + jTable.changeSelection` | `scroll(uitableHandle,'row',r)` |
| Button `Callback` | `ButtonPushedFcn` |
| Edit `Callback` | `ValueChangedFcn` |

### BatchOpt ↔ Widget Handle Naming (CRITICAL)
Every `.mlapp` widget that maps to a BatchOpt parameter must be **named exactly as its BatchOpt field**, so the widget handle is `obj.view.handles.TileOrder`, `obj.view.handles.GridRows`, etc. (PascalCase; exception: `showWaitbar` stays lowercase). `core.ChildView` copies the component name into `Tag`, and `utils.updateBatchOptFromGUI_Shared` writes `BatchOpt.(hObject.Tag)` — a mismatched handle name silently dumps the value into a junk field and the tool runs with defaults. Non-BatchOpt widgets (buttons, axes, labels) use descriptive lowerCamel handles (`selectInputBtn`, `previewAxes`).

### Controller Constructor Pattern
```matlab
core.ChildView(obj, 'views.XxxGUI')    % creates view, sets obj.view
utils.fontSizeUpdate(gui, Font)
utils.moveWindowOutside(gui, mibGUI, 'left')
obj.addCallbacks()                      % wire ALL callbacks here; set CloseRequestFcn first
obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(s,e) obj.ViewListner_Callback2(obj,s,e));
obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(s,e) obj.ViewListner_Callback2(obj,s,e));
```
`ViewListner_Callback2` — always guard:
```matlab
methods (Static)
    function ViewListner_Callback2(obj, src, evnt)
        if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
            for i=1:numel(obj.listener); delete(obj.listener{i}); end; return;
        end
        switch evnt.EventName
            case {'UpdateGuiWidgets','NewDataset'}; obj.updateWidgets();
        end
    end
end
```

### Data Structures

| MIB2 | MIB3 |
|------|------|
| `obj.model{1}` | `obj.labels.data{1}` |
| `obj.modelMaterialNames` | `obj.labels.materialNames` |
| `obj.modelFilename` | `obj.labels.filename` |
| `obj.modelVariable` | `obj.labels.labelsVariable` |
| `size(img,1/2/4/5)` → h/w/d/t | `obj.image.height/width/depth/time` |
| `obj.mibModel.I{id}.pixSize` | `obj.mibModel.I{id}.image.pixSize` |
| `getImageProperty('orientation')` | `obj.mibModel.I{id}.orientation` |
| `global mibPath` | `obj.mibModel.mibPath` |
| `global Font` | `obj.mibModel.preferences.System.Font` |
| `containers.Map` | `dictionary(keys, values)` (R2022b+) |

### Backup / Clearing
```matlab
obj.mibModel.backup('selection', 0, opts)   % switch3d=0: current slice, 1: full stack
obj.mibModel.I{id}.clearLayer('selection', '2D'/'3D'/'4D')
if obj.mibModel.I{id}.enableSelection == 0; return; end   % always check first
```

### Parallel Progress
```matlab
pwb = core.PoolWaitbar(n, 'Processing...', obj.mibGUI, 'Title');
parfor (i=1:n, parforArg); pwb.increment(); end
pwb.deletePoolWaitbar();
% Sequential loops: use plain uiprogressdlg with wb.Value = k/n
```

### Misc Renames

| MIB2 | MIB3 |
|------|------|
| `obj.View` | `obj.view` |
| `okBtn_Callback` / `cancelBtn_Callback` | `applyButton_Callback` / `closeButton_Callback` |
| `mibRescaleWidgets(gui)` | remove — AppDesigner handles scaling |
| `mibUpdateFontSize(gui, Font)` | `utils.fontSizeUpdate(gui, Font)` |
| `moveWindowOutside(h, 'left')` | `utils.moveWindowOutside(gui, mibGUI, 'left')` |
| `BatchOpt.mibBatchSectionName = 'Menu -> …'` | `'Ribbon -> …'` |

---

## MATLAB Coding Rules

- Use `dictionary` instead of `containers.Map`: `dictionary(keys, values)` for init, `isKey(d, key)` and `d(key)` for lookups. (R2022b+, supports type inference)
- Use descriptive variable names — avoid short abbreviations like `vp`, `wb`, `im`, `fn`. Write `viewPort`, `waitbar`, `image`, `filename` etc. in full so the code is self-explanatory without comments.

### Copy-on-write in per-slice loops (performance critical)

`MibImage.data` is a plain numeric array (not a cell — the former `data{1}` cell wrapper was removed). Caching it into a local variable before a tight loop eliminates repeated handle-chain traversal (`MibDataset → MibImage → data`) and per-iteration allocations.

**Rule:** Any loop that writes pixel data directly (bypassing `getData2D`) must cache `data` in a local variable first, mutate locally, then write back once after the loop.

```matlab
% WRONG — repeated handle-chain traversal, potentially slower in tight loops
for z = 1:depth
    obj.mibModel.I{id}.image.data(:,:,z,ch,t) = process(...);
end

% CORRECT — single read, single write
imageData = obj.mibModel.I{id}.image.data;
for z = 1:depth
    imageData(:,:,z,ch,t) = process(imageData(:,:,z,ch,t));
end
obj.mibModel.I{id}.image.data = imageData;
```

Applies to any code **outside** `MibImage` methods (controllers, model helpers). Inside `MibImage` methods `obj.data` is one hop and already safe — still worth caching for large nested loops. Full background: `development/guides/performance_for_loop_tweak.md`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- ALWAYS read graphify-out/GRAPH_REPORT.md before reading any source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files