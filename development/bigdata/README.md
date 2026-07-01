# BigData docs

All documentation for the MIB3 **BigData** dataset type (disk-backed pyramidal OME-Zarr v3
image + segmentation model) lives here.

## Read these (authoritative, consolidated 2026-06-25)

| File | Purpose |
|------|---------|
| [`bigdata_logic.md`](bigdata_logic.md) | **How it works.** Class architecture, image/model pyramids, the level map (`matLevel`) + `.levelmap` sidecar, getData/setData & coordinate conventions, WSI-safe editing, Save modes, invariants/gotchas, file map. Read this first whenever you touch BigData. |
| [`bigdata_implementation_plan.md`](bigdata_implementation_plan.md) | **Status & remaining work.** Streaming export (Phases 1–4), WSI direct readers (A–D done, E deferred), pending live-GUI validation checklist, deferred backlog, MCP verification helper. |
| [`user_checklist.md`](user_checklist.md) | **Live-GUI test checklist** for the export + ImageConverter features: units fix, OME-TIFF streaming, BigData mask export, native zarr3 convert, BioFormats→MATLAB warning, voxel round-trip. Automated baseline commands + click-through steps with pass criteria. |

## Superseded detail log (history only)

Kept for the dated, blow-by-blow fix history; everything actionable is folded into the two docs above.

- `plan_bigdata.md` — master log: architecture Phases 0–3, WSI-safe convention, export Phases 1–4, TODOs
- `bigdata_levelmap_spec.md` — level-map manager spec + perf/naming/crash-safety follow-ups
- `bigdata_levelmap_plan.md` — task-by-task level-map implementation plan
- `bigdata_brush_performance.md` — original brush-perf fix (superseded by the level map)
- `plan_wsi_readers.md` — direct WSI reading plan (BioFormats/OpenSlide), Phases A–E
- `wsi_livetest_checklist.md` — original GUI live-test checklist (now §4 of the implementation plan)
