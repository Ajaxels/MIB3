# Crop of BigData datasets: streaming, parallel, resumable

Status: implemented 2026-11-19, uncommitted. The `UseParallelComputing` checkbox ("parallel
processing", between Reset and Output type) is in `views.CropDatasetGUI`; guards removed, tooltip
set in `addCallbacks`. Its Tag comes from the property name (`core.ChildView` copies every
property name to `Tag`), so none is needed in the .mlapp. GUI checks below are open.

## Problem

`controllers.CropDataset` (Dataset ribbon -> Crop) on a BigData source:

| Output | Before | Peak memory |
|--------|--------|-------------|
| **BigData** (`MibDataset.cropToBigData`) | one `getData` of the whole crop at **s0**, `Zarr3Saver.save(array)`, then one `getData63` of the whole s0 model box, `setData63`, `materializeAll` | the whole s0 crop x colors + the saver's coarser levels + the whole packed model box |
| **Standard** (`MibDataset.cropDataset`) | one `getData` of the crop at the chosen level + the packed model box | the size of the result (unavoidable: it becomes a Standard dataset) |

- The BigData output only worked for crops that fit the memory at full resolution - the case it
  exists for (a crop too large for a Standard dataset) is exactly the one it could not do.
- Nothing checked the free memory before either read; the read is one call and cannot be cancelled.
- No parallel workers; an interrupted crop restarted from zero.
- The model copy always created a **uint8** store, so a 16383 (uint16) instance model was
  written into the wrong layout.

Not a problem (checked): the "copy before crop". For a BigData source `deepCopyDataset` copies only
the store references and metadata (`copy` of the image/labels objects, no pixels; closing the copy
closes only BioFormats readers; the BigData labels destructor releases nothing), and
`MibModel.backup('image')` skips non-Standard datasets. For a **Standard** source cropped into
another container the deep copy does hold the whole dataset twice before the crop - not changed
here.

## Decisions

1. **The image crop is written by the BigData image engine.** `cropToBigData` calls
   `utils.bigdata.processImageToStore(image, @(block) block, ...)` with `Region` = the crop box at
   level 1 and the new `SliceRange` = the crop slices. That engine already streams bands of rows
   (`io.savers.FilteredSliceProvider` + `Zarr3Saver.saveStreamResumable`), runs on a process pool,
   resumes an interrupted run and checks Cancel per band. Memory: about one band (256 MB budget)
   per worker, whatever the crop size.
2. **`SliceRange` is added to `FilteredSliceProvider` and `processImageToStore`** (`[first last]`
   level slices). `z` given to a block function stays the level slice. The bounding box of the
   result starts at the first slice of the range.
3. **The model is copied in strips on the client** (the pattern of
   `Alignment.applyAlignmentBigData`, pass A/B):
   - level 1: `getData63('everything')` of the source over a strip of rows x the crop width x one
     Z chunk of the new store, rows a whole number of chunk rows within a 128 MB budget,
     `writePackedLevel(1, ...)`;
   - each coarser level from the level above it, nearest decimation with the index map of
     `propagateRegion` (`floor((0:t-1)*s/t)+1`), in strips of target rows;
   - `markTiles(..., 1)` and `selectionTiles(:) = true` so every level reads directly.
   The store mirrors the **written image store** (`createStore(dims, path, croppedImage.pyramid)`),
   so its levels equal the image's whatever the saver chose. The layout follows the source
   (`setLayout(source.containerClass)`), `objects3D` and the material metadata are carried over.
   Not parallel: the model is one byte per voxel against the image's colors x bytes, and the
   packed store is written from the client in the other BigData model writers too.
4. **Parallel = BatchOpt `UseParallelComputing`** (default false), as in the BigData image tools.
   The pool logic of `BigDataOptions.startPool` moves to `utils.bigdata.startProcessPool` (second
   call site): open pool used as it is, otherwise `cpuParallelLimit` workers, a thread pool
   refused, zarrMex pinned on every worker, worker chunk caches cleared after the run.
5. **Resume.** An output folder holding `.mib_resume.json` -> Resume / Start over / Cancel (batch:
   start over). Resume reads the saver options of the stopped run from
   `.mib_run_settings.mat` (the file of `BigDataOptions`) and skips the settings dialog. A cancel
   during the image -> Keep (to resume) / Delete. A failed run keeps its resumable part and says so.
6. **Cancel during the model copy** removes the model store; the complete image store stays on
   disk, is not opened, and the message says both.
7. **Time series:** `saveStreamResumable` writes one time point, so a BigData output of more than
   one time point is refused with a message (before, the whole s0 crop of all time points was held
   in memory).
8. **Standard output memory check.** Before the deep copy and the read: crop size at the chosen
   level x colors x time points x image class + the packed model box, against
   the available physical memory (`[~, systemView] = memory`, as Quantification); refused with the two numbers and the advice (a coarser level
   or BigData output). Skipped where `memory` is not available (macOS/Linux).

## Changes

| File | Change |
|------|--------|
| `io/+savers/FilteredSliceProvider.m` | `SliceRange` option |
| `utils/+bigdata/processImageToStore.m` | `SliceRange` pass-through, Z origin of the box, fingerprint |
| `utils/+bigdata/startProcessPool.m` (new) | pool start, from `BigDataOptions.startPool` |
| `controllers/@BigDataOptions/BigDataOptions.m` | `startPool` calls `startProcessPool` |
| `core/@MibDataset/cropToBigData.m` | rewritten: streamed image (pool, resume), strip model copy, `[result, stopStage]` |
| `controllers/@CropDataset/CropDataset.m` | `UseParallelComputing`, resume / keep / delete dialogs, memory check, time block moved up |
| `docs/.../dataset-crop.md`, release notes | parallel, resume, memory refusal |

Also added on the way: `TimePoint` in `FilteredSliceProvider` / `processImageToStore` (default 1).
The reads now ask for one time point: `getData` without `t` returns every time point, which the
provider's reshape could not take, so a time-series BigData store never worked there before.

Known difference: the box of a single-slice crop now has a Z extent of 0 (processImageToStore
computes `(n - 1) * voxel`); the old in-memory path used `max(n, 2) - 1`.

## Tests (pass 2026-11-19 in `-batch`)

- `tests/core/CropToBigDataTest.m` (5, Integration): source pyramid kept, saver options win, the
  image equals the array crop and its box starts at the crop origin, model level 1 equals the
  source box and the coarsest level is filled, a uint16 instance model keeps layout and indices,
  two time points refused.
- `tests/utils/ProcessImageToStoreTest.m` (+3): `SliceRange` with a 3D halo read beyond the range
  and the Z origin of the box, `Region` + `SliceRange` crop, a wrong range refused.
- `tests/core/CropToBigDataParallelTest.m` (1, 2 workers): every level written by the workers
  equals the client crop.
- Unchanged and passing: `ImageFiltersBigDataTest`, `MorphOpsImagesBigDataTest`,
  `ImageFiltersBigDataParallelTest` (uses `startProcessPool` now).

Not covered: the controller dialogs (resume / keep / delete, memory refusal), cancel during the
model copy.

## Widget to add (author)

Checkbox `UseParallelComputing` (Tag = handle name) in `views.CropDatasetGUI`, label "parallel
processing" (added 2026-11-19; Tag from the property name). Value, Enable (BigData source with Output type
BigData only) and the tooltip are set in code.

## GUI checks (open)

- [ ] Crop to BigData of a large store (larger than memory at s0): memory stays flat, progress per band
- [ ] Same with Use parallel computing; pool started when none is open
- [ ] Cancel during the image -> Keep -> crop again to the same path -> Resume finishes it
- [ ] Cancel during the model copy: image store kept, model store removed, message
- [ ] Crop of a 16383 instance model to BigData; objects keep their indices
- [ ] Standard output larger than the free memory: refused with the numbers, nothing changed
- [ ] Standard dataset: crop unchanged
