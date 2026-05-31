# Object Separation with Watershed

Tools for separating objects that can be stored as materials in the current model, the mask layer, or the selection layer.

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Menu](../index.md) | [Tools](../tools/index.md)*

---

## Overview

![Overview of the Object Separation tool](images/menuToolsObjSep_Overview.jpg){.on-glb}

The **Object separation** tool in Microscopy Image Browser (MIB) utilizes watershed and graphcut segmentation techniques to divide connected objects into smaller, distinct entities. These objects can originate from the *Selection*, *Mask*, or *Model* layers, making this tool versatile for refining segmentation results.

---

## Mode panel

The *Mode panel* allows you to choose the segmentation scope, determining whether the operation applies to a single slice, multiple slices, or the entire volume.

![Mode panel for watershed/graphcut segmentation](images/menuToolsWatershed_Mode.jpg){align=left}

- <label class="widget widget-checkbox">2D, current slice only</label> performs segmentation only on the currently displayed slice in the [Image View panel](../../panels/imview/index.md)
- <label class="widget widget-checkbox">2D, slice-by-slice</label> applies 2D segmentation individually to each slice in the dataset
- <label class="widget widget-checkbox">3D, volume</label> executes 3D segmentation across the entire dataset or a selected subvolume (see *Subarea panel* below)
- <span class="widget widget-edit">Aspect ratio for 3D...</span> displays the dataset's aspect ratio, calculated from voxel sizes found in [Ribbon → Dataset → Parameters](../dataset/index.md#parameters). this ratio is used when watershed segmentation relies on a distance map (see *Object separation settings* below)

<div class="clear-float"></div>

---

## Subarea panel

The *Subarea panel* enables you to define a specific portion of the dataset for processing. this is particularly useful for large datasets that need to be segmented in parts or reduced in resolution.

![Subarea panel for selecting dataset region](images/menuToolsWatershed_Subarea.jpg){align=left}

- <span class="widget widget-edit">X:...</span>: specifies the width range of the dataset to process, using two numbers separated by a colon (e.g., `1:512`)
- <span class="widget widget-edit">Y:...</span>: defines the height range of the dataset to process
- <span class="widget widget-edit">Z:...</span>: sets the z-slice range of the dataset to process
- <span class="widget widget-button">from Selection</span>: populates the *X*, *Y*, and *Z* fields with coordinates from a bounding box around the *Selection* layer
- <span class="widget widget-button">Current View</span>: restricts the *X* and *Y* ranges to the currently visible area in the [Image View panel](../../panels/imview/index.md)
- <span class="widget widget-button">Reset</span>: restores the subarea fields to the full dimensions of the dataset
- <span class="widget widget-edit">Bin x times...</span>: applies a binning factor to downsample the data before segmentation, speeding up the process at the cost of detail.

!!! warning 
    binning in *Object separation* mode may lead to unpredictable results

<div class="clear-float"></div>

---

## Object separation settings

![Object separation settings panel](images/menuToolsWatershed_Objsep.jpg){.on-glb align=left width="340"}

The *Object separation* mode employs watershed transformation to split segmented objects into smaller units. below are the specific settings for this mode.

<div class="clear-float"></div>

- **Object to watershed**: selects the source layer containing the object to be separated, choosing from *Selection*, *Mask*, or *Model*
- <label class="widget widget-checkbox">Use seeds</label> activates the seeded watershed transformation, requiring additional settings in the *Seeds panel* below
- **Reduce oversegmentation**: (available only for unseeded watershed) reduces the number of resulting objects, helping to prevent excessive fragmentation
- **Seeds panel**: (active only when <label class="widget widget-checkbox">Use seeds</label> is checked)
  - **Layer with seeds**: specifies the layer containing seed points, selectable from *Selection*, *Mask*, or *Model*
  - **Watershed source**: determines the data used for watershed labeling
    - **Image intensity**: uses the actual image intensities instead of distance maps. for more details, see [Steve Eddins's blog on cell segmentation](http://blogs.mathworks.com/steve/2006/06/02/cell-segmentation/)

---

## Object separation example

The *Object separation* mode with watershed can split large, fused objects into smaller, individual components. for instance, in a segmentation example featuring mitochondria, some appear merged. this tool can separate them effectively.

1. Navigate to **Ribbon → Tools → Object separation**
2. Select *Mask* in the *Object to watershed* dropdown
3. Click the <span class="widget widget-button">Segment</span> button

??? Abstract "Snapshot"
    ![Result of unseeded watershed separation](images/menuToolsWatershed-imsegm05.jpg){.on-glb}

This separates the mitochondria, but unseeded watershed often oversegments, breaking long mitochondria into multiple small pieces. to address this, use the seeded watershed approach:

1. Check <span class="widget widget-checkbox">Use seeds</span>
2. In the *Seeds panel*, set *Layer with seeds* to *Model* and select the 'Seeds' material
3. Click the <span class="widget widget-button">Segment</span> button
4. If each mitochondrion has a single seed label, individual mitochondria will be extracted (highlighted in green)

??? Abstract "Snapshot"
    ![Result of seeded watershed separation](images/menuToolsWatershed-imsegm06.jpg){.on-glb}

---

## Algorithm for object separation with watershed

![Workflow of the object separation algorithm](images/menuToolsWatershed_obj_sep_alg.jpg){.on-glb}

The diagram above illustrates the step-by-step process of the watershed-based object separation algorithm, showing how it transforms input data into separated objects.

---

## References

For further reading on watershed segmentation in both image segmentation and object separation modes:

- [Watershed transform question from tech support](http://blogs.mathworks.com/steve/2013/11/19/watershed-transform-question-from-tech-support/) by Steve Eddins
- [Cell segmentation](http://blogs.mathworks.com/steve/2006/06/02/cell-segmentation/) by Steve Eddins

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Menu](../index.md) | [Tools](../tools/index.md)*