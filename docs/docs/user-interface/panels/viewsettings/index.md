# View Settings Panel

---

## Overview

![View Settings Panel](images/PanelsViewSettings.png){align=left}

The **View Settings Panel** offers essential tools for visualizing your dataset, 
allowing you to adjust color channels, layer visibility, transparency, and display settings.

<div class="clear-float"></div>

---

## Colors table and <span class="widget widget-checkbox">LUT</span> checkbox

![View Settings Panel -> color channel table](images/PanelsViewSettings-colors.png){align=left}

The **Colors table** lists the dataset’s color channels.<br>
Enable or disable channels by checking/unchecking their boxes.
<br>Use ++ctrl++ + <mouse class="left"></mouse> on a checkbox 
to select a single channel exclusively.

[:fontawesome-brands-youtube:{.red-color} Demo: Working with color channels](https://youtu.be/gT-c8TiLcuY)

<div class="clear-float"></div>

The <span class="widget widget-checkbox">LUT</span> checkbox determines how the image is rendered:

- **Checked**: MIB generates the image using colors defined in the table’s third column.
- **Unchecked**: Limits simultaneous display to 3 channels; if more are selected, only the first 3 are shown.

???+ info "Right-click actions for color channels"

    <mouse class="right"></mouse> a channel in the table for these options 
    (also available in [Ribbon → Image -> Color Channels](../../ribbon/image/index.md#color-channels)):

    - **Insert empty channel**: add a channel with all pixels set to 0 at a specified position.
    - **Copy channel**: duplicate the selected channel.
    - **Invert channel**: invert the selected channel’s intensities.
    - **Rotate channel**: rotate the selected channel.
    - **Shift channel**: shift the channel by X and Y pixels.
    - **Swap channels**: swap the selected channel with another.
    - **Delete channel**: remove the selected channel.
    - **Set LUT color**: define colors for use with <span class="widget widget-checkbox">LUT</span> (also in [Ribbon → Home -> Preferences](../../ribbon/home/home-preferences.md)).

---

## <span class="widget widget-checkbox">Show Model</span> checkbox

Toggles the Model layer on/off.<br>
Shortcut: <span class="widget widget-button">Space</span>.

---

## <span class="widget widget-checkbox">Show Mask</span> checkbox

Toggles the Mask layer on/off.<br>
Shortcut: <span class="widget widget-button">Ctrl</span> + <span class="widget widget-button">Space</span>.

---

## <span class="widget widget-checkbox">Hide image</span> checkbox

Toggles the Image layer on/off.

---

## <span class="widget widget-checkbox">Annotations</span> checkbox

Toggles visibility of the [Annotation layer](../segm/segm-annotations.md) 
and [Measurements](../../ribbon/tools/tools-measuretool.md).

---

## Checkboxes to toggle visibility of layers

![Display Adjustments](images/PanelsViewSettings-checkboxes.png){align=left}

These checkboxes can be used to toggle visibility of layers within MIB. 

<div class="clear-float"></div>

- <label class="widget widget-checkbox">Show model</label>: toggles visibility of the model layer; when 
<label class="widget widget-checkbox widget-checkbox-unchecked">Show model</label> the model layer is not visible. Use ++space++ key shortcut to toggle the model layer on and off.
- <label class="widget widget-checkbox">Show mask</label>: toggles visibility of the mask layer; when 
<label class="widget widget-checkbox widget-checkbox-unchecked">Show mask</label> the mask layer is not visible. Use ++ctrl+space++ key shortcut to toggle the model layer on and off.
- <label class="widget widget-checkbox">Hide image</label>: when checked the image will not be shown and rendered as a black background. 
All other layers visible when the corresponding checkboxes are in the checked state.
- <label class="widget widget-checkbox">Ann/Measure</label>: toggles visibility of annotations and measurements.

---

## Contrast panel

![Display Adjustments](images/PanelsViewSettings-contrast.png){align=left}

The contrast panel can be used to quickly adjust image contrast settings:

- <span class="widget widget-button">Display</span>: starts the [Display Adjustments dialog](viewsettings-adjustments.md) allowing 
contrast stretching by defining black and white points for the dataset.
<div class="clear-float"></div>
- <label class="widget widget-checkbox">On fly</label>: automatically adjusts contrast for each displayed image without altering the underlying data. 
The contrast stretching coefficients are taken from the portion of the image that is currently visible in the [Image View panel](../imview/index.md)].
- <span class="widget widget-button">Auto</span>: adjusts brightness across the entire dataset, prompting for saturation parameters (low/high intensity borders).
This recalculates image intensities to boost contrast. 

!!! info "The Auto button operation depends on the stack checkbox"

    ![Automatic contrast adjustment settings](images/PanelsViewSettings-autolimits.png){.on-glb align=left width="260"}
    Behavior depends on the <label class="widget widget-checkbox">stack</label> switch:
    
      - <span class="widget widget-checkbox widget-checkbox">stack</span> uses dataset-wide min/max parameters for uniform adjustment.
      - <span class="widget widget-checkbox widget-checkbox-unchecked">stack</span> adjusts each frame individually.
      
 
---


## Transparency sliders

![Display Adjustments](images/PanelsViewSettings-sliders.png){align=left}

Adjust layer transparency from opaque (left) to transparent (right):

- **Model slider**: controls the Model layer transparency.
- **Mask slider**: controls the Mask layer transparency.
- **Selection slider**: controls the Selection layer transparency.

---

## Right-click menu

![View settings panel -> context menu](images/PanelsViewSettings-context.png){align=left}

Right-click an empty area to open a dropdown menu for hiding/showing panels, expanding the [Image View Panel](../../panels/imview/index.md) space.


<div class="clear-float"></div>

---

*Back to [MIB](../../../index.md) | [User Guide](../../index.md) | [Panels](../index.md)*