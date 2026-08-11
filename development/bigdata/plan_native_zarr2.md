# Native Zarr v2 support

**Status:** implemented 2026-08-11.
**Trigger:** the bundled `zarrMex` gained Zarr v2 read/write, so the assumption every one of these
code paths was built on - *"zarr v2 has no native engine"* - stopped being true.

## What changed, in one line

Zarr v2 stopped being a python-only, read-only special case and became a peer of v3: same engine,
same facade, same editable model store, same exporter.

## The two facts that made this cheap

1. **The layout convention was already identical.** `zarrMex` returns an array whose layout is the
   reverse of the zarr `shape` declaration, and `io.zarr.PyBackend` was deliberately written to
   reproduce that byte for byte. Verified against the live Janelia store before touching anything:

   ```
   ZarrArray(.../fibsem-uint8/s5)      -> format=2, [1551 670 737] uint8, chunks [64 128 128]
   native vs PyBackend, same bbox      -> isequal = 1
   ```

   So every backend swap on the read path is a pure substitution - no permutation, no
   `computePermutation` change, no axis-order rework anywhere.

2. **v2 `order: 'F'` is the exact analogue of v3's transpose codec.** MIB's packed label bytes
   round-trip in `[y, x, z]` in both formats, which is what makes an editable v2 model store
   possible without touching `MibBigDataLabels`' read/write logic at all.

## Read path

`io.loaders.Zarr2VirtualLoader` now goes through `io.zarr.Array` + `io.zarr.ChunkCache`, making it
mechanically identical to `Zarr3VirtualLoader`. The classes stay separate only because
`MibVirtualImage` dispatches on the stored `objectType`/`sourceType`, which records the store's
format, not the library that can open it.

`Zarr2VirtualSetupLoader` and `MibBigDataLabelsZarr2` had an **unconditional**
`PyBackend.ensureLoaded()` / `ensureRemoteSupport()` at open time. Both are now gated on
`io.zarr.Config.isPython()`, as is the equivalent check in `SelectFromUrl`. The measured result,
against the public OpenOrganelle store with no python configured:

| | |
|---|---|
| `loadMetadata` from the container root | resolves `recon-1/em/fibsem-uint8`, 15 levels, 8 nm |
| `readRegion` 128 x 128 at `s5` | 1.58 s first, **0.010 s** next slice (chunk cache) |
| `pyenv().Status` afterwards | **`NotLoaded`** |

That last row is the point: python is never started.

## Write path

- `io.zarr.Group.create` forwards its arguments (it previously swallowed them), so
  `'zarrFormat', 2` reaches `ZarrGroup.create`; arrays added to a v2 group inherit v2.
- `io.zarr.Array`/`Group` gained `zarrFormat()`, and `PyBackend.arrayMeta`/`infoArray` report
  `zarrFormat` so the accessor answers identically on either backend.
- `MibBigDataLabels.createStore` takes an optional format, defaulting to
  `zarrFormatFromPath(storePath)` - **`.zarr2` means v2, everything else v3**, which is the same
  extension convention `ExtensionRegistryLoad` already uses and leaves every existing caller
  unchanged.
- `Zarr3Saver` resolves the format the same way (`resolveZarrFormat`), with an explicit
  `options.ZarrFormat` override for callers whose output path has no extension - which is exactly
  the ImageConverter's case.

## The dispatch decision, and why it needed a marker

With v2 writable, `loadModel` could no longer use "is it v2?" to decide whether a model store is
editable. **Format is not the question; authorship is.**

- A store **MIB wrote** holds packed bytes (bits 1-6 material, 7 mask, 8 selection) in `[y, x, z]`.
- A **foreign** store holds another tool's plain label indices in its own declared axis order.

The two are indistinguishable from their pixels alone, and writing MIB's packed bytes into a foreign
store would corrupt it. So `writeMultiscales` now stamps a `mibModelStore` attribute
(`version`, `layout: 'packed-uint8-yxz'`), and `loadModel` routes on
`core.MibBigDataLabels.isMibModelStore` rather than on the format:

```matlab
if isZarrV2Store && ~core.MibBigDataLabels.isMibModelStore(storePath)
    newLabels = core.MibBigDataLabelsZarr2([], bigMeta);   % read-only
else
    newLabels = core.MibBigDataLabels([], bigMeta);        % editable
end
```

`MibBigDataLabelsZarr2` therefore **stays read-only by decision, with a corrected rationale**. The
old reason ("no python-backed write path exists") is obsolete; the real reason - it is someone
else's data in someone else's layout - always was the stronger one and is now the stated one.

Missing markers cost nothing in practice: v3 stores go to the editable class regardless, and no v2
model store could be created before the marker existed, so there are none in the wild to
misclassify.

## Files touched

| Area | Files |
|------|-------|
| Facade | `+io/+zarr/Array.m`, `Group.m`, `Config.m`, `PyBackend.m` |
| Read path | `+io/+loaders/Zarr2VirtualLoader.m`, `Zarr2VirtualSetupLoader.m`, `+core/@MibBigDataLabelsZarr2/`, `+controllers/@SelectFromUrl/` (2), `+io/ExtensionRegistryLoad.m` |
| Write path | `+core/@MibBigDataLabels/MibBigDataLabels.m`, `+models/@MibModel/createModel.m`, `loadModel.m`, `+io/+savers/Zarr3Saver.m`, `+controllers/@MibRibbon/home_Callbacks.m`, `model_Callbacks.m`, `plugins/.../ImageConverter.m` |
| Tests | `tests/io/NativeZarrV2Test.m` (new, 12), `tests/io/ImageConverterNativeZarrTest.m` (+2) |

## Verification

- `buildtool test`: **0 failed** (only the 5 pre-existing assumption-filtered skips).
- `buildtool check`: 4 errors, **all pre-existing and unrelated** - `@IceImarisConnector`,
  `export_fig`, and two plugin files, none of them touched here.
- Dash grep over `.m` files: clean.
- Live remote read from `janelia-cosem-datasets` with `pyenv` untouched, as above.

New tests assert **values**, not just shapes and formats. An axis- or chunk-order mistake between
the two formats preserves every dimension while transposing the data, so a shape-only check would
pass on exactly the bug worth catching.

## Deliberately not done

- **`Zarr3Saver` was not renamed** despite now writing both formats. The rename would churn the
  saver factory, three ribbon callbacks, the ImageConverter, tests and docs for no behaviour change;
  it belongs in its own commit if it is wanted at all. Same reasoning for
  `ImageConverter.convertToZarr3Native`.
- **Sharding for v2** - the format has no sharding codec. Requests are refused with a message naming
  the conflict rather than silently dropped, since dropping it writes a store with a different chunk
  layout than was asked for. The ImageConverter dialog already clears the checkbox when v2 is
  picked, so this only fires in batch mode.
- **Write support for foreign v2 label stores** - see the dispatch section above.
