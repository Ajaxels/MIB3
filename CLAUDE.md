# CLAUDE.md

Guidance for Claude Code when working in this repository.

This file holds only what is needed on **every** task: the map, the architecture, and the rules whose
breach causes a silent bug. Everything else lives one hop away and is listed below - open it when the
task is of that kind, rather than guessing from memory.

## Project Overview

MIB3 (Microscopy Image Browser 3) is a MATLAB application for image processing, segmentation, and
visualization of multidimensional (2D-4D) microscopy datasets. Runs as a MATLAB script or compiled
standalone Windows app.

- Entry point: `mib/mib3.m`
- Version string format: `'ver. 2025.12 / 05.12.2025'`
- Author: Ilya Belevich, University of Helsinki

## Documentation Map

- **[`development/INDEX.md`](development/INDEX.md)** — contents page for all development docs: how-to
  guides, completed port logs, subsystem folders (`bigdata/`, `deepmib/`, `stitching/`, `graphify/`),
  notes. **Open it whenever this file is not enough.**
- [`docs/CLAUDE.md`](docs/CLAUDE.md) — user docs (Zensical/MkDocs): nav editing, custom elements, build
- [`docs_api/CLAUDE.md`](docs_api/CLAUDE.md) — API reference (Sphinx/RST): docblock format, build steps
- [`mib/plugins/plugins_instructions.md`](mib/plugins/plugins_instructions.md) — standalone,
  self-contained guide for plugin development tasks

Read before starting a task of the matching type:

| Task | Read first |
|------|-----------|
| Port a GUIDE dialog to AppDesigner | [`guides/appdesigner_guide.md`](development/guides/appdesigner_guide.md) — file layout, widget syntax, constructor, `ViewListner_Callback2`, renames, checklist |
| Any MIB2 → MIB3 conversion | [`guides/conversion_reference.md`](development/guides/conversion_reference.md) — data structures, get/setData accessors, backup, clearing, bit packing, PoolWaitbar API |
| UI behaviour (modifiers, coords, shortcuts) | [`guides/conversion_ui.md`](development/guides/conversion_ui.md) |
| Add a dialog, progress bar or BatchOpt field | [`guides/dialogs_and_batchopt.md`](development/guides/dialogs_and_batchopt.md) |
| Write or edit documentation | [`guides/documentation_style.md`](development/guides/documentation_style.md) |
| Write a docblock | [`guides/docs_api_sphinx.md`](development/guides/docs_api_sphinx.md) |

**Rule:** whenever you add, rename, or significantly change a public method or UI feature, update the
corresponding documentation (`docs/` and/or `docs_api/`).

---

## Writing rules

**Never use the long dash.** Plain hyphen `-` (U+002D) everywhere: documentation, code comments,
docblocks, tooltips, dialog text. Em dash `—` and en dash `–` are banned (they render inconsistently
in MATLAB tooltips and the compiled app). This is the rule broken most often, because an em dash is
what a model reaches for in English prose and nothing flags it. Before finishing any task that
touched `.m` files:

```bash
# must return nothing - strings, comments and RST docblocks alike
grep -rn --include=*.m "—\|–" . | grep -v "^./deployed/"
```

**Write for the right audience.** Detail belongs at one level and must not leak downwards:

| Where | What belongs there |
|-------|--------------------|
| Widget tooltip | one reminder line: name the options, give the one fact that decides between them |
| `docs/docs/...` | what the feature does and what to do. Behaviour, never mechanism, **never what the screen already shows**, no edge cases, no justification |
| RST docblocks in `.m` | full technical detail - arguments, types, defaults, edge cases, why the code does what it does. Being terse here is the mistake |
| `development/` | benchmarks, measured numbers, alternatives tried and rejected |

`docs/` is the level that gets over-written. Re-read a user-facing addition before finishing and
delete every sentence the user could have learned by looking at the screen; deleting the whole
addition is a normal outcome. Nothing is lost by trimming - the docblock takes the edge cases and
contracts, `development/` the rationale and measurements. Worked examples:
[`guides/documentation_style.md`](development/guides/documentation_style.md).

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

