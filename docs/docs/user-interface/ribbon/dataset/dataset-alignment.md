# Alignment and Drift Correction

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*

---

## Overview

The Alignment and Drift Correction tool aligns the slices of the currently opened dataset.

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

## Alignment algorithms

![Align Panel](images/menuDatasetAlignTool_2.png){align=left}

Select the alignment algorithm from the <span class="widget widget-dropdown">Algorithm</span> dropdown.

<div class="clear-float"></div>

### Drift correction

Translation correction; recommended for small shifts or comparably sized images.
Also implemented for image files without loading into MIB (see *HDD mode*).

### Template matching

Translation correction; best for aligning two stacks when the second stack is smaller than the main stack.
Not recommended for the currently opened stack.

### Automatic feature-based version 1 and 2

Automatic alignment based on features (blobs, regions, or corners) detected on
consecutive slices. The features are registered to find a suitable transformation and the images are aligned accordingly.<br>
Version 2 (based on [estgeotform2d](https://se.mathworks.com/help/releases/R2024b/vision/ref/estgeotform2d.html))
is recommended.

<div class="h3-like">Demonstration</div>

* [:fontawesome-brands-youtube:{.red-color} Standard mode](https://youtu.be/-en5zD5Ou9s)
* [:fontawesome-brands-youtube:{.red-color} HDD mode](https://youtu.be/tpe9GhpS2o8)

**Transformations**:

- **Version 1**: based on [estimateGeometricTransform](https://www.mathworks.com/help/vision/ref/estimategeometrictransform.html)
  supports: `similarity`, `affine`, `projective`

- **Version 2**: based on [estgeotform2d](https://se.mathworks.com/help/releases/R2024b/vision/ref/estgeotform2d.html):
    - *translation*: 2-D translation
    - *rigid*: nonreflective rigid (translation + rotation)
    - *similarity*: nonreflective similarity (translation + rotation + scaling)
    - *affine*: general affine<br>
  ([see more about various transformation types](https://se.mathworks.com/help/releases/R2024b/images/matrix-representation-of-geometric-transformations.html))

Results can be cropped (<span class="widget widget-dropdown">Mode: cropped</span>) to the first image's size/position or extended (<span class="widget widget-dropdown">Mode: extended</span>).

Use <span class="widget widget-button">Preview</span> to check and modify detection of points.<br>
See [matchFeatures](https://se.mathworks.com/help/vision/ref/matchfeatures.html) for details.
Also implemented for HDD mode.<br>

**Feature detectors ([see more on different point feature types](https://se.mathworks.com/help/vision/ug/point-feature-types.html))**:

* **Blobs: Speeded-Up Robust Features ([SURF](https://se.mathworks.com/help/vision/ref/detectsurffeatures.html))**: robust, fast, less effective for highly detailed targets (e.g., electrical boards)
* **Blobs: Detect scale invariant feature transform ([SIFT](https://se.mathworks.com/help/vision/ref/detectsiftfeatures.html))**: scale-invariant feature transform
* **Regions: Maximally Stable Extremal Regions ([MSER](https://se.mathworks.com/help/vision/ref/detectmserfeatures.html))**: Maximally stable extremal regions algorithm
* **Corners: [Harris-Stephens](https://se.mathworks.com/help/vision/ref/detectharrisfeatures.html)**: more efficient than the minimum eigenvalue algorithm
* **Corners: Binary Robust Invariant Scalable Keypoints ([BRISK](https://se.mathworks.com/help/vision/ref/detectbriskfeatures.html))**: similar to ORB, slightly more CPU-intensive
* **Corners: Features from Accelerated Segment Test ([FAST](https://se.mathworks.com/help/vision/ref/detectfastfeatures.html))**: fast, extracts many keypoints, not rotation-invariant
* **Corners: [Minimum Eigenvalue](https://se.mathworks.com/help/vision/ref/detectmineigenfeatures.html)**: uses minimum eigenvalue metric to determine corner locations
* **Oriented FAST and rotated BRIEF ([ORB](https://se.mathworks.com/help/vision/ref/detectorbfeatures.html))**: rotation-invariant, best for general use, comparable to SURF

### AMST: Alignment to Median Smoothed Template

Compensates for slight local deformations in 3D electron microscopy datasets.<br>
Pre-align with Drift correction, then register against a median-smoothed Z copy.<br>
Based on [Hennies et al., 2020](https://www.nature.com/articles/s41598-020-58736-7).

[:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/MNt_Yzt4pw0)

- <span class="widget widget-edit">Median size</span>: number of Z-sections for smoothing.
- <span class="widget widget-button">Settings</span>: configure parameters (see [imregtform](https://se.mathworks.com/help/images/ref/imregtform.html)).

### Single landmark point

Manual mode; mark corresponding areas on consecutive slices using the Brush tool (spot) or Annotations tool.
Images are translated to align marked areas.

### Landmarks, multi points

Align based on multiple marked points using the Selection layer or Annotations (*recommended*).
Corresponding points must have the same name.<br>
[Transformation types](https://se.mathworks.com/help/images/matrix-representation-of-geometric-transformations.html):<br>
![Landmark Modes](images/menuDatasetAlignToolLandmarkModes.jpg){.on-glb align=left}

<div class="clear-float"></div>

### Three landmark points

Manual mode; mark three corresponding areas on consecutive slices with the Brush tool.<br>
Images are translated/scaled/rotated to align.

!!! info "Recommendation"
    Use [Landmarks, multi points](#landmarks-multi-points) instead.

### Color channels, multi points

Register individual color channels using Annotations (*Segmentation panel → Annotations*):

* annotation text identifies corresponding points
* annotation value identifies fixed (1) and transformed (2) channels

??? example "Color Channel alignment example"
    ![Color Channel alignment](images/menuDatasetAlignTool-colorchannels.jpg){.on-glb align=left}

<div class="clear-float"></div>

---

## Alignment details

![Alignment tool settings](images/menuDatasetAlignTool-settings.png){align=left}

<div class="clear-float"></div>

- <label class="widget widget-checkbox">HDD mode</label>: align files specified in
  `Options → HDD Mode (Image directories and formats)`
  without loading into MIB. Suitable for large image collections.<br>
  Only for "Drift correction" (*same size required*) and "Automatic feature-based" algorithms.

<div class="h3-like">Demonstrations:</div>

- [:fontawesome-brands-youtube:{.red-color} Drift correction](https://youtu.be/FtvWjDUMZ1I)
- [:fontawesome-brands-youtube:{.red-color} Feature-based](https://youtu.be/tpe9GhpS2o8)

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

<div class="clear-float"></div>

<span class="widget widget-dropdown">Subarea</span>: defines the image area used to calculate alignment shifts:

- **Full image**: use the entire image (default).
- **Manually specified**: restrict to a sub-region defined by <span class="widget widget-edit">minX</span>, <span class="widget widget-edit">minY</span>, <span class="widget widget-edit">maxX</span>, <span class="widget widget-edit">maxY</span>, or <span class="widget widget-button">Get from Selection</span>.
- **Selection**: calculate from selected areas only. Use the Brush tool to mark distinct areas on the first and last slices, then interpolate with ++i++ or `Ribbon → Selection → Interpolate as Shape`.
- **Mask**: calculate from masked areas only.

<label class="widget widget-checkbox">Save/Load shifts to file</label>: save/load translation shifts to disk.

**HDD Mode (image directories and formats) panel**: used when *HDD Mode* is enabled

  - <span class="widget widget-dropdown">Extension</span>: file extension to align.
  - <label class="widget widget-checkbox">Bio</label>: enable Bio-Formats reader for microscope formats.
  - <span class="widget widget-edit">Index</span>: series index to load from a container \[Bio-Formats only\].
  - <span class="widget widget-button">...</span>: select directory with images.
  - **Output subfolder and extension**: specify output subfolder (relative to input) and file format.

---

## References and Acknowledgements

The alignment algorithm is based on:

- JC Russ, *The image processing handbook*, CRC Press, Boca Raton, FL, 1994.
- JD Sugar, AW Cummings, BW Jacobs, DB Robinson, *A Free MATLAB Script For Spatial Drift Correction*, Microscopy Today, Volume 22, Number 5, 2014. [Link](https://se.mathworks.com/matlabcentral/fileexchange/45453-drifty-shifty-deluxe-m)

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*
