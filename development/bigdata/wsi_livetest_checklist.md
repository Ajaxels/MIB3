# Live-test checklist — WSI / BigData via BioFormats & OpenSlide

> **Superseded 2026-06-25** — the live-validation checklist now lives in
> `bigdata_implementation_plan.md` §4. Kept as the dated detail log.

Interactive GUI validation for the WSI initiative (Phases A–D + fixes). Headless paths already pass
via MCP; this confirms the real File→Open / display / segmentation flow. See `plan_wsi_readers.md`.

## 0. Setup (do first)

- [ ] **Restart MIB** — the registry extension sets, reader-dropdown keys and the 3-slot file filter
      load at start-up; the running session predates these edits.
- [ ] Turn on **Developer Mode** (Preferences → System) so the console prints
      `models.MibModel.loadImages: [<type>/<reader>/<engine>] -> <file>` on every open.
- [ ] Confirm the **reader dropdown** exists in the Directory Contents panel with items
      `Default | BioFormats | OpenSlide` (replacing the old BioFormats checkbox).

Test files (all under `C:\Matlab2\Data\FileFormats\czi\`):
| File | What it is | Key trait |
|------|-----------|-----------|
| `CMU-1.ndpi` | Hamamatsu WSI | single pyramid scene, 4 levels (BF) / 9 (OpenSlide); + macro |
| `Zeiss-5-JXR.czi` | Zeiss WSI | **2 scenes** (ScanRegion0/1) + label + macro(uint16) |
| `DMSO_basal_Rep1.czi` | 50-series RGB | channel LUT colours (magenta/red/cyan) |
| `Clim_10BDE_5.czi` | confocal volume | **Z=111, C=4 uint16** (non-WSI volume) |

---

## 1. Reader dropdown + file-filter (fix: `.Items` crash, R7)

- [ ] Dataset type **Standard**, cycle reader **Default → BioFormats → OpenSlide**: no error; the
      file-filter dropdown repopulates each time (Default = native exts; BioFormats = long list;
      OpenSlide = `svs/ndpi/scn/mrxs/vms/vmu/tif/tiff/svslide/bif/czi/avs/dcm`).
- [ ] Switch dataset type to **Virtual**, then **BigData**: reader dropdown + filter update without
      error (previously BigData+BioFormats crashed on `.Items`).
- [ ] Each reader remembers its own last-used file filter when you switch back.

## 2. Standard mode (baseline — should be unchanged)

- [ ] `DMSO_basal_Rep1.czi`, **Standard / BioFormats** → series dialog appears; open one → displays;
      **channel colours correct** (magenta/red/cyan). Console: `[Standard/BioFormats/mib]`.
- [ ] A plain TIFF, **Standard / Default** → opens as before. Console: `[Standard/Default]`.

## 3. BigData — BioFormats engine = MIB (Java)

Set Preferences → Input/Output → **BioFormats library = MIB**. Dataset type **BigData**, reader
**BioFormats**.

- [ ] `CMU-1.ndpi` → **auto-loads** (single scene), no scene dialog. Console: `[BigData/BioFormats/mib]`.
- [ ] Pan / zoom: image stays sharp; zooming out switches pyramid levels (fast-pan auto-enabled).
- [ ] Orientation switch (XY/ZX/ZY) renders without error.
- [ ] `Zeiss-5-JXR.czi` → **scene dialog** appears listing `ScanRegion0` / `ScanRegion1` (+ sizes),
      default = largest; pick one → opens; macro/label are **not** offered.
- [ ] `Clim_10BDE_5.czi` (Z=111, C=4) → opens; **scroll Z** through the stack; all 4 channels show
      with correct colours; no `viewPort`/`reshape` errors (fixes: multichannel viewPort + dim-aware backend).
- [ ] `DMSO_basal_Rep1.czi` → scene/series handling OK; **LUT colours correct** (fix: BigData LUT).

## 4. BigData — BioFormats engine = MATLAB (bioformatsread)

Preferences → **BioFormats library = MATLAB**. Reader **BioFormats**.

- [ ] `CMU-1.ndpi` → opens, displays identically to MIB engine. Console: `[BigData/BioFormats/matlab]`.
- [ ] `Clim_10BDE_5.czi` → Z-scroll + 4 channels OK (dim-aware blockedImage backend).
- [ ] Switch the preference back to **MIB** afterwards (default).

## 5. BigData — OpenSlide reader

Reader **OpenSlide**.

- [ ] `CMU-1.ndpi` → opens via OpenSlide. Console: `[BigData/OpenSlide/openslide]`; pyramid has
      **9 levels** (denser than BF's 4) — zoom is smooth.
- [ ] `DMSO_basal_Rep1.czi` → OpenSlide can't read CZI in this build → console shows
      *"OpenSlide could not open … Falling back to the BioFormats engine"* → image still opens. ✔ fallback.
- [ ] (If available) a real `.svs` → opens via OpenSlide.

## 6. Model create + segmentation on a WSI BigData set  (key unproven area)

With `CMU-1.ndpi` open as BigData:

- [ ] **Create Model** → a disk-backed model store (`…zarr3`) is created beside the slide; no full-volume
      allocation; segmentation controls enable.
- [ ] **Brush** a few strokes at high zoom (full res) → undo (Ctrl+Z) restores exactly (footprint-bounded).
- [ ] Zoom out to a coarse level, brush, zoom back — edit lands in the right place (no shift).
- [ ] **Magic Wand / Region Growing** with a radius → stays radius-limited; no whole-slide read warning
      unless radius = 0.
- [ ] Scroll to another region, paint, scroll back → persistence correct.
- [ ] Save model, reopen the dataset + model → labels intact.

## 7. Export (optional, ties to the streaming-export plan)

- [ ] With a BigData WSI open, **Save image as…** → pick a pyramid **level** → export TIFF/HDF5 →
      reopen the file → dimensions match the chosen level; voxel size scaled.

---

## Known fixes / perf notes

- **OOM on brush at very low magnification (fixed 2026-06-17).** Painting zoomed-out made the brushed
  block span (nearly) the whole slide; `MibBigDataLabels.propagateRegion` then upsampled the coarse edit
  to the **full-res model level (38144×51200 ≈ 2 GB)** with `resizeBlockSmooth` (unpacks 3 layers +
  signed-distance temporaries → ~13.8 GB) → swap/hang. Fix: `propagateRegion` now gates smoothing to
  small targets (≤4 MP) and tiles large nearest upsamples in Y-strips (~8 MP/strip), **inlined** into
  `propagateRegion` (body-only change → hot-reloads onto a live model object; no new method).
  Verified: 12000×12000 coarse edit propagating to all levels incl. full-res → 1.2 s, +1 MB (was multi-GB).
- **`MATLAB:Java:DuplicateClass` warning (fixed).** `bioformatsread`/`openslideread` `javaaddpath` warned
  *"Objects of loci/formats/Memoizer class exist"* when MIB's Java Bio-Formats had live objects; benign
  (both stacks coexist), now silenced in `io.BioFormats.Reader.openBlocked`.
- **Remaining follow-up (disk I/O, not memory):** a *whole-slide* low-mag stroke still writes ~2 GB to
  the full-res level (bounded memory, but slow disk). Proper fix = lazy/bounded finer-level reconstruction
  on zoom-in instead of eager full-res propagation; and per-stroke region (not whole visible block)
  propagation. Tracked for a later pass.

## Reporting

For each failure, note: file, dataset type, reader, BioFormats library, the console
`[type/reader/engine]` line, and the full error stack. Add findings under "Open path — remaining" in
`plan_wsi_readers.md`. Green across sections 1–6 ⇒ the feature is production-ready (export = section 7).
