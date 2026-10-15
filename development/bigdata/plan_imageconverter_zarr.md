# ImageConverter -> Zarr: truncated output and slow conversion

**Status (2026-10-15): A1-A4, B1, B2 (TIFF), B3, B4 (as workers writing the store), B5, B6,
B8 and resume implemented; B7 open; C decided - the python pipeline stays.** DeveloperMode markers added to the plugin's widget callbacks. New
defaults: chunk `256, 256, 16`, shard factors `4, 4, 1`. Tests: `tests/io/Zarr3SaverTest.m`
(C-order codecs, sharded round trip, incomplete flag + loader warning).

### Result, measured end to end

48 LZW TIFFs of 4096 x 4096 uint8 (805 MB), native v3, chunk `256 256 16`, zstd level 1, 10-core
workstation whose cluster profile allows 2 workers:

| | Time |
|-|------|
| reading the 48 files alone (client `readimage`) | 11.6 s |
| `saveStream` from memory, all 4 levels (write + downsampling, no reading) | 13.0 s |
| of which level-0 writes | 6.7 s (120 MB/s; ~50 MB/s before B1) |
| full conversion, serial | 19.9-22.3 s |
| full conversion, 2 process workers reading ahead for the client (first attempt, removed) | 20.1 s |
| full conversion, 2 process workers writing the store themselves (current) | 16.8 s |
| same, 96 slices (6 slab tasks, balanced): serial / 2 workers writing | 36.8 / 30.7 s (1.2x) |

### Resume (`Zarr3Saver.saveStreamResumable`)

The slab writer below runs every native ImageConverter conversion, with a pool on the workers and
without one on the client, so serial conversions are resumable too. `.mib_resume.json` (written
once: sizes, level plan, chunk, shard, codec, format, method, and the plugin's source fingerprint
- number, first/last name, total size and latest modification time of the files) and
`.mib_progress.log` (one `<task key> <largest value>` line per finished task, appended by the
client) sit in the store root and are deleted on success. A resume reopens the store, skips the
recorded tasks and redoes the rest; any difference in `.mib_resume.json` refuses it
(`io:Zarr3Saver:cannotResume`) without touching the store. The largest label value per task is
kept in the log so material names still count the skipped slabs.

Plugin: an output directory holding `.mib_resume.json` offers Resume / Overwrite / Cancel; batch
mode resumes when possible and otherwise starts again. Not covered: the python pipeline (no
resume). Replacing a corrupt source file changes its modification time, so that resume is refused
- deliberate, the record cannot tell which slabs used the old file. Tests:
`tests/io/Zarr3SaverResumeTest.m` (Unit).

### Parallel processing: workers write the store (`Zarr3Saver.saveStreamResumable` with a pool)

1. Each task reads one chunk-aligned Z-slab of source files **on the worker** and writes it to
   level 0 and to every level that keeps the full Z. The slab depth is the level-0 write depth
   (chunk Z, or shard Z), so tasks never share a chunk or a shard.
2. The Z-downsampled levels are then built one after the other, each task reading a
   chunk-aligned block of the level above back from the store.

No slice crosses a process boundary; the provider goes to the workers once through
`parallel.pool.Constant`. Level 0 and the full-Z levels are identical to `saveStream`; a
Z-downsampled level is the mean of the rounded level above, so it may differ by 1 (tested in
`tests/io/Zarr3SaverParallelTest.m`, tag Integration).

**Why only 1.2x with 2 workers.** zarrMex itself is the limit: one writer already keeps ~7.5 of
10 cores busy, at ~25 CPU-s per GB even with no compression and the data in a layout that needs
no reordering (268 MB: 0.84 s wall / 6.8 s CPU, against 0.46 s for `fwrite`). Workers can only
add the single-threaded reading and downsampling in parallel. More workers help on machines with
more cores than one zarrMex writer uses.

**Rejected on the way:**
- *Read-ahead on the pool for the client's writer* (`ImageDatastoreSliceProvider` with a pool,
  removed): sending each 16 MB slice back costs a worker ~0.25 s on top of the 0.26 s read, so a
  worker delivers ~2 slices/s - 10% gain with 2 workers.
