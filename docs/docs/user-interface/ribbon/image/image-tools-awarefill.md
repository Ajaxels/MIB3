# Content-aware Fill

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

## Overview

![Content-aware fill dialog](images/menuImageToolsContentAware.png){.on-glb align=left width="320"}

Reconstruct selected areas of the dataset using information from neighboring regions,
modifying the image and corresponding Selection, Mask, and Labels layers.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Content-aware fill demonstration](https://youtu.be/H_TVvgA_br4)

<div class="clear-float"></div>

Mark the regions to fill using the Mask or Selection layers in the [Segmentation panel](../../panels/segm/index.md),
then open the dialog from `Ribbon → Image → Image tools → Content-aware fill`.

---

## Settings

<span class="widget widget-dropdown">Method</span>: fill algorithm — `inpaintCoherent` or `inpaintExemplar`.

<span class="widget widget-dropdown">Dataset type</span>: scope of the operation — `Shown slice (2D)`, `Current stack (3D)`, or `Complete volume (4D)`.

<span class="widget widget-dropdown">Mask</span>: layer that defines the fill region — `selection` or `mask`.

<span class="widget widget-edit">Radius</span>: for `inpaintCoherent` — neighbourhood radius (pixels) centred on each pixel to inpaint; for `inpaintExemplar` — patch size in pixels.

<span class="widget widget-edit">Smoothing factor</span> *(inpaintCoherent only)*: Gaussian filter scale for estimating the coherence direction; controls smoothness of the result (0 = no smoothing).

<span class="widget widget-dropdown">Fill order</span> *(inpaintExemplar only)*: priority function determining which pixels are filled first — `gradient` (edge-first) or `tensor`.

Use <span class="widget widget-button">Preview</span> to apply the fill to the current slice and inspect the result before committing to the full dataset. Enable <label class="widget widget-checkbox">Auto preview</label> to update the preview automatically whenever a parameter changes.

---

## inpaintCoherent

![inpaintCoherent example](images/menuImageToolsContentAwareFill.png){.on-glb align=left width="400"}

Restores regions using coherence transport-based inpainting — propagates edge direction and intensity from surrounding areas into the selected region. Works well for smooth textures and gradients. Available from MATLAB R2019a.

<div class="clear-float"></div>

Method-specific parameters:

- <span class="widget widget-edit">Radius</span>: neighbourhood radius (pixels) around each pixel to inpaint; larger values use more context.
- <span class="widget widget-edit">Smoothing factor</span>: controls how smoothly the coherence direction is estimated.

!!! info "Reference"

    * F. Bornemann and T. März, "Fast Image Inpainting Based on Coherence Transport," [Journal of Mathematical Imaging and Vision](https://link.springer.com/article/10.1007/s10851-007-0017-6), Vol. 28, 2007, pp. 259–278.
    * [inpaintCoherent](https://se.mathworks.com/help/images/ref/inpaintcoherent.html) at MathWorks

---

## inpaintExemplar

![inpaintExemplar example](images/menuImageToolsContentAwareFill2.png){.on-glb align=left width="400"}

Fills regions by copying and blending texture patches from nearby areas. Works well for repetitive textures and structured backgrounds. Available from MATLAB R2019b.

<div class="clear-float"></div>

Method-specific parameters:

- <span class="widget widget-edit">Radius</span>: patch size in pixels (e.g. `9` for a 9×9 patch).
- <span class="widget widget-dropdown">Fill order</span>: determines which pixels are filled first — `gradient` prioritises strong edges; `tensor` uses the local structure tensor.

!!! info "Reference"

    * A. Criminisi, P. Perez, and K. Toyama, "Region Filling and Object Removal by Exemplar-Based Image Inpainting," [IEEE Trans. on Image Processing](https://ieeexplore.ieee.org/document/1323101), Vol. 13, No. 9, 2004, pp. 1200–1212.
    * [inpaintExemplar](https://se.mathworks.com/help/images/ref/inpaintexemplar.html) at MathWorks

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
