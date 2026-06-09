# Model Ribbon Tab

---

## Overview

Actions that can be applied to the *Model* layers. The *Model layer* is one of three main segmentation layers 
(*Model*, *Selection*, *Mask*) which can be used in combination with other layers. 
See more about segmentation layers in the [Data layers section](../../image-layers.md).

![Model Ribbon Tab](images/menuModel.png){.on-glb align=left}

<div class="clear-float"></div>

---

## Convert type

Convert the model to a different type; the current type is indicated in the ribbon.

<div class="h3-like">Types of models in MIB</div>

- **63 materials** (*default*): Stores Models, Selection, and Mask layers in a single memory container, reducing memory requirements and improving performance, but limits materials to 63.
- **255 materials**: Allows up to 255 materials, requiring additional memory for Selection and Mask layers (doubles memory usage).
- **65535 materials**: Allows up to 65535 materials, requiring ~1.25x more memory than 255 materials. The [Segmentation panel](../../panels/segm/index.md) appearance changes in this mode.  
  [:fontawesome-brands-youtube:{.red-color} Short demonstration](https://youtu.be/r3lpmWyvrJU)
- **4294967295 materials**: Allows up to 4294967295 materials, requiring twice the memory of 65535 materials.
- **Indexed objects → 2D objects conn4**: Detects all 2D objects (connectivity 4) in all materials and generates a new model where each object has a unique index.
- **Indexed objects → 2D objects conn8**: Detects all 2D objects (connectivity 8) in all materials and generates a new model with unique indices.
- **Indexed objects → 3D objects conn6**: Detects all 3D objects (connectivity 6) in all materials and generates a new model with unique indices.
- **Indexed objects → 3D objects conn26**: Detects all 3D objects (connectivity 26) in all materials and generates a new model with unique indices.

??? example "Example of standard model conversion into indexed objects"

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

## New model

![Create a new model and select the appropriate type](images/menuModelNewModel.png){.on-glb align=left width="300"}

Allocates space for a new model. Use this to start a new model or delete the existing one.<br>
Alternatively, use the <span class="widget widget-button">Create</span> button in the [Segmentation Panel](../../panels/segm/index.md).<br>
<br>
For model types see [above](index.md#convert-type)

<div class="clear-float"></div>

---

## Load model

Loads a model from disk. By default, MIB reads models in MATLAB format (.model), but other formats are supported.

<div class="h3-like">List of compatible model types</div>

- **.AM, Amira Mesh**: Amira Mesh label field for models from [Amira](http://www.vsg3d.com/amira/overview).
- **.NRRD, Nearly Raw Raster Data**: Compatible with [3D Slicer](https://www.slicer.org).
- **.MRC, Medical Research Council format**: Compatible with [IMOD](http://bio3d.colorado.edu/imod). Can load multiple MRC files, each encoding an object, and merge them into a single model.
- **.PNG, PNG format**: Saves models as 2D slices in Portable Network Graphic format.
- **.TIF, TIF format**: Saves models as 2D slices or 3D volumes in Tag Image File format.

!!! note
    Almost any standard image format can be loaded as a model using the *All files (*.*)* filter in the Open model dialog.

Alternatively, use the <span class="widget widget-button">Load</span> button in the [Segmentation Panel](../../panels/segm/index.md).

!!! note
    Models can be opened by drag-and-droping of the selected model files into the [Segmentation panel](../../panels/segm/index.md)

---

## Import model from MATLAB

![Import model from the main MATLAB workspace](images/menuModelImportModel.png){.on-glb align=left width="300"}

Imports a model from the main MATLAB workspace.
<br>Provide a variable name with a matrix matching the dataset dimensions `[1:height, 1:width, 1:no-slices]` of `uint8` class, or a structure with the fields below.

<div class="clear-float"></div>

<div class="h3-like">Fields of MIB model structure</div>

- **.model**: Matrix matching dataset dimensions `[1:height, 1:width, 1:depth, 1:time]` of `uint8` class.
- **.modelMaterialNames** (*optional*): Cell array with material names.
- **.modelMaterialColors** (*optional*): Matrix with colors (0-1) `[1:materialIndex, Red Green Blue]`.
- **.labelText** (*optional*): Cell array with annotation labels.
- **.labelPosition** (*optional*): Matrix with annotation positions `[1:annotationIndex, x y z]`.

---

## Export model to...

![Export model from MIB](images/menuModelExportModel.png){.on-glb align=left width="300"}

Exports the model from MIB to other programs.

<div class="h3-like">List of options to export the models</div>

- **MATLAB**: Exports to the main MATLAB workspace as a structure (see above). Can be re-imported using *Import model from MATLAB*.
- **Imaris as volume**: Exports to Imaris if available. See [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#imaris) for details.

---

## Save model

Saves the model to a file in MATLAB format without prompting for a filename.

<div class="h3-like">Model filename considerations</div>

- Default template: `Labels_NAME_OF_THE_DATASET.model`.
- Otherwise, the filename is taken from the last *Save model as...* operation.
- Otherwise, the filename is assigned when a model is loaded.

!!! info 
    
    Can also be saved using the *Save model* button in the [Quick Access Bar](../../quick-access-bar/index.md).

---

## Save model as...

Prompts for a filename and format to save the model.

<div class="h3-like">List of model formats available for saving</div>

- **.AM, Amira Mesh**: RAW, RAW-ASCII, or RLE compressed formats (RLE is slow).
- **.MAT, MATLAB format**: Native format for MIB version 1.
- **.MODEL, MATLAB format** (*default*): Native format for MIB version 2.
- **.MOD, IMOD format**: Contours for IMOD.
- **.MRC, IMOD format**: Volume for IMOD.
- **.NRRD, Nearly Raw Raster Data**: Compatible with [3D Slicer](https://www.slicer.org).
- **.PNG**: 2D slices in Portable Network Graphic format.
- **.STL, STL format**: Triangulated mesh for visualization programs like Blender.
- **.TIF, TIF format**: 2D slices or 3D volumes.

---

## Material...

![Import model from the main MATLAB workspace](images/menuModelMaterials.png){align=left}

Operations for model materials, also available by right-clicking the [Segmentation table](../../panels/segm/index.md#segmentation-table).

[:fontawesome-brands-youtube:{.red-color} Materials menu demo](https://youtu.be/l1RkVkq59To)

<div class="clear-float"></div>

<div class="h3-like">Available operations</div>

- **Rename material**: Rename the selected material.
- **Add material**: Add a new material to the bottom of the list.
- **Insert material**: Insert a material at a specified position, shifting others.
- **Swap materials**: Swap positions of two materials.
- **Reorder materials**: Reorder materials with a new sequence.
- **Export material**: Export the selected material to MATLAB or Imaris.
- **Save material to file**: Save the selected material to a file.
- **Remove material**: Remove selected material(s) from the model.

---

## Render model...

Renders segmented models using various methods.

### MIB rendering

![Rendering of mitochondria in Trypanosoma bricei](images/menuModelRendering-3d-viewer.png){.on-glb align=left width="300"}

From MIB 2.5 and MATLAB R2018b, materials can be visualized in MIB with hardware-accelerated volume rendering. Datasets can be downsampled. Snapshots and animations are supported.
<br>See more: [MIB 3D Viewer](../home/home-mib3Dviewer.md)

[:fontawesome-brands-youtube:{.red-color} Introduction to an updated 3D viewer](https://youtu.be/840o6zni3KE)<br>
[:fontawesome-brands-youtube:{.red-color} Original version of 3D viewer](https://youtu.be/4arfdOiZebk)

### MATLAB isosurface

![MATLAB Isosurface](images/menuModelRendering-isosurface.jpg){.on-glb align=left width="300"}

Uses MATLAB to generate and visualize isosurfaces with a modified [view3d](http://www.mathworks.com/matlabcentral/fileexchange/334-view3d-m) function by Torsten Vogel.

<div class="h3-like">Demonstrations:</div>
- [:fontawesome-brands-youtube:{.red-color} Basic demo](https://youtu.be/svAFGBRfeoI)
- [:fontawesome-brands-youtube:{.red-color} Advanced demo](https://youtu.be/dMeoIZPaDS4?t=16m56s)

<div class="clear-float"></div>

<div class="h3-like">Controls:</div>

- Double <mouse class="left"></mouse> to restore the original view.
- ++z++: Switch from *ROTATION* to *ZOOM*.  
- <mouse class="left"></mouse> - to *ZOOM*.
- hold middle mouse to *PAN*.
- ++r++: Switch from *ZOOM* to *ROTATION*.  
  - *ROTATION*: <mouse class="left"></mouse> for xy-axis rotation, middle mouse for z-axis rotation.

<div class="clear-float"></div>

### MATLAB isosurface and export to Imaris

Generates isosurfaces in MATLAB and exports them to Imaris for visualization.

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/nDpa8b8lqo4)

### MATLAB volume viewer

![MATLAB Volume Viewer](images/menuModelsRendering-Matlabvolvewer.jpg){.on-glb align=left width="300"}

Renders the model using MATLAB’s Volume Viewer (R2017b–R2019b+). In R2019b, materials can display with the volume, but lighting controls are limited.

<div class="h3-like">Demonstrations:</div>
- [:fontawesome-brands-youtube:{.red-color} Volume demo](https://www.youtube.com/watch?v=J70V33f7bas)

- [:fontawesome-brands-youtube:{.red-color} Materials with dataset](https://youtu.be/GM9V1IxNkTI)

<div class="clear-float"></div>

### Fiji volume

![Fiji Volume](images/menuModelsRendering-fiji.jpg){.on-glb align=left width="400"}

Uses [Fiji 3D Viewer](http://mib.helsinki.fi/tutorials/VisualizationOverview.html) for volume visualization.<br>
Requires Fiji installation (see [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#fiji)).

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/DZ1Tj3Fh2HM)

<div class="clear-float"></div>

### Imaris surface

![Imaris Surface](images/menuModelsRendering-imaris.jpg){.on-glb align=left width="300"}

Renders the model in Imaris. Requires Imaris and ImarisXT (see [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#imaris)).

<div class="h3-like">Demonstrations:</div>

- [:fontawesome-brands-youtube:{.red-color} Without ImarisXT](https://youtu.be/MbK2JcTrZFw)

- [:fontawesome-brands-youtube:{.red-color} With ImarisXT](https://youtu.be/yODGYJUzTr0)


The rendered material is specified in the Material list of the [Segmentation Panel](../../panels/segm/index.md).

<div class="clear-float"></div>

---

## Annotations...

![Imaris Surface](images/menuModelsAnnotationsMenu.png){ align=left}

Modify the *Annotations* layer.

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/3lARjx9dPi0)

<div class="clear-float"></div>

<div class="h3-like">Available operations</div>

- **List of annotations...**: opens a window with existing annotations (see [Segmentation Tools](../../panels/segm/segm-annotations.md)).
- **Export to Imaris as Spots**: exports annotations as Spots in Imaris (export the dataset first).
- **Remove all annotations...**: deletes all annotations in the model.

---

## Model Statistics...

Gets statistics for the selected material, usable to filter the model by object properties. 

![Start quantification directly from the Segmentation table](images/menuModelStats-frompanel.png){ align=left}

Accessible also via<br>
`Segmentation Panel → Materials List → Right-click → Get statistics...`
<br>See [Mask and Model Statistics](../mask/mask-stats.md) for details.

<div class="clear-float"></div>

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md)*

