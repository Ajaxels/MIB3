# Image Layers

Microscopy Image Browser (MIB) organizes datasets in a layered structure, storing each opened image in the **Image** layer. This is supplemented by **Model**, **Mask**, and **Selection** layers, all matching the Image layer’s X, Y, Z dimensions. These additional layers support the image segmentation process.

## General Organization

For visualization, MIB combines all layers to produce the image shown in the [Image View Panel](panels/selection_imview/imview.md). 
You can toggle each layer on or off, adjust transparency, and change colors (see the [View Settings Panel](panels/selection_imview/viewsettings.md) docs).

![Schematic of data layers combined into the final image](images/dataLayersToFinalImage.jpg)

To save memory, the **Model**, **Mask**, and **Selection** layers are stored in a single 8-bit unsigned integer block by default. 
This limits the number of materials to 63 but reduces memory usage. Alternatively, you can increase the material 
limit to 255 by storing each layer in separate blocks, doubling memory requirements. 
<br>
Choose the organization type in the [Ribbon -> Model -> Convert type](ribbon/model/index.md#convert-type).

??? example "Image Example"
    ![Example of data layers](images/dataLayers.jpg)

## Image Layer

The **Image** layer holds the core 2D-4D microscopy dataset. It’s always present and forms the foundation of MIB’s data structure.

## Selection Layer

The **Selection** layer is used for image segmentation, acting as a temporary workspace that’s easy to modify with 
manual or automatic tools. By default, it appears in green, but you can change its color in 
the [Preferences Dialog](ribbon/home/home-preferences.md#colors-and-styles).

Segmentation tools typically affect only the **Selection** layer (except some automatic routines that modify the **Mask** layer), 
leaving the **Model** layer untouched to preserve final results.<br>

If you make a mistake during selection, you can:

- Undo recent actions with ++ctrl+z++ or the **Undo** button in the [Quick Access Bar](quick-access-bar/index.md).
- Fix manually using the [Brush tool](panels/segm/segm-brush.md) in eraser mode: 
hold ++ctrl++ while brushing.
- Clear the **Selection** layer completely with ++c++ (or ++shift+c++ to clear the entire dataset).

When satisfied with the selection, transfer selection to the **Model** layer using:

- ++a++, add selection on the current slice to the selected material of the model
- ++shift+a++, add selection on all slices to the selected material of the model
- ++r++, replace the selected material of the model with the selection on the current slice
- ++shift+r++, replace the selected material of the model with the selection for the whole dataset

## Model Layer

The **Model** layer stores the final segmentation results. You can save it to a file, visualize it, or analyze it further.

## Mask Layer

The **Mask** layer is an auxiliary segmentation tool used to define areas for independent analysis or 
filtering, such as with [Ribbon -> Mask -> Mask Statistics](ribbon/mask/mask-stats.md). 
It operates separately from the **Selection** and **Model** layers.

The **Mask** layer also very useful when doing the [local black-and-white thresholding](panels/segm/segm-bwthres.md), 
where it defines the areas to be thresholded.

---

*Back to [MIB](../index.md) | [User Interface](index.md)*