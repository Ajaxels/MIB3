# Black and White Thresholding

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*

---

## Overview

![BW Thresholding Tool](images/PanelsSegmentationToolsBWThres.png){align=left}

Performs black-and-white thresholding on the current slice or dataset, depending on <span class="widget widget-checkbox">3D</span> and 
<span class="widget widget-checkbox">4D</span>.

<br>Start thresholding modifying slider/edit box values or by pressing <span class="widget widget-button">Threshold</span>.

- [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/ZcJQb59YzUA?t=4m37s)

<div class="clear-float"></div>

## Parameters and controls
Use the <span class="widget widget-edit">Low</span> and <span class="widget widget-edit">High</span>
sliders/edit boxes to set threshold values, selecting pixels with intensities between them. Thresholding starts automatically upon interaction.

If <span class="widget widget-checkbox">Masked area</span> is checked, thresholding is limited to masked areas, ideal for local thresholding.

![BW Thresholding Tool](images/PanelsSegmentationBWthres-sliders.png){align=left}
Right-click (<mouse class="right"></mouse>) on sliders opens a popup menu to set precision for slider movement.

<div class="clear-float"></div>

The <span class="widget widget-checkbox">Adaptive</span> checkbox enables adaptive thresholding with 
<span class="widget widget-edit">Sensitivity</span> and <span class="widget widget-edit">Width</span> parameters adjusted by scroll bars.

!!! tips "Usage notes"  
    For large 3D/4D datasets: 

    - Start in 2D mode (uncheck <span class="widget widget-checkbox">3D</span> and <span class="widget widget-checkbox">4D</span>).
    - Adjust parameters on the current slice.
    - Check <span class="widget widget-checkbox">3D</span> or <span class="widget widget-checkbox">4D</span> when ready.
    - Press <span class="widget widget-button">Threshold</span> to apply.

---

## Presets
Use the following key shortcuts to define and restore presets

- ++shift+1++, ++shift+2++, ++shift+3++ - store preset 1, 2, or 3 correspondingly
- ++1++, ++2++, ++3++ - restore preset 1, 2, or 3 correspondingly

---
*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*