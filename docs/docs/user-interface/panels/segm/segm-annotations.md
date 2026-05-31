# The Annotations Tool

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*

---

## Overview

![Annotations Tool](images/PanelsSegmentationToolsAnnotations.png){align=left}

Tools to add/remove annotations, marking specific locations with labels and values.

- [:fontawesome-brands-youtube:{.red-color} MIB in brief: Annotations](https://youtu.be/3lARjx9dPi0)
- [:fontawesome-brands-youtube:{.red-color} MIB in brief: Annotations](https://youtu.be/6otBey1eJ0U)

<div class="clear-float"></div>

<div class="h4-like">Addition and removal of annotations</div>
  
- <mouse class="left"></mouse>: add an annotation at the mouse cursor.
- ++ctrl++ + <mouse class="left"></mouse>: remove the closest annotation.
- ++shift++ + <mouse class="left"></mouse>: interpolate annotations between the previous and new annotation across dataset depth.

## Annotation panel widgets
- <span class="widget widget-button">Annotation list</span> open a window listing annotations. Load/save to MATLAB workspace or file (MATLAB/Excel formats), [see below](#list-of-annotations).
- <span class="widget widget-button">Delete All</span> remove all annotations.
- <span class="widget widget-edit">Precision</span> specify digits after the decimal point.
- <span class="widget widget-checkbox">Show prompt</span> show a dialog for label/value after adding an annotation; otherwise, use the previous annotation’s values.
- <span class="widget widget-checkbox">Focus on Value</span> prioritize value over label during visualization.
- **Display as**: choose display mode in the [Image View panel](../imview/index.md):
      - **Marker**: show only a cross-marker.
      - **Label**: show marker and label.
      - **Value**: show marker and value.
      - **Label + Value**: show marker, label, and value.

## List of annotations

![Annotations Table](images/PanelsSegmentationToolsAnnotationsTable.png){.on-glb align=left width="400"}

- **List of annotations table**: shows annotations.<br>

<div class="h4-like">Right-click (<mouse class="right"></mouse>) for options</div>

- **Jump to annotation**: center the selected annotation in the [Image View panel](../imview/index.md).
- **Add annotation**: manually add an annotation by manually specifying its position, value and name.
- **Rename selected annotations**: rename selected annotations.
- **Batch modify selected annotations**: modify values/coordinates with expressions (e.g., set, multiply, add).
- **Count selected annotations**: count occurrences, displayed in MATLAB and copied to clipboard. [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/rqZbH3Jpru8)
---

<div class="clear-float"></div>

- **Copy selected annotations to clipboard**: copy as text for Excel.
- **Paste from clipboard to column**: paste Excel values to a selected column.
  
- ![Convert to Mask](images/PanelsSegmentationToolsAnnotationsTableToMask.png){.on-glb align=left width="300"}
**Convert selected annotations to Mask**: generate 2D/3D Mask spots from annotations (fixed or scaled size).  
  
<div class="clear-float"></div>

- **Crop out patches around selected annotations**: generate 2D/3D patches with customizable options (e.g., jitter). [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/QrKHgP76_R0)
- ![Interpolate annotations across slices](images/PanelsSegmentationAnn-interpolate.png){align=left}
**Interpolate between selected annotations**: interpolate annotations across slices (linear for two, linear/cubic/spline for more).
<div class="clear-float"></div>
- **Export selected annotations**:
    - export to MATLAB
    - Amira landmarks (coordinates only)
    - PSI format
    - Excel

- **Export selected annotations to Imaris**: export to Imaris (export dataset first).
- **Order**: move annotations up/down the list.
- **Delete annotation**: delete selected annotations.

### Tools panel

![Convert to Mask](images/PanelsSegmentationAnn-tools.png){.on-glb align=left width="300}

- <span class="widget widget-button">Load</span> import annotations from MATLAB or a file.
- <span class="widget widget-button">Save</span> export to MATLAB, CSV, Excel, Amira landmarks (coordinates only), or PSI format. [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/wHr6nHpmVMo)

<div class="clear-float"></div>

- <span class="widget widget-edit">Precision</span> adjust value field precision.
- <span class="widget widget-checkbox">Auto jump</span> center the selected annotation in the [Image View panel](../imview/index.md).
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
## Presets
Use the following key shortcuts to define and restore presets

- ++shift+1++, ++shift+2++, ++shift+3++ - store preset 1, 2, or 3 correspondingly
- ++1++, ++2++, ++3++ - restore preset 1, 2, or 3 correspondingly

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*