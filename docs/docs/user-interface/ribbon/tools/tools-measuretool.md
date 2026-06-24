# Measure Tool

## Overview

![Measure Tool](images/menuToolsMeasureTool.png){.on-glb align=left width="300"}

Based on the [Image Measurement Utility](http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility) by Jan Neggers, Eindhoven University of Technology. This tool enables various length measurements and generates corresponding intensity profiles.

!!! note
    Visualization of measurements can be switched on/off using 
    the <label class="widget widget-checkbox">Ann/Measure</label> checkbox in 
    the [View Settings panel](../../panels/selection_imview/viewsettings.md).

<div class="clear-float"></div>

---

## Measure panel

![Measure Tool -> Measure panel](images/menuToolsMeasure-measurepanel.png){.on-glb align=left width="340"}

Defines the measurement type, started with the <span class="widget widget-button">Add</span> button.

<div class="clear-float"></div>

- <span class="widget widget-dropdown">Type</span>: measurement type —
  *Angle*, *Caliper*, *Circle (R)*, *Distance (freehand)*, *Distance (linear)*, *Distance (polyline)*, *Point*.
- <span class="widget widget-dropdown">Color channel</span>: color channel used for intensity profiles.
- <label class="widget widget-checkbox">Fine-tuning</label>: allows position adjustment of each vertex during placement before accepting.
- <label class="widget widget-checkbox">Calculate intensity</label>: generates an intensity profile along each measurement.
- <label class="widget widget-checkbox">Show info dialog</label>: after placing a measurement, prompts for an annotation text label.
- <label class="widget widget-checkbox">Preview intensity</label> (*Distance, linear* only): shows a live intensity profile while drawing the line.
- <label class="widget widget-checkbox">Integrate</label> (*Distance, linear* only): laterally integrates the intensity profile across the line.
  Set the integration half-width with the <span class="widget widget-edit">Width</span> edit box.
- <label class="widget widget-checkbox">automatic point spacing</label> (*Distance, freehand* only): when checked, the freehand path is automatically simplified (every 10th raw point is kept). When unchecked, a dialog prompts for a density reduction factor.
- <span class="widget widget-dropdown">Interpolation</span> (*Distance, freehand* and *Distance, polyline* only): spline interpolation method used to compute the path arc-length.


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

* **Circle (R)**: measures the radius of a circle.  
  ![Circle](images/menuToolsMeasureOverviewCircle.jpg){.on-glb align=left}  
  a) place a point at the circle’s center;  
  b) place a point at the edge;  
  c) adjust if needed; double-click above the circle to accept.

<div class="clear-float"></div>

* **Distance (freehand)**: measures the length of a path.  
  ![Freehand](images/menuToolsMeasureOverviewFreehand.jpg){.on-glb align=left}  
  a) select interpolation type with the <span class="widget widget-dropdown">Interpolation</span> combo box;  
  b) press <span class="widget widget-button">Add</span>;  
  c) draw the freehand path;  
  d) if <label class="widget widget-checkbox">automatic point spacing</label> is unchecked,
     enter a density reduction factor to simplify the path;  
  e) adjust if needed; double-click above the path to accept.

<div class="clear-float"></div>

* **Distance (linear)**: measures the distance between two points.  
  ![Linear](images/menuToolsMeasureOverviewLinear.jpg){.on-glb align=left}  
  a) place the first point;  
  b) place the second point;  
  c) adjust if needed; double-click above the line to accept.

<div class="clear-float"></div>

* **Distance (polyline)**: measures a path defined by a series of clicked vertices.  
  ![Polyline](images/menuToolsMeasureOverviewFreehand.jpg){.on-glb align=left}  
  a) select interpolation type with the <span class="widget widget-dropdown">Interpolation</span> combo box;  
  b) press <span class="widget widget-button">Add</span>;  
  c) click to place vertices;  
  d) adjust if needed; double-click above the path to accept.

<div class="clear-float"></div>

- **Point**: places a single point.  
  ![Point](images/menuToolsMeasureOverviewPoint.jpg){.on-glb align=left}  
  a) place a point;  
  b) adjust if needed; double-click above the point to accept.

<div class="clear-float"></div>

---

## Plot panel

![Plot panel](images/menuToolsMeasure-plotpanel.png){.on-glb align=left}  

Controls which measurement parts are drawn on the image.

- <label class="widget widget-checkbox">Markers</label>: show vertex markers (dots) for each measurement.
- <label class="widget widget-checkbox">Lines</label>: show the measurement lines or paths.
- <label class="widget widget-checkbox">Text</label>: show the numeric result and annotation label next to each measurement.
- <span class="widget widget-button">Options</span>: opens a dialog to customise line width, marker size, and color for each measurement type.

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
the [Image View panel](../../image-document/index.md) centers on the selected measurement.

<div class="clear-float"></div>

<span class="widget widget-button">Refresh table</span>: refreshes the measurement table.

<div class="h3-like">Right-click a selected item for a context menu:</div>

- **Modify info...**: edits the annotation text label stored with the measurement.
- **Jump to measurement**: centers the selected measurement in the [Image View panel](../../image-document/index.md).
- **Modify measurement...**: enters edit mode to reposition vertices and adjust the shape.
- **Recalculate selected...**: recomputes distances and intensity profiles for the selected measurement (useful after pixel size or color channel changes).
- **Duplicate measurement**: duplicates the selected measurement.
- **Generate kymograph (line, polyline)**: creates a depth projection image beneath the profile for linear, polyline, or freehand measurements. Previewable or savable in TIF, MATLAB, or CSV formats. [:fontawesome-brands-youtube:{.red-color} Tutorial](https://youtu.be/ifr6bWtcnUg)
- **Plot intensity profile...**: opens the intensity profile in a new figure.
- **Delete measurement**: removes the measurement from the list.

---

## Buttons at the bottom of the window

![Measure tool -> buttons](images/menuToolsMeasure-bottom.png){.on-glb align=left}

<div class="clear-float"></div>

- <span class="widget widget-button">Load</span>: loads a measurement structure from a file or MATLAB workspace.
- <span class="widget widget-button">Save</span>: saves measurements and intensity profiles to a file (MATLAB or Excel) or MATLAB workspace.
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


