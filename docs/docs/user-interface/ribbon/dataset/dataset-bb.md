# Bounding Box

---

## Description

![Bounding Box Dialog](images/menuDatasetBoundingBox.png){.on-glb align=left width="300"}

The Bounding Box defines the position of the dataset in 3D space, which is crucial 
for accurate positioning in visualization software like Amira or for aligning multiple 
datasets.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Bounding Box demonstration](https://youtu.be/lY0XjNy4Dr8)

<div class="clear-float"></div>

Adjust the bounding box by specifying its minimal or central coordinates, or import 
settings from the clipboard. Current coordinates are displayed under 
the **Current Bounding Box** text in the dialog. 

Use the <span class="widget widget-edit">X, Y, Z, min</span> fields to set the starting 
point of the dataset, or the <span class="widget widget-edit">X, Y, center</span> 
fields to define its center, which automatically recalculates minimal coordinates.

Maximal coordinates (<span class="widget widget-edit">X, Y, Z max</span>) can be set to
adjust voxel sizes, and a <span class="widget widget-edit">Stage rotation bias, degrees</span>
field accounts for acquisition biases, such as the 45-degree tilt in Gatan 3View systems. 

Click the <span class="widget widget-button">Apply</span> button to update the dataset’s 
bounding box, or use <span class="widget widget-button">Cancel</span> to close the dialog 
without changes.

!!! warning "Bounding Box Note"
    For 3D images, the bounding box is calculated as the smallest box containing all voxel centers, not all voxels. It’s defined by voxel centers, meaning 1/2 voxel is subtracted on both sides, resulting in a box 1 voxel smaller in all three directions.

## Widgets and parameters

- <span class="widget widget-edit">X, Y, Z, min</span> define the minimal coordinates of the 
bounding box (e.g., the lower-left-front corner in 3D space).
- <span class="widget widget-edit">X, Y, center</span> specify the central coordinates of 
the dataset; automatically recalculates <span class="widget widget-edit">X, min</span> 
and <span class="widget widget-edit">Y, min</span> based on dataset dimensions.
- <span class="widget widget-edit">X, Y, Z max</span> set the maximal coordinates; when 
used with minimal coordinates, recalculates voxel sizes to match the new bounding
box dimensions.
- <span class="widget widget-edit">Stage rotation bias, degrees</span> adjust for stage 
rotation bias in degrees (e.g., enter 45 for Gatan 3View’s default tilt).
- <span class="widget widget-button">Import from Clipboard</span> parse text from the 
system clipboard to set bounding box parameters (see below for syntax).

??? info "Import from clipboard settings"

    Syntax: `[ParameterName] = [ParameterValue]` to extract parameters.

    | Parameter Name | Description                                                                 |
    |----------------|-----------------------------------------------------------------------------|
    | ScaleX         | Physical size of pixels in X (e.g., micrometers per pixel)                  |
    | ScaleY         | Physical size of pixels in Y (e.g., micrometers per pixel)                  |
    | ScaleZ         | Physical size of pixels in Z (e.g., micrometers per pixel)                  |
    | xPos           | Central position of the dataset in the X plane                             |
    | yPos           | Central position of the dataset in the Y plane                             |
    | Z Position     | Minimal Z coordinate                                                       |
    | Rotation       | Rotation bias (MIB adds 45 degrees for Gatan 3View compatibility)          |
    
    ??? example "Example 1"
    
        Copy the following text into the system clipboard and press 
        <span class="widget widget-button">Import from Clipboard</span> to set voxel size 
        for the current dataset.
        ```
        ScaleX = 0.015
        ScaleY = 0.015
        ScaleZ = 0.05
        ```

    ??? example "Example 2"
        ```
        Magnification = 897x
        Voltage = 2500 V
        ScaleX( µm) = 0.0150039
        ScaleY( µm) = 0.0150039
        xPos (um) = -103.759
        yPos (um) = -535.899
        ScaleZ (µm) = 0.05
        Z Position (um) = 58.9802
        Dwell time = 8 ms

        Spot Size = 3000
        Pressure (Torr) = 0.0865544
        Rotation = 0
        Working Distance (mm) = 5.64201
        Width x Height = 7000 x 7000
        Acquisition Date = 24/03/2025
        ```

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*
