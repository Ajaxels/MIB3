## Overview

![Resample Dataset Dialog](images/menuDatasetResample.png){.on-glb align=left width="320"}

Resample the image and corresponding Selection, Mask, and Model layers to 
adjust voxel sizes or dataset dimensions. 

Resampling can be done using:

- Dimensions mode
- Voxels mode
- Percentage XYZ mode
- Percentage XY mode

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Resample dataset demonstration](https://youtu.be/placeholder)

<div class="clear-float"></div>

Select the resampling mode to define how the dataset is resized.<br> 
In <label class="widget widget-checkbox">Dimensions</label> mode, specify the 
new width, height, and depth in pixels using<br>
<span class="widget widget-edit">Width</span>, <span class="widget widget-edit">Height</span>, 
and <span class="widget widget-edit">Depth</span> fields. 

In <label class="widget widget-checkbox">Voxels</label> mode, enter the desired voxel 
sizes in physical units (e.g., micrometers) for each dataset dimension. 

Choose the resampling function from the 
<span class="widget widget-dropdown">Resampling Function</span> dropdown to determine 
the interpolation technique. 

Select methods for images and models using 
<span class="widget widget-dropdown">Resampling Method</span> 
and <span class="widget widget-dropdown">Resampling Method Models</span>. 

Click the <span class="widget widget-button">Resample</span> button to apply the changes, 
or use the <span class="widget widget-button">Reset</span> button to restore default settings.

## Dimensions Mode

In <label class="widget widget-checkbox">Dimensions</label> mode, you define the new 
size of the dataset by entering the desired width, height, and depth in pixels:

- <span class="widget widget-edit">Width</span> field: set the number of pixels along the X-axis.
- <span class="widget widget-edit">Height</span> set the number of pixels along the Y-axis.
- <span class="widget widget-edit">Depth</span> set the number of pixels along the Z-axis.

This mode is ideal for adjusting the dataset to a specific resolution, 
such as reducing a large dataset for faster processing or matching another 
dataset’s dimensions. 

The image and associated layers (Selection, Mask, Model) are resized to the specified 
pixel counts, maintaining the aspect ratio if X, Y, and Z are scaled proportionally.

## Voxels Mode

In <label class="widget widget-checkbox">Voxels</label> mode, you specify the desired 
voxel sizes in physical units (e.g., micrometers) to adjust the dataset’s 
spatial resolution:

- <span class="widget widget-edit">Voxel X</span>enter the voxel size along the X-axis.
- <span class="widget widget-edit">Voxel Y</span>enter the voxel size along the Y-axis.
- <span class="widget widget-edit">Voxel Z</span>enter the voxel size along the Z-axis.

This mode recalculates the dataset’s pixel dimensions based on the provided voxel 
sizes and the dataset’s physical dimensions. It’s useful for standardizing 
datasets to a common resolution (e.g., for multi-modal imaging) or 
correcting anisotropic voxel sizes. 

The resampling process adjusts all layers to 
match the new voxel dimensions.

!!! info
    The voxel size of the dataset are specified in [Ribbon → Dataset →Parameters](index.md#voxels)

## Percentage XYZ Mode

In <label class="widget widget-checkbox">Percentage XYZ</label> mode, you define a
single scaling factor to resize all dimensions of the dataset:

<span class="widget widget-edit">Scaling Factor</span> enter a percentage 
(e.g., 50 for half size, 200 for double size).

All dimensions (width, height, depth) are scaled uniformly by this factor, 
affecting the image and all layers. 
!!! info
    This mode is convenient for quick resizing tasks, such as creating a 
    lower-resolution preview or enlarging a dataset for detailed inspection, 
    while preserving the dataset’s proportions.

## Percentage XY Mode

In <label class="widget widget-checkbox">Percentage XY</label> mode, you define a 
scaling factor that applies only to the XY dimensions, 
leaving the Z dimension unchanged:

<span class="widget widget-edit">Scaling Factor</span> enter XY percentage 
(e.g., 50 for half size, 200 for double size)..

Only the width (X) and height (Y) of the dataset are resized, 
making this mode suitable for adjusting in-plane resolution without altering the 
number of slices in a 3D stack. 

It’s particularly useful for datasets with anisotropic voxels where Z-resolution 
differs significantly from XY, allowing targeted scaling of the image and layers.

## Resampling Functions

The <span class="widget widget-dropdown">Resampling Function</span> dropdown offers three 
MATLAB-based methods to compute the resampled dataset, 
each with specific interpolation options for images and models:

<div class="h4-like">interpn</div>
Uses MATLAB’s [interpn](https://se.mathworks.com/help/releases/R2024b/matlab/ref/interpn.html)
function for n-dimensional interpolation, suitable for precise resampling of 3D and 4D 
datasets. It calculates new pixel values by interpolating between existing ones, 
supporting isotropic and anisotropic scaling.

- **Image resample methods**: 
    - `nearest`: assigns the value of the nearest pixel (fast, blocky).
    - `linear`: linear interpolation for smooth transitions (balanced speed and quality).
    - `spline`: spline interpolation for higher smoothness (slower, high quality).
    - `cubic`: cubic interpolation, similar to spline but slightly different curve fitting.
- **Model  resample methods**: Same as image methods (`nearest`, `linear`, `spline`, `cubic`), ensuring consistent resampling of segmented layers.

<div class="h4-like">imresize</div>
Employs MATLAB’s [imresize](https://se.mathworks.com/help/releases/R2024b/matlab/ref/imresize.html)
function, optimized for 2D image resizing but extended to 3D datasets slice-by-slice.<br> 
It’s faster for large datasets but less flexible for anisotropic scaling.

- **Image resample methods**: 
    - `nearest`: Nearest-neighbor interpolation (fastest, least smooth).
    - `box`: Box kernel averaging (simple, moderate quality).
    - `triangle`: Triangular kernel (bilinear-like, balanced).
    - `cubic`: Bicubic interpolation (smooth, high quality).
    - `lanczos2`: Lanczos kernel with 2-lobe window (sharp, detailed).
    - `lanczos3`: Lanczos kernel with 3-lobe window (sharpest, slowest).
    - `osc`: Custom oscillation-based method (experimental, high quality).
- **Model resample methods**: 
    - Only `nearest` is supported, as models require discrete values to preserve segmentation boundaries.

<div class="h4-like">tformarray</div>
Utilizes MATLAB’s [tformarray](https://se.mathworks.com/help/releases/R2024b/images/ref/tformarray.html) function 
for affine transformation-based resampling, ideal for complex scaling and alignment tasks. 

It applies a transformation matrix to the entire dataset.

- **Image resample methods**:
  - `nearest`: Nearest-neighbor interpolation (fast, preserves edges).
  - `linear`: Linear interpolation (smooth, moderate quality).
  - `cubic`: Cubic interpolation (smoothest, computationally intensive).
- **Model resample methods**:
  - Same as image methods (`nearest`, `linear`, `cubic`), allowing flexible resampling of model layers.

Select the desired method for images via <span class="widget widget-dropdown">Resampling Method</span> and for models via <span class="widget widget-dropdown">Resampling Method Models</span> to balance quality and performance based on your dataset’s needs.

!!! note
    For large datasets, use `nearest` or `imresize` for faster processing, and test settings on a small region using the [ROI panel](../../panels/roi/index.md) before resampling the entire dataset.
---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*
