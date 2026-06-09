# Measure Tool

---

## Overview

Based on the [Image Measurement Utility](http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility) by Jan Neggers, Eindhoven University of Technology. This tool enables various length measurements and generates corresponding intensity profiles.

![Measure Tool](images/menuToolsMeasureTool.png){.on-glb align=left width="300"}

!!! note
    Visualization of measurements can be switched on/off using 
    the <label class="widget widget-checkbox">Ann/Measure</label> checkbox in 
    the [View Settings panel](../../panels/selection_imview/viewsettings.md).

<div class="clear-float"></div>

---

## Measure panel

![Measure Tool -> Measure panel](images/menuToolsMeasure-measurepanel.png){ align=left}

Defines the measurement type, started with the <span class="widget widget-button">Add</span> button. 
<br>Select the color channel for intensity profiles via the <span class="widget widget-dropdown">Color channel</span> combo box.

<div class="clear-float"></div>

### Examples of tools for manual measurement

* **Angle**: measures the angle between two lines.  
  ![Angle](images/menuToolsMeasureOverviewAngle.jpg){.on-glb align=left}  
  a) place the intersection point;  
  b) place the second point to form the first line with the intersection;  
  c) place the third point to form the second line with the intersection;  
  d) adjust if needed; double-click above the line to accept.

<div class="clear-float"></div>

* **Caliper**: measures the perpendicular distance from a line to a point.  
  ![Caliper](images/menuToolsMeasureOverviewCaliper.jpg){.on-glb align=left}  
  a) place two points to define the line;  
  b) adjust if needed; double-click above the line to accept;  
  c) place the point;  
  d) adjust if needed; double-click above the point to accept.

<div class="clear-float"></div>

* **Circle**: measures the radius of a circle.  
  ![Circle](images/menuToolsMeasureOverviewCircle.jpg){.on-glb align=left}  
  a) place a point at the circle’s center;  
  b) place a point at the edge;  
  c) adjust if needed; double-click above the circle to accept.

<div class="clear-float"></div>

* **Distance (freehand)**: measures the length of a path.  
  ![Freehand](images/menuToolsMeasureOverviewFreehand.jpg){.on-glb align=left}  
  a) select interpolation type with the <span class="widget widget-dropdown">Interpolation</span> combo box;  
  b) press <span class="widget widget-button">Add</span>;  
  c) draw the path;  
  d) convert to polyline, providing a factor to reduce vertices;  
  e) adjust if needed; double-click above the path to accept.

<div class="clear-float"></div>

* **Distance (linear)**: measures the distance between two points.  
  ![Linear](images/menuToolsMeasureOverviewLinear.jpg){.on-glb align=left}  
  a) place the first point;  
  b) place the second point;  
  c) adjust if needed; double-click above the line to accept.

<div class="clear-float"></div>

* **Distance (polyline)**: measures a path with a set number of vertices.  
  ![Polyline](images/menuToolsMeasureOverviewFreehand.jpg){.on-glb align=left}  
  a) set vertex count with the <span class="widget widget-edit">Number of points</span> edit box;  
  b) select interpolation type with the <span class="widget widget-dropdown">Interpolation</span> combo box;  
  c) press <span class="widget widget-button">Add</span>;  
  d) place the defined number of points;  
  e) adjust if needed; press ++a++ and use the left mouse button to add a vertex, then double-click above the path to accept.

<div class="clear-float"></div>

- **Point**: places a single point.  
  ![Point](images/menuToolsMeasureOverviewPoint.jpg){.on-glb align=left}  
  a) place a point;  
  b) adjust if needed; double-click above the point to accept.

<div class="clear-float"></div>

- <label class="widget widget-checkbox">Fine-tuning</label>: allows position adjustments during placement.
- <label class="widget widget-checkbox">Calculate intensities</label>: generates an intensity profile for each measurement.
- <span class="widget widget-checkbox">Edit info</span>: automatically show a dialog to provide additional information related to an added measurement
- <span class="widget widget-checkbox">Preview intensity</span> (Distance, linear only): shows an intensity profile during placement.
- <span class="widget widget-button">Integrate</span> (Distance, linear only): integrates multiple points for intensity profiles, with point count set via the <span class="widget widget-edit">Width</span> edit box.
- <label class="widget widget-checkbox">fixed number of points</label> (freehand mode only): skips the vertex reduction dialog.
- <span class="widget widget-edit">Number of points</span> (freehand and polyline modes): sets the number of points to place.

---

## Plot panel

![Plot panel](images/menuToolsMeasure-plotpanel.png){.on-glb align=left}  

Controls which measurement parts display in the [Image View panel](../../panels/selection_imview/imview.md). 
<br>Customize line and marker appearance with the <span class="widget widget-button">Options</span> button.

<div class="clear-float"></div>
---

## Voxel sizes panel

![Plot panel](images/menuToolsMeasure-voxelpanel.png){.on-glb align=left}

Shows voxel dimensions of the dataset. Update them with 
the <span class="widget widget-button">Update</span> button.

<div class="clear-float"></div>

---

## Results panel

![Context Menu](images/menuToolsMeasureContext.png){.on-glb align=left width="400"}

Displays measurement results.<br> Filter types with 
the <span class="widget widget-dropdown">Filter</span> combo box. 
<br>Intensity profiles for selected measurements appear in a plot below the table. 
<br>With <label class="widget widget-checkbox">Jump on selection</label> checked, 
the [Image View panel](../../panels/selection_imview/imview.md) centers on the selected measurement.

<div class="clear-float"></div>

<div class="h3-like">Right-click a selected item for a context menu:</div>

- **Jump to measurement**: centers the selected measurement in the [Image View panel](../../panels/selection_imview/imview.md).
- **Modify measurement**: enters edit mode to adjust shape and size.
- **Recalculate selected measurements...**: updates distances and intensity profiles if pixel size or color channels change.
- **Duplicate measurement**: duplicates the measurement.
- **Generate kymograph**: creates a depth projection image under the profile (linear, polyline, freehand only), previewable or savable in TIF, MATLAB, or CSV formats. [:fontawesome-brands-youtube:{.red-color} Tutorial](https://youtu.be/ifr6bWtcnUg)
- **Plot intensity profile**: plots intensity profile in a new figure.
- **Delete measurement**: removes the measurement from the list.

---

## Buttons at the bottom of the window

![Measure tool -> buttons](images/menuToolsMeasure-bottom.png){.on-glb align=left}

<div class="clear-float"></div>

- <span class="widget widget-button">Load</span>: loads a measurement structure from a file or MATLAB workspace.
- <span class="widget widget-button">Save</span>: saves measurements and intensity profiles to a file (MATLAB or Excel) or MATLAB workspace.
- <span class="widget widget-button">Refresh table</span>: refreshes the measurement table.
- <span class="widget widget-button">Delete all</span>: removes all measurements.
- <span class="widget widget-button">?</span>: opens this help page.
- <span class="widget widget-button">Add</span>: adds a new measurement of the type selected in the *Measure panel*.
!!! note
    you can use ++m++ key shortcut to start selected measurement

- <span class="widget widget-button">Close</span>: closes the tool.

---

## Reference

- [Image Measurement Utility by Jan Neggers](http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility/)

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Tools](index.md)*


