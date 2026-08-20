# VolRenApp: visualize models with 65535 / 4294967295 materials

## Context

`controllers.VolRenApp` renders the image volume plus a model overlay through MATLAB's
`volshow`. It works for the small model types (63 / 255) but produces a useless picture for the
large types (65535, 4294967295) that instance segmentation produces. The goal is to make the 3D
viewer usable for instance models: an at-a-glance view of the whole segmentation, plus exact
inspection of individual instances.

### Why it fails today

1. **volshow caps the overlay LUT at 256 entries.** Verified against R2026a class metadata
   (`meta.class.fromName('images.ui.graphics.Volume')`):

   | internal property | declared size |
   |---|---|
   | `OverlayColormap_I` | `uint8 [3 256]` |
   | `OverlayAlphamap_I` | `uint8 [256 1]` |
   | `Colormap_I` / `Alphamap_I` | `[3 256]` / `[256 1]` |

   So at most **255 distinct instance colours + background** can ever be displayed in one overlay,
   whatever we pass in. Any colormap with a different row count is resampled into those 256 slots,
   which destroys exact label-to-colour indexing.

2. **`noOverlayMaterials` is wrong for large models.** `VolRenApp.m:2134` uses
   `numel(dataset.labels.materialNames)`, but `core.MibDataset.createModel` (`createModel.m:204`)
   sets `materialNames = {'1'; '2'}` for large models - the names are two renameable *slots*
   holding a material index as text, not a list of materials. Result: a 3-row colormap
   (`VolRenApp.m:2136`) and a 3-entry alphamap (`:2190`) for a model with tens of thousands of
   instances.

3. **`OverlayDisplayRangeMode = 'data-range'`** (`VolRenApp.m:2186`) then linearly squeezes the
   label range (e.g. 0..40000) onto those 3 rows, so every instance renders in the same colour.

4. **The material dropdown in `grabVolume`** (`VolRenApp.m:1618`) is built from `materialNames`, so
   for a large model it offers exactly two entries and cannot address material 5000.

5. **Pre-existing bug found on the way:** in `grabVolume` the labels branch maps "All materials" to
   `colorChannel = 0` (`VolRenApp.m:1681`, `:1699`), and `core.MibImage.getData` treats a non-empty
   non-NaN `colChannel` on a `labels` layer as a material index (`getData.m:77-99`), returning
   `data == 0`, i.e. the **background** mask. The image branch already converts its "All" entry to
   `NaN`; the labels branch must do the same.

### Existing patterns to reuse (do not reinvent)

- Colour of an arbitrary material index for a large model:
  `materialColors(mod(idx-1, 65535) + 1, :)` - see `models/@MibModel/getRGBimage.m:460-475` and
  `controllers/@MibSegmentation/updateMaterialsTable.m:155-165`.
- The 2-slot UI convention for large models: `updateMaterialsTable.m:79-83, 114-135`.
- Resolving a slot to a real material index: `core/@MibDataset/getSelectedMaterialIndex.m:48-57`.
- Fetching a single material as a binary mask: `getData3D('labels', t, 3, materialIndex, options)`
  (documented in `core/@MibDataset/getData3D.m:38-42`).
- Resizing an overlay: `utils.resizeImage3d(vol, factor, struct('imgType','3D','method','nearest'))`.

## Design

Two overlay modes, selected by a new dropdown that is only enabled when
`labels.maxMaterials >= 256`.

### Mode A - "All instances (cycled colours)" (default for large models)

Remap every label into one of 255 colour bins: `bin = mod(idx - 1, 255) + 1`, background stays 0.
Palette rows 1..255 come from `labels.materialColors(1:255, :)`. Neighbouring instance indices get
different colours, so an instance segmentation reads correctly; indices 255 apart share a colour,
which is the same trade-off `getRGBimage` already makes in 2D. One global alpha and one show/hide
for the whole overlay.

### Mode B - "Selected instances"

The user names up to 255 material indices; each gets its **exact** colour
`materialColors(idx, :)` (identical to the 2D view), its own alpha and its own show/hide row in the
existing `modelTable`. Everything not listed maps to 0 and is invisible. Selection UI:

