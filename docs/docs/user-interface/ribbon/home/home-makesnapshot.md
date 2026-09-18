# Make Snapshot

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*

---

## Overview

![Make a Snapshot Dialog](images/menuFileSnapshot.png){.on-glb align=left width="400"}

This dialog provides access to different settings for making snapshots.

<div class="clear-float"></div>

---

## Destination

![Make a Snapshot Dialog, Destination](images/menuFileSnapshot-target.png){align=left}

Define the destination for the rendered snapshot:

- **File**: save the snapshot to a file.
- **Clipboard**: copy the snapshot to the system clipboard.

---

## Crop

![Make a Snapshot Dialog, Crop](images/menuFileSnapshot-crop.png){align=left}

- **Full image**: make snapshot of the whole image.
- **Shown area**: make snapshot of the displayed area in the [Image Document](../../image-document/index.md) only.
- **ROI**: use selected ROI (the ROI may be defined using [the ROI panel](../../panels/roi/index.md)) as area for the snapshot.

---

## Resize

![Make a Snapshot Dialog, Resize](images/menuFileSnapshot-resize.png){align=left}

- <span class="widget widget-edit">Width</span>: modifies width of the snapshot, or the width of a single panel when <label class="widget widget-checkbox">Split channels</label> mode is enabled.
- <span class="widget widget-edit">Height</span>: modifies height of the snapshot, or the height of a single panel when <label class="widget widget-checkbox">Split channels</label> mode is enabled.
- <span class="widget widget-dropdown">Resizing method</span>: select one of the possible resizing methods.

!!! note
    Snapshots of the volume rendering are grabbed from the viewer window and therefore cannot be larger than the visible area of the screen. When the requested size does not fit, MIB reports the largest size that can be captured.

??? info "List of image resizing methods"
    - ***nearest***: nearest-neighbor interpolation; the output pixel is assigned the value of the pixel that the point falls within. No other pixels are considered; best for upsampling of the images.
    - ***bilinear***: bilinear interpolation; the output pixel value is a weighted average of pixels in the nearest 2-by-2 neighborhood.
    - ***bicubic***: bicubic interpolation; the output pixel value is a weighted average of pixels in the nearest 4-by-4 neighborhood; best for downsampling of the images.

- <label class="widget widget-checkbox">bin</label>: when checked, the buttons below reduce the image size by the specified factor and update the Width/Height fields accordingly.
  - <span class="widget widget-button">bin x2</span>: decrease image dimensions by a factor of 2.
  - <span class="widget widget-button">bin x4</span>: decrease image dimensions by a factor of 4.
  - <span class="widget widget-button">bin x8</span>: decrease image dimensions by a factor of 8.

---

## Options

![Make a Snapshot Dialog, Options](images/menuFileSnapshot-options.png)

- <label class="widget widget-checkbox">Split channels</label>: generate a montage image where each panel shows only one color channel.
- <span class="widget widget-edit">Cols</span>: number of horizontal panels in the montage.
- <span class="widget widget-edit">Rows</span>: number of vertical panels in the montage.
- <label class="widget widget-checkbox">Grayscale</label>: render individual color channels in grayscale mode.
- <label class="widget widget-checkbox">whiteBg</label>: render background in white color for the split channel mode and the scale bars.
- <span class="widget widget-edit">Margin:</span>: gap in pixels between panels in the montage.

???+ example "Split channel example"
    ![Split Channel Example](images/menuFileSnapshot_split.jpg){.on-glb align=left width="300"}
    <div class="clear-float"></div>

- <label class="widget widget-checkbox">Scale bar</label>: add a scale bar to the snapshot.

!!! warning "Scale bar"
    If the width of the snapshot is too small the scale bar is not generated.

- <label class="widget widget-checkbox">Measurements</label>: add the displayed measurements to the snapshot.
- <span class="widget widget-button">Options</span> (next to Measurements): define visualization options for the measurements.

---

## Format

![Make a Snapshot Dialog, File format settings](images/menuFileSnapshot-format.png)

Select the output format from the <span class="widget widget-dropdown">File format</span> dropdown. Each format exposes additional settings:

### BMP

Windows Bitmap; 1-bit, 8-bit, and 24-bit uncompressed images. No additional settings.

### JPG

Joint Photographic Experts Group (JPEG).

- <span class="widget widget-edit">Quality</span>: compression quality from 0–100; higher values give better quality and larger files.
- <span class="widget widget-dropdown">Mode</span>: color mode (e.g. RGB, grayscale).
- <span class="widget widget-dropdown">Bitdepth</span>: output bit depth.
- <span class="widget widget-edit">Comment</span>: optional text comment embedded in the file metadata.

### PNG

Portable Network Graphics. No additional settings.

### TIF

Tagged Image File Format.

- <span class="widget widget-dropdown">Compression</span>: compression type (e.g. none, LZW, Deflate).
- <span class="widget widget-dropdown">Color space</span>: output color space.
- <span class="widget widget-edit">Resolution</span>: pixel resolution written to the file metadata.
- <span class="widget widget-edit">RowsPerStrip</span>: number of rows per TIFF strip; affects read performance for large files.
- <span class="widget widget-edit">Description</span>: optional text description embedded in the file metadata.

---

## Output filename

- <span class="widget widget-edit">Output filename</span>: name and location of the destination file. Use <span class="widget widget-button">...</span> to browse.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*
