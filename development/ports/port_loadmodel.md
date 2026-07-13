# loadModel Port: MIB2 → MIB3

**Status: DONE** (2026-03-24)

Files created: `+models/@MibModel/loadModel.m`, `+core/@MibDataset/loadModel.m`, `+io/+loaders/MatModelLoader.m`

---

## Architecture

```
MibModel.loadModel          ← thin wrapper: BatchOpt, GUI, virtual guard, events
  └── MibDataset.loadModel  ← orchestrator: extension dispatch, dim check, property set
        └── io.LoaderFactory.create → loader.loadMetadata + loader.loadImages
```

---

## MibModel.loadModel — BatchOpt Fields

| Field | Type | Default |
|-------|------|---------|
| `DirectoryName` | `{char}` | `{'Inherit from dataset filename'}` |
| `FilenameFilter` | `char` | `'Labels_[F].model'` (`[F]` = base filename of open image) |
| `showWaitbar` | `logical` | `true` |
| `id` | `double` | `obj.getActiveId()` |
| `mibBatchSectionName` | `char` | `'Ribbon -> Models'` |
| `mibBatchActionName` | `char` | `'Load model'` |

## File Browser Filter List

```
*.model           MIB model file
*.mat             MATLAB data file
*.am              Amira mesh labels
*.h5;*.hdf5       HDF5 model
*.mibCat          MIB categorical model
*.mrc;*.rec;*.st  MRC/IMOD format
*.nrrd            NRRD format
*.tif;*.tiff      TIFF image
*.xml             HDF5 with XML header
*.*               All files
```

---

## MibDataset.loadModel — Key Logic

1. Import path (when `options.model` is set): skip file loading, go directly to type detection
2. Detect extension → resolve loader via `options.extensionRegistryLoad` (passed from MibModel)
3. Create loader → `loadMetadata` → `loadImages`
4. Determine modelType: `options.modelType` > `imginfo{"modelType"}` > auto-detect from class
5. Dimension validation: pad/crop H, W, Z, T to match image dims
6. Material metadata priority chain: `options.*` > `imginfo{*}` > file-specific > auto-generate
7. `obj.createModel(modelType)` → store data via `setData3D`/`setData4D`
8. Set `obj.labels.*` metadata fields; call `obj.labels.countMaterials()`
9. Handle annotations if present in file or options

**Important:** Pass `extensionRegistryLoad` via `options.extensionRegistryLoad` — keeps MibDataset decoupled from ExtensionRegistryLoad.

---

## MatModelLoader — Supported Formats

Handles `.model`, `.mat`, `.mibCat` (MATLAB-format files).

Key special cases:
- `.mibCat`: `iscategorical(rawArr)` → `grp2idx` to uint8; material order from `categories()`
- MIB v1 `model_var` field: fallback for old `.model` files
- Metadata fields auto-skipped: `modelMaterialNames`, `modelMaterialColors`, `modelType`, `modelVariable`, `model_var`, `BoundingBox`, `labelText`, `labelPosition`, `labelValue`, `material_list`, `color_list`, `options`, `imgVariable`

---

## ExtensionRegistryLoad Changes

Added `"Model.Default"` extension set and `mode == "Model"` routing in `defaultLoaderId`:

| Extension | Loader |
|-----------|--------|
| `model`, `mat`, `mibcat` | `MatModel` |
| `am` | `AmiraMesh` |
| `xml` | `hdf5-header` |
| `h5`, `hdf5` | `hdf5-no-header` |
| `mrc`, `rec`, `st` | `imod` |
| `nrrd` | `nrrd` |
| `tif`, `tiff`, etc. | `imread` |

---

## Edge Cases

| Case | Handling |
|------|----------|
| `.mibCat` categorical | `grp2idx(categorical_array)` → uint8 |
| `double` class input | GUI: `uiconfirm` before `uint32(model)`; batch: auto-convert |
| H×W mismatch | GUI: confirm; pad/crop; batch: pad/crop silently |
| Z mismatch | Pad with zeros or crop to `obj.image.depth` |
| 4D models | `size(rawModel,4)` == `obj.image.time`; use `setData4D` |
| Annotations in .model | `clearContents()` first; then `addLabels(text, pos, val)` |
| MIB2 `model_var` field | Fallback for v1 `.model` files |

---

## Amira .am Material Color Extraction

After `loader.loadImages` for `.am` files, call `io.AmiraMesh.getAmiraMeshHeader` and extract keys matching `'Materials_N_Name'` and `'Materials_N_Color'` (space-separated RGBA, values 0–1) until no more keys exist.
