# Adjust Display Window

---

## Overview

![Adjust Display Window](images/PanelsViewSettingsDisplay.png){align=left}

The **Adjust Display window** lets you fine-tune the contrast of your dataset for each color channel individually. A histogram at the bottom shows intensity values for the currently displayed slice, helping you visualize adjustments.

- [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/WhpzGMyslZU)

<div class="clear-float"></div>

---

## List of widgets

- <span class="widget widget-dropdown">Color channel</span>: choose the color channel to adjust.
- **Min slider and edit box** (*define the black point*)  
  ![Min Slider](images/panelsDisplayAdj_min.png){align=left}  
  Sets the black point; intensities below this are rendered black.  
     - <mouse class="right"></mouse> on the slider sets it to 1.  
     - <mouse class="left"></mouse> on the histogram sets this value.
     - - Enter values (including negative) directly in the edit box.
  <div class="clear-float"></div>
  - <span class="widget widget-button">Min button</span>: assigns the channel’s minimal intensity as black.  
     - <mouse class="right"></mouse> on the button opens a menu to exclude a percentage of low-intensity points.  
  
- **Max slider and edit box** (*define the white point*)  
  ![Max Slider](images/panelsDisplayAdj_max.png){align=left}  
  Sets the white point; intensities above this are rendered white or pure color.  
     - <mouse class="right"></mouse> on the slider sets it to the maximum for the image class.  
     - <mouse class="right"></mouse> on the histogram sets this value.
     - Enter values (including above max) in the edit box.
  <div class="clear-float"></div>

  - <span class="widget widget-button">Max button</span>: assigns the channel’s maximal intensity as white.  
     - <mouse class="right"></mouse> on the button opens a menu to define the white point from the histogram.  
  
- **Gamma**: adjusts gamma: <1 enhances high intensities, >1 enhances low intensities.  
     - <mouse class="right"></mouse> on the slider sets it to 1.
- <span class="widget widget-checkbox">Link</span>: links all channels so Min/Max/Gamma changes apply to all simultaneously.
- <span class="widget widget-checkbox">Log</span>: switches histogram between linear and logarithmic scales.
- <span class="widget widget-checkbox">Auto update</span>: enables automatic histogram updates after each slice change.  
- <span class="widget widget-button">Update</span>: updates the histogram for the current slice.
- <span class="widget widget-button">Current</span>: recalculates intensities for the selected channel on the current slice using specified parameters.  
- <span class="widget widget-button">All slices</span>: recalculates intensities for the selected channel across all slices using specified parameters.

---

## Histogram 

The histogram plots intensity values (X-axis) against pixel counts 
(Y-axis) for the image shown in the [Image Document](../../image-document/index.md) — not the full slice. 
!!! warning
    Adjustments to **Gamma** are not reflected here.

Set **Min** and **Max** values for the histogram via:

- Manual entry in the edit boxes.
- Slider adjustments.
- <mouse class="left"></mouse> (to set the minimum intensity, i.e. the black point) 
or <mouse class="right"></mouse> (to set the maximum intensity, i.e. the white point) clicks on the histogram.

---

*Back to [MIB](../../../index.md) | [User Guide](../../index.md) | [Panels](../index.md) | [View Settings](index.md)*