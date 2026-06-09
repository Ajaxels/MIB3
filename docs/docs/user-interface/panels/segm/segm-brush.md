# The Brush Tool

---

## Overview

![Brush Tool](images/PanelsSegmentationToolsBrush.png){align=left}

Use the brush to make selections, with size regulated by the <span class="widget widget-edit">Radius, px</span> edit box<br>

- [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/VlTCxVAUxFc)
- [:fontawesome-brands-youtube:{.red-color} MIB in brief: Manual segmentation tools](https://youtu.be/ZcJQb59YzUA?t=37s)

<div class="clear-float"></div>

???+ info "Controls"
    - <span class="widget widget-button">Ctrl</span> + **Mouse wheel**: change brush size.
    - **None** or <span class="widget widget-button">Shift</span> + <mouse class="left"></mouse>: paint with brush.
    - <span class="widget widget-button">Ctrl</span> + <mouse class="left"></mouse>: start eraser (radius amplified by <span class="widget widget-dropdown">Eraser, x</span>).
    - <span class="widget widget-checkbox">Auto fill</span> in the [Selection panel](../selection/index.md): autofill areas after brushing.

!!! tip
    Connect objects across slices using *Interpolation* (<span class="widget widget-button">i</span> shortcut or 
    [Ribbon → Selection -> Interpolate](../../ribbon/selection/index.md#interpolate)).


## Widgets of the brush panel

- **Radius**: define brush radius in pixels.
- **Eraser, x**: define eraser size multiplier.
- ![Interpolation Settings](images/PanelsSegmentationToolsBrushInterpolation.png){.on-glb align=left width="200"}
  **Interpolation settings**: modify settings via dialog (also adjustable in<br>
  [Ribbon → Home -> Preferences -> Segmentation tools](../../ribbon/home/home-preferences.md)<br> 
  or in [toolbar](../../quick-access-bar/index.md)).

<div class="clear-float"></div>
- <span class="widget widget-checkbox">Watershed</span>: cluster pixels with the watershed algorithm for selection as clusters.
- <span class="widget widget-checkbox">SLIC</span>: cluster pixels with the SLIC algorithm for selection as clusters.


??? info "Superpixels with the Brush tool"
    Enable *Superpixels mode* with [:fontawesome-brands-youtube:{.red-color} Watershed](https://youtu.be/vVh1j3HBh-c) 
    or [:fontawesome-brands-youtube:{.red-color} SLIC](https://youtu.be/6bZb_Mr_nS0?list=PLGkFvW985wz8cj8CWmXOFkXpvoX_HwXzj) checkboxes. 
    The brush selects groups of pixels (superpixels) instead of individual pixels.<br>
    Undo the last superpixel with ++ctrl++ + ++z++.

    Algorithms:

    - **SLIC**: Simple Linear Iterative Clustering by [Radhakrishna Achanta et al., 2015](http://ivrl.epfl.ch/supplementary_material/RK_SLICSuperpixels/index.html) (good for distinct intensities).
    - **Watershed**: Good for distinct boundaries.

    Adjust superpixel size and shape with

    - <span class="widget widget-edit">N</span> (default, **220** for SLIC, **15** for Watershed) 
    - **Compact/Invert** (higher compactness = more rectangular shapes; Invert: **1** for dark boundaries, **0** for bright). 
    !!! tip
        Use<br>
        ++ctrl++ + ++alt++ + **mouse wheel** or<br>
        ++ctrl++ + ++alt++ + ++shift++ + **mouse wheel** to adjust <span class="widget widget-edit">N</span>.

    ![Example of SLIC and Watershed superpixels](images/PanelsSegmentationToolsBrushSupervoxels.jpg){.on-glb}
    /// caption
    Example of SLIC and Watershed superpixels
    ///

    SLIC boundaries use _drawregionboundaries.m_ by [Peter Kovesi](http://www.peterkovesi.com/projects/segmentation/).  
    !!! note
        * **Note 1**: Sensitive to <span class="widget widget-checkbox">Adapt.</span> in the 
        [Selection panel](../selection/index.md), selecting superpixels based on mean ± standard deviation × <span class="widget widget-edit">Adapt.</span> factor.  
        * **Note 2**: Adjust <span class="widget widget-edit">Adapt.</span>  with the mouse wheel while drawing.  
        * **Note 3**: Requires compiling [slicmex.c](https://mib.helsinki.fi/downloads_systemreq.html#superpixels) for your OS.

    !!! abstract "References"  
    - Achanta et al., *SLIC Superpixels Compared to State-of-the-art Superpixel Methods*, IEEE TPAMI, 2012.  
    - Achanta et al., *SLIC Superpixels*, EPFL Technical Report, 2010.

---

## Presets
Use the following key shortcuts to define and restore presets

- ++shift+1++, ++shift+2++, ++shift+3++ - store preset 1, 2, or 3 correspondingly
- ++1++, ++2++, ++3++ - restore preset 1, 2, or 3 correspondingly

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*
