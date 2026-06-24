# Image Ribbon Tab

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md)*

---

## Overview

Image processing functions.

![Image Ribbon Tab](images/menuImage.png)

---

## Convert Section

### Mode

![Image Ribbon Tab -> operations with image modes](images/menuImage-mode.png){align=left}

Change the mode or color depth of the dataset.

<div class="h4-like">Image mode</div>

- **Grayscale**: convert to grayscale by removing color information.
- **Multi-channel**: convert to a multi-channel (RGB) color space.
- **HSV color**: convert to the HSV (hue, saturation, value) color space.
- **Indexed**: convert to indexed colors (not implemented for True Color images).

<div class="h4-like">Bit depth</div>

- **8 bit**: convert to 8-bit; intensities are scaled to preserve adjustments from the [Display dialog](../../panels/selection_imview/viewsettings-adjustments.md).
- **16 bit**: convert to 16-bit; intensities are scaled to preserve original contrast.
- **32 bit**: convert to 32-bit; intensities are scaled to preserve original contrast.

---

## Image adjustments Section

### Adjust display

![Image Ribbon Tab -> operations with image modes](images/menuImage-imadjust.png){align=left}

Starts a dialog to adjust display settings or resample image intensities.
See more in the [Adjust display window section](../../panels/selection_imview/viewsettings-adjustments.md).

---

### Color channels

![Image Ribbon Tab -> operations with color channels](images/menuImage-colorchannels.png){align=left}

Perform actions with color channels of the image.

<div class="h4-like">Demonstrations</div>