- an edit field parsed with `str2num(['[' text ']'])`, so `1-20` style input is written
  `1:20, 45, 900:5:1000`;
- an **Add current** button that appends
  `obj.mibModel.I{id}.getSelectedMaterialIndex()` (the material selected in the main MIB
  materials table);
- a `modelTable` context-menu item to remove the selected rows.

Indices are clamped to `[1, maxMaterials]`, de-duplicated, sorted, and truncated at 255 with a
warning dialog if the user asks for more.

### Shared mapping layer

New method file `mib/+controllers/@VolRenApp/buildOverlayIndexVolume.m` (two call sites -
`modelUpdateOverlay` and `refreshOverlayData` - so it earns its own file per the repo rule):

```matlab
[overlayIdx, overlayColormap, rowMaterials] = obj.buildOverlayIndexVolume(labelVolume)
```

- `overlayIdx` - `uint8`, 0 = background, 1..N = palette row.
- `overlayColormap` - **exactly 256x3** (row 1 = background black, unused tail rows zero-filled).
  Passing fewer rows lets volshow resample and breaks 1:1 indexing.
- `rowMaterials` - real material index behind each row (`[]` in Mode A).

Mapping is done with a lookup table, applied slice by slice to bound the temporary allocation
(`development/guides/performance_for_loop_tweak.md`):

```matlab
lut = zeros(65536, 1, 'uint8');            % index = labelValue + 1
lut(2:end) = uint8(mod((1:65535) - 1, 255) + 1);        % Mode A
% Mode B: lut(:) = 0; lut(rowMaterials + 1) = uint8(1:numel(rowMaterials));
for z = 1:size(labelVolume, 3)
    overlayIdx(:,:,z) = lut(uint32(labelVolume(:,:,z)) + 1);
end
```

For `maxMaterials == 4294967295` a 2^32 LUT is impossible: Mode B loops over the selected indices
(`overlayIdx(labelVolume == idx) = k`), Mode A computes the modulo per slice and restores zeros.

Then, **for every model type** (this also fixes the latent `data-range` fragility on 63/255 models,
where a volume containing only a subset of the materials currently shifts all colours):

```matlab
obj.volume.OverlayColormap          = overlayColormap;   % 256 x 3
obj.volume.OverlayAlphamap          = alphamap;          % 256 x 1, alphamap(1) = 0
obj.volume.OverlayDisplayRangeMode  = 'manual';
obj.volume.OverlayDisplayRange      = [0 255];
obj.volume.OverlayThreshold         = 0.0001;
```

With data in 0..255 and a manual range of `[0 255]` the mapping is 1:1 under either possible
volshow semantics (index-direct for `LabelOverlay`, or rescaled for the other styles), so this is
safe without knowing the internals of the `.p` file.

### Table row to alphamap row indirection

New property `overlayRowMap` (cell array, one entry per `modelTable` row, holding the alphamap rows
that row controls):

- small models and Mode B: `num2cell((1:N) + 1)`
- Mode A: `{2:256}` - the single row drives all 255 bins

`modelTableCellEdit` (`VolRenApp.m:2586-2599`) and `modelHideAllMaterials` (`:2476-2482`) then write
`obj.volume.OverlayAlphamap(obj.overlayRowMap{r}) = value` and build a full 256-entry vector instead
of `noOverlayMaterials+1` entries. Everything else in those methods is unchanged.

### Surfaces

`modelTable_cm_generateSurface` (`VolRenApp.m:1135-1152`) currently uses the table row directly as
both the overlay value and the colour index. Change to: mask `obj.volume.OverlayData == r`, colour
`materialColors(rowMaterials(r), :)`, name `num2str(rowMaterials(r))`. Add a second context-menu
item **"Generate surface for material index..."** that prompts with
`utils.dlgs.inputSingleDlg` (spinner, limits `[1 maxMaterials]`), refetches the binary mask via
`getData3D('labels', [], 3, idx, getOptions)` through the same resize path, and builds the surface.
This is the only sensible per-instance action in Mode A and works in every mode.

### `grabVolume` dialog

