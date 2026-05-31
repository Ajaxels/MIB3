# Graphcut Segmentation

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Tools](index.md)*

Semi-automated image segmentation using the max-flow/min-cut graphcut method in Microscopy Image Browser (MIB).

---

## Overview

The **Graphcut segmentation** tool in MIB provides semi-automated segmentation using the max-flow/min-cut 
algorithm. It is based on the [Max-flow/min-cut algorithm](http://vision.csd.uwo.ca/code/) by Yuri Boykov and 
Vladimir Kolmogorov, with a MATLAB implementation 
by [Michael Rubinstein](http://www.mathworks.com/matlabcentral/fileexchange/21310-maxflow). 

![Graphcut segmentation interface](images/menuToolsGraphcut_Overview.jpg)

Instead of segmenting individual pixels, it operates on superpixels (2D) or supervoxels (3D), 
generated via the [SLIC algorithm](http://ivrl.epfl.ch/research/superpixels) by 
Radhakrishna Achanta et al. or the Watershed algorithm. SLIC superpixels excel for 
objects with intensity contrast, while Watershed superpixels are better for objects with 
distinct boundaries. 
<br>Precomputing superpixels requires initial processing time but accelerates subsequent segmentation.

---

## General example

A demonstration is available in this video:  
[:fontawesome-brands-youtube:{.red-color} Watch on YouTube](https://youtu.be/dMeoIZPaDS4)

??? abstract "How to use"
    ![Graphcut workflow example](images/menuToolsWatershedGraphcut.jpg){.on-glb}

    Steps to perform graphcut segmentation:

    1. Use two labels to mark background and object areas of interest
    2. Launch the tool via `Ribbon → Tools → Semi-automatic segmentation → Graphcut`
    3. Choose a mode: *2D* or *3D*
    4. Select superpixel/supervoxel type: *SLIC* or *Watershed*
    5. Generate superpixels/supervoxels by clicking <span class="widget widget-button">Superpixels/Graph</span>
    6. Verify and adjust superpixel size if necessary
    7. Click <span class="widget widget-button">Segment</span> to start segmentation

    ??? note
        Some functions may require compilation; see the [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#superpixels) page for details

---

## Mode panel

The *Mode panel* lets you select the segmentation scope.

![Mode panel options](images/menuToolsGraphcut_Mode.jpg){align=left}

- <label class="widget widget-checkbox">2D, current slice only</label> segments only the current slice in the [Image View panel](../../panels/imview/index.md)
- <label class="widget widget-checkbox">2D, slice-by-slice</label> applies 2D segmentation to each slice individually
- <label class="widget widget-checkbox">3D, volume</label> performs 3D segmentation on the entire dataset or a subarea (see *Subarea panel* below)
- <label class="widget widget-checkbox">3D, volume, grid</label> segments a large dataset by dividing it 
into subvolumes (defined by *Chop* fields). the subvolume centered in 
the [Image View panel](../../panels/imview/index.md) is processed 
(enable the center marker via 
![](../../quick-access-bar/images/toolbar-centralmarker.png) on the Quick Access Bar). <br>Use <span class="widget widget-button">Segment All</span> to process all subvolumes

<div class="clear-float"></div>

---

## Subarea panel

The *Subarea panel* defines a dataset subset for processing, useful for large datasets or binning.

![Subarea panel settings](images/menuToolsWatershed_Subarea.jpg){align=left}

- <span class="widget widget-edit">X:...</span> sets the width range (e.g., `1:512`)
- <span class="widget widget-edit">Y:...</span> sets the height range
- <span class="widget widget-edit">Z:...</span> sets the z-slice range
- <span class="widget widget-button">from Selection</span> fills *X*, *Y*, and *Z* with coordinates from the *Selection* layer’s bounding box
- <span class="widget widget-button">Current View</span> limits *X* and *Y* to the visible area in the [Image View panel](../../panels/imview/index.md)
- <span class="widget widget-button">Reset</span> restores full dataset dimensions
- <span class="widget widget-edit">Bin x times...</span> applies a binning factor to reduce detail for faster processing

!!! warning
    Auto update mode (<label class="widget widget-checkbox">auto update</label>) is unavailable with binned datasets

<div class="clear-float"></div>

---

## Calculation of superpixels/supervoxels

Superpixels (2D) or supervoxels (3D) are precomputed using SLIC or Watershed algorithms. SLIC suits intensity-contrast objects (e.g., lipid droplets), while Watershed excels for boundary-defined objects.

??? abstract "Image example of clusters"
    ![SLIC vs. Watershed superpixels](images/menuToolsWatershedGraphcut_slic_vs_watershed.jpg){.on-glb}

![Superpixel settings](images/menuToolsGraphcut_Superpixels.jpg){.on-glb align=left width="340"}

- <span class="widget widget-dropdown">Superpixels</span> selects the type: *SLIC* or *Watershed*
- <span class="widget widget-edit">Size of superpixels</span> sets approximate superpixel size (SLIC only)
- <span class="widget widget-edit">Reduce number of superpixels</span> scaling factor defining size of superpixels (Watershed only)
- <span class="widget widget-edit">Compactness</span> (1-99) controls superpixel squareness; higher values yield squarer shapes (SLIC only)

<div class="clear-float"></div>

- <span class="widget widget-dropdown">Color channel</span> chooses the color channel for superpixel calculation
- <span class="widget widget-dropdown">Type of signal</span> selects *black-on-white* (electron microscopy) or *light-on-black* (light microscopy)
- <span class="widget widget-edit">Chop...</span> defines subvolume sizes for *3D volume grid* mode or SLIC supervoxels
- <label class="widget widget-checkbox">autosave</label> saves the graphcut structure and supervoxels to disk automatically
- <label class="widget widget-checkbox">parfor</label> enables parallel processing for Watershed clustering in *3D volume grid* mode, boosting performance
- <label class="widget widget-checkbox">use PixelIdsList</label> uses supervoxel indices for final models, improving performance but requiring more memory
- <span class="widget widget-button">Superpixels/Graph</span> generates superpixels and organizes them into a graph
- <span class="widget widget-button">Import</span> loads superpixels and graphs from disk or MATLAB
- <span class="widget widget-button">Export</span> saves superpixels and graphs to a file, MATLAB, a new model, or as a Lines3D graph object (not recommended for many superpixels; see [this video](https://youtu.be/xrsTVqD7kOQ))
- <span class="widget widget-button">Preview superpixels</span> displays the generated superpixels

<div class="clear-float"></div>

---

## Image segmentation settings

The *Graphcut* workflow uses labeled areas (Background and Object) for segmentation, offering faster interaction than the [Watershed workflow](tools-watershed.md). It handles objects with both boundaries and intensity contrast, making it versatile.

![Segmentation settings](images/menuToolsGraphcut_ImageSegmSettings.jpg){.on-glb align=left width="340"}

- <span class="widget widget-dropdown">Background</span> selects the model material labeling background areas
- <span class="widget widget-dropdown">Object</span> selects the model material labeling objects
- <span class="widget widget-button">Update lists</span> refreshes material lists
- <label class="widget widget-checkbox">Auto update</label> updates segmentation automatically when materials change (best for small datasets, ~400x400x400 pixels)

!!! warning
    In *Auto update* mode, use only the <span class="widget widget-button">A</span> 
    shortcut (not <span class="widget widget-button">Shift+A</span>).<br>
    Recalculate final segmentation with 
    <span class="widget widget-button">Segment</span>.<br>
    This mode is unavailable with binned datasets

<div class="clear-float"></div>

---

## Image segmentation example

Follow these steps to segment mitochondria using Graphcut:

* Load a sample dataset: `Ribbon → Home → Import image from → URL`, enter *http://mib.helsinki.fi/tutorials/WatershedDemo/watershed_demo1.tif*
* Add a material named *Background* in the [Segmentation panel](../../panels/segm/index.md) with <span class="widget widget-button">+</span> (right-click to rename)
* Use the Brush tool to label cytoplasm, then press <span class="widget widget-button">A</span> to add it to *Background*

??? abstract "Snapshot"
    ![Labeling Background](images/watershed_imsegm_01.jpg){.on-glb}

* Add another material named *Seeds* with <span class="widget widget-button">+</span>
* Label mitochondria interiors, then press <span class="widget widget-button">A</span> to add to *Seeds*

??? abstract "Snapshot"
    ![Labeling Seeds](images/watershed_imsegm_03.jpg){.on-glb}

* Start Graphcut via **Ribbon → Tools → Semi-automatic segmentation → Graphcut**
* Select *Watershed* in <span class="widget widget-dropdown">Superpixels</span>
* Ensure *Background* and *Seeds* are set in *Image segmentation settings*
* Click <span class="widget widget-button">Segment</span> to segment mitochondria
* Add more seeds to refine, then re-segment with <span class="widget widget-button">Segment</span> or enable <label class="widget widget-checkbox">Auto update</label>
* Results appear in the *Mask* layer
* Optionally smooth the mask: **Ribbon → Mask → Smooth Mask**

??? abstract "Snapshot"
    ![Segmented mitochondria](images/watershed_imsegm_04.jpg){.on-glb}

---

## References

- [Max-flow/min-cut algorithm](http://vision.csd.uwo.ca/code/) by Yuri Boykov and Vladimir Kolmogorov (research license only)
- [MATLAB wrapper for maxflow](http://www.mathworks.com/matlabcentral/fileexchange/21310-maxflow) by Michael Rubinstein
- [SLIC superpixels and supervoxels](http://ivrl.epfl.ch/research/superpixels) by Radhakrishna Achanta et al.
- [Region Adjacency Graph (RAG)](http://www.mathworks.com/matlabcentral/fileexchange/16938-region-adjacency-graph--rag-) by David Legland, INRA, France (modified for Watershed)

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Tools](index.md)*
