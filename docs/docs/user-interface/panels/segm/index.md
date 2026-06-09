# Segmentation Panel

---

## Overview

The segmentation panel is the main panel used for segmentation. It allows creating models, modifying materials, and selecting different segmentation tools.

![Segmentation Panel](images/PanelsSegmentation.png)

<div class="clear-float"></div>

---

## What are the models

A model is a matrix with dimensions equal to those of the opened image dataset: <br> 
`[1:imageHeight, 1:imageWidth, 1:imageThickness]`.<br>
The model consists of materials, and each element of the model matrix (pixel) can belong only to a 
single material (having indices: `1, 2, 3, etc`) or to an exterior (with index `0`). 
Therefore, it is not possible to have 
several materials overlapping above the same pixel of the image. 
<br>Each material in the model matrix is encoded with its own index.

???+ example "Example of a model 4x4 pixels"

    ```
    Model = \[1 1 0 0; 1 1 0 0; 0 0 2 2; 0 0 2 2\]
       
    [   1 1 0 0
        1 1 0 0
        0 0 2 2
        0 0 2 2   ]
    ```
    In this example, the shown matrix represents a model with 2 materials encrypted with **1** 
    (the upper left corner) and **2** (the lower right corner) for the image of 4x4 pixels.
    Index *0* encodes background (Exterior).

---

## Create button

![Create Model Dialog](images/PanelsSegmentation_Create.png){.on-glb align=left width="250"}

The <span class="widget widget-button">Create</span> button is used to start a new model. W
hen clicked, the existing model layer will be removed.

Whenever possible, it is recommended to use models with **63** materials. 
If you need to work with materials exceeding 255, see this video:

