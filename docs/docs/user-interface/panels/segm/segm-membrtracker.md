## The Membrane Click Tracker Tool

---

## Overview

![Membrane Click Tracker Tool](images/PanelsSegmentationToolsMembraneClick.png){align=left}

Tracks membrane-type objects using two mouse clicks to define start and end points.

- [:fontawesome-brands-youtube:{.red-color} 2D Demo](https://youtu.be/ZcJQb59YzUA?t=3m14s)
- [:fontawesome-brands-youtube:{.red-color} 3D Demo](https://youtu.be/ZcJQb59YzUA?t=2m22s)

<div class="clear-float"></div>

## How to use
- <span class="widget widget-button">Ctrl</span> + <mouse class="left"></mouse>: define the starting point (before MIB 2.651, <span class="widget widget-button">Shift</span> + <mouse class="left"></mouse> was used).
- <mouse class="left"></mouse>: trace the membrane from the start to the clicked point.

## Additional parameters
- <span class="widget widget-edit">Scale</span>: enhance the image during tracing based on start/end intensities<br> 
(`img(img>min([val1 val2])-diff([val1 val2])*options.scaleFactor) = maxIntensity`).
- <span class="widget widget-edit">Width</span>: define the trace width.
- <span class="widget widget-checkbox">BlackSignal</span>: set signal as black on white or white on black.
- <span class="widget widget-checkbox">Straight line</span>: connect points with a straight line.

    !!! note
        When the 3D switch in the [Selection panel](../../panels/selection_imview/selection.md) is enabled, it connects points linearly in 3D (useful for microtubules).
        Alternatively, use the [3D lines tool](segm-3dlines.md).

???+ info "Reference and compilation"
    Uses the *Accurate Fast Marching* function by [Dirk-Jan Kroon, 2011](http://www.mathworks.se/matlabcentral/fileexchange/24531-accurate-fast-marching), University of Twente.

    !!! note
        Compile the function for your OS (see [System Requirements - Membrane Click Tracker](https://mib.helsinki.fi/downloads_systemreq.html#clicktracker)), as it’s slow otherwise.

---

## Presets
Use the following key shortcuts to define and restore presets

- ++shift+1++, ++shift+2++, ++shift+3++ - store preset 1, 2, or 3 correspondingly
- ++1++, ++2++, ++3++ - restore preset 1, 2, or 3 correspondingly

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*