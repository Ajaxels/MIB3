# Development Docs — Contents

Entry point for all deep documentation. Read the root [`CLAUDE.md`](../CLAUDE.md) first — it holds the
always-needed conventions and MIB2→MIB3 quick reference. Come here when you need the full story on a
specific topic, then open only the file(s) you need.

Folder layout:

| Folder | Contains |
|--------|----------|
| [`guides/`](#guides) | Evergreen how-to guides and lookup references — read **before** starting a task of that type |
| [`ports/`](#port--feature-logs) | Completed MIB2→MIB3 port and feature logs — historical record; consult when revisiting that feature |
| Subsystem folders | `bigdata/`, `deepmib/`, `stitching/`, `graphify/` — self-contained work areas with their own plans |
| [`notes/`](#notes--scratch) | Scratch notes, code snippets, environment quirks |
| `assets/` | Binary sources: `icons.cdr` (CorelDraw icon master), backup copy |

---

## Guides

Read before starting a task of the matching type. All in `development/guides/`.

### Porting MIB2 → MIB3

| File | When to read |
|------|--------------|
| [appdesigner_guide.md](guides/appdesigner_guide.md) | **Start here for any new GUIDE → AppDesigner port**: file layout, widget syntax, constructor pattern, checklist |
| [plan_appdesigner_GUI_conversion.md](guides/plan_appdesigner_GUI_conversion.md) | Step-by-step phased procedure for porting a `mibXxxController` + `.mlapp` pair; tick-box format |
| [guide_to_appdesigner_conversion.md](guides/guide_to_appdesigner_conversion.md) | Extended lookup tables for GUIDE → AppDesigner conversion; add new patterns here as discovered |
| [conversion_reference.md](guides/conversion_reference.md) | Conversion tables: data structures, backup, clearing, bit packing, PoolWaitbar |
| [conversion_ui.md](guides/conversion_ui.md) | Modifier keys, image display coords, child-dialog keyboard shortcuts, orientation switching |
| [plan_headless_to_gui.md](guides/plan_headless_to_gui.md) | Pattern: MIB2 headless `mibModel` method → MIB3 child controller with `.mlapp`, batch mode, live preview (worked example: ContrastClahe) |
| [segmentationTools_conversion.md](guides/segmentationTools_conversion.md) | Porting segmentation tools into `@MibImageDocument` (reference case: segmentationSpot) |

### MIB3 subsystem how-tos

| File | When to read |
|------|--------------|
| [dialogs_and_batchopt.md](guides/dialogs_and_batchopt.md) | **Read before adding a dialog, a progress bar or a BatchOpt field**: MIB2→MIB3 dialog map, `inputUniversalDlg` signature and widget specs, the always-cancelable rule and what a long function owes its caller, numeric BatchOpt fields, widget↔field naming, session memory |
| [how_to_make_input_dialog.md](guides/how_to_make_input_dialog.md) | Building input dialogs; focus handling without Java Robot (see also `../notes/focusExample.m`) |
| [uiprogressdlg_to_PoolWaitbar.md](guides/uiprogressdlg_to_PoolWaitbar.md) | When and how to convert `uiprogressdlg` → `core.PoolWaitbar` (Cancel button, parfor) |
| [startController.md](guides/startController.md) | `utils.startController` — launching child controllers from anywhere (interactive, batch, already-open) |
| [ctrl_stale.md](guides/ctrl_stale.md) | **Read before touching modifier-key state or adding a blocking dialog**: why MIB tracks `currentModifier` itself, the two ways a key release goes missing, every site that resets it, and what is still open on macOS/Linux |
| [drag-and-drop.md](guides/drag-and-drop.md) | OS file drag-and-drop into uifigure/AppContainer apps; `utils.attachFileDnD` helper |
| [mouse_recentering_screen.md](guides/mouse_recentering_screen.md) | Moving the OS cursor after zoom/moveView; docked vs undocked, multi-monitor, DPI scaling |
| [performance_for_loop_tweak.md](guides/performance_for_loop_tweak.md) | Copy-on-write fix for per-slice loops — full background behind the root-CLAUDE.md caching rule |
| [developer_mode_callback_markers.md](guides/developer_mode_callback_markers.md) | Adding `DeveloperMode` "triggered" trace markers to a controller's GUI callbacks: the marker, placement, what to mark/skip, the `gui_Callbacks` global-marker rule |
| [plugin_system.md](guides/plugin_system.md) | Plugin discovery architecture (MIB2 and MIB3); filesystem-based, no registry |
| [docs_api_sphinx.md](guides/docs_api_sphinx.md) | **RST docblock style guide** — authoritative for all new/updated function docs |
| [documentation_style.md](guides/documentation_style.md) | **Read before writing user-facing docs**: which of the four levels a fact belongs to, why `docs/` gets over-written, worked before/after examples, the long-dash rule and its background |

### Plugin development (standalone)

[`mib/plugins/plugins_instructions.md`](../mib/plugins/plugins_instructions.md) — self-contained guide for
writing an MIB3 GUI plugin (controller + `.mlapp` view + API reference). Give this single file to a coding
agent working on a plugin. Cheat sheet for converting MIB2 plugins:
`mib/plugins/Tutorials/GuiTutorial/conversion_MIB2_to_MIB3_cheat_sheet.md`.

---

## Subsystems

| Folder | Topic | Entry point |
|--------|-------|-------------|
| `bigdata/` | BigData mode: tiled/WSI datasets, levelmap, block-mode brush | [bigdata/README.md](bigdata/README.md) |
| `deepmib/` | DeepMIB deep learning: 2D/3D instance segmentation plans, 3D U-Net migration, MIB3 axis-order pitfalls (`deepmib_dimensions_problems.md`), deferred ideas ([deepmib/potential_improvements.md](deepmib/potential_improvements.md)) | folder files |
| `stitching/` | Tile stitching tool — **implemented** (translation/affine/rigid/similarity, 2D+3D, seam inspector, Fibics Atlas import). [stitching/plan_stitching.md](stitching/plan_stitching.md) is the reference (architecture, load-bearing pitfalls, status); [stitching/plan_transforms.md](stitching/plan_transforms.md) covers transform models + future (elastic) directions; [stitching/plan_inspector.md](stitching/plan_inspector.md) the seam inspector; [stitching/mlapp_widgets.md](stitching/mlapp_widgets.md) the widget spec; [stitching/smoke_tests.md](stitching/smoke_tests.md) the GUI regression checklist (`NN_stitch_smoke*/` generators) | [stitching/plan_stitching.md](stitching/plan_stitching.md) |
| `graphify/` | Codebase knowledge-graph tooling (see graphify section in root CLAUDE.md) | [graphify/run_graphify.md](graphify/run_graphify.md) |

Related, outside `development/`:

- [`tests/plan_unittests.md`](../tests/plan_unittests.md) — unit-test & perf-benchmark system plan
- [`docs/CLAUDE.md`](../docs/CLAUDE.md) — user docs (Zensical/MkDocs): nav, custom elements, build
- [`docs_api/CLAUDE.md`](../docs_api/CLAUDE.md) — API reference (Sphinx/RST): docblocks, build

---

## Port & feature logs

Historical record of completed conversions in `development/ports/`. Consult when revisiting the feature,
debugging a regression in it, or looking for a precedent pattern. One line each:

### Controllers / tools

| File | Covers |
|------|--------|
| [plan_alignment.md](ports/plan_alignment.md) | `mibAlignmentController` → `controllers.Alignment` (largest port log) |
| [BatchProcessing.md](ports/BatchProcessing.md) | BatchProcessing port plan incl. widget list. **Doc predates implementation** — `@BatchProcessing` now exists (26 files + GUI); "NOT STARTED" status is stale |
| [contrast_normalization_plan.md](ports/contrast_normalization_plan.md) | `controllers.ContrastNormalization` — implemented; key BatchOpt decisions |
| [plan_Measurements_class.md](ports/plan_Measurements_class.md) | `core.Measurements` + `controllers.MeasureTool` — implemented 2026-05 |
| [mibStatistics_conversion.md](ports/mibStatistics_conversion.md) | `mibStatisticsController` → `controllers.Quantification` |
| [plan_stereology_improvements.md](ports/plan_stereology_improvements.md) | **Evaluation (not yet implemented)** of `controllers.Stereology`: missing probes (cycloid/line/disector), metrics (S_v/L_v/N_v/size), organelle presets, CE rigor, segmentation automation; V_v naming + dY-axis bug fixes |
| [plan_stereology_implementation.md](ports/plan_stereology_implementation.md) | **Implementation plan** for the Stereology upgrade (companion to the evaluation): 9 phases M1–M4, each with a per-phase Opus/Sonnet model recommendation; reuse map (SurfaceMeasurements, regionprops3mib, skeleton) |
| [plan_crop.md](ports/plan_crop.md) | CropDataset port: widgets, events, BatchOpt radio pattern, mlapp startupFcn fix |
| [plan_resample.md](ports/plan_resample.md) | ResampleDataset port: data-write pattern, boundingBox/dim sync |
| [plan_snapshot.md](ports/plan_snapshot.md) | Snapshot controller port; `AxesLimitsChanged` event |
| [plan_convertImage.md](ports/plan_convertImage.md) | Image format/bit-depth conversion pipeline |
| [RoiClassConversion.md](ports/RoiClassConversion.md) + [port_roi.md](ports/port_roi.md) | ROI class architecture and port state |
| [importDataset.md](ports/importDataset.md) | `MibModel.importDataset` (workspace → dataset) |
| [conversion_of_model_loader.md](ports/conversion_of_model_loader.md) + [port_loadmodel.md](ports/port_loadmodel.md) | `MibModel.loadModel`: BatchOpt fields, extension→loader map, edge cases |
| [moveLayers_conversion.md](ports/moveLayers_conversion.md) + [port_movelayers.md](ports/port_movelayers.md) | `moveLayers` + fast-path helpers between selection/mask/model |
| [plan_palettes.md](ports/plan_palettes.md) | `MibModel.setDefaultColorPalette` + `utils.defaults.generateDefaultPalette` |
| [lasso_pan_implementation.md](ports/lasso_pan_implementation.md) | Custom polyline vertex placement for the Lasso tool |

### Infrastructure / performance

| File | Covers |
|------|--------|
| [audit_get-setdata.md](ports/audit_get-setdata.md) | getData/setData pipeline audit + benchmarks (hottest code path) |
| [optimize_getRGBimage.md](ports/optimize_getRGBimage.md) | `getRGBimage` per-step optimization log |
| [plan_startup.md](ports/plan_startup.md) | Startup speed-up 13.35 → 6.34 s: lazy Java gateway, deferred update check |
| [plan_inputUniversalDlg.md](ports/plan_inputUniversalDlg.md) | Dialog audit/refactor (done): shared helpers, 10 bug fixes, auto-height formula |
| [inputDlgs_caching.md](ports/inputDlgs_caching.md) | UIFigure & icon caching for dialogs; modal-caching fix |
| [plan_sliceSize_implementation.md](ports/plan_sliceSize_implementation.md) | `MibImage.sliceSize` property (N×2 matrix) — 21 files touched |
| [fixing_selection_documents.md](ports/fixing_selection_documents.md) + [port_splitpanel.md](ports/port_splitpanel.md) | Split-panel `mibModel.id` corruption: root causes, all fixes, reliable UI chain diagram |
| [link_views_plan.md](ports/link_views_plan.md) | Linked-view propagation: `linkedPairs`, propagation in `showImage` |

---

## Notes & scratch

`development/notes/` — small odds and ends:

| File | What |
|------|------|
| [cuda.txt](notes/cuda.txt) | CUDA / SAM2 "no kernel image" error and fix |
| [mathworks_bugreport_dltrain_stop.md](notes/mathworks_bugreport_dltrain_stop.md) + [dltrainStopRepro.m](notes/dltrainStopRepro.m) | `trainSOLOV2`/`images.dltrain` ignores stop requests in its outer epoch loop — bug report draft, repro, and what DeepMIB does about it |
| [linking_split_view_problem.txt](notes/linking_split_view_problem.txt) | Cursor repositioning issue in split view (zoom recentering) |
| [volren_movie_capture_speed.md](notes/volren_movie_capture_speed.md) | Why 3D viewer animations record at ~1 fps — measured capture routes, what was ruled out, and why it was not "fixed" |
| [plan_mib3_json.md](notes/plan_mib3_json.md) | **Evaluation (not implemented)**: replacing binary `mib3.mat` preferences with JSON - what the file holds, measured load times (JSON is faster), the 24 leaves that break on round trip, why `writestruct` is disqualified, two-phase plan starting with the override file |
| [sync_memory.md](notes/sync_memory.md) | One-time Claude memory-sync junction setup for a new workstation |
| [doc_template.md](notes/doc_template.md) | **Legacy** Doxygen doc template — superseded by `guides/docs_api_sphinx.md` |
| [focusExample.m](notes/focusExample.m) | Proof that `focus()` works on visible uifigures (basis of dialog focus handling) |
| [image_reader.m](notes/image_reader.m), [syntax_changes.m](notes/syntax_changes.m), [test_CurrentModifier_sticky_python.m](notes/test_CurrentModifier_sticky_python.m) | Code snippets / experiments |
| [AppContainerFrameworkNotes.mlx](notes/AppContainerFrameworkNotes.mlx) | Live-script notes on the AppContainer framework (binary, open in MATLAB) |
