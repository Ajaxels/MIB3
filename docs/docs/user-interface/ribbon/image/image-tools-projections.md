# Intensity Projection

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

## Description

![Intensity Projection](images/menuImageToolsIntensityProjection.png){align=left}

Generate a 2D intensity projection from the dataset across a specified dimension, affecting the image and corresponding Selection, Mask, and Model layers.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Intensity projection demonstration](https://youtu.be/hwFpS_3eP9U)
- [:fontawesome-brands-youtube:{.red-color} Focus stacking demo](https://youtu.be/5L0xMSFVxiU)

<div class="clear-float"></div>

Select a projection method from the <span class="widget widget-dropdown">Projection Type</span>
dropdown and choose the dimension (e.g., Z, T) to project along using 
the <span class="widget widget-dropdown">Dimension</span> dropdown. 
Use the <span class="widget widget-dropdown">Destination buffer</span> dropdown
to specify destination for the results.

Click the <span class="widget widget-button">OK</span> button to generate the 
projection, replacing the dataset specified in <span class="widget widget-dropdown">Destination buffer</span>. 
Use the <span class="widget widget-button">Cancel</span> button to close the dialog 
without changes.

## List of available projection calculations

### Maximum Intensity Projection

This method projects the voxel with the highest intensity value along 
the selected dimension onto a 2D image:

- No additional parameters are required.

The resulting image highlights the brightest features across the dimension, 
such as peak intensities in a Z-stack or time series. 
This is useful for visualizing dominant structures or signals in volumetric datasets, 
such as fluorescent markers or high-contrast objects. The image and layers are 
compressed into a single 2D slice, preserving the maximum values.

### Minimum Intensity Projection

This method projects the voxel with the lowest intensity value along the 
selected dimension onto a 2D image:

- No additional parameters are required.

The output emphasizes the darkest regions, making it ideal for identifying low-intensity 
features, such as voids or background areas in a stack. This projection is often 
used in contrast to maximum projection to analyze the range of intensities. 
The image and layers are reduced to a 2D slice containing the minimum values.

### Mean Intensity Projection

This method projects the average intensity value of voxels along the selected dimension 
onto a 2D image:

- No additional parameters are required.

The resulting image represents the mean intensity across the dimension, 
providing a balanced view of the dataset’s content. This is useful for summarizing 
overall intensity trends, such as in time-lapse data or Z-stacks with varying signal 
strength. The image and layers are consolidated into a 2D slice with averaged values.

### Median Intensity Projection

This method projects the median intensity value of voxels along the selected 
dimension onto a 2D image:

- No additional parameters are required.

The median projection reduces the impact of outliers, offering a robust
representation of typical intensities. It’s particularly effective for noisy datasets, 
where extreme values might skew mean projections. The image and layers are transformed 
into a 2D slice with median values, maintaining data integrity.

### Focus Stacking

This method generates an extended depth-of-field image from a focus sequence using a 
noise-robust selective all-in-focus algorithm:

- No additional parameters are required.

Focus stacking combines slices from a Z-stack to produce a single 2D image where 
all regions are in focus, ideal for datasets with varying focal planes, such as 
microscopy images with limited depth-of-field. The algorithm selectively fuses 
sharp areas, enhancing clarity for visualization or analysis. The image and layers 
are merged into a focused 2D slice.

!!! info "Focus stacking reference"

    * Pertuz et al., "Generation of all-in-focus images by noise-robust selective fusion of limited depth-of-field images, [IEEE Trans. Image Process](https://ieeexplore.ieee.org/document/6373725), 22(3):1242–1251, 2013).


---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