- [:fontawesome-brands-youtube:{.red-color} General demonstration](https://youtu.be/gT-c8TiLcuY)
- [:fontawesome-brands-youtube:{.red-color} Correction of color shifts between images](https://youtu.be/-J2P8a_z7pE)

<div class="clear-float"></div>

The **Color channels** dropdown contains:

- **Insert empty channel...**: insert an empty channel (all pixels intensity 0) at a specified position.
- **Copy channel...**: copy one channel to another position.
- **Invert channel...**: invert intensities of a specified color channel.
- **Rotate channel...**: rotate a specified color channel.
- **Shift channel...**: shift a channel by X and Y pixels.
- **Swap channel...**: swap two color channels.
- **Delete channel...**: delete a specified color channel from the dataset.

Color channel operations are also available from the *Colors* table in the [View settings panel](../../panels/selection_imview/viewsettings.md).

---

### Contrast

![Image Ribbon Tab -> contrast adjustments](images/menuImage-contrast.png){align=left}

Adjust or normalize image contrast. For linear contrast stretching, use the Image Adjustment dialog via the <span class="widget widget-button">Display</span> button in the [View Settings panel](../../panels/selection_imview/viewsettings.md).

The **Contrast** dropdown contains:

<div class="clear-float"></div>

#### Normalize layers

![Normalize layers dialog](images/menuImage-contrast-norm.png){.on-glb align=left width="320"}

Normalizes image intensities slice-by-slice across Z or time to reduce illumination variation.

See more on [Normalize layers](normalize.md)

<div class="clear-float"></div>

#### Contrast-limited adaptive histogram equalization

![CLAHE dialog](images/menuImage-contrast-clahe.png){.on-glb align=left width="320"}

CLAHE enhances contrast locally in small rectangular tiles rather than globally, then blends the tiles with bilinear interpolation to avoid sharp boundaries. A clip limit suppresses noise amplification in uniform areas.

See more on [CLAHE](clahe.md)

<div class="clear-float"></div>

---

### Invert

![Image Ribbon Tab -> invert image](images/menuImage-invert.png){align=left}

Invert image intensities.

Key shortcut: ++ctrl+i++

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Invert image demonstration](https://youtu.be/1DG2w5XYA18)

<div class="clear-float"></div>

The **Invert** dropdown contains:

- **Shown slice (2D)**: invert only the currently shown slice.
- **Current stack (3D)**: invert the current Z-stack.
- **Complete volume (4D)**: invert the complete dataset.

---

### Visualization

![Image Ribbon Tab -> invert image](images/menuImage-visual.png){.on-glb align=left width="320"}

Select the interpolation method used when rendering the image for display.

<div class="clear-float"></div>

The **Visualization** dropdown contains:

- **Bicubic**: bicubic interpolation (best quality when zooming out).
- **Nearest**: nearest-neighbour interpolation (best for zooming in, preserves pixel boundaries).
- **Automatic**: nearest when zooming in, bicubic when zooming out.

---

## Image tools Section

### Image filters

![Image Filters dialog](images/menuImageImageFilters.png){.on-glb align=left width="300"}

Opens a dialog with image filters in four categories:

- Basic image filtering in the spatial domain
- Edge-preserving filtering
- Contrast adjustment
- Image binarization

See the [Image Filters](image-filters.md) for details.

<div class="clear-float"></div>

---

### Image tools

![Image Ribbon Tab -> tools for images](images/menuImage-tools.png){align=left}

A collection of specialised image processing tools.

The **Image tools** dropdown contains:

<div class="clear-float"></div>

<div class="clear-float"></div>

#### Content-aware fill

![inpaintCoherent example](images/menuImageToolsContentAwareFill.png){.on-glb align=left width="400"}

Reconstruct selected areas using information from neighboring regions.

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Content-aware fill demonstration](https://youtu.be/H_TVvgA_br4)

<div class="clear-float"></div>

- See more on content-aware fill using [inpaintCoherent](image-tools-awarefill.md#inpaintcoherent)
- See more on content-aware fill using [inpaintExemplar](image-tools-awarefill.md#inpaintexemplar)

---

#### Debris removal

![Debris Removal Dialog](images/menuImageToolsDebrisRemoval.png)

<div class="clear-float"></div>

Automatically or manually restore areas of volumetric datasets corrupted with debris.
Areas can be detected automatically or selected into the Mask or Selection layers.

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Debris removal demo](https://youtu.be/iM2nHBxTjRw)

See more on [Debris removal](image-tools-debris.md)

---

#### Image arithmetics

![Image Arithmetics](images/menuImageToolsArithmetics.png){.on-glb align=left width="360"}

Use MATLAB syntax to apply custom arithmetic expressions to Image, Model, Mask, or Selection layers.

<div class="h4-like">Demonstrations</div>

- [:fontawesome-brands-youtube:{.red-color} MIB 2.60 and newer](https://youtu.be/sDwvnJGLi8Q)
- [:fontawesome-brands-youtube:{.red-color} MIB 2.52 and older](https://youtu.be/-puVxiNYGsI)

!!! warning "Limitations"

    Only in MIB for MATLAB

See more on [Image arithmetics](image-tools-arithmetic.md)

<div class="clear-float"></div>

---

#### Intensity projection

![Intensity Projection](images/menuImageToolsIntensityProjection.png){.on-glb align=left width="340"}

Generate intensity projection across any dimension of the loaded dataset.

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Intensity projection demonstration](https://youtu.be/hwFpS_3eP9U)

See more on [Intensity projections](image-tools-projections.md)

<div class="clear-float"></div>

---

#### Select image frame

![Select Image Frame](images/menuImageToolsDebrisRemoval-borderdetection.png){.off-glb align=left width="300"}

Detects the frame (an area of uniform intensity touching the image edge).
The detected area can be assigned to the *Selection* or *Mask* layers or replaced
with another color in the *Image* layer.

<div class="clear-float"></div>

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Select image frame demonstration](https://youtu.be/sWjipmeU5eA)

See more on [Select image frame](image-tools-selectframe.md)

---

#### White balance correction

![White Balance Correction](images/menuImageToolsWhiteBalanceCorrection.png){.on-glb align=left width="380"}

Corrects white balance of the dataset. Select an area that should be white or gray and assign it to the *Mask* or *Selection* layers, or use *Manual* mode to provide an RGB value directly.

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} White balance correction demo](https://youtu.be/Fdm-W4e6kHA)

See more on [White balance correction](image-tools-whitebalance.md)

<div class="clear-float"></div>

---

### MorphOps

![Morphological Operations](images/menuImageMorphOps.png){.on-glb align=left width="400"}

Applies morphological operations to images. The processed image can be added to or subtracted from the existing image (see *Additional action to the result* panel).

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Morphological operations demonstration](https://youtu.be/itbVLFm0FKQ)

<div class="clear-float"></div>

The **MorphOps** dropdown contains: Bottom-hat filtering, Clear border, Morphological closing, Dilate image, Erode image, Fill regions, H-maxima transform, H-minima transform, Morphological opening, Top-hat filtering.

See more on [Morphological operations](image-morphops.md)

---

### Intensity profile

![Intensity profile](images/menuImage-intensityProfile.png){.on-glb align=left width="320"}

Generates an intensity profile of the image data.

![Intensity profile](images/menuImage-intensityProfile2.png){align=left}

<div class="clear-float"></div>

The **Intensity profile** dropdown contains:

- **Line intensity profile**: profile along a straight line.
- **Arbitrary intensity profile**: profile along a user-drawn path.

For intensity profiles, use the [Measure tool](../tools/index.md#measure-tool).

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md)*
