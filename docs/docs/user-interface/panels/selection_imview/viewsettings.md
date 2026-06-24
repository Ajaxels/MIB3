# View Settings Panel

---

## Overview

The **View Settings Panel** offers essential tools for visualizing your dataset, 
allowing you to adjust color channels, layer visibility, transparency, and display settings.

![View Settings Panel](images/PanelsViewSettings.png){align=left}

<div class="clear-float"></div>

---

## Colors table and <span class="widget widget-checkbox">LUT</span> checkbox

![View Settings Panel -> color channel table](images/PanelsViewSettings-colors.png){align=left}

The **Colors table** lists the dataset's color channels.<br>
Enable or disable channels by checking/unchecking their boxes.
<br>Use ++ctrl++ + <mouse class="left"></mouse> on a checkbox 
to select a single channel exclusively.

[:fontawesome-brands-youtube:{.red-color} Demo: Working with color channels](https://youtu.be/gT-c8TiLcuY)

<div class="clear-float"></div>

The <span class="widget widget-checkbox">LUT</span> checkbox determines how the image is rendered:

- **Checked**: MIB generates the image using colors defined in the table's third column.
- **Unchecked**: Limits simultaneous display to 3 channels; if more are selected, only the first 3 are shown.

???+ info "Right-click actions for color channels"

    <mouse class="right"></mouse> a channel in the table for these options 
    (also available in [Ribbon → Image -> Color Channels](../../ribbon/image/index.md#color-channels)):

    - **Insert empty channel**: add a channel with all pixels set to 0 at a specified position.
    - **Copy channel**: duplicate the selected channel.
    - **Invert channel**: invert the selected channel's intensities.
    - **Rotate channel**: rotate the selected channel.
    - **Shift channel**: shift the channel by X and Y pixels.
    - **Swap channels**: swap the selected channel with another.
    - **Delete channel**: remove the selected channel.
    - **Set LUT color**: define colors for use with <span class="widget widget-checkbox">LUT</span> (also in [Ribbon → Home -> Preferences](../../ribbon/home/home-preferences.md)).

---

## Checkboxes to toggle visibility of layers

![Checkboxes](images/PanelsViewSettings-checkboxes.png){align=left}

<span class="widget widget-checkbox">Show Model</span> checkbox, toggles the Model layer on/off.<br>
Shortcut: <span class="widget widget-button">Space</span>

<span class="widget widget-checkbox">Show Mask</span> checkbox, toggles the Mask layer on/off.<br>
Shortcut: <span class="widget widget-button">Ctrl</span> + <span class="widget widget-button">Space</span>.

<span class="widget widget-checkbox">Ann/Measure</span> checkbox, toggles visibility of the [Annotation layer](../segm/segm-annotations.md) 
and [Measurements](../../ribbon/tools/tools-measuretool.md).

<span class="widget widget-checkbox">Hide image</span> checkbox, toggles the Image layer on/off.

---

## Other controls

![Display Adjustments](images/PanelsViewSettings-contrast.png){align=left}

The contrast panel can be used to quickly adjust image contrast settings:

- <span class="widget widget-button">Display</span>: starts the [Display Adjustments dialog](viewsettings-adjustments.md) allowing 
contrast stretching by defining black and white points for the dataset.
<div class="clear-float"></div>
- <label class="widget widget-checkbox">On fly</label>: automatically adjusts contrast for each displayed image without altering the underlying data. 
The contrast stretching coefficients are taken from the portion of the image that is currently visible in the [Image View panel](../../image-document/index.md).

---


## Transparency sliders

![Display Adjustments](images/PanelsViewSettings-sliders.png){align=left}

Adjust layer transparency from opaque (left) to transparent (right):

- **Model slider**: controls the Model layer transparency.
- **Mask slider**: controls the Mask layer transparency.
- **Selection slider**: controls the Selection layer transparency.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Selection and View Settings](index.md)*
