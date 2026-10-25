# BigData docs

All documentation for the MIB3 **BigData** dataset type (disk-backed pyramidal OME-Zarr v3
image + segmentation model) lives here.

## Read these

| File | Purpose |
|------|---------|
| [`bigdata_logic.md`](bigdata_logic.md) | **How it works.** Class architecture, image/model pyramids, the level map (`matLevel`) + `.levelmap` sidecar, getData/setData & coordinate conventions, WSI-safe editing, Save modes, invariants/gotchas, file map. Read this first whenever you touch BigData. |
| [`bigdata_implementation_plan.md`](bigdata_implementation_plan.md) | **Status & remaining work.** What's done, the still-open streaming-export items, WSI Phase E (deferred), the deferred backlog (T>1, `removeMaterial` renumbering, remote zarr, …), and audit findings not yet acted on. **Check here for open work before starting anything BigData-related.** |
| [`user_checklist.md`](user_checklist.md) | **Live-GUI test checklist** for the export + ImageConverter features - several rows are still unchecked (§D5-D7, §E, §F). |
| [`alignment_plan.md`](alignment_plan.md) | **Alignment for BigData** - implementation done; gotchas log + the still-open live-GUI acceptance checklists. |
| [`plan_url_s3.md`](plan_url_s3.md) | **Remote OME-Zarr over URL / S3** - implemented through step 21. Opening public cloud stores (Janelia OpenOrganelle et al.) as BigData via `Home -> Import -> URL / Zarr`: the lazy S3 group browser, URL-aware zarr version detection, the chunk cache, label crops loaded with their image region, and pairing a coarse label pyramid with the image level that matches it. Supersedes the deferred remote-zarr item in `bigdata_implementation_plan.md`. **Note:** its `aiohttp`/`requests` prerequisite no longer applies - see `plan_native_zarr2.md`. |
| [`plan_url_s3_labels_mismatch.md`](plan_url_s3_labels_mismatch.md) | **Label pyramids that do not match the image** - stages A-D done; only the manual in-a-running-MIB checklist remains. Fixes what step 21 of `plan_url_s3.md` got wrong (the dataset mode was silently overridden and the Datasets panel went stale) and delivers the path it never attempted: browsing the image as **BigData** with a read-only label overlay (`core.MibBigDataLabelsIndex`) served per slice, missing fine levels gathered from the finest label level, instance ids drawn merged or per object, and "Save model as" exporting one chosen level. Carries the level-registration and gather arithmetic, and the audit of what assumes a BigData model is the packed 63-material scheme. |
| [`plan_imageconverter_zarr.md`](plan_imageconverter_zarr.md) | **Implemented** (2026-10-15). Conversions run as resumable slab tasks (`Zarr3Saver.saveStreamResumable`), written by the pool workers with Parallel processing, and in bands of rows for TIFF slices too large for memory (resizes are exactly 0.5 per level, so bands equal whole slices); zarrMex CPU is the measured limit. Image converter -> Zarr: why a week-long conversion could end truncated yet report success (swallowed python worker errors, unbounded `chunkZ x H x W` memory), a native-path bug that recursively deletes the output folder, and measured write costs (transpose codec 2.5x, partial-shard writes 3.4x, compression negligible) behind an A (correctness) / B (speed) fix list. |
| [`zarrmex_exit_crash.md`](zarrmex_exit_crash.md) | **zarrMex exit crash** - fixed 2026-10-24. MATLAB died in `zarrMex.mexw64_unloaded` when it unloaded the Rust library while its worker threads lived; MIB now pins the library at startup. Measurements, the control experiment, and the upstream `mexLock` suggestion. |
| [`plan_native_zarr2.md`](plan_native_zarr2.md) | **Native Zarr v2** - done 2026-08-11. `zarrMex` gained v2 read/write, so v2 stopped being a python-only, read-only special case: same engine as v3, editable v2 model stores, v2 export. Explains the `mibModelStore` marker and why model-store editability now turns on **authorship, not format**. |

Historical dated fix-logs (`plan_bigdata.md`, `bigdata_levelmap_spec.md`/`_plan.md`,
`bigdata_brush_performance.md`, `plan_wsi_readers.md`, `wsi_livetest_checklist.md`) were removed
2026-07-27 - everything actionable in them was already folded into the two docs above; recover
from git history if the blow-by-blow is ever needed.