For `maxMaterials >= 256`, replace the material dropdown with a spinner prompt
`'Material index (0 = all materials)'`, limits `[0 maxMaterials]`, default
`max(0, getSelectedMaterialIndex())` - `inputUniversalDlg` returns the number directly for spinner
entries. Map `0` to `NaN` before calling `getData3D` (this is the fix for the background-mask bug),
in both the BigData and Standard branches. Also note in the code comment that rendering a large
label volume *as the volume* still goes through the 256-entry `Colormap`, so it can only ever be a
gradient - the overlay path is the right tool, and `Isosurface` is already forced for non-image
volume types (`VolRenApp.m:1783`).

### Guards

- Top up `labels.materialColors` when a loaded model carries fewer rows than needed
  (`loadModel.m:356-360` only fills a full palette when the file has none) - generate the missing
  rows with `rand`, matching `updateMaterialsTable.m:86-92`.
- `updateModelTable` (`:2489`) must not be handed 65535 rows: Mode A produces one row (white
  background, since 255 colours cannot be shown in one cell), Mode B produces `numel(rowMaterials)`
  rows coloured from the real palette.
- Mode A alpha writes to 255 rows at once - do it as one vectorised assignment, not a loop.
- No progress dialog is needed for the remap (single pass over an already in-memory volume); if
  profiling on a large volume says otherwise, use `uiprogressdlg` with `'Cancelable','on'` per
  CLAUDE.md.

## Files to change

| File | Change |
|---|---|
| `mib/+views/VolRenAppGUI.mlapp` | Model tab: add `overlayMaterialsMode` dropdown, `overlayMaterialsList` edit field, `addCurrentMaterialButton`, and a `modelTable_cm_generateSurfaceByIndex` / `modelTable_cm_removeRows` context-menu item. `modelTopPanel` is absolute-positioned (widgets occupy y = 104..295); the free band is y ~ 6..100, so the three new widgets need compact spacing. New callbacks forward to controller methods, as the existing ones do. |
| `mib/+controllers/@VolRenApp/buildOverlayIndexVolume.m` | **new** - the LUT remap described above |
| `mib/+controllers/@VolRenApp/VolRenApp.m` | `modelUpdateOverlay`, `refreshOverlayData`, `updateModelTable`, `modelTableCellEdit`, `modelHideAllMaterials`, `modelTable_cm_Callback`, `grabVolume`; new properties `overlayRowMap`, `overlayRowMaterials`, `overlayMaterialsMode`; declare the new method in the class file |
| `docs/docs/user-interface/ribbon/home/home-mib3Dviewer.md` | document the two modes, the 255-colour cap and the index-list syntax |
| `docs_api/source/api/controllers/VolRenApp.rst` | pick up the new method (autodoc) |

Widget handles that map to no BatchOpt field stay lowerCamel; this controller does not use BatchOpt
for the overlay, so the existing descriptive-handle convention applies.

## Verification

1. `buildtool check` and `buildtool test` (`C:\MATLAB\MIB3`).
2. Dash sweep required by CLAUDE.md - must print nothing:
   `grep -rn --include=*.m "—\|–" . | grep -v "^./deployed/"`
3. In MATLAB (`cd C:\Matlab\MIB3\mib; mib3`):
   - open a stack, `Model -> New model -> 65535`, or load an instance-segmentation result;
   - launch the 3D viewer, Model tab, **Update overlay**;
   - Mode A: every instance should be individually coloured, alpha and Hide all should act on the
     whole overlay;
   - Mode B: type `1:10, 500`, confirm 11 rows appear with the same colours the 2D view shows for
     those indices, that per-row alpha and show/hide work, and that unlisted instances vanish;
   - **Add current**: select a material slot in the main window, press the button, confirm the real
     index (not the slot number) is appended;
   - context menu: generate a surface from a Mode B row and from an arbitrary index in Mode A;
   - **live update**: tick it, paint in the main window, confirm the overlay refreshes without
     losing colours or per-row visibility.
4. Regression on a 255-material model: colours, alpha, Hide all and surface generation must be
   unchanged after the switch to the 256-row / manual-range formulation.
5. Regression on the volume path: `grabVolume` with volume type `labels` and "all materials" must
   render the model, not the background (item 5 of the diagnosis).
