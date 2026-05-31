# Selection Ribbon Tab

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md)*

---

## Overview

Actions that can be applied to the *Selection* layer. The *Selection* is one of three main segmentation layers 
(*Model*, *Selection*, *Mask*) which can be used in combination with other layers. 
See more about segmentation layers in the [Data layers section](../../image-layers.md).

![Selection Ribbon Tab](images/menuSelection.png)

<div class="clear-float"></div>

---

## Selection to Buffer

Allows copying (++ctrl+c++) the *Selection* of the currently shown slice to a buffer, 
which can later be pasted to any slice (++ctrl+v++) or all slices (++ctrl+shift+v++).<br> 
The buffer can be cleared via `Ribbon → Selection → Selection to Buffer → Clear`, 
affecting only the buffer, not other layers (*Selection*, *Mask*, *Model*).

---

## ..→Mask

Allows modification of the *Mask* layer by the *Selection* layer. Options include replacing 
the mask with the selection, adding selection to the mask, or removing selection from the mask. 
Can be applied to the current slice or entire volume.

---

## Morphological 2D/3D operations

![Morphological Ops](images/menuSelectionMorphOps.png){.on-glb align=left width="300"}

Performs morphological operations on 2D and 3D objects in the *Selection* layer. 
See MATLAB’s [bwmorph](https://se.mathworks.com/help/releases/R2024b/images/ref/bwmorph.html), 
[bwmorph3](https://se.mathworks.com/help/releases/R2024b/images/ref/bwmorph3.html), and 
[bwskel](https://se.mathworks.com/help/releases/R2024b/images/ref/bwskel.html) functions for details.

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/L-w8eGDfUkU)  
[:fontawesome-brands-youtube:{.red-color} Skeleton for 3D objects](https://youtu.be/Au4vb7max9Q)

See more on [Morphological Ops](selection-morphops.md)

<div class="clear-float"></div>

---

## Expand to mask borders

Expands each selected area to match the borders of the containing mask.

---

## Interpolate

Reconstructs the *Selection* layer on empty slices between two slices with selection, using shortcut ++i++. 
Choose the interpolator type in the [Preferences dialog](../../ribbon/home/home-preferences.md).

<div class="h3-like">Shape interpolation example</div>

- **shape**: ideal for interpolating blobs (filled structures); [:fontawesome-brands-youtube:{.red-color} demo](https://youtu.be/ZcJQb59YzUA?t=4m3s).
- **line**: suited for interpolating unclosed lines (e.g., membranes); [:fontawesome-brands-youtube:{.red-color} demo](https://youtu.be/ZcJQb59YzUA?t=2m22s)

??? example "Shape interpolation example"
    ![Shape Interpolation](images/menuSelectionInterpolationShape.jpg){.on-glb align=left}

??? example "Line interpolation example"
    ![Line Interpolation](images/menuSelectionInterpolationLine.jpg){.on-glb align=left}

<div class="clear-float"></div>
!!! warning
    Only one object should be in the *Selection* layer on the starting and ending slices

---

## Replace selected area in the image

![Replace Color](../mask/images/menuMaskReplaceColor.png){.on-glb align=left width="220"}

Replaces image intensities in selected areas with new values. 
A dialog prompts for intensities, slices, and color channels.

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/fNz1vGq7Hb0)

<div class="clear-float"></div>

---

## Smooth selection

![Replace Color](../mask/images/menuMaskSmooth.png){.on-glb align=left width="300"}

Smooths the *Selection* layer in 2D or 3D space.

!!! info "Selection smoothing"
    
    It is recommended to use [Image Filters](../image/image-filters.md) for interactive evaluation of smoothing results

<div class="clear-float"></div>

---


## Invert selection

Inverts the current selection across the entire dataset.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md)*
