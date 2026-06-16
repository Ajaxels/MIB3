# Model Ribbon Tab

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md)*

---

## Overview

Actions that can be applied to the *Labels* layer. The *Labels layer* is one of three main segmentation layers
(*Labels*, *Selection*, *Mask*) which can be used in combination with other layers.
See more about segmentation layers in the [Data layers section](../../image-layers.md).

![Model Ribbon Tab](images/menuModel.png){.on-glb align=left}

<div class="clear-float"></div>

---

## Convert Section

### Convert type

![Model Ribbon Tab](images/menuModel-convert.png){align=left}

Convert the model to a different type; the current type is indicated in the ribbon.

<div class="h4-like">Types of models in MIB</div>

- **63 materials** (*default*): Stores Labels, Selection, and Mask layers in a single memory container, 
reducing memory requirements with some performance costs and limiting materials to 63.
- **255 materials**: Allows up to 255 materials, requiring additional memory for Selection and Mask layers (doubles memory usage).
- **65535 materials**: Allows up to 65535 materials, requiring ~1.25× more memory than 255 materials. The [Segmentation panel](../../panels/segm/index.md) appearance changes in this mode.  
  [:fontawesome-brands-youtube:{.red-color} Short demonstration](https://youtu.be/r3lpmWyvrJU)
- **4294967295 materials**: Allows up to 4294967295 materials, requiring twice the memory of 65535 materials.

<div class="h4-like">Indexed objects</div>

Detects objects in all materials and generates a new model where each object has a unique index:

- **2D objects conn4**: 2D connected objects, 4-connectivity.
- **2D objects conn8**: 2D connected objects, 8-connectivity.
- **3D objects conn4**: 3D connected objects, 4-connectivity.
- **3D objects conn8**: 3D connected objects, 8-connectivity.

??? example "Example: standard model converted to indexed objects"

    ![Indexed Objects Example](images/menuModelsConvertIndexedObjects.png){.on-glb align=left}

??? info "How to work with models having more than 255 materials"

    ![Segmentation Panel 65535](images/panelsSegmentation_65535materials.png){.on-glb align=left width="300"}
    Materials should be named with numbers representing the current working material index
    (e.g., 11555 means that when selection is added to the model, it will be assigned to index 11555).

    Select materials by:

    - Right-clicking the segmentation table and choosing *Rename...* or by pressing ++f2++
    - Hovering over an object in the Image View panel and pressing ++ctrl+f++.

<div class="clear-float"></div>

---

## Import Section

### New model

![Create a new model and select the appropriate type](images/menuModelNewModel.png){align=left}

Allocates space for a new model. Use this to start a new model or delete the existing one.<br>
Alternatively, use the <span class="widget widget-button">Create</span> button in the [Segmentation Panel](../../panels/segm/index.md).<br>
<br>
For model types see [Convert type](#convert-type) above.

<div class="clear-float"></div>

---

### Load model

Loads a model from disk. By default, MIB reads models in MATLAB format (`.model`), but other formats are supported.

<div class="h4-like">Compatible model formats</div>

- [x] **AM, Amira Mesh**: Amira Mesh label field for models from [Amira](http://www.vsg3d.com/amira/overview).
- [x] **NRRD, Nearly Raw Raster Data**: Compatible with [3D Slicer](https://www.slicer.org).
- [x] **MRC, Medical Research Council format**: Compatible with [IMOD](http://bio3d.colorado.edu/imod). Can load multiple MRC files, each encoding an object, and merge them into a single model.
- [x] **PNG, PNG format**: Saves models as 2D slices in Portable Network Graphic format.
- [x] **TIF, TIF format**: Saves models as 2D slices or 3D volumes in Tag Image File format.

!!! tip
    Almost any standard image format can be loaded as a model using the *All files (*.*)* filter in the Open model dialog.

Alternatively, use the <span class="widget widget-button">Load</span> button in the [Segmentation Panel](../../panels/segm/index.md).

!!! note
    Models can also be opened by drag-and-dropping model files into the [Image view document](../../panels/imview/index.md).

---

### Import

![Import model from the main MATLAB workspace](images/menuModelImportModel2.png){align=left}

Imports a model from an external source. 

The **Import** dropdown contains:

<div class="clear-float"></div>

#### Import model from MATLAB

![Import model from the main MATLAB workspace](images/menuModelImportModel.png){.on-glb align=left width="300"}

Imports a model from the main MATLAB workspace.
Provide a variable name with a matrix matching the dataset dimensions `[height, width, depth]` of `uint8` class, or a structure with the fields below.

<div class="clear-float"></div>

<div class="h4-like">Fields of the MIB model structure</div>

- **.model**: Matrix `[height, width, depth, time]` of `uint8` class.
- **.modelMaterialNames** *(optional)*: Cell array with material names.
- **.modelMaterialColors** *(optional)*: Matrix with colors (0–1) `[materialIndex, R G B]`.
- **.labelText** *(optional)*: Cell array with annotation labels.
- **.labelPosition** *(optional)*: Matrix with annotation positions `[annotationIndex, x y z]`.

---

#### Import model from another MIB dataset

![Import model from the main MATLAB workspace](images/menuModelImportModel3.png){.on-glb align=left width="300"}

Copies the model from another currently open MIB dataset into the active dataset.

<div class="clear-float"></div>

---

## Export Section

Save or export the model to files and external programs.

### Export

![Export model from MIB](images/menuModelExportModel.png){align=left}

Exports the model to an external destination. The **Export** dropdown contains:

<div class="clear-float"></div>

- **Export model to MATLAB**: Exports to the main MATLAB workspace as a structure (see [Import model from MATLAB](#import-model-from-matlab) for structure fields). Can be re-imported using *Import model from MATLAB*.
- **Export model to another MIB dataset**: Copies the model into another currently open MIB dataset.
- **Export model to Imaris as volume**: Exports to Imaris if available. See [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#imaris) for details.

---

### Save model

Saves the model to a file in MATLAB format without prompting for a filename.

<div class="h4-like">Filename resolution</div>

- Default template: `Labels_NAME_OF_THE_DATASET.model`.
- Otherwise, the filename from the last *Save model as...* operation.
- Otherwise, the filename assigned when the model was loaded.


!!! info
    Can also be saved using the *Save model* button in the [Quick Access Bar](../../quick-access-bar/index.md).

---

### Save model as...

Prompts for a filename and format to save the model.

<div class="h4-like">Available formats</div>

- [x] **AM (Amira Mesh)**: RAW, RAW-ASCII, or RLE compressed formats (RLE is slow).
- [x] **MAT (MATLAB format)**: Native format for MIB version 1.
- [x] **MODEL (MATLAB format)** (*default*): Native format for MIB version 2.
- [x] **MOD (IMOD format)**: Contours for IMOD.
- [x] **MRC (IMOD format)**: Volume for IMOD.
- [x] **NRRD (Nearly Raw Raster Data)**: Compatible with [3D Slicer](https://www.slicer.org).
- [x] **OME-Zarr v3 (*.zarr3)**: Chunked, pyramidal OME-Zarr v3 store. Labels are downsampled with nearest-neighbour and material names/colours are preserved; reopenable as a [BigData](../../panels/datasets/index.md) model and by external OME-Zarr tools. Choosing this format opens an export-settings dialog (pyramid levels, chunk size, sharding, compression).
- [x] **PNG**: 2D slices in Portable Network Graphic format.
- [x] **STL (STL format)**: Triangulated mesh for visualization programs like Blender.
- [x] **TIF (TIF format)**: 2D slices or 3D volumes.

!!! tip "Exporting a pyramid level (BigData models)"

    For a disk-backed **BigData** model, the *Save model as...* dialog adds a <span class="widget widget-dropdown">Pyramid level</span> selector (`s0` = full resolution … `sN` = coarsest). The chosen level is **streamed to disk one slice at a time**, so the full model is never loaded into memory. Per-slice streaming is available for **TIFF**, the native **MODEL** (`*.model`), **HDF5** and **OME-Zarr v3**; other formats write the selected level as a whole.

??? info "BigData models — format compatibility & memory use"

    **All** formats above can save a **BigData** model at the chosen pyramid level. They differ only in how much memory the write needs:

    | Format | BigData | Memory-optimized (streamed slice-by-slice) |
    |--------|:-------:|:------------------------------------------:|
    | MODEL (`*.model`) — *native* | ✅ | ✅ disk-backed matfile |
    | TIF | ✅ | ✅ |
    | HDF5 (`*.h5`) | ✅ | ✅ |
    | OME-Zarr v3 (`*.zarr3`) | ✅ | ✅ |
    | AM, MAT, MOD, MRC, NRRD, PNG, STL, mibCat | ✅ | ❌ selected level is gathered whole before writing |

    Use the <span class="widget widget-dropdown">Pyramid level</span> dropdown to bound memory — a coarse level is small. The **memory-optimized** formats never hold even one full level in memory, so prefer them when exporting the full-resolution level (`s0`) of a large model.

---

## Model tools Section

### Materials

![Model materials operations](images/menuModelMaterials.png){.on-glb align=left width="190"}

Operations for model materials, also available by right-clicking the [Segmentation table](../../panels/segm/index.md#segmentation-table).

[:fontawesome-brands-youtube:{.red-color} Materials menu demo](https://youtu.be/l1RkVkq59To)

The **Materials** dropdown contains:

- **Rename material**: Rename the selected material.
- **Add material**: Add a new material to the bottom of the list.
- **Insert material**: Insert a material at a specified position, shifting others down.
- **Swap materials**: Swap positions of two materials.
- **Reorder materials**: Reorder materials with a new sequence.
- **Export material**: Export the selected material to MATLAB or Imaris.
- **Save material to file**: Save the selected material to a file.
- **Remove materials**: Remove selected material(s) from the model.

<div class="clear-float"></div>

---

### List of annotations

![Annotations operations](images/menuModelsAnnotationsMenu.png){.on-glb align=left width="190"}

Operations for the *Annotations* layer.

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/3lARjx9dPi0)

The **List of annotations** dropdown contains:

- **List of annotations**: opens the annotations window (see [Segmentation Tools](../../panels/segm/segm-annotations.md)).
- **Export to Imaris as Spots**: exports annotations as Spots in Imaris (export the dataset first).
- **Remove all annotations**: deletes all annotations in the model.

<div class="clear-float"></div>

---

### Render

![Render options](images/menuModelsRenderMenu.png){.on-glb align=left width="190"}

Renders segmented models using various methods. The **Render** dropdown contains:

<div class="clear-float"></div>

#### MIB rendering

![Rendering of mitochondria in Trypanosoma brucei](images/menuModelRendering-3d-viewer.png){.on-glb align=left width="300"}

Materials can be visualized in MIB with hardware-accelerated volume rendering (MIB 2.5+, MATLAB R2018b+). Datasets can be downsampled. Snapshots and animations are supported.<br>
See more: [MIB 3D Viewer](../home/home-mib3Dviewer.md)

[:fontawesome-brands-youtube:{.red-color} Introduction to updated 3D viewer](https://youtu.be/840o6zni3KE)<br>
[:fontawesome-brands-youtube:{.red-color} Original version of 3D viewer](https://youtu.be/4arfdOiZebk)

<div class="clear-float"></div>

---

#### MATLAB isosurface

![MATLAB Isosurface](images/menuModelRendering-isosurface.jpg){.on-glb align=left width="300"}

Uses MATLAB to generate and visualize isosurfaces with a modified [view3d](http://www.mathworks.com/matlabcentral/fileexchange/334-view3d-m) function by Torsten Vogel.

<div class="h4-like">Demonstrations</div>

- [:fontawesome-brands-youtube:{.red-color} Basic demo](https://youtu.be/svAFGBRfeoI)
- [:fontawesome-brands-youtube:{.red-color} Advanced demo](https://youtu.be/dMeoIZPaDS4?t=16m56s)

<div class="clear-float"></div>

<div class="h4-like">Controls</div>

- Double <mouse class="left"></mouse> to restore the original view.
- other controls available from a toolbar menu in the upper-right corner and via <mouse class="right"></mouse>

---

#### MATLAB volume viewer

![MATLAB Volume Viewer](images/menuModelsRendering-Matlabvolvewer.jpg){.on-glb align=left width="300"}

Renders the model using MATLAB's Volume Viewer (R2017b+). In R2019b+, materials can be displayed 
alongside the volume.

:warning: only for the MATLAB version of MIB

<div class="h4-like">Demonstrations</div>

- [:fontawesome-brands-youtube:{.red-color} Volume demo](https://www.youtube.com/watch?v=J70V33f7bas)
- [:fontawesome-brands-youtube:{.red-color} Materials with dataset](https://youtu.be/GM9V1IxNkTI)

<div class="clear-float"></div>

---

#### Fiji volume viewer

![Fiji Volume](images/menuModelsRendering-fiji.jpg){.on-glb align=left width="400"}

Uses [Fiji 3D Viewer](http://mib.helsinki.fi/tutorials/VisualizationOverview.html) for volume visualization.<br>
Requires Fiji installation (see [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#fiji)).

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/DZ1Tj3Fh2HM)

<div class="clear-float"></div>

---

#### Imaris surface

![Imaris Surface](images/menuModelsRendering-imaris.jpg){.on-glb align=left width="300"}

Renders the model in Imaris. Requires Imaris and ImarisXT (see [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#imaris)).

<div class="h4-like">Demonstrations</div>

- [:fontawesome-brands-youtube:{.red-color} Without ImarisXT](https://youtu.be/MbK2JcTrZFw)
- [:fontawesome-brands-youtube:{.red-color} With ImarisXT](https://youtu.be/yODGYJUzTr0)

The rendered material is specified in the Materials list of the [Segmentation Panel](../../panels/segm/index.md).

<div class="clear-float"></div>

---

## Quantification Section

### Quantify

Gets quantification statistics for the selected material, usable to filter the model by object properties.

![Start quantification directly from the Segmentation table](images/menuModelStats-frompanel.png){.on-glb align=left width="230"}

Accessible also via `Segmentation Panel → Materials List → Right-click → Quantify material...`

<div class="clear-float"></div>

See [Mask and Model Quantification](../mask/mask-stats.md) for details.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md)*
