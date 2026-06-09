# Crop Dataset

---

![Crop Dataset Dialog](images/menuDatasetCrop.png){.on-glb align=left width="260"}

Crop the image and corresponding Selection, Mask, and Model layers. 

Cropping can be done in:

- Interactive
- Manual
- ROI mode

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Crop dataset demonstration](https://youtu.be/PQtpYUuJwG8)

<div class="clear-float"></div>

### Interactive mode

When the **Interactive** mode is selected, you can draw a rectangular area on the image 
by pressing and holding the <mouse class="left"></mouse> button. 
This area defines the region to be cropped.

!!! warning "The Interactive mode is not compatible with zooming"

    Whenever you are using the interactive crop do not change magnification, as it
    is not yet implemented

### Manual mode

Alternatively, enable the <label class="widget widget-checkbox">Manual</label> 
mode to enter specific cropping coordinates directly in the dialog. 

### ROI-based cropping

You can also crop based on a selected region of interest by enabling the 
<label class="widget widget-checkbox">from ROI</label> mode, 
which uses ROIs defined in the [ROI panel](../../panels/roi/index.md).

### Start cropping

To perform the crop, click the <span class="widget widget-button">Crop</span> button to 
crop the current dataset.<br> 
Alternatively, use the 
<span class="widget widget-button">Crop to</span> button to copy the cropped dataset
to another buffer. Buffers are managed via the buttons at the top of 
the [Directory Contents panel](../../panels/dircontents/index.md).

!!! note
    To restore a cropped dataset into the original, use the **Fuse into existing** mode 
    of the **Chop image tool** available at 
    [Ribbon → Home → Chopped Images → Import](../home/home-choppedimages.md).

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*

