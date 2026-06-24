# First Dataset

This walkthrough takes you from an empty MIB window to a loaded, navigable dataset with your first
segmentation. It assumes MIB is already [running](../starting-mib/index.md).

!!! tip "New to the terminology?"
    A quick read of [Basic concepts](../basic-concepts/index.md) (layers, dataset types, models)
    will make the steps below clearer.

!!! tip "Explore the Tip of the Day"
    Each time MIB starts it shows a **Tip of the Day** window highlighting a feature you may not
    know about. Browsing a few of these is one of the quickest ways to discover what MIB can do.

---

## 1. Choose a working directory

Point MIB at the folder that holds your images. You can:

- use the <span class="widget widget-button">Load</span> button in the [Home ribbon](../../user-interface/ribbon/home/index.md), or
- use the working-directory widgets in the [Status Bar](../../user-interface/statusbar/index.md), or
- simply **drag and drop** image files onto the image document — the working directory updates automatically.

## 2. Find your files

The files in the chosen folder appear in the
[Directory Contents panel](../../user-interface/panels/dircontents/index.md). Use the
<span class="widget widget-dropdown">Filter</span> dropdown to narrow the list to a given format.

!!! note
    To open the wide variety of proprietary microscopy formats, enable the
    <span class="widget widget-checkbox">Bio</span> checkbox — this loads files through the
    [Bio-Formats reader](../../user-interface/panels/dircontents/index.md#bio-checkbox).

## 3. Select and load

- Select files with <mouse class="left"></mouse>, or multiple files with
  ++ctrl++ + <mouse class="left"></mouse> and ++shift++ + <mouse class="left"></mouse>.
- <mouse class="right"></mouse> and choose
  [**Combine selected datasets**](../../user-interface/panels/dircontents/index.md#file-list-box)
  to load them as a single 2D/3D/4D dataset.

A single file can also be opened by double-clicking it.

## 4. Adjust the display

Tune brightness, contrast, and visible color channels in the
[View Settings panel](../../user-interface/panels/selection_imview/viewsettings.md). This changes
only how the image is shown — the pixel data is untouched.

## 5. Navigate

- Scroll the **mouse wheel** to move between slices.
- Press ++w++ to zoom in and ++q++ to zoom out (default mouse-wheel mode).
- See all bindings on the [Key and mouse shortcuts](../../user-interface/key-and-mouse-shortcuts.md) page.

## 6. Make your first selection

Pick a tool in the [Segmentation panel](../../user-interface/panels/segm/index.md) — for example the
[Brush](../../user-interface/panels/segm/segm-brush.md) — and paint over a structure. Then transfer
the selection into the model:

- ++a++ — add the selection on the current slice to the active material,
- ++shift+a++ — add the selection on all slices.

Your result is now stored in the **Model** layer, ready to save or analyse.

---

## Where to go next

- [Basic concepts](../basic-concepts/index.md) — layers, dataset types, and models explained.
- [Tutorials](../tutorials/index.md) — step-by-step guides and video demonstrations.
- [User Interface](../../user-interface/index.md) — full reference for every panel and ribbon tab.

---

*Back to [MIB](../../index.md) | [Getting started](../index.md)*
