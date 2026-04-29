# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

MIB3 (Microscopy Image Browser 3) is a MATLAB application for image processing, segmentation, and visualization of multidimensional (2D-4D) microscopy datasets. Runs as a MATLAB script or compiled standalone Windows app.

- Entry point: `mib/mib3.m`
- Version string format: `'ver. 2025.12 / 05.12.2025'`
- Author: Ilya Belevich, University of Helsinki

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
3. Apply the full conversion cheat sheet regardless — `MIB2_RENAMED_FOR_MIB3` renaming is incomplete and inconsistent

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
- **`MibImage`** — pixel data as `data{1}` with dims `[height, width, depth, colors, time]`; types: `'Standard'`, `'Virtual'`, `'BigData'`
- **`MibBackup`** — undo history; **`ChildView`** — base class for child dialog views

### I/O Layer (`+io/`)

`ExtensionRegistryLoad` → `LoaderFactory.create()` → loader (`loadMetadata` + `loadImages`). Loaders in `+loaders/`: AmiraMesh, BioFormats, HDF5, Imod, Imread, MibImg, Nrrd, VideoReader, MatModel.

---

## Key Conventions

- Package namespace: `controllers.MibController`, `models.MibModel`, `core.MibImage`, `io.LoaderFactory`, `utils.dlgs.showErrorDialog`, etc.
- Methods split into separate `.m` files in `@ClassName/`; constructor + signatures in main class file.
- Event-driven: `events`/`notify`/`addlistener`. Listener naming: `listner1_Standard`, `listenerNewDataset`, etc.
- `.asv` files are MATLAB autosave backups — ignore them.
- Pixel/voxel size: `MibDataset.pixSize` struct — `.x .y .z .t .units .tunits`.
- Image orientation: `3` = XY (default), `1` = ZX, `2` = ZY.

---

## MIB2 → MIB3 Quick Reference

Full tables in `.claude/conversion_reference.md` (data structures, backup, clearing, bit packing, PoolWaitbar) and `.claude/conversion_ui.md` (modifier keys, display coords, child dialog keyboard shortcuts, orientation switching).

### Dialogs

| MIB2 | MIB3 |
|------|------|
| `warndlg(msg, title)` | `dlgOpt.MsgBoxOnly=true; dlgOpt.Icon='puffin_warning'; dlgOpt.HeaderLines=N;` + `utils.dlgs.inputUniversalDlg(obj.mibGUI, msg, {}, {}, title, dlgOpt)` |
| `warndlg` with body text | same but pass body in prompts/defAns: `utils.dlgs.inputUniversalDlg(obj.mibGUI, '!!! Warning !!!', {''}, {'body text'}, title, dlgOpt)` |
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.mibGUI, msg, title)` |
| `questdlg(msg,title,b1,b2,def)` | `utils.dlgs.inputQuestDlg(obj.mibGUI, msg, title, b1, b2, def)` |
| `waitbar` | `wb = uiprogressdlg(obj.mibGUI,'Value',v,'Message',msg,'Title',title)` |
| `inputdlg` / `mibInputMultiDlg` | `utils.dlgs.inputUniversalDlg(obj.mibGUI, header, prompts, defAns, title, options)` |

**`inputUniversalDlg` signature:** `(ParentFigure, header, prompts, defAns, dlgTitle, options)` — `header` is a bold label shown above the content; pass `''` when not needed.

**Dropdown `defAns`:** `{'item1', 'item2', 'item3', 2}` — string items followed by a **numeric default index** as last element. `answer{i}` returns the selected item string.

`inputUniversalDlg` icons: `'puffin_question'` (default), `'puffin_warning'`, `'puffin_error'`, `'puffin_info'`

### Events & Notifications

| MIB2 | MIB3 |
|------|------|
| `notify(obj, 'updateId')` | `notify(obj, 'UpdateGuiWidgets')` |
| `notify(obj, 'plotImage')` | `notify(obj, 'ShowImage')` |
| `notify(obj, 'showModel', evd)` | `obj.showModel = true` then `notify(obj, 'ShowImage')` |
| `notify(obj, 'updateGuiWidgets')` | `notify(obj, 'UpdateGuiWidgets')` |

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

**Important:** MIB2 `setData` calls had `(type, dataset, ...)` — MIB3 swaps to `(dataset, type, ...)`. The `getData` order (`type` first) is unchanged.

Use `[]` (not `NaN`) for `slice_no` and `orient` to get current slice/orientation.

**Orient values changed:** MIB2 used `4` for native YX; MIB3 uses `3`. All `getData`/`setData` orient arguments: `4` → `3`.

**Data type renamed:** MIB2 `'model'` → MIB3 `'labels'` in `getData`/`setData` type argument.

### obj.id vs obj.getActiveId() — Split-Panel Safety

**`obj.id` can be stale** between user clicks in split-panel mode.

```matlab
BatchOpt.id = obj.id;           % WRONG — may point at wrong dataset
BatchOpt.id = obj.getActiveId();  % CORRECT — always uses Sets.selectedSet
```

**Rule:** Every MibModel method that initializes `BatchOpt.id` as a default must use `obj.getActiveId()`. Direct `obj.id` is fine after it was explicitly set by the caller.

**`gui_WinMouseMotionFcn` must NEVER write to `mibModel.id` or `Sets.selectedSet`** — doing so breaks panning and keyboard shortcuts. See `.claude/port_splitpanel.md`.

---

## Documentation

All MATLAB docblocks use **RST format** compatible with `sphinxcontrib-matlabdomain` (Sphinx).
See `development/docs_api_sphinx.md` for the complete style guide and `docs_api/README.md` for build instructions.

Quick rules:
- **Header line:** `% FUNCTIONNAME - One-line description.` — all-caps name, no function call in the text
- **Syntax:** `.. code-block:: matlab` (never bare `::`)
- **Parameter names:** `**bold**` with em-dash `—` separator
- **Struct fields:** nested RST bullets with backtick field names — `` ``.fieldName`` — description ``
- **Optional params:** `*(optional)*` after the bold name
- **Examples:** `**Example N** — title` heading + `.. code-block:: matlab`
- **Inline code / defaults:** double backticks `` ``value`` ``
- **No Doxygen:** replace `@b`, `@li`, `[@em optional]`, `@ Note:` with RST equivalents

---

## MATLAB Coding Rules

- Use `dictionary` instead of `containers.Map`: `dictionary(keys, values)` for init, `isKey(d, key)` and `d(key)` for lookups. (R2022b+, supports type inference)
- Use descriptive variable names — avoid short abbreviations like `vp`, `wb`, `im`, `fn`. Write `viewPort`, `waitbar`, `image`, `filename` etc. in full so the code is self-explanatory without comments.
