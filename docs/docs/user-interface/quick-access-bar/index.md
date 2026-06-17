# Quick Access Bar

The **Quick Access Bar (QAB)** runs along the top of the MIB window and gives one-click access to the most frequently used actions, without switching ribbon tabs.

---

## Overview

![Quick Access Bar](images/Toolbar.png)

Buttons are grouped from left to right by function. Hover over any button to read its tooltip.

---

## Undo / Redo

| Button                                                   | Action                                                                                          |
|----------------------------------------------------------|-------------------------------------------------------------------------------------------------|
| ![Undo](images/toolbar_undo.png){.inline-image} **Undo** | Restores the previous dataset state. Use ++ctrl+z++ to toggle undo-redo for the last operation. |
| ![Redo](images/toolbar_redo.png){.inline-image} **Redo** | Reapplies the last undone action.                                                               |

Set undo history length in [Ribbon → Home → Preferences → Backup and Undo](../ribbon/home/home-preferences.md#backup-and-undo).

---

## Zoom controls

These buttons adjust the magnification of the image in the [Image View panel](../panels/selection_imview/imview.md).

| Button                                                              | Action |
|---------------------------------------------------------------------|--------|
| ![Zoom in](images/toolbar_zoomin.png){.inline-image} **Zoom in**    | Increases magnification by 1.5×. |
| ![1:1](images/toolbar_zoom100.png){.inline-image} **1:1**           | Sets magnification to 100%. |
| ![Fit](images/toolbar_zoomfit.png){.inline-image} **Fit**           | Fits the image to the [Image View panel](../panels/selection_imview/imview.md). |
| ![Zoom out](images/toolbar_zoomout.png){.inline-image} **Zoom out** | Decreases magnification by 1.5×. |

!!! tip "Keyboard shortcuts are faster"
    For continuous zooming while working, use the keyboard shortcuts ++q++ (zoom out) and ++w++ (zoom in) instead of clicking these buttons.
    See the full list of shortcuts on the [Key and Mouse Shortcuts](../key-and-mouse-shortcuts.md) page.

---

## Fast pan mode

![Fast pan](images/toolbar_fastpan.png){align=left}

Toggles **Fast pan** mode for panning the image in the [Image View panel](../panels/selection_imview/imview.md) with <mouse class="right"></mouse>.

<div class="clear-float"></div>

MIB3 is optimised for smooth panning — holding <mouse class="right"></mouse> and dragging moves the image with minimal delay under normal conditions. **Fast pan** mode trades visual completeness for even lower latency: while dragging, only the previously cached portion of the image is shown; the newly exposed area is revealed only when the mouse button is released and the full view is refreshed.

!!! tip "When to use Fast pan"
    Enable Fast pan when working with very large or high-bit-depth datasets where the standard panning still feels sluggish. For most datasets MIB3's default panning is sufficient and Fast pan is not needed.

---

## Orientation buttons

![Plane orientation](images/toolbar_xyz.png){align=left}

Switch the viewing plane between XY, ZX, and ZY orientations.

[:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/4NXSEkrhnts)

<div class="clear-float"></div>

| Button / Shortcut | Plane |
|-------------------|-------|
| **YX** / ++alt+1++ | XY plane (default) |
| **XZ** / ++alt+2++ | ZX plane |
| **YZ** / ++alt+3++ | ZY plane |

!!! tip "Keyboard shortcuts rotate around the cursor"
    When using ++alt+1++, ++alt+2++, or ++alt+3++ with the mouse cursor positioned over the image, the view rotates around the point under the cursor, keeping that location centred in the panel.

!!! warning
    Some segmentation tools may only be applied to the dataset in the XY orientation.

??? abstract "Example of a dataset in different orientations"
    ![Example of a dataset in different orientations](images/toolbarPlaneChangeButtons.jpg){.on-glb}

---

## Line measure tool

![Measure](images/toolbar_measure.png){align=left}

Measures linear distances.<br>
See more [Ribbon → Tools → Measure tool](../ribbon/tools/index.md#measure-tool).

<div class="clear-float"></div>

---

## Center marker toggle

![Center marker](images/toolbar_center_marker.png){align=left}

Toggles the center marker on the image axes, useful for graphcut segmentation in grid mode.

<div class="clear-float"></div>

---

## ROI mode switch

![ROI toggle](images/toolbar_roi.png){align=left}

Toggles ROI visibility. When ROIs are shown, certain tools automatically restrict their operation to the ROI area.

<div class="clear-float"></div>

!!! info "ROI-aware tools"
    Some tools respect the shown ROI and process only the pixels within it:

    - **[Image Filters](../ribbon/image/image-filters.md)** — filtering is applied exclusively inside the ROI, both during preview and when committing the result.
    - **Adding Selection to Model or Mask** (++a++, ++shift+a++, and related shortcuts) — the addition is restricted to the ROI area; pixels outside the ROI boundary are not affected.

    Tools that are not ROI-aware always process the full dataset or current slice regardless of ROI visibility.

See [ROI Panel](../panels/roi/index.md) for creating and managing ROIs.

---

## Block-mode switch

![Block mode](images/toolbar_blockmode.png){align=left}

When enabled, filters and operations act only on the visible portion of the dataset, speeding up testing or segmentation.

<div class="clear-float"></div>

!!! warning
    Incompatible with ROIs (full dataset is used when ROIs are active).

---

## Save model

![Save model](images/toolbar_save.png){align=left}

Saves the model without prompting for a name, using:

- Default template: `Labels_NAME_OF_THE_DATASET.model`, or
- Name from the last *Save model as…*, or
- Name from a prior *Load model* action

Also accessible via [Ribbon → Model → Save model](../ribbon/model/index.md#save-model).

<div class="clear-float"></div>

---

## Make snapshot

![Snapshot](images/toolbar_snapshot.png){align=left}

Opens a dialog to capture the current slice.<br>
See [more details](../ribbon/home/home-makesnapshot.md).

??? info "Make snapshot dialog"
    ![Snapshot options](../ribbon/home/images/menuFileSnapshot.png){.on-glb}

<div class="clear-float"></div>

---

## Help

![Help](images/toolbar_help.png){align=left}

Opens the MIB documentation. 

The documentation is also available directly from MIB website: [https://mib.helsinki.fi/help/main3/index.html](https://mib.helsinki.fi/help/main3/index.html) 

---

*Back to [MIB](../../index.md) | [User interface](../index.md)*