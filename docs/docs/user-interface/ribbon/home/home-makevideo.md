# Make Movie

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*

---

## Overview

![Make Movie Dialog](images/menuFileMakeMovie.png){.on-glb align=left width="400"}

This dialog provides access to different settings for making video files.

<div class="clear-float"></div>

---

## Crop

![Make Movie Dialog, Options->Crop](images/menuFileMakeMovie-crop.png){align=left}

- **Full image**: renders video of the whole dataset.
- **Shown area**: renders video of the shown area only.
- **ROI**: use selected ROI (the ROI may be defined using [the ROI panel](../../panels/roi/index.md)) as area for the video.

---

## Resize

![Make Movie Dialog, Options->Resize](images/menuFileMakeMovie-resize.png){align=left}

- **Width**: modify width of the video file (the width depends on aspect ratio of the voxels).
- **Height**: modify height of the video file.
- **Resizing method**: select one of possible resizing methods.

??? info "List of image resizing methods"
    - **nearest**: nearest-neighbor interpolation; the output pixel is assigned the value of the pixel that the point falls within. No other pixels are considered.
    - **bilinear**: bilinear interpolation; the output pixel value is a weighted average of pixels in the nearest 2-by-2 neighborhood.
    - **bicubic**: bicubic interpolation; the output pixel value is a weighted average of pixels in the nearest 4-by-4 neighborhood.
    - **lanczos2**: lanczos-2 kernel.
    - **lanczos3**: lanczos-3 kernel.

---

## Extras

![Make Movie Dialog, Options->Extras](images/menuFileMakeMovie-extras.png){align=left}

- <label class="widget widget-checkbox">Scale bar</label> check to add a scale bar to the video file.
- <span class="widget widget-dropdown">Direction</span>: (only for 5D datasets), use it to select direction for video generation: "Z-stack" or "Time" for a time series.

!!! warning "Scale bar"
    **Note!** if the width of the video is too small the scale bar is not rendered.

---

## Options

![Make Movie Dialog, Options->Options](images/menuFileMakeMovie-options.png)

- <label class="widget widget-checkbox">Split channel</label> generate a montage image, where each panel has only one color channel.

- The dimensions of the montage image can be specified using the <span class="widget widget-edit">Cols</span> 
(number of horizontal panels) and <span class="widget widget-edit">Rows</span> (number of vertical panels)
edit boxes. In addition, it is possible to force rendering of individual color channels in the grayscale mode 
(the <label class="widget widget-checkbox">Grayscale</label> checkbox).
 
- <label class="widget widget-checkbox">White Bg</label> render background in white color for the split channel mode and the scale bars.

???+ example "Split channel example"
    ![Split Channel Example](images/menuFileSnapshot_split.jpg){.on-glb align=left width="300"}
    <div class="clear-float"></div>

---

## Format

![Make Movie Dialog, Options->File format settings](images/menuFileMakeMovie-format.png)

Select one of the possible formats:

- **Archival**: motion JPEG 2000 file with lossless compression.
- **Motion JPEG AVI**: compressed AVI file using Motion JPEG codec.
- **Motion JPEG 2000**: compressed Motion JPEG 2000 file.
- **MPEG-4**: compressed MPEG-4 file with H.264 encoding (Windows 7 systems only).
- **Uncompressed AVI**: uncompressed AVI file with RGB24 video.
 
---

### Settings

Select additional parameters for video rendering:

- <span class="widget widget-edit">Frame rate</span> rate of playback for the video in frames per second.
- <span class="widget widget-edit">Quality</span> number from 0 through 100. Higher quality numbers result in higher video quality and larger file sizes. Lower quality numbers result in lower video quality and smaller file sizes. Only available for objects associated with the MPEG-4 or Motion JPEG AVI profile.
- <span class="widget widget-edit">The first frame number</span>: the number of the first frame for the video.
- <span class="widget widget-edit">The last frame number</span>: the number of the last frame for the video.
- <label class="widget widget-checkbox">Back and forth</label>: complement the video with the same video rendered in the reverse direction.
 
### Output filename

- <span class="widget widget-edit">Output filename</span>: name and location of the destination file.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*

