# Alignment and Drift Correction

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*

---

## Overview

The Alignment and Drift Correction tool can be used either to align slices of the 
opened dataset or to align two separate datasets.

<div class="h3-like">Demos and tutorials</div>

- [:fontawesome-brands-youtube:{.red-color} How to do image alignment](https://youtu.be/-qwoO5z02aA)
- [:fontawesome-brands-youtube:{.red-color} Multi-point landmarks](https://youtu.be/rlXoyZcTpJs)
- [:fontawesome-brands-youtube:{.red-color} Automatic feature-based](https://youtu.be/-en5zD5Ou9s)
- [:fontawesome-brands-youtube:{.red-color} Automatic feature-based using HDD mode](https://youtu.be/tpe9GhpS2o8)
- [:fontawesome-brands-youtube:{.red-color} HDD mode](https://youtu.be/FtvWjDUMZ1I) (Drift correction and Automatic feature-based only)

---

## Current dataset panel

![Current Dataset Panel](images/menuDatasetAlignTool_1.png){align=left}

<div class="clear-float"></div>

The *Current dataset panel* displays details of the currently opened dataset, such as its filename, dimensions, and pixel size.


---

## Align panel

![Align Panel](images/menuDatasetAlignTool_2.png){align=left}

The *Align panel* allows selection of main parameters for alignment and drift correction.

<div class="clear-float"></div>

- **The Mode panel**: selection of alignment mode
    - **Current dataset**: align the opened dataset.
      - **Two stacks**: align two stacks; the second stack can be loaded or imported from MATLAB.
- **Algorithm**: selection of method for alignment

### Algorithm: Drift correction

Translation correction; recommended for small shifts or comparably sized images. 
Also implemented for image files without loading into MIB (see *HDD mode*).

### Algorithm: Template matching

Translation correction; best for aligning two stacks when the second stack is smaller than the main stack. 
Not recommended for the currently opened stack.

### Algorithm: Automatic feature-based version 1 and 2

Automatic alignment based on features (blobs, regions, or corners) detected on 
consecutive slices. The features registered to find suitable transformation and the images are aligned using the detected transformation.<br> 
Version 2 (based on [estgeotform2d](https://se.mathworks.com/help/releases/R2024b/vision/ref/estgeotform2d.html)) 
is recommended.

<div class="h3-like">Demonstration</div>

* [:fontawesome-brands-youtube:{.red-color} Standard mode](https://youtu.be/-en5zD5Ou9s)
* [:fontawesome-brands-youtube:{.red-color} HDD mode](https://youtu.be/tpe9GhpS2o8)

**Transformations**:

- **Version 1**: based on [estimateGeometricTransform](https://www.mathworks.com/help/vision/ref/estimategeometrictransform.html) 
can be used to align datasets using following transformations:

    - 'similarity'
    - 'affine'
    - 'projective'
  
- **Version 2**: based on [estgeotform2d](https://se.mathworks.com/help/releases/R2024b/vision/ref/estgeotform2d.html):
    - *translation*: 2-D translation
    - *rigid*: nonreflective rigid (translation + rotation)
    - *similarity*: nonreflective similarity (translation + rotation + scaling)
    - *affine*: general affine<br>
  ([see more about various transformation types](https://se.mathworks.com/help/releases/R2024b/images/matrix-representation-of-geometric-transformations.html))
  
Results can be cropped (<span class="widget widget-dropdown">Mode: cropped</span>) to the first image’s size/position or extended (<span class="widget widget-dropdown">Mode: extended</span>). 

Use <span class="widget widget-button">Preview</span> to check and modify detection of points.<br> 
See [matchFeatures](https://se.mathworks.com/help/vision/ref/matchfeatures.html) for details.
Also implemented for HDD mode.<br>

**Feature detectors ([see more on different point feature types](https://se.mathworks.com/help/vision/ug/point-feature-types.html))**:

* **Blobs: Speeded-Up Robust Features ([SURF](https://se.mathworks.com/help/vision/ref/detectsurffeatures.html)) algorithm**: robust, fast, less effective for highly detailed targets (e.g., electrical boards)
* **Blobs: Detect scale invariant feature transform ([SIFT](https://se.mathworks.com/help/vision/ref/detectsiftfeatures.html))**: scale-invariant feature transform
* **Regions: Maximally Stable Extremal Regions ([MSER](https://se.mathworks.com/help/vision/ref/detectmserfeatures.html)) algorithm**: Maximally stable extremal regions (MSER) algorithm
* **Corners: [Harris-Stephens](https://se.mathworks.com/help/vision/ref/detectharrisfeatures.html) algorithm**: Harris-Stephens algorithm. More efficient than the minimum eigenvalue algorithm
* **Corners: Binary Robust Invariant Scalable Keypoints ([BRISK](https://se.mathworks.com/help/vision/ref/detectbriskfeatures.html))**: similar to ORB, slightly more CPU-intensive
* **Corners: Features from Accelerated Segment Test ([FAST](https://se.mathworks.com/help/vision/ref/detectfastfeatures.html))**: fast, extracts many keypoints, not rotation-invariant
* **Corners: [Minimum Eigenvalue](https://se.mathworks.com/help/vision/ref/detectmineigenfeatures.html) algorithm**: uses minimum eigenvalue metric to determine corner locations.
* **Oriented FAST and rotated BRIEF ([ORB](https://se.mathworks.com/help/vision/ref/detectorbfeatures.html))**: rotation-invariant (Oriented FAST and Rotated BRIEF), best for general use, comparable to SURF

### Algorithm: AMST: Alignment to Median Smoothed Template

compensates for slight local deformations in 3D electron microscopy datasets.<br>
Pre-align with Drift correction, then register against a median-smoothed Z copy.<br>
Based on [Hennies et al., 2020](https://www.nature.com/articles/s41598-020-58736-7).

[:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/MNt_Yzt4pw0)

- <span class="widget widget-edit">Median size</span>: number of Z-sections for smoothing
- <span class="widget widget-button">Settings</span>: configure parameters
(see [imregtform](https://se.mathworks.com/help/images/ref/imregtform.html))


### Algorithm: Single landmark point

Manual mode; mark corresponding areas on consecutive slices using the Brush tool (spot) or Annotations tool. 
Images are translated to align marked areas.

### Algorithm: Landmarks, multi points

Align based on multiple marked points using the Selection layer or Annotations (*recommended*). 
Corresponding points must have the same name.<br> 
[Transformation types](https://se.mathworks.com/help/images/matrix-representation-of-geometric-transformations.html):<br>
![Landmark Modes](images/menuDatasetAlignToolLandmarkModes.jpg){.on-glb align=left}


### Algorithm: Three landmark points

Manual mode; mark three corresponding areas on consecutive slices with the Brush tool.<br>
Images are translated/scaled/rotated to align.

!!! info "Recommendation"
    use [Landmarks, multi points](dataset-alignment.md#algorithm-landmarks-multi-points) instead!

### Algorithm: Color channels, multi points

Register individual color channels using Annotations (*Segmentation panel -> Annotations*):<br>
 
* annotation text identifies corresponding points
* annotation value identifies fixed (1) and transformed (2) channels
 
??? example "Color Channel alignment example"
    ![Color Channel alignment](images/menuDatasetAlignTool-colorchannels.jpg){.on-glb align=left}

<div class="clear-float"></div>

## Other settings

![Alignment tool settings](images/menuDatasetAlignTool-settings.png){align=left}

- <label class="widget widget-checkbox">HDD mode</label>: align files specified in <br> `Options->`<br>`HDD Mode (Image directories and formats)`<br> 
without loading into MIB.<br>Suitable for large image collections.<br> 
Only for "Drift correction" (*same size required*) and "Automatic feature-based" algorithms.
<div class="h3-like">Demonstrations:</div>
- [:fontawesome-brands-youtube:{.red-color} Drift correction](https://youtu.be/FtvWjDUMZ1I)
- [:fontawesome-brands-youtube:{.red-color} Feature-based](https://youtu.be/tpe9GhpS2o8)

<div class="clear-float"></div>

<span class="widget widget-dropdown">Correlate with</span>: reference slice options

  - **Previous slice**: align each slice to the previous one.
  - **First slice**: align all to the first Z-slice; good for drift correction with minimal dataset changes.
  - **Relative to**: align each slice to an earlier slice, defined by <span class="widget widget-edit">Step</span>.

<span class="widget widget-dropdown">Color channel</span>: select the color channel for alignment.

<label class="widget widget-checkbox">Use intensity gradient</label>: use intensity gradients instead of raw images for better alignment.

<span class="widget widget-dropdown">Background</span>: define background after alignment:

  - **White**: all background pixels white.
  - **Black**: all background pixels black.
  - **Mean**: average value of original dataset pixels.
  - **Custom**: specify a custom intensity.

---

## Options panel

![Options Panel](images/menuDatasetAlignTool_3.png){align=left}

Shown only during alignment of the currently opened dataset.

<div class="clear-float"></div>

<label class="widget widget-checkbox">Use Mask/Selection</label>: calculate correlation only from masked or selected areas. 
Use the Brush tool to select distinct areas on the first and last slices, 
then interpolate with ++i++ or<br>`Ribbon → Selection → Interpolate as Shape`.

<label class="widget widget-checkbox">Use subwindow</label>: speed up alignment for large uniform images. 
Define with <span class="widget widget-edit">minX</span>, <span class="widget widget-edit">minY</span>,
<span class="widget widget-edit">maxX</span>, <span class="widget widget-edit">maxY</span>, 
or <span class="widget widget-button">Get from Selection</span>.

<label class="widget widget-checkbox">Save/Load shifts to file</label>: save/load translation shifts to disk.

**HDD Mode (image directories and formats) panel**: used when *HDD Mode* is enabled

  - <span class="widget widget-dropdown">Extension</span>: file extension to align.
  - <label class="widget widget-checkbox">Bio</label>: enable Bio-Formats reader for microscope formats.
  - <span class="widget widget-edit">Index</span>: series index to load from a container [Bio-Formats only].
  - <span class="widget widget-button">...</span>: select directory with images.
  - **Output subfolder and extension**: specify output subfolder (relative to input) and file format.

---

## Second stack panel

![Second Stack Panel](images/menuDatasetAlignTool_4.png){align=left}

Shown only during alignment of two stacks. 

<div class="clear-float"></div>

- **Directory of images**: select directory with second stack images.
- <label class="widget widget-checkbox">Volume in a single file</label>: use if the second stack is in one file.
- <span class="widget widget-button">Import from MATLAB</span>: import a stack from MATLAB for alignment.
- <label class="widget widget-checkbox">Automatic mode</label>: align automatically; otherwise, manually set <span class="widget widget-edit">ShiftX</span> and <span class="widget widget-edit">ShiftY</span>.

---

## References and Acknowledgements

The alignment algorithm is based on:

- JC Russ, *The image processing handbook*, CRC Press, Boca Raton, FL, 1994.
- JD Sugar, AW Cummings, BW Jacobs, DB Robinson, *A Free MATLAB Script For Spatial Drift Correction*, Microscopy Today, Volume 22, Number 5, 2014. [Link](https://se.mathworks.com/matlabcentral/fileexchange/45453-drifty-shifty-deluxe-m)

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*
