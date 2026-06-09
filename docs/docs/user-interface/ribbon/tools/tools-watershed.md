# Watershed Segmentation

Semi-automated image segmentation using the Watershed method in 
Microscopy Image Browser.

---

## Overview

![Watershed segmentation interface](images/menuToolsWatershed_Overview.jpg){.on-glb}

The **Watershed segmentation** tool in MIB provides semi-automated 
segmentation using the Watershed method, ideal for separating objects 
with distinct boundaries, such as membrane-enclosed organelles. 

!!! note

    For better interactivity and performance consider using the [Graphcut segmentation tool](tools-graphcut.md) instead.

---

## Mode panel

The *Mode panel* lets you select the segmentation scope.

![Mode panel options](images/menuToolsWatershed_Mode.jpg){align=left}

- <label class="widget widget-checkbox">2D, current slice only</label> segments only the current slice in the [Image View panel](../../panels/selection_imview/imview.md)
- <label class="widget widget-checkbox">2D, slice-by-slice</label> applies 2D segmentation to each slice individually
- <label class="widget widget-checkbox">3D, volume</label> performs 3D segmentation on the entire dataset or a subarea (see *Subarea panel* below)
- <span class="widget widget-edit">Aspect ratio for 3D...</span> displays the dataset’s 
aspect ratio, derived from voxel sizes in ([Ribbon → Dataset → Parameters](../dataset/index.md#parameters)). this is used when Watershed relies on a distance map (see *Image segmentation settings* below)

<div class="clear-float"></div>

---

## Subarea panel

The *Subarea panel* defines a dataset subset for processing, useful for large datasets or binning.

![Subarea panel settings](images/menuToolsWatershed_Subarea.jpg){align=left}

- <span class="widget widget-edit">X:...</span> sets the width range (e.g., `1:512`)
- <span class="widget widget-edit">Y:...</span> sets the height range
- <span class="widget widget-edit">Z:...</span> sets the z-slice range
- <span class="widget widget-button">from Selection</span> fills *X*, *Y*, and *Z* with coordinates from the *Selection* layer’s bounding box
- <span class="widget widget-button">Current View</span> limits *X* and *Y* to the visible area in the [Image View panel](../../panels/selection_imview/imview.md)
- <span class="widget widget-button">Reset</span> restores full dataset dimensions
- <span class="widget widget-edit">Bin x times...</span> applies a binning factor to reduce detail for faster processing

<div class="clear-float"></div>

---

## Image segmentation settings

The *Watershed* workflow uses labeled areas (Background and Object) for segmentation, 
contrasting with the [Graphcut workflow](tools-graphcut.md). 
It’s less interactive, slower per execution, and best for objects with 
distinct boundaries. Graphcut, with its preprocessing focus, is faster for 
repeated interactions and handles both boundaries and intensity contrast, making 
it preferable for most cases.

![Segmentation settings](images/menuToolsWatershed_Imsegm.jpg){.on-glb align=left width="300"}

- <span class="widget widget-dropdown">Color channel</span> selects the channel for segmentation
- <span class="widget widget-dropdown">Background</span> selects the model material labeling background areas
- <span class="widget widget-dropdown">Object</span> selects the model material labeling objects
- <span class="widget widget-dropdown">Type of signal</span> chooses *black-on-white* (dark boundaries) or *white-on-black* (bright boundaries)
- <span class="widget widget-button">Update lists</span> refreshes material lists

<div class="clear-float"></div> 

<div class="h3-like">Optional pre-processing (Watershed only):</div>

  - <label class="widget widget-checkbox">Gradient</label> applies a gradient filter to enhance object borders
  - <label class="widget widget-checkbox">Eigenvalue of Hessian</label> preprocesses data for improved Watershed results; adjust with *Sigma* fields
  - <label class="widget widget-checkbox">Export to MATLAB</label> sends preprocessed data to the MATLAB workspace
  - <label class="widget widget-checkbox">Preview</label> displays preprocessing results in the [Image View panel](../../panels/selection_imview/imview.md)
  - <span class="widget widget-button">Pre-process</span> starts preprocessing (turns green when data is ready)
  - <span class="widget widget-button">Import from MATLAB</span> loads a dataset from the MATLAB workspace for segmentation
  - <span class="widget widget-button">Clear</span> removes preprocessed data from memory


---

## Image segmentation example

Follow these steps to segment mitochondria using Watershed:

* Load a sample dataset: `Ribbon → Home → Import image from → URL`, enter<br>
*http://mib.helsinki.fi/tutorials/WatershedDemo/watershed_demo1.tif*
* Add a material named *Background* in the [Segmentation panel](../../panels/segm/index.md) with <span class="widget widget-button">+</span> (right-click to rename)
* Use the Brush tool to label cytoplasm, then press <span class="widget widget-button">A</span> to add it to *Background*

??? abstract "Snapshot"
    ![Labeling Background](images/watershed_imsegm_01.jpg){.on-glb}

* Add another material named *Seeds* with <span class="widget widget-button">+</span>
* Label mitochondria interiors, then press <span class="widget widget-button">A</span> to add to *Seeds*

??? abstract "Snapshot"
    ![Labeling Seeds](images/watershed_imsegm_03.jpg){.on-glb}

* Start Watershed via `Ribbon → Tools → Semi-automatic segmentation → Watershed`
* Ensure *Background* and *Seeds* are set in *Image segmentation settings*
* Click <span class="widget widget-button">Segment</span> to segment mitochondria
* Add more seeds to refine, then re-segment with <span class="widget widget-button">Segment</span>
* Results appear in the *Mask* layer
* Optionally smooth the mask: [Ribbon → Mask → Smooth Mask](../mask/index.md#smooth-mask)

??? abstract "Snapshot"
    ![Segmented mitochondria](images/watershed_imsegm_04.jpg){.on-glb}

---

## Algorithm for image segmentation with watershed

![Watershed algorithm workflow](images/menuToolsWatershedGraphcut_img_segm_alg.jpg){.on-glb}

The diagram illustrates the step-by-step process of the Watershed segmentation algorithm, transforming labeled input into segmented objects.

---

## References

- [Watershed transform question from tech support](http://blogs.mathworks.com/steve/2013/11/19/watershed-transform-question-from-tech-support/) by Steve Eddins
- [Cell segmentation](http://blogs.mathworks.com/steve/2006/06/02/cell-segmentation/) by Steve Eddins

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Menu](../index.md) | [Tools](index.md)*