**Model** (`+models/@MibModel`): Central state. Holds `I{}` array of `MibDataset` instances. Fires
events (`NewDataset`, `ShowImage`, `SliceChanged`, …) that controllers listen to.

**Controller** (`+controllers/@MibController`): Owns sub-controllers — `cRibbon`, `cSegmentation`,
`cDirContents`, `cActiveDataset`, `cImageDoc{}`, `cSelection`, `cRoi`, `cStatus`, `cQuickAccessBar`,
`childControllers{}`.

**View** (`+views/@MibView`): Builds the main app window. Ribbon tabs added by `addRibbonHome.m`, etc.
Panel components are `.mlapp` files in `+views/+components/`.

### Core Data (`+core/`)

- **`MibDataset`** — one open dataset; layers: `image` (MibImage), `labels` (MibLabels/MibLabels63),
  `mask`, `selection`, `annotations`, `lines3D`
- **`MibImage`** — pixel data as `data` (plain numeric array) with dims
  `[height, width, depth, colors, time]`; types: `'Standard'`, `'Virtual'`, `'BigData'`
- **`MibBackup`** — undo history; **`ChildView`** — base class for child dialog views

### I/O Layer (`+io/`)

`ExtensionRegistryLoad` → `LoaderFactory.create()` → loader (`loadMetadata` + `loadImages`). Loaders
in `+loaders/`: AmiraMesh, BioFormats, HDF5, Imod, Imread, MibImg, Nrrd, VideoReader, MatModel.

### Key Conventions

- Package namespace: `controllers.MibController`, `models.MibModel`, `core.MibImage`,
  `io.LoaderFactory`, `utils.dlgs.showErrorDialog`, etc.
- Methods split into separate `.m` files in `@ClassName/`; constructor + signatures in main class file.
- Event-driven: `events`/`notify`/`addlistener`. Listener naming: `listner1_Standard`,
  `listenerNewDataset`, etc.
- `.asv` files are MATLAB autosave backups — ignore them.
- Pixel/voxel size: `MibDataset.pixSize` struct — `.x .y .z .t .units .tunits`.
- Image orientation: `3` = XY (default), `1` = ZX, `2` = ZY.

---

## MIB2 → MIB3 Migration

Active port of MIB2 to MIB3. MIB3 uses MATLAB's **AppContainer framework** (ribbon UI, `.mlapp` panel
components, docked documents). MIB2 uses GUIDE-based `.fig`/`.m` with a flat `Classes/` structure.

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
3. Apply the conversion rules regardless — `MIB2_RENAMED_FOR_MIB3` renaming is incomplete and
   inconsistent
4. Open [`guides/appdesigner_guide.md`](development/guides/appdesigner_guide.md) for a full GUI
   controller port and [`guides/conversion_reference.md`](development/guides/conversion_reference.md)
   for the lookup tables — naming, widget syntax, events, renames and data structures all live there

### Naming
- Classes: `mibXxxController` → `Xxx` (PascalCase, no `mib` prefix), in `+controllers/@Xxx/`
- Views: `mibXxxGUI.fig` → `+views/XxxGUI.mlapp`; accessed as `obj.view` (lowercase)
- Orientation XY: `4` → `3`; layer `'model'` → `'labels'`

---

## Rules that fail silently

Each of these produces working-looking code that is wrong, with no error to catch it. The rest of the
conversion detail is in the guides; these stay here because a wrong guess is expensive.

**`setData` argument order is swapped.** MIB2 `(type, dataset, ...)` → MIB3 `(dataset, type, ...)`.
`getData` (type first) is unchanged. Use `[]`, not `NaN`, for the current slice/orientation.

**`BatchOpt.id` must come from `obj.getActiveId()`**, never `obj.id` — the latter goes stale between
clicks in split-panel mode. A direct `obj.id` is fine only after the caller set it explicitly.

