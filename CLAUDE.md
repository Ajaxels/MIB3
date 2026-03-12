# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MIB3 (Microscopy Image Browser 3) is a MATLAB application for image processing, segmentation, and visualization of multidimensional (2D-4D) microscopy datasets. It runs either as a MATLAB script or as a compiled standalone Windows application.

- Entry point: `mib/mib3.m`
- Version string is defined in `mib/mib3.m` in the format: `'ver. 2025.12 / 05.12.2025'`
- Author: Ilya Belevich, University of Helsinki

### MIB2 → MIB3 Migration Context

This repository is an active port of MIB2 (`C:\Matlab\MIB2_RENAMED_FOR_MIB3`) to MIB3. MIB3 is a complete rewrite using MATLAB's **AppContainer framework** (ribbon UI, `.mlapp` panel components, docked documents). MIB2 uses the older GUIDE-based `.fig`/`.m` GUI approach with a flat class structure under `Classes/` and `GuiTools/`.

Key structural differences:
- MIB2 classes live directly in `Classes/@mibController`, `Classes/@mibModel`, etc. (no packages)
- MIB3 uses MATLAB packages: `+controllers/`, `+models/`, `+core/`, `+io/`, `+views/`, `+utils/`
- MIB2 naming: `mibController`, `mibModel`, `mibImage`, `mibView` (lowercase prefix)
- MIB3 naming: `MibController`, `MibModel`, `MibImage`, `MibView` (PascalCase)
- MIB2 GUI tools are in `GuiTools/` as `.fig`+`.m` pairs; MIB3 uses `.mlapp` files
- `MIB2_RENAMED_FOR_MIB3` has some methods/calls already renamed to match MIB3 namespace — use it as the primary reference when porting logic

When porting a feature from MIB2 to MIB3:
1. Find the MIB2 source in `C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\` or `GuiTools\`
2. Adapt the logic to the MIB3 package namespace and class hierarchy
3. Replace direct property access patterns with MIB3 equivalents (e.g. `obj.mibModel.I{obj.mibModel.Id}` → `obj.mibModel.I{obj.mibModel.id}`)

## Common Commands

**Run MIB from MATLAB:**
```matlab
cd C:\Matlab\MIB3\mib
mib3
```

**Run build checks and tests (MATLAB Build Tool):**
```matlab
cd C:\Matlab\MIB3
buildtool          % runs default tasks: check + test
buildtool check    % run code issues check only
buildtool test     % run tests only
buildtool clean    % clean build artifacts
```

**Compile standalone application:**
```matlab
% Edit deploymentScript.m to update projectRoot path, then run:
run('C:\Matlab\MIB3\deploymentScript.m')
```

## Architecture

MIB3 uses a strict **MVC pattern** implemented with MATLAB packages (`+pkg`) and classes (`@ClassName`). All source lives under `mib/`:

```
mib/
  mib3.m              % Entry point: creates MibModel, then MibController
  +controllers/       % UI controllers
  +models/            % Application model
  +views/             % UI views (.mlapp components + MibView class)
  +core/              % Core data classes
  +io/                % Image I/O with factory pattern
  +utils/             % Utilities, dialogs, defaults
  assets/             % Icons, images
  external/           % Third-party libraries
  jars/               % Java .jar files (BioFormats)
  plugins/            % User plugins
```

### MVC Layer Responsibilities

**Model** (`+models/@MibModel`): Central application state. Holds an array `I{}` of `MibDataset` instances (supporting multiple simultaneously open datasets). Fires MATLAB events (`NewDataset`, `ShowImage`, `SliceChanged`, etc.) that controllers listen to.

**Controller** (`+controllers/@MibController`): Main controller; owns sub-controllers for each UI panel:
- `cRibbon` — top ribbon with tabs (Home, Image, Mask, Model, Dataset, Tools)
- `cSegmentation` — segmentation panel with tools (brush, magic wand, lasso, SAM, etc.)
- `cDirContents` — directory contents / file browser
- `cActiveDataset` — dataset/set switcher
- `cImageDoc{}` — one `MibImageDocument` per open image document
- `cSelection`, `cRoi`, `cStatus`, `cQuickAccessBar`
- `childControllers{}` — dynamically spawned sub-controllers (dialogs, tools)

**View** (`+views/@MibView`): Builds the main MATLAB app window. Ribbon tabs are added by methods like `addRibbonHome.m`, `addRibbonImage.m`, etc. Panel components are `.mlapp` files in `+views/+components/`.

### Core Data Model (`+core/`)

- **`MibDataset`** — one open dataset; contains named layers:
  - `image` — `MibImage` instance (the pixel data)
  - `labels` — `MibLabels` or `MibLabels63` (segmentation model)
  - `mask` — binary mask layer
  - `selection` — active selection layer
  - `annotations` — `Annotations` instance
  - `lines3D` — `Lines3D` instance (skeletons)
- **`MibImage`** — stores image data as a cell array `data{1}` with dimensions `[height, width, depth, colors, time]`. Dataset types: `'Standard'` (in memory), `'Virtual'` (loaded on demand), `'BigData'`.
- **`MibVirtualImage`** — virtual/lazy loading variant of MibImage (supports Zarr via `getDataZarr.m`).
- **`MibUndo`** — undo history manager.
- **`ChildView`** — base class for child dialog views.

### I/O Layer (`+io/`)

Factory pattern for image loading:
1. `ExtensionRegistryLoad` — registry mapping file extensions to loader IDs, grouped by mode (`Standard`/`Virtual`/`BigData`) and reader (`Default`/`BioFormats`).
2. `LoaderFactory.create(loaderInfo, options)` — instantiates the appropriate loader.
3. Loaders (in `+loaders/`): `AmiraMeshLoader`, `BioFormatsStdLoader`, `HDF5HeaderLoader`, `HDF5NoHeaderLoader`, `ImodLoader`, `ImreadLoader`, `MibImgLoader`, `NrrdLoader`, `VideoReaderLoader`. All implement `loadMetadata` and `loadImages` methods.

### Utilities (`+utils/`)

- `+defaults/` — functions that generate default preferences, LUTs, key shortcuts, session settings
- `+dlgs/` — reusable dialog functions (`mibInputUniversalDlg`, `mibQuestDlg`, `showErrorDialog`, etc.)
- `+deepmib/` — deep learning augmentation helpers

## Key Conventions

- MATLAB package namespace: all classes are referenced as `controllers.MibController`, `models.MibModel`, `core.MibImage`, `io.LoaderFactory`, `utils.dlgs.showErrorDialog`, etc.
- Multi-method classes: methods are split into separate `.m` files in the `@ClassName/` folder; the constructor and method signatures are declared in the main class file.
- Event-driven communication between Model and Controller uses MATLAB `events`/`notify`/`addlistener`. Controller listener methods follow the naming pattern `listner1_Standard`, `listner2_ModelEvent`, `listenerNewDataset`, etc.
- `.asv` files are MATLAB autosave backups — ignore them.
- Pixel/voxel size is stored in `MibDataset.pixSize` struct with fields `.x .y .z .t .units .tunits`.
- Image orientation: `3` = XY plane (default), `1` = ZX plane, `2` = ZY plane.

## MATLAB Coding Rules
- Always use `dictionary` instead of `containers.Map` for key-value storage.
  - Use `dictionary(keys, values)` syntax for initialization.
  - Use `isKey(d, key)` and `d(key)` for lookups.
  - `dictionary` is the modern replacement (R2022b+) and supports type inference.
