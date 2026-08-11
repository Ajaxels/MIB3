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
| [`plan_url_s3.md`](plan_url_s3.md) | **Remote OME-Zarr over URL / S3** - implemented through step 15; step 16 (label crops with their image region) designed, not built. Opening public cloud stores (Janelia OpenOrganelle et al.) as BigData via `Home -> Import -> URL`: the lazy S3 group browser, URL-aware zarr version detection and the chunk cache. Supersedes the deferred remote-zarr item in `bigdata_implementation_plan.md`. **Note:** its `aiohttp`/`requests` prerequisite no longer applies - see `plan_native_zarr2.md`. |
| [`plan_native_zarr2.md`](plan_native_zarr2.md) | **Native Zarr v2** - done 2026-08-11. `zarrMex` gained v2 read/write, so v2 stopped being a python-only, read-only special case: same engine as v3, editable v2 model stores, v2 export. Explains the `mibModelStore` marker and why model-store editability now turns on **authorship, not format**. |

Historical dated fix-logs (`plan_bigdata.md`, `bigdata_levelmap_spec.md`/`_plan.md`,
`bigdata_brush_performance.md`, `plan_wsi_readers.md`, `wsi_livetest_checklist.md`) were removed
2026-07-27 — everything actionable in them was already folded into the two docs above; recover
from git history if the blow-by-blow is ever needed.