- *Thread workers* (no copy): TIFF cannot be read on thread-based workers
  (`matlab.internal.imagesci.rtifc` is not supported - tried `parpool('Threads')` and
  `backgroundPool`).
- *Declaring the array in MATLAB's memory order* to spare zarrMex the reordering: 0.84 s + 0.19 s
  `permute` against 1.12 s, and it would break the `[y x z]` axis convention. Not worth it.

### XY bands for TIFF (B2, `saveStreamResumable` with `BandHeight`)

When whole slices need more than 80% of the free memory (`2.5 x writeDepth + 2` rows per row, per
process) and the source reads rows (`ImageDatastoreSliceProvider.SupportsRowReads`: all files TIFF,
the first 16 rows of `imread` equal those of the datastore reader), ImageConverter sets
`BandHeight` to the whole chunk (shard) rows of level 0 that fit. Level 0 is then written in
Z-slab x row-band tasks read with `imread(..., 'PixelRegion', ...)`; every coarser level is built
band by band from the level above, each band sized to read about as much as a level-0 band.

**Why a banded store equals an unbanded one.** Every level halves XY (`computeLevelPlan`,
`round(n/2) = ceil(n/2)`), so all streaming writers now resize by exactly 0.5
(`imresize(x, 0.5, method)`): output row `u` sits on source row `2u - 0.5`, the `2^k` scale of
the metadata. A band reads 8 extra source rows on each side and starts on an odd source row;
measured on 1001 x 777 uint16 for bilinear, bicubic and nearest, with 4 or 8 extra rows, the
band resize equals the whole-slice resize with zero difference. The previous `imresize(x,
[Yl Xl])` differs from this for odd sizes (it stretches by `n/Yl`; up to 1175 on random uint16)
and disagreed with the metadata scale, so it was replaced in `saveStream`, `writeDirectSlab` and
`buildLevelBand` alike. `save` (in-memory export) now builds each level from the level above the
same way, and halves Z by the mean of slice pairs instead of `imresize3` interpolation, so it
writes exactly the pyramid of `saveStreamResumable`; `'mode'`/`'median'` keep their block
reduction from full resolution. `saveStream` likewise averages Z over the output slices of the
level above (a cascade: level L consumes level L-1's output stream, trailing partial groups
flushed level by level) instead of over the source slices, so `save`, `saveStream` and
`saveStreamResumable` write identical stores - also with Z halved twice (test
`Zarr3SaverTest/allWriters_samePyramid`; `'mode'` compared between the two streaming writers in
`saveStream_modeLabels_samePyramidAsResumable`). `'mode'`/`'median'` need whole slices and refuse bands (`io:Zarr3Saver:bandsUnsupported`).

Measured, 32 x 4096 x 4096 uint8 LZW TIFF (64 rows per strip), chunk `256 256 16`, one process:
whole slices 10.8 s, bands of 512 rows 9.7 s, stores identical; estimated task memory 705 MB
against 88 MB. A TIFF written as one strip is decoded whole for every band - memory stays
bounded, decoding time multiplies by the number of bands. The band height is recorded in
`.mib_resume.json` and reused on resume (it depends on the free memory, which changes).
Tests: `tests/io/Zarr3SaverBandsTest.m` (Unit).

## The report

An external user converted a stack of 2D files to Zarr v3 with
`Plugins -> File processing -> Image converter`. The run took **one week**. MIB reported the
conversion as finished, but:

- level `s0` was truncated (stopped before the end of the stack)
- the root `zarr.json` and `s0/zarr.json` were missing (the user wrote them by hand)
- the coarser levels looked fine

Asked of the user (needed before choosing what to fix first): MIB version/build, Zarr backend in
Preferences (native or python), dataset size `H x W x Z`, class, channels, chunk / shard settings,
Parallel processing on/off and number of workers, the RAM in the machine, and the command-window
output of the run.

## Two pipelines

`ImageConverter.generateZarr` picks one by `io.zarr.Config.isPython()`:

