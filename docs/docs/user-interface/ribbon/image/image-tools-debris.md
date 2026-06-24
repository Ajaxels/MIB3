# Debris Removal

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

![Debris Removal dialog](images/menuImageToolsDebrisRemoval2.png){.on-glb align=left width="360"}

Automatically or manually restore areas of volumetric datasets corrupted by
debris, replacing affected pixels with the average of the previous and following slices.
Updates the image and the corresponding Selection, Mask, and Labels layers.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Debris removal demo](https://youtu.be/iM2nHBxTjRw)

<div class="clear-float"></div>

!!! warning "Limitations"

    - Debris removal is available for **grayscale (single-channel) images only**.
    - The **first and last slices** of the stack are never processed — the algorithm needs one slice before and one slice after each target slice.

---

## Settings

<span class="widget widget-dropdown">Detection mode</span>: how debris areas are identified — see sections below for details.

The following parameters are active for **Automatic detection** only:

- <span class="widget widget-edit">Intensity threshold</span>: threshold applied to the summed difference between a slice and its neighbours. Lower values detect larger regions.
- <span class="widget widget-edit">Object size threshold</span>: minimum area (pixels) for a detected region to be considered debris; smaller objects are ignored.
- <span class="widget widget-edit">Strel size</span>: radius of the disk structuring element (pixels) used for morphological refinement of the detected area.
- <span class="widget widget-dropdown">Highlight as</span>: layer used to mark detected debris — `mask` or `selection`.

Click <span class="widget widget-button">Current</span> to process the current slice only, or <span class="widget widget-button">Remove all</span> to process the entire stack.

---

## Automatic detection

Detects debris by comparing each slice to its neighbours:

1. Computes the intensity difference between the current slice and its previous and following slices.
2. Thresholds the summed difference using <span class="widget widget-edit">Intensity threshold</span>.
3. Removes connected regions smaller than <span class="widget widget-edit">Object size threshold</span>.
4. Refines the mask with morphological operations (dilation → fill → erosion) controlled by <span class="widget widget-edit">Strel size</span>.
5. Replaces debris pixels with the average of the previous and following slices.
6. Writes the detected area to the layer selected in <span class="widget widget-dropdown">Highlight as</span>.

Best for datasets with scattered artifacts (dust, staining residues) that were not pre-segmented.

!!! tip
    Test on the current slice with <span class="widget widget-button">Current</span> before applying to the full stack.

---

## Masked areas

Restores regions defined in the **Mask** layer. No detection parameters are required.

Use the [Segmentation panel](../../panels/segm/index.md) to paint or refine the Mask layer over the debris, then run debris removal. Each marked pixel is replaced with the average of the corresponding pixel in the previous and following slices.

Suitable when debris locations are already known and manually segmented.

---

## Selected areas

Restores regions defined in the **Selection** layer. No detection parameters are required.

Define debris areas in the Selection layer using tools in the [Segmentation panel](../../panels/segm/index.md). Processing is identical to the Masked areas mode.

Useful for quick interactive corrections during visual inspection without modifying the permanent Mask layer.

---

## Example

![Debris Removal example](images/menuImageToolsDebrisRemoval.png)

<div class="clear-float"></div>

Debris removal applied to a volumetric dataset with automatic detection settings.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