- [:fontawesome-brands-youtube:{.red-color} MIB 2.1: Compatible with models with more than 255 materials](https://youtu.be/r3lpmWyvrJU)

For more information about different types of models, visit the [Ribbon → Model → Convert type](../../ribbon/model/index.md#convert-type).

<div class="clear-float"></div>

---

## Load button

The <span class="widget widget-button">Load</span> button is used to load a model from disk. The following formats are accepted:

- MATLAB (`*.MAT`): default and recommended format.
- Amira Mesh binary (`*.AM`): for models saved in [Amira](http://www.vsg3d.com/amira/overview) format.
- Hierarchical Data Format (`*.H5`): for data exchange with [Ilastik](http://ilastik.org/).
- Medical Research Council format (`*.MRC`): for data exchange with [IMOD](http://bio3d.colorado.edu/imod/).
- NRRD format (`*.NRRD`): for models saved in [3D Slicer](http://www.slicer.org/) format.
- TIF format (`*.TIF`).
- Hierarchical Data Format with XML header (`*.XML`).
- All standard file formats when selecting `All files(*.*)`.

Alternatively, use [Ribbon → Model → Load model](../../ribbon/model/index.md#load-model) or 
drag-and-drop a `*.model` file to the [Image View panel](../imview/index.md) or the [Segmentation table](#segmentation-table).

---

## \[+\], \[-\], \[>|\], \[Squeeze\], \[Recolor\] buttons

These buttons are located in the Segmentation panel above the segmentation table and depending on the model type
do different operations.

- <span class="widget widget-button">+</span> add a new material to the model (*only for models with 63 and 255 materials*).
- <span class="widget widget-button">-</span> delete the selected material(s) from the model (*only for models with 63 and 255 materials*).
- <img src="images/PanelsSegmentation_next_empty_button.png"> find and select the next empty index in the model (*only for models with more than 255 materials*).
- <img src="images/PanelsSegmentation_squeeze_button.png"> squeeze the model—remove all empty indices and select the next available empty index (*only for models with more than 255 materials*).
- <img src="images/PanelsSegmentation_recolor_button.png"> regenerate colors of materials (*only for models with more than 255 materials*).

---

## Filled/Contour dropdown

![Filled Mode](images/PanelsSegmentation_filled.png){align=left}
![Contour Mode](images/PanelsSegmentation_contour.png){align=left}

<div class="clear-float"></div>

The <span class="widget widget-dropdown">Filled/Contour ▼</span> dropdown modifies visualization of 
materials in the [Image View panel](../imview/index.md):

- **Filled**: draw materials as filled shapes (faster, left image).
- **Contour**: draw only the contours of materials (slower, right image).

??? info

    ![Filled vs Contour](images/PanelsSegmentation_filled_contours.png)    
    <div class="clear-float"></div>    
    Tweak contour thickness via<br>
    [Ribbon → Home → Preferences → Colors and styles → Contours](../../ribbon/home/home-preferences.md#colors-and-styles).
    

---

## Segmentation table

![Segmentation Table](images/PanelsSegmentation_table.png){align=left}

The Segmentation table displays the list of materials in the model.

- [:fontawesome-brands-youtube:{.red-color} MIB in brief: Segmentation Table](https://youtu.be/_iwQI2DIDjk)

<div class="clear-float"></div>

<div class="h4-like">The table has three columns:</div>

- **C**: shows colors for each material. <mouse class="left"></mouse> over the color box to open a color selection dialog.
- **Material**: lists all model materials. Right-click (<mouse class="right"></mouse>) to open a context menu with additional options (see below).
- **Add to**: defines the destination material for the Selection layer during **Add** (++a++) and **Replace** (++r++)
actions.
<br>Linked to the selected material by default, but can be unlinked with 
<span class="widget widget-checkbox">Fix selection to material</span> or the 
context menus **Unlink material from Add to**.

<div class="h4-like">Context menu options</div>

![Context Menu](images/PanelsSegmentation_table_cm.png){align=left}

- **Show selected material only** toggle to show only the selected material in 
the [Image View panel](../imview/index.md).
- **Rename (F2)** rename the selected material, use ++f2++ key shortcut.
- **Set color** change the color of the selected material.
- **Color scheme** update material colors using predefined palettes 
(more tools at [Ribbon → Home → Preferences → Colors](../../ribbon/home/home-preferences.md)). 
Random colors are generated if the model exceeds the palette. It is possible to swap colors or store/restore palettes.
 
<div class="clear-float"></div>

- **Get statistics** calculate properties for objects of the selected material. 
See [Ribbon → Model → Model/Mask statistics](../../ribbon/mask/mask-stats.md).
- **Materials**: direct operations available for materials of the model ([:fontawesome-brands-youtube:{.red-color} Materials menu demo](https://youtu.be/l1RkVkq59To))
 
??? abstract "List of available Material operations"
     - **Rename material** rename the selected material.
     - **Add material** add a new material to the bottom of the list.
     - **Insert material** insert a material at a specified position, shifting others.
     - **Swap materials** swap positions of two materials.
     - **Reorder materials** reorder materials with a new order.
     - **Export material** export to MATLAB workspace or Imaris.
     - **Save material to file** save the selected material to a file.
     - **Remove material** remove selected material(s).
  
- **Material to Selection**: copy the selected materials to the Selection layer.
??? abstract "List of available operations"
    - **NEW (2D, Slice)** generate a new Selection layer from the selected material for the current slice.
    - **ADD (2D, Slice)** add the selected material to the Selection layer for the current slice.
    - **REMOVE (2D, Slice)** remove the selected material from the Selection layer for the current slice.
    - **NEW (3D, Stack)** generate a new Selection layer for the current 3D stack.
    - **ADD (3D, Stack)** add to the Selection layer for the current 3D stack.
    - **REMOVE (3D, Stack)** remove from the Selection layer for the current 3D stack.
    - **NEW (4D, Dataset)** generate a new Selection layer for the whole dataset.
    - **ADD (4D, Dataset)** add to the Selection layer for the whole dataset.
    - **REMOVE (4D, Dataset)** remove from the Selection layer for the whole dataset.
- **Material to Mask** copy the selected material to the Mask layer.
??? abstract "List of available operations"
    - **NEW (2D, Slice)** generate a new Mask layer from the selected material for the current slice.
    - **ADD (2D, Slice)** add the selected material to the Mask layer for the current slice.
    - **REMOVE (2D, Slice)** remove the selected material from the Mask layer for the current slice.
    - **NEW (3D, Stack)** generate a new Mask layer from the selected material for the current 3D stack.
    - **ADD (3D, Stack)** add the selected material to the Mask layer for the current 3D stack.
    - **REMOVE (3D, Stack)** remove from the Mask layer the selected material for the current 3D stack.
    - **NEW (4D, Dataset)** generate a new Mask layer from the selected material for the whole dataset.
    - **ADD (4D, Dataset)** add the selected material to the Mask layer for the whole dataset.
    - **REMOVE (4D, Dataset)** remove the selected material from the Mask layer for the whole dataset.

- **Mask to Material** copy the Mask layer to the selected material.
??? abstract "List of available operations"
    - **NEW (2D, Slice)** generate a new Material layer from the Mask layer for the current slice.
    - **ADD (2D, Slice)** add the Mask layer to the Material layer for the current slice.
    - **REMOVE (2D, Slice)** remove the Mask layer from the Material layer for the current slice.
    - **NEW (3D, Stack)** generate a new Material layer from the Mask layer for the current 3D stack.
    - **ADD (3D, Stack)** add to the Mask layer the Material layer for the current 3D stack.
    - **REMOVE (3D, Stack)** remove the Mask layer from the Material layer for the current 3D stack.
    - **NEW (4D, Dataset)** generate a new Material layer from the Mask layer for the whole dataset.
    - **ADD (4D, Dataset)** add the Mask layer to the Material layer for the whole dataset.
    - **REMOVE (4D, Dataset)** remove the Mask layer from the Material layer for the whole dataset.
- **Show as volume (MIB)** visualize the selected material using [MIB 3D Viewer](../../ribbon/home/home-mib3Dviewer.md) (MATLAB R2018b+).
- **Show isosurface (MATLAB)** visualize the model or selected material 
(if **Show selected material only** is checked) as an [isosurface](../../ribbon/model/index.md#matlab-isosurface).
- **Show as volume (Fiji)** visualize using [Fiji 3D viewer](../../ribbon/model/index.md#fiji-volume).
- **Unlink material from Add to** prevent the **Add to** column from changing with material selection.

<div class="clear-float"></div>

<div class="h3-like">Keyboard shortcuts</div>

- <span class="widget widget-button">Ctrl</span> + <span class="widget widget-button">A</span>: highlight the selected material in the Selection layer for the current slice.
- <span class="widget widget-button">Alt</span> + <span class="widget widget-button">A</span>: highlight for the whole dataset.
!!! info 
    Sensitive to <span class="widget widget-checkbox">Fix selection to material</span> 
    and <span class="widget widget-checkbox">Masked area</span>.<br> 
    See [Shortcuts](../../key-and-mouse-shortcuts.md).

??? info "Select a combination of Mask and another layer"
    - Select the Mask entry in the table.
    - Check <span class="widget widget-checkbox">Fix selection to material</span>.
    - Select the second material in the **Add to** column.
    - Press ++ctrl+a++ or ++alt+a++.

<div class="h3-like">Drag and drop models</div>

- Drag-and-drop model files (e.g., `*.model`) from a file explorer to the Segmentation table to load as a new model.
- Drag-and-drop annotation files (`*.ann`) to open automatically.

---

## Fix selection to material checkbox

The <span class="widget widget-checkbox">Fix selection to material</span> checkbox ensures segmentation tools apply only to the material selected in the table. This is useful for focusing segmentation on a specific material.

---

## Masked area checkbox

The <span class="widget widget-checkbox">Masked area</span> checkbox limits segmentation tools 
to masked areas of the image. This isolates specific regions for segmentation.

---

## "D" checkbox (fast access tools)

The <span class="widget widget-checkbox">D</span> checkbox marks favorite selection tools 
for quick access with the <span class="widget widget-button">D</span> key. 
Selected tools are highlighted with an orange background in 
the <span class="widget widget-dropdown">Selection type</span> dropdown.

!!! info "Specify two additional tools"
    - ++shift+d++ - use this key shortcut to select the first predefined favorite tool
    - ++ctrl+d++ - use this key shortcut to select the second predefined favorite tool
    <br>These favorite tools can be specified from
    [Ribbon → Home → Preferences → Segmentation tools](../../ribbon/home/home-preferences.md#segmentation-tools)

---

## Segmentation tools dropdown

The <span class="widget widget-dropdown">Segmentation tools</span> dropdown provides tools to 
separate and identify regions or objects within an image. 

<div class="h4-like">List of the segmentation tools:</div>

- [3D ball](segm-3dball.md)
- [3D lines](segm-3dlines.md)
- [Annotations](segm-annotations.md)
- [Brush](segm-brush.md)
- [BW Thresholding](segm-bwthres.md)
- [Drag & Drop materials](segm-dragdrop.md)
- [Lasso](segm-lasso.md)
- [MagicWand-RegionGrowing](segm-magicwand.md)
- [Membrane ClickTracker](segm-membrtracker.md)
- [Object Picker](segm-objpick.md)
- [Segment-anything model](segm-sam.md)
- [Spot](segm-spot.md)

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md)*