| | Native (default) | Python (legacy) |
|-|------------------|-----------------|
| Entry | `generateZarrNative` -> `convertToZarr3Native` -> `io.savers.Zarr3Saver.saveStream` | `createMultiscaleDataset` + `processZChunk` |
| Level folder names | `0`, `1`, `2`... | `s0`, `s1`, `s2`... |
| Group metadata | written **at the end** (`grp.setAttributes`) | written **at the start** |
| Parallel processing checkbox | **ignored** | `parfeval` per Z-slab |
| Errors | propagate, no success message | parallel: caught, `disp`ed, **success reported** |

The user's folders are named `s0`..., which only the python pipeline produces - so the user most
likely ran the python backend (or an older build). Confirm before acting on it.

## Why the output can be truncated and still reported as finished

1. **Python + parallel swallows every worker error.** `generateZarr` wraps `fetchNext` in
   `try ... catch err; disp(err.getReport()); end` and then shows "Zarr conversion done!". A worker
   killed for lack of memory loses its Z-slab and the run still reports success. This matches the
   report.
2. **Memory grows with the full XY slice times the chunk depth, with no upper limit.** Both
   pipelines hold a whole-XY slab of `chunkZ` slices (plugin default chunk Z = 64):
   - native `saveStream`: `writeBatch{1}` (64 slices) + the concatenated `batchData` copy +
     the zarrMex transpose copy, roughly **3 x 64 x H x W x C x bytes**
   - python `processZChunk`: `subvol` + `permute` copies + the `imresize3` cubic result + the
     copy made when the data passes to Python, **per worker**; with sharding enabled the slab
     is a whole shard deep (`zChunk = shards(3)`, e.g. 4 x 64 = 256 slices)

   Example: 20000 x 20000 uint8 slices, chunk Z 64 -> 25.6 GB per slab, ~77 GB peak for native,
   more per python worker. On a 64 GB machine this is swapping (a week-long run) or an OOM
   failure. Nothing estimates the requirement before starting.
3. **Native cancel returns silently** (`if isempty(fnOut); return; end`) and leaves a partial store
   without the multiscales attributes; a crash or a reboot (likely within a week on Windows) does
   the same. There is no "incomplete" marker for the loader to warn about.

Not explained by the code: `s0/zarr.json` missing. Both pipelines create every level array
(and its `zarr.json`) before writing pixels. A deleted or interrupted copy of the store is more
likely than a writer bug - ask the user how the store was moved.

### Related data-loss bug found on the way (native path)

`Convert` runs `mkdir(OutputDirectory)`, then `saveStream` runs
`if isfolder(filename); rmdir(filename, 's'); end` on that same folder - it **always recursively
deletes the output directory**, whatever else it contains. The overwrite prompt in `Convert`
looks for `.zattrs` or `s0`, which the native writer never creates, so the user is never asked.
If the output directory is the input directory, or a parent of it, the source images are deleted.

## Measurements

Workstation, 10 cores, MATLAB live session, synthetic uint8 data, zarr v3, chunk `[128 128 64]`.

| What | Time | Note |
|------|------|------|
| `imresize` one 4096^2 slice to 4 levels, each from full res (current) | 0.070 s | negligible next to the write |
| same, cascaded from the previous level | 0.027 s | 2.6x faster |
| `imread` one 4096^2 TIFF (16 MB) | 0.42 s | MIB loader overhead (`readWithLoader`) not measured |
| zarrMex write 4096x4096x64 (1.07 GB), zstd | 19.7 s wall / 154 s CPU | ~54 MB/s; zarrMex is already multi-threaded (~7.8 cores busy) |
| zarrMex write 2048x2048x64 (268 MB), **no compression** | 4.6 s / 32 s CPU | compression is **not** the cost |
| same, zstd 3 / zstd 1 / gzip 5 | 4.4 / 4.5 / 6.8 s | |
| same, zarr v2 zstd | 4.4 s | |
| same, no compression, **without the transpose codec** (`'filters','none'`) | **1.7 s** / 13 s CPU | 2.5x faster; round-trip verified identical |
| same, without transpose, zstd | 2.2 s | |
| `fwrite` of the same 268 MB | 0.46 s | disk is not the limit |
| sharded `[512 512 256]`: four 64-deep writes into one shard row | 21 + 45 + 150 + 114 = **330 s** | each partial write re-reads and rewrites the shard |
| sharded: the same 256 slices in one write | 96 s | |

