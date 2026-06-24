# The Annotations Tool

!!! success "BigData mode: supported"
    Annotations work with **BigData** datasets (they are stored as coordinates, independent of resolution).

---

## Overview

![Annotations Tool](images/PanelsSegmentationToolsAnnotations.png){align=left}

Tools to add/remove annotations, marking specific locations with a label and a value.

- [:fontawesome-brands-youtube:{.red-color} MIB in brief: Annotations](https://youtu.be/3lARjx9dPi0)
- [:fontawesome-brands-youtube:{.red-color} MIB in brief: Annotations](https://youtu.be/6otBey1eJ0U)

<div class="clear-float"></div>

<div class="h4-like">Addition and removal of annotations</div>
  
- <mouse class="left"></mouse>: add an annotation at the mouse cursor.
- ++ctrl++ + <mouse class="left"></mouse>: remove the closest annotation.
- ++shift++ + <mouse class="left"></mouse>: interpolate annotations between the previous and new annotation across dataset depth.

---

## Annotation panel widgets
- <span class="widget widget-button">Annotation list</span> open a window listing annotations. Load/save to MATLAB workspace or file (MATLAB/Excel formats), [see below](#list-of-annotations).
- <span class="widget widget-edit">Precision</span> specify digits after the decimal point.
- <span class="widget widget-checkbox">Show prompt</span> show a dialog for label/value after adding an annotation; otherwise, use the previous annotation’s values. 
- <span class="widget widget-checkbox">Focus on Value</span> prioritize value over label during visualization. 
- <span class="widget widget-button">Delete All</span> remove all annotations.
- **Display as**: choose display mode in the [Image View panel](../../image-document/index.md):
      - **Marker**: show only a cross-marker.
      - **Label**: show marker and label.
      - **Value**: show marker and value.
      - **Label + Value**: show marker, label, and value.
---

## Presets
Use the following key shortcuts to define and restore presets

- ++shift+1++, ++shift+2++, ++shift+3++ - store preset 1, 2, or 3 correspondingly
- ++1++, ++2++, ++3++ - restore preset 1, 2, or 3 correspondingly

---

## List of annotations

![Annotations Table](images/PanelsSegmentationToolsAnnotationsTable.png){.on-glb align=left width="400"}

- **List of annotations table**: shows annotations.<br>

<div class="h4-like">Right-click (<mouse class="right"></mouse>) for options</div>

- **Jump to annotation**: center the selected annotation in the [Image View panel](../../image-document/index.md).
- **Add annotation**: manually add an annotation by manually specifying its position, value and name.
- **Rename selected annotations**: rename selected annotations.
- **Batch modify selected annotations**: modify values/coordinates with expressions (e.g., set, multiply, add).
![Annotations Table](images/PanelsSegmentationToolsAnnotationsBatch.png){.on-glb align=left width="320"}
- **Count selected annotations**: count occurrences, displayed in MATLAB and copied to clipboard. [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/rqZbH3Jpru8)
---

<div class="clear-float"></div>

- **Copy selected annotations to clipboard**: copy as text for Excel.
- **Paste from clipboard to column**: paste Excel values to a selected column.
  
- ![Convert to Mask](images/PanelsSegmentationToolsAnnotationsTableToMask.png){.on-glb align=right width="300"}
**Convert selected annotations to Mask**: generate 2D/3D Mask spots from annotations (fixed or scaled size).  
  
<div class="clear-float"></div>

- **Crop out patches around selected annotations**: generate 2D/3D patches with customizable options (e.g., jitter). [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/QrKHgP76_R0)

??? info "Crop patches dialog"

    ![Convert to Mask](images/PanelsSegmentationCropPatches.png){.on-glb align=left width="300"}

    Each patch is centred on an annotation coordinate. The dialog controls how large the patches are, where they go, and what layers are included.

    **Output destination**

    - **Crop to file** — saves each patch as a separate image file in the chosen directory.
      Supported formats: TIF (LZW or uncompressed), Amira Mesh binary (`*.am`), MRC for IMOD (`*.mrc`), NRRD (`*.nrrd`).
    - **Crop to MATLAB** — exports each patch as a struct into the MATLAB workspace under an auto-generated variable name.
      The struct contains `img` (pixel data), `pixSize` (voxel size), and optionally `Model` and `Mask` subfields.

    <div class="clear-float"></div>

    **Patch dimensions**

    - **Width, px** — total patch width in pixels (centred on the annotation X coordinate).
    - **Height, px** — total patch height in pixels (centred on the annotation Y coordinate).
    - **Crop 3D objects** checkbox — when checked, crops a 3D slab; the **Depth** field sets the number of slices centred on the annotation Z coordinate.

    **Filename options** *(file output only)*

    A dialog asks which components to append to the base filename:

    - annotation name
    - Z, X, or Y coordinate
    - slice name as the filename template (uses per-slice names from the dataset when available)

    **Include model / mask**

    - **Crop Model** — include a cropped copy of the model layer alongside each image patch; choose the save format from the adjacent dropdown.
    - **Crop Mask** — include a cropped copy of the mask layer; choose its format separately.

    **Jitter**

    Adds a random XY offset to each patch centre, useful for data augmentation:

    - **Variation** — maximum pixel offset in each direction (offset drawn from `±Variation`).
    - **Seed** — random seed for reproducibility; `0` uses a new random seed each run.

- ![Interpolate annotations across slices](images/PanelsSegmentationAnn-interpolate.png){.on-glb align=right width="320"}
**Interpolate between selected annotations**: interpolate annotations across slices (linear for two, linear/cubic/spline for more).
<div class="clear-float"></div>
- **Export selected annotations**:
    - export to MATLAB
    - Amira landmarks (coordinates only)
    - PSI format
    - Excel

- **Export selected annotations to Imaris**: export to Imaris (export dataset first) :material-information-outline:{.red-color title="Implemented but not tested" }.
- **Order**: move annotations up/down the list.
- **Delete selected annotation(s)**: delete selected annotations.

### Tools panel

![Convert to Mask](images/PanelsSegmentationAnn-tools.png){.on-glb align=left width="300}

- <span class="widget widget-button">Load</span> import annotations from MATLAB or a file.
- <span class="widget widget-button">Save</span> export to MATLAB, CSV, Excel, Amira landmarks (coordinates only), or PSI format. [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/wHr6nHpmVMo)

<div class="clear-float"></div>

- <span class="widget widget-edit">Precision</span> adjust value field precision.
- <span class="widget widget-checkbox">Auto jump</span> center the selected annotation in the [Image View panel](../../image-document/index.md).
- <span class="widget widget-dropdown">Sort table</span> sort by Name, Value, X, Y, Z, T.
- <span class="widget widget-button">Settings</span>:

![Annotations visualization settings](images/PanelsSegmentationToolsAnnotationsSettings.png){.on-glb align=left width="340"}

  - **Show annotations for extra slices**: set depth range (0 = current slice only).
  - **Annotation size**: set marker size (8–20pt).
  - **Annotation color**: select color.
<div class="clear-float"></div>
- <span class="widget widget-button">Refresh table</span> update the list.
- <span class="widget widget-button">Delete all</span> remove all annotations.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*