# The Magic Wand + Region Growing Tools

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*

---

## Overview

![Magic Wand Tool](images/PanelsSegmentationToolsMagicWand.png){align=left}

Selects pixels based on intensity with mouse clicks.<br>
Intensity variation is calculated from the clicked pixel and two <span class="widget widget-edit">Variation</span> edit box values.<br>
[:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/ZcJQb59YzUA?t=1m50s)

<div class="clear-float"></div>

## Widgets and parameters

- <span class="widget widget-edit">Variation</span>: specify intensity variation relative to the clicked value.
- <span class="widget widget-checkbox">Connect 8</span>: use 8 (26 for 3D) connected neighborhood connectivity.
- <span class="widget widget-checkbox">Connect 4</span>: use 4 (6 for 3D) connected neighborhood connectivity.
- <span class="widget widget-edit">Radius</span>: define the effective range for the magic wand.

???+ info "Selection modifiers for the Magic Wand tool"
    - <mouse class="left"></mouse>: replace existing selection with the new one.
    - ++shift++ + <mouse class="left"></mouse>: add new selection to the existing one.
    - ++ctrl++ + <mouse class="left"></mouse>: remove new selection from the current one.

!!! info
    Works in 3D<br>
    Requires checked <span class="widget widget-checkbox">3D</span> in the [Selection panel](../selection/index.md)

---

## Presets
Use the following key shortcuts to define and restore presets

- ++shift+1++, ++shift+2++, ++shift+3++ - store preset 1, 2, or 3 correspondingly
- ++1++, ++2++, ++3++ - restore preset 1, 2, or 3 correspondingly

---
*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*