# BigData / export — user test checklist

Live-GUI verification for the features added in the 2026-06/07 export + ImageConverter work.
Automated tests already cover the logic (see §0); this list is the sit-down, click-through pass.

**Test data used below**
- WSI BigData: `C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi` (open as BigData)
- Any `.zarr3` BigData folder
- A folder of ordinary image slices (for ImageConverter)

**Restart MIB before the GUI tests** — registry extensions, the reader dropdown keys, the 3-slot
file filter and the zarr/BioFormats library preferences all load at start-up.

---

## 0. Automated baseline (run first)

Run each as its own command (a `+` between `runtests(...)` calls is not valid MATLAB):

```matlab
runtests('tests/utils/PureUtilsTest.m')                 % units normalization           17/17
runtests('tests/io/ImageDatastoreSliceProviderTest.m')  % datastore provider             2/2
runtests('tests/core/BigDataMaskStreamTest.m')          % BigData mask stream            2/2
runtests('tests/io/OmeTiffStreamTest.m')                % OME-TIFF streaming (Integr.)   4/4
runtests('tests/io/ImageConverterNativeZarrTest.m')     % native zarr3 convert (Integr.) 1/1
runtests('tests/io/BigDataExportBoundingBoxTest.m')     % voxel round-trip (Integr.)     2/2
runtests('tests/io/SaveLoadMaskTest.m')                 % mask regression                2/2
runtests('tests/core/MibBigDataLevelMapTest.m')         % BigData labels regression      9/9
```

Or the whole suite: `buildtool test` (Unit) then `buildtool testAll` (adds the Integration ones).

- [x] All of the above pass.

---

## A. Units fix — the OME-TIFF unblocker

*Precondition: open a zarr/BigData dataset whose voxel units are `micrometers` (CMU-1.ndpi as BigData,
or any `.zarr3`).*

- [x] **A1** Save image → **OME-TIFF 5D** → writes **without error** (previously threw "Undefined
      variable scaleFactor").
- [x] **A2** Reopen that OME-TIFF → voxel size is correct (µm), not defaulted.
- [x] **A3** Save image → **TIFF** → reopen → voxel size is correct (see §F for the round-trip detail).

## B. OME-TIFF streaming

- [x] **B1** Standard, multi-Z grayscale → Save → OME-TIFF 5D → reopen → pixels + depth exact.
- [x] **B2** Standard, multichannel (a CZI) → OME-TIFF 5D → reopen → **channel count + LUT colours**
      preserved, pixels exact.
- [x] **B3** OME-TIFF **2D sequence** → one `.ome.tiff` per Z×T slice; reopen a few, pixels exact.
- [x] **B4** BigData → Save image at a **coarse pyramid level** → OME-TIFF → reopen → dims match the
      level, voxel scaled; large export stays responsive (Z-streamed, ~one plane in memory).
- [x] **B5** Cancel the OME-TIFF progress dialog mid-write → aborts cleanly, no half-file left.

## C. BigData mask export

*Precondition: BigData dataset with a model + a mask.*

- [x] **C1** Save **mask** → TIFF at full level → reopen → mask matches; memory stays bounded.
- [x] **C2** Save **mask** at a **coarse pyramid level** → reopen → downsampled mask, voxel scaled.
- [x] **C3 Regression:** Standard dataset → Save mask (`.mask` and `.tif`) works as before.

## D. ImageConverter ⇄ native zarr3

*Plugins → File Processing → **Convert image files**. Input = folder of slices; Output format = `zarr`.*

- [x] **D1 Native v3 (default):** Preferences → Zarr library = **native**; converter → **Zarr v3**, set
      voxel size, BB shifts, chunk sizes, compression → **Convert**. Verify: zarr3 written; **console
      shows no Python/pyenv startup**; "Native Zarr v3 written" message.
- [x] **D2** Reopen the result as **BigData** → dims, **voxel size**, and **bounding box / translation**
      are correct (BB shifts applied).
- [x] **D3 Sharding:** Zarr v3 + sharding on → shard files produced; reopens correctly.
- [x] **D4 Labels:** Image type = **labels** → converts with nearest-neighbour downsampling; reopens.
- [ ] **D5 Zarr v2 → legacy path:** select **Zarr v2** → still uses the **Python** pipeline (Python
      starts), writes v2, reopens. (Confirms native didn't break v2.)
- [ ] **D6 Python backend:** Preferences → Zarr library = **python**, output **Zarr v3** → uses the
      Python path, not native.
- [ ] **D7** Compression blosc / gzip / none each convert without error.

## E. BioFormats → MATLAB reader warning

- [ ] **E1 (package absent):** on a machine **without** the "Medical Imaging Toolbox Interface for Whole
      Slide Imaging File Reader" support package → Preferences → BioFormats library dropdown → pick
      **MATLAB** → a **MIB warning dialog** (`inputUniversalDlg`, puffin-warning icon) appears naming
      the package + the Add-Ons install path.
- [ ] **E2 (package present):** pick **MATLAB** → **no** warning.
- [ ] **E3** Pick **MIB** → never warns.

## F. Voxel round-trip: BigData → standard TIFF → reopen (the two fixes)

*This is the A3 detail. It exercises both the export (write BoundingBox) and import (parse a
separator-less BoundingBox) fixes.*

- [ ] **F1** Open **CMU-1.ndpi as BigData** (or any BioFormats-backed BigData with a real voxel size).
- [ ] **F2** Save image → **TIF** (3D stack) at full or a chosen level.
- [ ] **F3** Reopen the saved TIF as **Standard / Default** → **voxel X/Y/Z match the source** (µm),
      **not** `1 / 1 / 1`. Check the `Dataset info` / pixel size widget.
- [ ] **F4** Repeat via **HDF5** and **NRRD** (they also carry the bounding box) → voxel preserved.
- [ ] **F5 Regression:** a normal Standard dataset that has an action log still round-trips its voxel
      size through TIF (unchanged behaviour).

---

## Reporting a failure

Per failure note: file, dataset type, reader (Default/BioFormats/OpenSlide), zarr backend
(native/python), the exact steps, and the full console error/stack. For voxel issues (§A/§F) also
paste the reopened dataset's pixel-size values and, if handy, the TIF `ImageDescription`
(`imfinfo(file).ImageDescription`).