**Modifier keys come from the controller.** `UIFigure.CurrentModifier` is unreliable — stale after
`pyrun()`, wrong in sub-figures.
```matlab
modifier = obj.mibController.currentModifier;  % CORRECT
modifier = hFig.CurrentModifier;               % WRONG
```

**A BatchOpt widget must be named exactly as its BatchOpt field.** `utils.updateBatchOptFromGUI_Shared`
writes `BatchOpt.(hObject.Tag)`, so a mismatched handle dumps the value into a junk field and the tool
runs with defaults. Details and the non-BatchOpt naming convention:
[`guides/dialogs_and_batchopt.md`](development/guides/dialogs_and_batchopt.md).

**Progress dialogs are always cancelable** — `uiprogressdlg` with `'Cancelable', 'on'`,
`core.PoolWaitbar` with its 5th argument `true` (it defaults to **false**). Creating it is not enough:
check `wb.CancelRequested` / `pwb.getCancelState()` at the top of every loop and before every
irreversible operation, then clean up and return. Return no partial result, and say what was and was
not done rather than reporting success. Patterns:
[`guides/dialogs_and_batchopt.md`](development/guides/dialogs_and_batchopt.md).

**Always check `enableSelection` first:** `if obj.mibModel.I{id}.enableSelection == 0; return; end`.

---

## MATLAB Coding Rules

- Use `dictionary` instead of `containers.Map`: `dictionary(keys, values)` for init, `isKey(d, key)`
  and `d(key)` for lookups. (R2022b+, supports type inference)
- Use descriptive variable names — avoid short abbreviations like `vp`, `im`, `fn`. Write
  `viewPort`, `image`, `filename` etc. in full so the code is self-explanatory without comments.
  Match the surrounding code when an established local name already exists.

### Keep single-use logic inline — do not extract it to make it testable

**A helper earns its own file when it has two or more real call sites.** Wanting to unit-test it is
not a second call site. Fixing a few lines inside a method that is hard to instantiate (a controller
method needing a live `MibController` and a window, say) does **not** justify moving those lines into
`+utils` or a new `@Class/method.m`. This applies to fixes especially: a one-line guard added to an
existing method should stay a one-line guard in that method.

When logic is worth testing but unreachable where it lives, **say so and ask** — do not extract
unilaterally. The trade (an extra file and an indirection, against coverage of a specific bug) is the
author's call, not a default.

**Do not cite recent code as precedent.** Before arguing "this pattern already exists here", check who
added it and when:

```bash
git log --format='%an %ad %s' --date=short --diff-filter=A -- path/to/file.m
```

Code added in the last few sessions may be unreviewed, or your own from an earlier session. Citing it
back as established convention turns one unilateral decision into a rule. Precedent means several
independent uses that predate the current work.

### Copy-on-write in per-slice loops (performance critical)

Any loop that writes pixel data directly (bypassing `getData2D`) must cache `data` in a local
variable first, mutate locally, then write back once after the loop — repeated handle-chain traversal
(`MibDataset → MibImage → data`) allocates on every iteration.

```matlab
% WRONG                                    % CORRECT
for z = 1:depth                            imageData = obj.mibModel.I{id}.image.data;
    obj.mibModel.I{id}.image.data(...)     for z = 1:depth
        = process(...);                        imageData(:,:,z,ch,t) = process(imageData(:,:,z,ch,t));
end                                        end
                                           obj.mibModel.I{id}.image.data = imageData;
```

Applies to code **outside** `MibImage` methods (controllers, model helpers). Inside `MibImage`,
`obj.data` is one hop and already safe — still worth caching for large nested loops. Full background:
[`guides/performance_for_loop_tweak.md`](development/guides/performance_for_loop_tweak.md).

## graphify

This project has a knowledge graph at `graphify-out/` with god nodes, community structure, and
cross-file relationships.

- ALWAYS read `graphify-out/GRAPH_REPORT.md` before reading any source files, running grep/glob
  searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF `graphify-out/wiki/index.md` EXISTS, navigate it instead of reading raw files.
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`,
  `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the
  graph's EXTRACTED + INFERRED edges instead of scanning files.
