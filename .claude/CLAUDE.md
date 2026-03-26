# MIB3 Session Context

Supplementary to the root `CLAUDE.md` (architecture, conventions, essential conversion rules).

---

## Port Status

| Component | Status | Details |
|-----------|--------|---------|
| `core.RoiRegion` + `controllers.MibRoi` | DONE | [port_roi.md](port_roi.md) — **remaining: `roiToSelection`** |
| `models.MibModel.moveLayers` + 6 helpers | DONE | [port_movelayers.md](port_movelayers.md) |
| `models.MibModel.loadModel` + `MibDataset.loadModel` + `io.MatModelLoader` | DONE | [port_loadmodel.md](port_loadmodel.md) |
| Split-panel `id` corruption fixes | DONE | [port_splitpanel.md](port_splitpanel.md) |
| `controllers.BatchProcessing` | **NOT STARTED** | [port_batchprocessing.md](port_batchprocessing.md) |

---

## Subtopic Guides

| File | When to read |
|------|--------------|
| [appdesigner_guide.md](appdesigner_guide.md) | Starting any new GUIDE → AppDesigner port: file layout, widget syntax, constructor pattern, checklist |
| [conversion_reference.md](conversion_reference.md) | Full conversion tables: PoolWaitbar, backup, clearing, data structures, bit packing, misc |
| [conversion_ui.md](conversion_ui.md) | Modifier keys, image display coords, orientation switching |
| [doc_template.md](doc_template.md) | Documentation block template and rules |
| [port_batchprocessing.md](port_batchprocessing.md) | Full plan: 31 files, phased steps, `.mlapp` widget list |
| [port_roi.md](port_roi.md) | ROI architecture, widget handles, `roiToSelection` remaining |
| [port_loadmodel.md](port_loadmodel.md) | BatchOpt fields, extension→loader map, edge cases |
| [port_movelayers.md](port_movelayers.md) | Property mapping, fast/slow path, performance notes |
| [port_splitpanel.md](port_splitpanel.md) | Root causes, all fixes, reliable UI chain diagram |
| [sync_memory.md](sync_memory.md) | One-time setup command for Claude memory sync on a new workstation |
