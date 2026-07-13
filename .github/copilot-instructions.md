# GitHub Copilot Instructions — MIB3

MIB3 (Microscopy Image Browser 3) is a MATLAB AppContainer application for image processing and segmentation of multidimensional microscopy data. It is an active port from MIB2 (GUIDE-based) to MIB3 (AppDesigner + AppContainer).

**For full project context, coding conventions, and MIB2→MIB3 conversion rules read `CLAUDE.md` in the repository root.**

For deeper reference on specific topics, start from the contents page `development/INDEX.md`, or attach directly:

| Topic | File to attach |
|-------|----------------|
| Contents page for all development docs | `development/INDEX.md` |
| AppDesigner conversion patterns | `development/guides/appdesigner_guide.md` |
| Data structures, PoolWaitbar, backup, clearing | `development/guides/conversion_reference.md` |
| Modifier keys, display coords, orientation | `development/guides/conversion_ui.md` |
| RST docblock style guide | `development/guides/docs_api_sphinx.md` |
| ROI class notes + remaining work | `development/ports/port_roi.md` |
| Plugin development (standalone guide) | `mib/plugins/plugins_instructions.md` |

---

## Essential Quick Reference

### Package layout
```
mib/+controllers/   UI controllers (@MibController, @MibImageDocument, @MibRoi, …)
mib/+models/        Application state (@MibModel)
mib/+views/         .mlapp UI components + @MibView
mib/+core/          Data classes (@MibDataset, @MibImage, @MibLabels, …)
mib/+io/            Image I/O — factory pattern (ExtensionRegistryLoad → LoaderFactory → loaders)
mib/+utils/         Dialogs (+dlgs), defaults, utilities
```

### Critical rules

- **`BatchOpt.id = obj.getActiveId()`** — never `obj.id`; it is stale in split-panel mode
- **`gui_WinMouseMotionFcn` must never write `mibModel.id`** — breaks panning and keyboard shortcuts
- **Modifier keys**: read `obj.mibController.currentModifier`, not `obj.UIFigure.CurrentModifier`
- **Dialogs**: use `utils.dlgs.inputUniversalDlg` / `utils.dlgs.inputQuestDlg`; parent to `obj.mibGUI` (AppContainer), not `obj.UIFigure`
- **`parfor` progress**: always use `core.PoolWaitbar`; never update `uiprogressdlg.Value` inside parfor
- **Key-value storage**: `dictionary` (R2022b+), never `containers.Map`
- **`[]` not `NaN`** for `slice_no`/`orient` in getData/setData calls

### Build and test
```matlab
cd C:\Matlab\MIB3
buildtool          % check + test
buildtool check    % code issues only
buildtool test     % tests only
```

### MIB2 source references

| Path | Use for |
|------|---------|
| `C:\Matlab\MIB2\` | **Verifying behavior** — original working code; run/debug to confirm intent |
| `C:\Matlab\MIB2_RENAMED_FOR_MIB3\` | **Copying logic** — partial rename to MIB3 style; use as starting point but apply the full cheat sheet regardless (renaming is incomplete) |
