# Graphcut Segmentation

Semi-automated image segmentation using the max-flow/min-cut graphcut method.

---

## Overview

The **Graphcut segmentation** tool provides semi-automated segmentation using the max-flow/min-cut
algorithm. It is based on the [Max-flow/min-cut algorithm](http://vision.csd.uwo.ca/code/) by Yuri Boykov and
Vladimir Kolmogorov, with a MATLAB implementation
by [Michael Rubinstein](http://www.mathworks.com/matlabcentral/fileexchange/21310-maxflow).

![Graphcut segmentation interface](images/menuToolsGraphcut_Overview.jpg)

Instead of segmenting individual pixels, it operates on superpixels (2D) or supervoxels (3D),
generated via the [SLIC algorithm](http://ivrl.epfl.ch/research/superpixels) by
Radhakrishna Achanta et al. or the Watershed algorithm. SLIC superpixels excel for
objects with intensity contrast, while Watershed superpixels are better for objects with
distinct boundaries.  
Precomputing superpixels requires initial processing time but accelerates subsequent segmentation.

---

## General example

[:fontawesome-brands-youtube:{.red-color} Watch on YouTube](https://youtu.be/dMeoIZPaDS4)

??? abstract "How to use"
    ![Graphcut workflow example](images/menuToolsWatershedGraphcut.jpg){.on-glb}

    Steps to perform graphcut segmentation:

    1. Use two model materials to mark background and object areas of interest
    2. Launch the tool via `Ribbon → Tools → Semi-automatic segmentation → Graphcut`
    3. Choose a mode: *2D* or *3D*
    4. Select superpixel/supervoxel type: *SLIC* or *Watershed*
    5. Generate superpixels/supervoxels by clicking <span class="widget widget-button">Calculate Superpixels</span>
    6. Verify and adjust superpixel size if necessary
    7. Click <span class="widget widget-button">Segment</span> to start segmentation

    ??? note
        Some functions may require compilation; see the [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#superpixels) page for details

---

## Mode panel

The *Mode panel* lets you select the segmentation scope.

![Mode panel options](images/menuToolsGraphcut_Mode.png){align=left}

- <span class="widget widget-radio">2D, current slice only</span> — segments only the current slice in the [Image View panel](../../image-document/index.md)
- <span class="widget widget-radio">2D, slice-by-slice</span> — applies 2D segmentation to each slice individually
- <span class="widget widget-radio">3D, volume</span> — performs 3D segmentation on the entire dataset or a subarea (see *Subarea panel* below)
- <span class="widget widget-radio">3D, volume, grid</span> — segments a large dataset by dividing it
  into subvolumes (defined by *Chop* fields); the subvolume centred in
  the [Image View panel](../../image-document/index.md) is processed
  (enable the centre marker via
  ![](../../quick-access-bar/images/toolbar-centralmarker.png) on the Quick Access Bar).  
  Use <span class="widget widget-button">Segment All</span> to process all subvolumes.

<div class="clear-float"></div>

---

## Subarea panel

The *Subarea panel* defines a dataset subset for processing, useful for large datasets or binning.

![Subarea panel settings](images/menuToolsWatershed_Subarea.png){align=left}

- <span class="widget widget-edit">X</span> sets the width range (e.g., `1:512`)
- <span class="widget widget-edit">Y</span> sets the height range
- <span class="widget widget-edit">Z</span> sets the z-slice range
- <span class="widget widget-button">from Selection</span> fills *X*, *Y*, and *Z* with coordinates from the *Selection* layer's bounding box
- <span class="widget widget-button">Current View</span> limits *X* and *Y* to the visible area in the [Image View panel](../../image-document/index.md)
- <span class="widget widget-button">Reset</span> restores full dataset dimensions
- <span class="widget widget-edit">Bin, xtimes:</span> binning factor `XY; Z` to reduce resolution for faster processing (e.g., `2; 1` halves XY)

!!! warning
    Auto update mode (<label class="widget widget-checkbox">Auto update</label>) is unavailable with binned datasets.

<div class="clear-float"></div>

---

## Calculation of superpixels/supervoxels

Superpixels (2D) or supervoxels (3D) are precomputed using SLIC or Watershed algorithms.
SLIC suits intensity-contrast objects (e.g., lipid droplets);
Watershed excels for boundary-defined objects.

??? abstract "SLIC vs. Watershed example"
    ![SLIC vs. Watershed superpixels](images/menuToolsWatershedGraphcut_slic_vs_watershed.jpg){.on-glb}

![Superpixel settings](images/menuToolsGraphcut_Superpixels.png){.on-glb align=left width="340"}

- <span class="widget widget-dropdown">Superpixels</span>: superpixel type — *SLIC* or *Watershed*
- <span class="widget widget-edit">Size of superpixels</span>: approximate size of each superpixel (2D) or
  supervoxel (3D) in pixels. Smaller values give finer segmentation but increase computation time.
- <span class="widget widget-edit">Compactness</span>: controls SLIC superpixel squareness
  (higher values yield squarer shapes). Not applicable to Watershed.
- <span class="widget widget-dropdown">Color channel</span>: color channel for superpixel calculation.
- <span class="widget widget-dropdown">Type of signal</span>: signal polarity —
  *black-on-white* (electron microscopy) or *light-on-black* (light microscopy, fluorescence).
- <span class="widget widget-button">Calculate Superpixels</span>: computes superpixels/supervoxels
  and builds the boundary graph. The button turns green on completion.

<div class="clear-float"></div>

- <span class="widget widget-edit">Chop</span> X/Y/Z: number of grid tiles in each dimension for
  *3D, volume, grid* mode. Also controls SLIC supervoxel grid tiling.
- <label class="widget widget-checkbox">autosave</label>: automatically prompts to save the graphcut
  structure to disk (`*.graph`) after superpixels are computed.
- <label class="widget widget-checkbox">parallel</label>: enables parallel processing (parfor)
  for Watershed clustering in *3D, volume, grid* mode. Starts a parallel pool if not already running.
- <label class="widget widget-checkbox">use PixelIdxList</label>: pre-computes pixel index lists
  per superpixel. Speeds up mask updates at the cost of extra memory.
- <span class="widget widget-button">Preview superpixels</span>: overlays the computed superpixel
  boundaries on the current image.
- <span class="widget widget-button">Import</span>: loads a previously saved graphcut structure
  from disk (`*.graph`) or the MATLAB workspace.
- <span class="widget widget-button">Export</span>: saves superpixels and the graph. Options:
    - *Export to Matlab* — exports the `Graphcut` struct to the MATLAB workspace.
    - *Save to a file* — saves to a `*.graph` file (excluding the sparse `Graph` field).
    - *Export to a model* — writes the superpixel labels into the model layer as materials.
    - *Export to 3DLines* — converts the adjacency graph to a Lines3D object
      (not recommended for large numbers of supervoxels;
      see [this video](https://youtu.be/xrsTVqD7kOQ)).

**Recalculate Graph panel**

- <span class="widget widget-edit">Coef</span>: edge weight scaling factor (default 25).
  Graph edge weights are computed as *exp(−normalised\_intensity\_difference × Coef)*.
  Increase to sharpen boundary cuts; decrease to allow softer cuts.
- <span class="widget widget-button">Recalculate</span>: rebuilds the sparse boundary graph
  from the existing edge list without recomputing superpixels.
  Use this after changing <span class="widget widget-edit">Coef</span>.

---

## Image segmentation settings

The *Graphcut* workflow uses labeled areas (Background and Object) for segmentation.
It handles objects with both boundaries and intensity contrast, making it versatile.

![Segmentation settings](images/menuToolsGraphcut_ImageSegmSettings.png){.on-glb align=left width="340"}

- <span class="widget widget-dropdown">Background</span>: model material that labels background areas.
- <span class="widget widget-dropdown">Object</span>: model material that labels objects of interest.
- <span class="widget widget-button">Update lists</span>: refreshes the material dropdowns from the current model.
- <label class="widget widget-checkbox">Auto update</label>: re-runs segmentation automatically
  after each paint stroke on the currently shown slice.
  Best for small datasets (~400×400×400 px).

!!! warning
    In *Auto update* mode, use only the <span class="widget widget-button">A</span>
    shortcut (not ++shift+a++).  
    Recalculate final segmentation with <span class="widget widget-button">Segment</span>.  
    Unavailable with binned datasets.

<div class="clear-float"></div>

---

## Image segmentation example

Steps for segmenting mitochondria using Graphcut:

* Load a sample dataset: `Ribbon → Home → Import image from → URL`, enter *http://mib.helsinki.fi/tutorials/WatershedDemo/watershed_demo1.tif*
* Add a material named *Background* in the [Segmentation panel](../../panels/segm/index.md) with <span class="widget widget-button">+</span> (right-click to rename)
* Use the Brush tool to label cytoplasm, then press <span class="widget widget-button">A</span> to add it to *Background*

??? abstract "Snapshot"
    ![Labeling Background](images/watershed_imsegm_01.jpg){.on-glb}

* Add another material named *Seeds* with <span class="widget widget-button">+</span>
* Label mitochondria interiors, then press <span class="widget widget-button">A</span> to add to *Seeds*

??? abstract "Snapshot"
    ![Labeling Seeds](images/watershed_imsegm_03.jpg){.on-glb}

* Start Graphcut via `Ribbon → Tools → Semi-automatic segmentation → Graphcut`
* Select *Watershed* in <span class="widget widget-dropdown">Superpixels</span>
* Ensure *Background* and *Seeds* are set in the *Image segmentation settings* panel
* Click <span class="widget widget-button">Segment</span> to segment mitochondria
* Add more seeds to refine, then re-segment with <span class="widget widget-button">Segment</span> or enable <label class="widget widget-checkbox">Auto update</label>
* Results appear in the *Mask* layer
* Optionally smooth the mask: `Ribbon → Mask → Smooth Mask`

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
