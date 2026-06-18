# ROI Panel

---

## Overview

The **ROI Panel** allows you to add one or more Regions of Interest (ROIs)
over your image for focused analysis or filtering. <br>
Updated in MIB version 0.998, this implementation uses code 
from Jan Neggers’ [Image Measurement Utility](http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility) 
(Eindhoven University of Technology).

![ROI Panel](images/PanelsROI.png){align=left}

<div class="clear-float"></div>

---

## Select ROI type and add it

![ROI Panel](images/PanelsROI-type.png){align=left}

<span class="widget widget-dropdown">ROI type</span>

Select the ROI type to add. By default, ROIs are placed interactively, but you can define them manually using the *Define parameters manually* panel below the dropdown.

<div class="clear-float"></div>

<div class="h4-like">Available ROI types:</div>

- **Rectangle**: Rectangular ROI. 
- **Ellipse**: Ellipsoid ROI. 
- **Polyline**: Polyline with a set number of vertices. 
- **Lasso**: Freehand ROI.  
    - release to convert to a polyline ROI with a suggested vertex reduction 
    (fewer vertices improve rendering performance).

??? info "How to place ROI"
    - press <span class="widget widget-button">Add</span> 
    - use <mouse class="left"></mouse> to place a ROI
    - use <mouse class="double"></mouse> to accept the ROI

### ROI List

![ROI Context Menu](images/PanelsROIContext.png){align=left}

Select single or all ROIs for filtering/analysis.

<div class="clear-float"></div>

### Settings and buttons

<span class="widget widget-button">Add</span> button: adds ROI of the selected type to the image

<span class="widget widget-button">Modify</span> button: modify ROI selected in **ROI List**

<span class="widget widget-button">Remove</span> button: deletes the highlighted ROI from the **ROI List**.

<span class="widget widget-button">Load</span> button: loads ROIs from disk.

<span class="widget widget-button">Save</span> button: saves ROI data to disk in MATLAB format (structure with `label`, `type`, `X`, `Y`, `orientation` fields).

<span class="widget widget-checkbox">Show ROI</span>: shows ROIs in the [Image View Panel](../../image-document/index.md) when checked. 
Alternatively, toggle visibility with the ![Image title](../../quick-access-bar/images/toolbar_roi.png){.off-glb } button in the [Toolbar](../../quick-access-bar/index.md#roi-mode-switch).

![ROI visualization options](images/PanelsROI-options.png){.on-glb align=right width="200"}

<span class="widget widget-button">Options</span>: customize ROI visualization (marker type/size/color, line width/color, label size/color).

<div class="clear-float"></div>

---

## Define parameters manually

![ROI Context Menu](images/PanelsROI_manual.png){align=left}

Enable manual ROI placement by checking 
<span class="widget widget-checkbox">Manually</span> and use:

- <span class="widget widget-edit">X1</span> to define X-coordinate of the top left corner
- <span class="widget widget-edit">Y1</span> to define Y-coordinate of the top left corner
- <span class="widget widget-edit">Width</span> to define width of the ROI
- <span class="widget widget-edit">Height</span> to define height of the ROI
- press <span class="widget widget-button">Add</span>.

<span class="widget widget-checkbox">Fix aspect</span>: locks the aspect ratio of ROIs during initial placement or later edits.

<span class="widget widget-button">ROI to Selection</span>: transfers the area under the current ROI to the Selection layer.

---

*Back to [MIB](../../../index.md) | [User Guide](../../index.md) | [Panels](../index.md)*