# ROI Panel

---

## Overview

![ROI Panel](images/PanelsROI.png){align=left}

The **ROI Panel** allows you to add one or more Regions of Interest (ROIs)
over your image for focused analysis or filtering. <br>
Updated in MIB version 0.998, this implementation uses code 
from Jan Neggers’ [Image Measurement Utility](http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility) 
(Eindhoven University of Technology).

<div class="clear-float"></div>

---

## Select ROI type and add it

![ROI Panel](images/PanelsROI-type.png){align=left}

<span class="widget widget-dropdown">ROI type</span>

Select the ROI type to add. By default, ROIs are placed interactively, but you can define them manually using the *Define parameters manually* panel below the dropdown.

<div class="clear-float"></div>

<div class="h4-like">Available ROI types:</div>

- **Rectangle**: Rectangular ROI. 
    - press <span class="widget widget-button">Add</span>, 
    - define two corners with <mouse class="left"></mouse>, 
    - adjust as needed, and 
    - double-click to accept.
- **Ellipse**: Ellipsoid ROI. 
    - press <span class="widget widget-button">Add</span>, 
    - define the center and a side with <mouse class="left"></mouse>, 
    - adjust, and 
    - double-click to accept.
- **Polyline**: Polyline with a set number of vertices (specified in *Define parameters manually*). 
    - press <span class="widget widget-button">Add</span>, 
    - click for each vertex, 
    - adjust (add vertices with <span class="widget widget-button">A</span> + <mouse class="left"></mouse>, remove with <mouse class="right"></mouse> → <span class="widget widget-button">Delete</span>), 
    - and double-click to accept.
- **Lasso**: Freehand ROI. 
    - press <span class="widget widget-button">Add</span>, 
    - hold <mouse class="left"></mouse> to draw, 
    - release to convert to a polyline ROI with a suggested vertex reduction 
    (fewer vertices improve rendering performance).

<div class="h3-like">Define parameters manually</div>

Enable manual ROI placement by checking 
<span class="widget widget-checkbox">Manually</span>:

- enter coordinates, 
- press <span class="widget widget-button">Add</span>.

<span class="widget widget-checkbox">Fix aspect ratio</span>: locks the aspect ratio of ROIs during initial placement or later edits.

---

## ROI List

![ROI Context Menu](images/PanelsROIContext.png){align=left}

Select single or all ROIs for filtering/analysis. 

<div class="h3-like"><mouse class="right"></mouse> for additional actions:</div>

- **Rename**: Change the ROI’s name.
- **Edit**: Modify the ROI’s position (double-click to finish; add vertices to polylines with <span class="widget widget-button">A</span>).
- **Remove**: Delete the ROI from the list.

<div class="clear-float"></div>

![ROI visualization options](images/PanelsROI-options.png){.on-glb align=left width="200"}

<span class="widget widget-button">Options</span>: customize ROI visualization (marker type/size/color, line width/color, label size/color).

<div class="clear-float"></div>

---

## Settings and buttons

![ROI Context Menu](images/PanelsROI-buttons.png){align=left}

- <span class="widget widget-button">Add</span> button: adds the selected ROI to the image.
- <span class="widget widget-button">Remove</span> button: deletes the highlighted ROI from the **ROI List**.
- <span class="widget widget-button">ROI to Selection</span> button: transfers the area under the current ROI to the Selection layer.
- <span class="widget widget-button">Load</span> button: loads ROIs from disk.
- <span class="widget widget-button">Save</span> button: saves ROI data to disk in MATLAB format (structure with `label`, `type`, `X`, `Y`, `orientation` fields).

<div class="clear-float"></div>

- <span class="widget widget-checkbox">Show label</span>: displays ROI labels in the [Image View Panel](../../image-document/index.md) when checked.
- <span class="widget widget-checkbox">Show ROI</span>: shows ROIs in the [Image View Panel](../../image-document/index.md) when checked. 
Alternatively, toggle visibility with the <span class="widget widget-button">R</span> 
button in the [Toolbar](../../quick-access-bar/index.md#roi-mode-switch).

---

---

*Back to [MIB](../../../index.md) | [User Guide](../../index.md) | [Panels](../index.md)*