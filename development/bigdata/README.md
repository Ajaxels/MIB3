# BigData docs

All documentation for the MIB3 **BigData** dataset type (disk-backed pyramidal OME-Zarr v3
image + segmentation model) lives here.

## Read these

| File | Purpose |
|------|---------|
| [`bigdata_logic.md`](bigdata_logic.md) | **How it works.** Class architecture, image/model pyramids, the level map (`matLevel`) + `.levelmap` sidecar, getData/setData & coordinate conventions, WSI-safe editing, Save modes, invariants/gotchas, file map. Read this first whenever you touch BigData. |
| [`bigdata_implementation_plan.md`](bigdata_implementation_plan.md) | **Status & remaining work.** What's done, the still-open streaming-export items, WSI Phase E (deferred), the deferred backlog (T>1, `removeMaterial` renumbering, remote zarr, …), and audit findings not yet acted on. **Check here for open work before starting anything BigData-related.** |
| [`user_checklist.md`](user_checklist.md) | **Live-GUI test checklist** for the export + ImageConverter features — several rows are still unchecked (§D5–D7, §E, §F). |
| [`alignment_plan.md`](alignment_plan.md) | **Alignment for BigData** — implementation done; gotchas log + the still-open live-GUI acceptance checklists. |
| [`plan_url_s3.md`](plan_url_s3.md) | **Remote OME-Zarr over URL / S3** - planned, not started. Opening public cloud stores (Janelia OpenOrganelle et al.) as BigData via `Home -> Import -> URL`: the lazy S3 group browser, URL-aware zarr version detection, the `aiohttp`/`requests` prerequisite, and why sub-volume label crops are scoped out. Supersedes the deferred remote-zarr item in `bigdata_implementation_plan.md`. |

Historical dated fix-logs (`plan_bigdata.md`, `bigdata_levelmap_spec.md`/`_plan.md`,
`bigdata_brush_performance.md`, `plan_wsi_readers.md`, `wsi_livetest_checklist.md`) were removed
2026-07-27 — everything actionable in them was already folded into the two docs above; recover
from git history if the blow-by-blow is ever needed.