Throughput of the current native path is about 50 MB/s for uint8 (half that per voxel for
uint16), so a 1 TB stack is ~6 h of writing. A week means swapping, the python pipeline, or both.

## Plan

Ordered by priority. A-items are correctness and should land before any speed work.

### A. Correctness

- **A1 - Never report success after a failed slab** (python path). Collect `fetchNext` errors; on
  any error delete the progress dialog, report which Z ranges failed, show no success message.
- **A2 - Stop the recursive delete of the output folder** (native path). In `Convert`, treat the
  output as an existing store when it holds `zarr.json`, `.zgroup`, `.zattrs`, `0/` or `s0/`
  and ask before overwriting; refuse a non-empty folder that is not a zarr store. Fix it in the
  plugin, not in `Zarr3Saver.saveStream`, whose other callers pass a dedicated `.zarr` path.
- **A3 - Memory pre-flight.** Estimate peak = `k x chunkZ x H x W x C x bytes` (x workers for
  python) and compare with `memory` / available RAM; refuse or offer a smaller chunk Z before
  starting.
- **A4 - Make an interrupted store recognisable.** Write the multiscales attributes at the start
  (native writes them at the end) with an `incomplete` flag, clear it after the last slab; have
  the Zarr loader warn when the flag is set. Report native cancel explicitly.

### B. Speed (native path)

- **B1 - Drop the transpose codec** in `Zarr3Saver` (`'filters','none'`, C order): 2.5x on the
  write, the measured main cost. C order is also the layout every other zarr reader expects.
  Shared by every `saveStream` / `save` caller (Convert to BigData, exports, alignment), so
  check MIB's own loaders plus napari / zarr-python / neuroglancer on the result before
  switching. Existing stores keep their codec and stay readable.
- **B2 - Limit memory by streaming XY bands.** For TIFF sources, read row bands with
  `imread(..., 'PixelRegion', ...)` / `Tiff.readEncodedStrip` and write `band x W x chunkZ`
  blocks: memory independent of slice size, chunk Z can stay 64. Other formats keep the slab
  path, limited by A3.
- **B3 - Sharding: write whole shards.** Partial-shard writes cost 3.4x (measured). Default the Z
  shard factor to 1 so a chunk-deep slab is a whole shard row, or buffer to the shard depth when
  A3 says it fits.
- **B4 - Overlap reading and writing.** zarrMex already uses all cores while writing, so more
  workers writing gains little; reading is serial and single-core. Prefetch the next slab's
  files (`parfeval` on a pool, or `backgroundPool` if the loader is thread-safe) while the
  current slab is written. This is where the Parallel processing checkbox should act for Zarr;
  until then hide or disable it when the output is Zarr.
- **B5 - Cascade the downsampling** (each level from the previous level, not from full res):
  measured 2.6x on that step; cheap.
- **B6 - Labels: drop the pre-pass** in `convertToZarr3Native` that reads every file only to find
  the maximum label (doubles read time). Track the maximum during streaming - the attributes are
  written at the end anyway (or at the start with A4, updated at the end).
- **B7 - Measure `readWithLoader`** (`loadMetadata` + `loadImages` per file) against plain `imread`
  for TIFF; use the direct read when MIB's loader adds nothing for single-page files.
- **B8 - Pass `ZarrCompressionLevel` through** to the native codec; it is currently ignored.

### C. Python pipeline

The native writer covers v2 and v3, so the plugin's python pipeline exists only for users with the
python backend selected. Options: (a) always use native in ImageConverter regardless of the
backend preference, retiring `processZChunk` / `createMultiscaleDataset`; (b) keep it and apply
A1/A3. With `OutOfProcess` execution every block is also copied between processes, which makes
that path slower still. Recommendation: (a), after B1-B3, if the developer agrees.

## Expected gain

B1 (2.5x on the write) plus B3 (3.4x when sharded) plus B4 (read time hidden behind the write)
bring the native path from ~50 MB/s to roughly 120-150 MB/s uint8 without sharding, with memory
limited by B2/A3 instead of slice size. These are estimates from the measurements above, not
measured end to end.
