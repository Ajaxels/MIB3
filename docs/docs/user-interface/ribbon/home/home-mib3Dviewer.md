# MIB 3D Volume Rendering

---

## Overview

Starting from MIB version 2.84, a new 3D volume rendering engine is available. The 3D viewer in MIB is capable
to show volumes using volume rendering techniques, models as overlays and generate surfaces from the overlay models.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Introduction to an updated 3D viewer](https://youtu.be/840o6zni3KE)

---

## Downsampling of datasets

Whenever 3D volume rendering is selected, the current image volume is transferred into the 3D viewer. 
During the transfer, it is possible to select color channels or downsample the dataset to improve rendering performance:

![Downsampling Dialog](images/menuFileRenderingMIB_downsample.png){.on-glb align=left width="300"}
<div class="clear-float"></div>

---

## Composition of the 3D viewer

The 3D viewer has two main windows:

- **3D Controls**: the main window for setting parameters, generating surfaces, and making snapshots and animations. Most controls are grouped under corresponding tabs.
- **3D Viewer**: the visualization window used to render volumes and models.

![User interface of the 3D viewer](images/menuFileRenderingMIB_R2022b.png){.on-glb align=left}
/// caption 
User interface of the 3D viewer
///

<div class="clear-float"></div>

---

## 3D Controls -> Menu

Menu gives access to the following operations:

| Section            | Operation                   | Description                                                                                             |
|--------------------|-----------------------------|---------------------------------------------------------------------------------------------------------|
| **File section**   |                             |                                                                                                         |
|                    | **Load animation path**     | animations created using the 3D viewer can be saved and loaded back using this operation.              |
|                    | **Save animation path**     | save the current animation path to the disk.                                                           |
|                    | **Make snapshot**           | starts the [MIB snapshot tool](home-makesnapshot.md) to create an image snapshot of the current view.      |
|                    | **Make spin movie**         | starts the [MIB movie maker tool](home-makevideo.md) to create a movie of a camera spin around the object. |
|                    | **Make animation movie**    | starts the [MIB movie maker tool](home-makevideo.md) to create an animation movie along a predefined path set in the *Animation tab*. |
| **View section**   |                             |                                                                                                         |
|                    | **Default view**            | reset the view to its default state (also via <span class="widget widget-button">Home</span> in the upper-right corner of the **3D Viewer**). |
|                    | **XY view**                 | set the view from above (also via <span class="widget widget-button">Z</span> in the axes, lower-left corner). |
|                    | **XZ view**                 | set the view from the Y-side (also via <span class="widget widget-button">Y</span> in the axes, lower-left corner). |
|                    | **YZ view**                 | set the view from the X-side (also via <span class="widget widget-button">X</span> in the axes, lower-left corner). |
| **Settings section** |                           |                                                                                                         |
|                    | **Background color**        | set the background color for the scene.                                                                |
|                    | **Background gradient color** | set the secondary background color for a gradient.                                                  |
|                    | **Background gradient**     | enable to render background as a gradient of two colors.                                               |

---

## 3D Controls -> Viewer

![Viewer Tab](images/menuFileRenderingMIB_R2022b_3DControls_Viewer.png){.on-glb align=left width="300"}

The Viewer tab allows control over the following widgets and parameters:

- <label class="widget widget-checkbox">Show scale</label>: show or hide the scale bar in the 3D viewer window.
- <label class="widget widget-checkbox">Show axes</label>: show or hide 3D axes; clicking the axes changes orientation.
- <label class="widget widget-checkbox">Show box</label>: show or hide the bounding box around the volume.
- <span class="widget widget-button">Help</span>: open this help section of MIB.
- <span class="widget widget-edit">Ambient light</span>: define strength of the ambient light in the scene.
- <span class="widget widget-edit">Diffuse light</span>: define strength of the diffuse light in the scene.
- <span class="widget widget-edit">Rotation</span>: define rotation center:
      - <span class="widget widget-edit">cursor</span> rotate the scene around the current position of the mouse cursor.
      - <span class="widget widget-edit">orbit</span> rotate the scene around the central point of the dataset.
- <label class="widget widget-checkbox">Live update</label>: when enabled, the model overlay in the 3D viewer is refreshed automatically as you segment in the main MIB window, so edits appear in 3D without pressing <span class="widget widget-button">Refresh view</span>. Updates are debounced and triggered by data changes only (drawing, add/subtract to model, etc.) — not by panning, zooming, or slice navigation — and work for the model, mask, and selection overlays. For BigData datasets the overlay is re-fetched at the currently rendered pyramid level.

<div class="clear-float"></div>

### Camera

Use these widgets to specify camera position (updated interactively), it is possible to update any of these fields
to modify position of the camera.

- <span class="widget widget-edit">Zoom</span> camera zoom level.
- <span class="widget widget-edit">Distance</span> distance from camera to the scene center.
- <span class="widget widget-edit">Position</span> camera position as a 3-element vector \[x y z\]. See [Camera Graphics Terminology](https://se.mathworks.com/help/matlab/creating_plots/defining-scenes-with-camera-graphics.html).
- <span class="widget widget-edit">Target</span> camera target as a 3-element vector \[x y z\].
- <span class="widget widget-edit">Up vector</span> upwards direction as a 3-element vector \[x y z\] (default: \[0 0 1\]).

<div class="clear-float"></div>

---

## 3D Controls -> Volume

The Volume tab contains tools for interacting with the shown volume.

![3D Controls -> Volume Tab](images/menuFileRenderingMIB_R2022b_3DControls_Volume.png){.on-glb align=left width="300"}

List of widgets for tweaking visualization settings:

- <label class="widget widget-checkbox">Show volume</label>: toggle visibility of both volume and model (does not affect surfaces).
- <label class="widget widget-checkbox">Transparent volume</label>: toggle volume visualization (does not affect models or surfaces).
- <span class="widget widget-dropdown">Renderer</span>:
  - **VolumeRendering**: render using color and transparency per voxel.
  - **GradientOpacity**: render with additional transparency based on intensity/luminance gradients; adjust with the **Opacity** slider.
  - **SlicePlanes**: use orthogonal slice planes, adjustable via **Slices** sliders or mouse.
  - **Isosurface**: show an isosurface at the **iso-value** slider value.
  - **MaximumIntensityProjection**: render the highest intensity voxel per ray (luminance for RGB).
  - **MinimumIntensityProjection**: render the lowest intensity voxel per ray (luminance for RGB).

<div class="clear-float"></div>  

- <span class="widget widget-dropdown">Opacity</span> / <span class="widget widget-dropdown">iso-value</span>: slider to tweak **GradientOpacity** and **Isosurface** settings.
- <span class="widget widget-dropdown">Color map</span>: update the colormap; use <label class="widget widget-checkbox">Invert</label>, <span class="widget widget-edit">Black point</span>, and <span class="widget widget-edit">White point</span> for adjustments.
- <span class="widget widget-dropdown">Slices</span> \[*only for SlicePlanes*\]: sliders to change orthogonal slice positions.
- **Alpha curve**: define transparency for the volume (1 = opaque, 0 = transparent).
  - <mouse class="right"></mouse>: select the point.
  - <mouse class="left"></mouse>: change position of the selected point.
  - ++shift++ + <mouse class="left"></mouse>: add a point at the clicked position.
  - ++ctrl++ + <mouse class="left"></mouse>: remove the closest point.
  - <span class="widget widget-button">Invert</span>: invert the alpha curve.
  - <span class="widget widget-button">Reset</span>: reset to default state.

<div class="clear-float"></div>

---

## 3D Controls -> Model

The Model tab contains tools for visualizing the model loaded into MIB.

![3D Controls -> Model Tab](images/menuFileRenderingMIB_R2022b_3DControls_Model.png){.on-glb align=left width="300"}

List of widgets for tweaking visualization settings:

- <span class="widget widget-dropdown">Overlay source</span>: specify the layer type for visualization as a model.
- <span class="widget widget-button">Update overlay</span>: grab the layer specified in <span class="widget widget-dropdown">Overlay source</span> and visualize it in the 3D Viewer.
- <span class="widget widget-dropdown">Materials to show</span>, <span class="widget widget-edit">material list</span> and <span class="widget widget-button">Add current</span>: choose which materials to render, see [Models with many materials](#models-with-many-materials) below.
- <label class="widget widget-checkbox">Hide all</label>: toggle show/hide all selected materials in the table.
- <span class="widget widget-button">Refresh view</span>: pull the latest segmentation into the overlay on demand. The first use initialises the overlay (same as <span class="widget widget-button">Update overlay</span>); afterwards it performs a lightweight refresh that updates only the overlay data while preserving per-material visibility and display settings. This is also the action invoked automatically by <label class="widget widget-checkbox">Live update</label>.

<div class="clear-float"></div>

- **Table with materials**: list of model materials; each can be shown/hidden and assigned a transparency value (**Alpha**, 0-1). Right-click for a menu with:
    - **Generate surface(s)**: create surfaces for the selected rows in the *Surfaces* tab. In the
      *All materials* mode the single row covers the whole model, so this builds one surface per
      object; it asks first, because that is one surface per object rather than one per row.
    - **Generate surface by index...**: create a surface for any material by typing its index.
      For an imported overlay this reads the object ids from the store, so it works even when the
      objects are shown fused together.
    - **Remove selected materials**: drop the selected rows from the rendered list (*Selected materials* mode only).

### Models with many materials

Instance segmentation produces models with thousands of materials (the 65535 and 4294967295 model types). The 3D viewer shows up to 255 materials at a time, so these models offer two modes in the <span class="widget widget-dropdown">Materials to show</span> dropdown:

- **All materials**: everything is shown at once, using a repeating set of colors. Neighbouring objects always get different colors, so the segmentation is easy to judge as a whole. The material table has a single row that sets transparency and visibility for the whole overlay.
- **Selected materials**: only the materials you list are shown, each in the same color as in the 2D view and with its own transparency and show/hide switch. Type indices and ranges into the edit field, for example `1:10,45`, or press <span class="widget widget-button">Add current</span> to add the material selected in the main MIB window.

!!! tip
    Use <span class="widget widget-button">Update overlay</span> for these models. Showing the model as the volume itself gives a gradient rather than separate objects.

An [imported overlay](home-importfromurl.md#labels-published-only-at-coarse-resolution) shows its
objects fused into one material. **Generate surface(s)** on such a model builds a single surface
covering all of them, after asking; objects that touch end up as one connected surface. Use
**Generate surface by index...** for one object on its own.

---

## 3D Controls -> Surfaces

Surfaces generated from the *Model* tab’s material table (via right-click) are visualized using settings in this tab.

![3D Controls -> Surfaces Tab](images/menuFileRenderingMIB_R2022b_3DControls_Surfaces.png){.on-glb align=left width="300"}

List of widgets for tweaking visualization settings:

**Table**:

- **C**: click to set color for the selected surface.
- **Name**: double-click to change the surface name.
- **Alpha**: tweak transparency (0-1).
- <label class="widget widget-checkbox">Show</label>: toggle show/hide the selected surface.
- <label class="widget widget-checkbox">Wire</label>: toggle wireframe visualization.
- <span class="widget widget-dropdown">Additional settings via right mouse click</span>:
  - **Save surface(s)**: export selected surface(s) to SLT format.
  - **Remove surface(s)**: remove the selected surface from the 3D viewer.

<label class="widget widget-checkbox">Hide all</label>: toggle show/hide all surfaces from the view

<div class="clear-float"></div>

---

## 3D Controls -> Animation

![3D Controls -> Animation Tab](images/menuFileRenderingMIB_R2022b_3DControls_Animation.png){.on-glb align=left width="300"}

The *Animation* tab allows setting key frames for making movies with volume animations.
<br>Rendering is done via<br>
`Ribbon → Home → Make animation movie`<br>
Animations can be saved/loaded from<br>
`Ribbon → Home → Load/Save animation path`.

<div class="clear-float"></div>

List of widgets for designing animations:

- **Keyframes table**: animations are based on key frames added with <span class="widget widget-button">Add keyframe</span>. Right-click for additional operations:
    - **Jump to the keyframe**: update the viewer to the selected keyframe.
    - **Insert a keyframe**: insert the current scene into the sequence.
    - **Replace keyframe**: replace the selected keyframe with the current view.
    - **Remove keyframe**: remove the selected keyframe.
- <span class="widget widget-button">Add keyframe</span>: add a keyframe to the sequence.
- <label class="widget widget-checkbox">Auto jump</label>: automatically update the scene to match a clicked keyframe.
- <span class="widget widget-button">Spin test</span>: test spinning around the specified axis (<span class="widget widget-dropdown">Z-axis</span>).
- <span class="widget widget-edit">No. frames</span>: define number of frames for the preview.
- <span class="widget widget-button">Delete all</span>: delete all keyframes.
- <span class="widget widget-button">Preview</span>: preview the animation.

<div class="clear-float"></div>

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*


