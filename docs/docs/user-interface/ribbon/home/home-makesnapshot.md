# Make Snapshot

---

## Overview

![Make a Snapshot Dialog](images/menuFileSnapshot.png){.on-glb align=left width="400"}

This dialog provides access to different settings for making snapshots.

<div class="clear-float"></div>

---

## Target

![Make a Snapshot Dialog, Options->Target](images/menuFileSnapshot-target.png){align=left}

Define the destination for the rendered snapshot:

- **File**: save the snapshot to a file.
- **Clipboard**: copy the snapshot to the system clipboard.

---

## Crop

![Make a Snapshot Dialog, Options->Crop](images/menuFileSnapshot-crop.png){align=left}

- **Full image**: make snapshot of the whole image.
- **Shown area**: make snapshot of the displayed in the [Image View panel](../../panels/selection_imview/imview.md) area only.
- **ROI**: use selected ROI (the ROI may be defined using [the ROI panel](../../panels/roi/index.md)) as area for the snapshot.

---

## Resize

![Make a Snapshot Dialog, Options->Resize](images/menuFileSnapshot-resize.png){align=left}

- <span class="widget widget-edit">Width</span> modifies width of the snapshot, or the width of a single panel when the <label class="widget widget-checkbox">Split channel</label> mode is enabled.
- <span class="widget widget-edit">Height</span> modifies height of the snapshot, or the height of a single panel when the <label class="widget widget-checkbox">Split channel</label> mode is enabled.
- <span class="widget widget-dropdown">Resizing method</span> select one of possible resizing methods.

??? info "List of image resizing methods"
    - *nearest*: nearest-neighbor interpolation; the output pixel is assigned the value of the pixel that the point falls within. No other pixels are considered; best for upsampling of the images.
    - *bilinear*: bilinear interpolation; the output pixel value is a weighted average of pixels in the nearest 2-by-2 neighborhood.
    - *bicubic*: bicubic interpolation; the output pixel value is a weighted average of pixels in the nearest 4-by-4 neighborhood; best for downsampling of the images.

- <label class="widget widget-checkbox">Bin</label>: when checked, the <span class="widget widget-button">bin2</span>, <span class="widget widget-button">bin4</span>, and 
<span class="widget widget-button">bin8</span> buttons reduce image size; otherwise, they become <span class="widget widget-button">mag2</span>, 
<span class="widget widget-button">mag4</span>, and <span class="widget widget-button">mag8</span> and increase the image size.
  - <span class="widget widget-button">bin2/mag2</span>: update the dimensions of the snapshot after decreasing/increasing the image size in 2 times.
  - <span class="widget widget-button">bin4/mag4</span>: update the dimensions of the snapshot after decreasing/increasing the image size in 4 times.
  - <span class="widget widget-button">bin8/mag8</span>: update the dimensions of the snapshot after decreasing/increasing the image size in 8 times.

---

## Options

![Make a Snapshot Dialog, Options->Options](images/menuFileSnapshot-options.png)

- <label class="widget widget-checkbox">Split channel</label>: generate a montage image, where each panel has only one color channel.

- The dimensions of the montage image can be specified using the <span class="widget widget-edit">Cols</span> 
(number of horizontal panels) and <span class="widget widget-edit">Rows</span> (number of vertical panels) 
edit boxes. 
- In addition, it is possible to force rendering of individual color channels in the grayscale mode (the <label class="widget widget-checkbox">Grayscale</label> checkbox).

???+ example "Split channel example"
    ![Split Channel Example](images/menuFileSnapshot_split.jpg){.on-glb align=left width="300"}
    <div class="clear-float"></div>

- <label class="widget widget-checkbox">White Bg</label>: render background in white color for the split channel mode and the scale bars.
- <label class="widget widget-checkbox">Scale bar</label>: add a scale bar to the snapshot.

!!! warning "Scale bar"
    **Note!** if the width of the snapshot is too small the scale bar is not generated.

- <label class="widget widget-checkbox">Measurements</label>: add the displayed measurements to the snapshot.

!!! warning "Measurements"
    Warning! The resulting image may have border artifacts, at least in MATLAB R2014b. The snapshot is done using the *export_fig* function written by [Oliver Woodford and Yair Altman](http://www.mathworks.com/matlabcentral/fileexchange/23629-export-fig).

- <span class="widget widget-button">Options</span>: define visualization options for the measurements.

---

## Format

![Make a Snapshot Dialog, Options->File format settings](images/menuFileSnapshot-format.png)

Select one of the possible formats:

- **BMP**: windows Bitmap (BMP); 1-bit, 8-bit, and 24-bit uncompressed images.
- **JPG**: joint Photographic Experts Group (JPEG), 8-bit, 12-bit, and 16-bit Baseline JPEG images.
- **PNG**: portable Network Graphics (PNG) format.
- **TIF**: baseline Tagged Image File Format images, including 1-bit, 8-bit, 16-bit, and 24-bit uncompressed images.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*

