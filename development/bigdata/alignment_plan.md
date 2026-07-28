# Alignment for BigData mode

Architecture (two-pass streaming, transform scaling, packed-63 warp, canvas/OutputView, buffer
switch-over) is documented in [`bigdata_logic.md`](bigdata_logic.md) §13 — read that first.
This file keeps the implementation gotchas and the **still-open live-GUI acceptance checklists**.

**Status: implementation DONE** (Phases 0–4, all algorithms: drift/template, feature-based v2
affine, landmark single/three/multi). `AppDesigner` BigData panel on `AlignmentGUI.mlapp` was
added by hand (per IB). **Still open: the final live-GUI acceptance run on real data** — run the
checklists in §1/§2 below and tick them off.

## Gotchas fixed during implementation (do not re-break)

- **Shift double-scaling.** Drift/Template stores level-0 shifts in `obj.shiftsX/Y` at all times
  (scaled to level 0 right after `calcShifts`); apply is `round(obj.shiftsX)` with **no re-scale**.
  Loading a saved (level-0) file and re-scaling by `scaleX` again silently doubled the canvas
  growth whenever the analysis level was >1 — this is why level-0 is the single stored unit.
- **Feature-v2 save/replay was missing entirely** — v2 now has its own `saveV2ToFile` (level-0
  `cumulativeTforms` struct) and a replay branch that skips detection/fit/smoothing and reuses the
  loaded cumulative tforms directly.
- **Loaded-shift preview/confirm happens at Apply**, not at load time (`continueBtn_Callback` →
  `previewConfirmLoadedShifts`): classifies numeric vs `cumulativeTforms` struct vs legacy cell,
  plots them, asks for confirmation, and **aborts with a mismatch error** if the loaded
  coefficient type doesn't match the selected algorithm (never silently recomputes).
- **Landmark modes now preview detected displacements before applying** too (shared
  `plotAlignmentTransforms` + `confirmDetectedTransforms`), matching drift/single-landmark.
- **`TransformationMode` was stuck on `cropped`** for Single/Three-landmark (disabled by the
  default disable-all loop, sticky from a prior algorithm) — now defaults to `extended` and is
  enabled for BigData on those two modes specifically (the only place the BigData apply path
  honours the choice).
- **Aligned store must mirror the source pyramid** — `applyAlignmentBigData` derives chunk size,
  level count, `DownsampleStrategy` (anisotropy-preserving iff the source ever halves Z) and shard
  size from `ds.image.pyramid`, rather than hardcoding `[256 256 16]`/8 levels/bilinear; the labels
  store shares the same plan so image and labels co-register.
- **Silent vs GUI dialog behavior:** batch/silent runs use the source-matched settings directly
  (no dialog); GUI runs open `Zarr3Saver.optionsDialog` **pre-filled from the source dataset**
  (`presetDefaults` argument) so the user can review/adjust before writing.
- **Aligned model lost material names/colours** — `createStore` starts with an empty material
  list; `applyAlignmentBigData` now copies `materialNames`/`materialColors`/`materialsCount` onto
  the new labels object and calls `writeMaterialMetadata()` before `closeStore()`.
- **Labels store perf: ~15× faster.** The old per-slice `setData63('everything', ...)` loop did a
  read-before + diff + eager cross-level propagation + selection-bbox scan per Z-slice (89 s on an
  887×813×171 3-level model). Replaced with a two-pass writer: Pass A warps into level 1 in
  Z-chunk-sized strips (one write per chunk), Pass B bulk-builds every coarser level from level 1
  via global index maps, then one `markTiles` call over the whole volume. Now ~6 s, level 1
  bit-identical to the old output.
- **`MibDataset.initialize` leaves `slices=[1 1]` and `axesX/axesY=NaN`** for an off-screen
  buffer — `applyAlignmentBigData` resets `slices` to the new full extent and seeds `axesX/axesY`
  when uninitialised, or the first display read crashes.

## Scope & limitations

Drift correction / Template matching, Automatic feature-based **v2** (affine), Landmark modes
(single/three/multi, **annotation-driven** — selection-layer extraction is a possible later add).
Feature-based v1 and AMST remain blocked in BigData. XY orientation (3) only; `time == 1`; Subarea
by Mask/Selection rejected for drift (Full image / Manually specified only). No undo — the
untouched source store is the backup (`mibModel.backup()` is skipped in all BigData paths).

Tests: `tests/controllers/AlignmentBigDataTest.m` (9 Integration tests, headless against a bare
`models.MibModel`).

## 1. Live-GUI checklist (final acceptance) — OPEN

1. Open a pyramidal `.zarr3` (BigData) with a painted model+mask+selection.
2. Alignment dialog opens; BigData panel visible; level dropdown default ≈3k px; output path
   prefilled `<name>_aligned.zarr3`.
3. Drift correction, extended mode → new store written, buffer swaps, image+model+mask+selection
   all shifted identically at every zoom level; bounding box updated.
4. Same, cropped mode → canvas unchanged.
5. Feature-based v2 rigid on a rotated synthetic stack → straightened; annotations follow.
6. Three-landmark alignment via annotations → correct.
7. Cancel mid-write → partial stores deleted, source dataset still active and intact.
8. AMST / feature-v1 → friendly "not supported in BigData" dialog.
9. Batch Processing: record + replay a BigData drift-correction action headlessly.

## 2. Phase 1 (drift correction) live-GUI acceptance — OPEN

Run in the real GUI on a **displayed, multi-slice** pyramidal `.zarr3` (depth ≥ 2). Headless +
end-to-end tests already pass; this confirms the interactive path on real data.

- [ ] Open a multi-slice `.zarr3` BigData dataset (ideally with a painted model + mask + selection).
- [ ] **Ribbon → Dataset → Alignment** — BigData panel visible; level dropdown lists all levels
      with the `<auto>` (~3000 px) default; output path prefilled `<name>_aligned.zarr3`.
- [ ] Drift correction, extended mode, background White → Apply → preview plot of detected shifts
      → Apply current values (or Fix drifts to smooth).
- [ ] Progress bar runs (image, then labels); on completion the active buffer **swaps** to the
      aligned store and renders immediately.
- [ ] Image + model + mask + selection shifted identically at multiple zoom levels (overlay stays
      registered when zooming).
- [ ] Directory Contents highlights the new store; sibling `Labels_<name>_aligned.zarr3` exists;
      source store untouched.
- [ ] Bounding box / pixel size sensible.
- [ ] Cropped mode → canvas dimensions unchanged.
- [ ] Cancel mid-write → partial stores deleted, source still active, no buffer swap.
- [ ] AMST / feature-v1 / Color-channels-multi → friendly rejection dialog.
- [ ] Subarea = Mask/Selection on BigData drift → friendly "use Full image / Manually specified"
      dialog.

## File map

**Modify:** `+controllers/@Alignment/{Alignment,continueBtn_Callback}.m`,
`+views/AlignmentGUI.mlapp` (BigData panel).
**New:** `+controllers/@Alignment/{DriftCorrectionBigData_Alignment,
AutomaticFeatureBasedV2BigData_Alignment, LandmarksBigData_Alignment,
applyAlignmentBigData}.m`; `+io/+savers/AlignedImageSliceProvider.m`.
**Reused unchanged:** `+utils/+align/{calcShifts,crossShiftStack,detectFeatures,
subtractRunningAverage,runningAverageSmoothPoints}.m`; `Zarr3Saver.{saveStream,computeLevelPlan,
patchMetadata}`; `MibBigDataLabels.{createStore,openStore}`; buffer-switch pattern from
`CropDataset.m`.
