# Mask Generators Panel

*Back to [MIB](../../../index.md) | [User Guide](../../index.md) | [Panels](../index.md)*

---

## Overview

The **Mask Generators Panel** offers automated methods to create masks based on specific criteria or algorithms. These masks are useful for segmentation or targeting areas of interest. Learn more in [Data Layers](../../image-layers.md).

---

## Common fields

![Common Fields](images/PanelsMaskGen.png){align=left}

These controls apply across all mask generators:

<div class="clear-float"></div>

- **1. <span class="widget widget-dropdown">Filter type</span>**: select a mask generator 
from the list.
- **2. Mode radio buttons**:
- 
    - <span class="widget widget-radio">Current</span>: generates a mask for the current 
    slice only.
    - <span class="widget widget-radio">2D all</span>: generates masks for 
    all slices using a 2D approach.
    - <span class="widget widget-radio">3D</span>: generates a mask for the entire 
    dataset in 3D.
- **3. <span class="widget widget-button">Do it</span> button**:
    - <mouse class="left"></mouse>: Starts the selected generator, replacing the existing mask.
    - <mouse class="right"></mouse> → **Do new mask**: Starts the generator, replacing the existing mask.  
    ![Dropdown Menu](images/PanelsMaskGeneratorDropdown.png){.on-glb align=left width="300"}
    - <mouse class="right"></mouse> → **Generate new mask and add it to the existing mask**: 
    Adds the new mask to the existing one.<br>
    Useful for multidimensional filtering:
        1. Run generator for XY.
        2. Switch to XZ or YZ via the [Toolbar](../../quick-access-bar/index.md).
        3. Run generator again with this option.

<div class="clear-float"></div>

---

## Frangi Filter

![Frangi Filter](images/PanelsMaskGeneratorFrangi.png){align=left}

Based on Marc Schrijver and Dirk-Jan Kroon’s 
[Hessian-based Frangi Vesselness filter](http://www.mathworks.com/matlabcentral/fileexchange/24409-hessian-based-frangi-vesselness-filter), this uses 
Hessian eigenvectors to detect vessels or 
ridges (Frangi [1998](http://www.dtic.upf.edu/~afrangi/articles/miccai1998.pdf), [2001](http://www.tecn.upf.es/~afrangi/articles/tmi2001.pdf)). 

<div class="clear-float"></div>

May require compilation; see [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#frangi).

???+ info "Parameters"
    - **Range**: Sigma range (default: [1-6]).
    - **Ratio**: Step size between sigmas (default: 2).
    - **beta1**: Frangi correction constant (default: 0.9).
    - **beta2**: Frangi correction constant (default: 15).
    - **beta3**: Vesselness threshold (default: 500; rule of thumb: vessel greyvalues ÷ 4–6).
    - **B/W threshold**: Threshold for Mask layer; 0 yields a filtered image instead of binary.
    - **Object size limit**: Removes 2D objects smaller than this value post-filtering.
    - <span class="widget widget-checkbox">Black on white</span>: Detects black ridges on white background when checked.

---

## Morphological Filters

![Morphological Filters](images/PanelsMaskGeneratorMorphFilters.png){align=left}

MATLAB-based morphological filters

<div class="clear-float"></div>

![Extended-Maxima](images/PanelsMaskGeneratorMorphFiltersExtMaxTrans.jpg){align=left}
**Extended-maxima transform**: Uses MATLAB’s [imextendedmax](https://se.mathworks.com/help/releases/R2024b/images/ref/imextendedmax.html) 
to find regional maxima in the H-maxima transform (constant-intensity regions 
with lower external boundaries).

<div class="clear-float"></div>

![Extended-Minima](images/PanelsMaskGeneratorMorphFiltersExtMinTrans.jpg){align=left} 
**Extended-minima transform**: Uses [imextendedmin](https://se.mathworks.com/help/releases/R2024b/images/ref/imextendedmin.html)
 for regional minima in the H-minima transform (constant-intensity regions with higher external boundaries).  
 
<div class="clear-float"></div>

![H-Maxima](images/PanelsMaskGeneratorMorphFiltersHMaxTrans.jpg){align=left}
**H-maxima transform**: Suppresses maxima below an H-value, then thresholds with a specified value. 
Regional maxima have constant intensity and lower external boundaries.
<div class="clear-float"></div>
**H-minima transform**: Suppresses minima below an H-value, then thresholds. Regional minima have constant intensity and higher external boundaries.
<br>**Regional maxima**: Uses [imregionalmax](https://se.mathworks.com/help/releases/R2024b/images/ref/imregionalmax.html)
to create a binary mask of regional maxima (1 for maxima, 0 otherwise).
<br>**Regional minima**: Uses [imregionalmin](https://se.mathworks.com/help/releases/R2024b/images/ref/imregionalmin.html)
for a binary mask of regional minima (1 for minima, 0 otherwise).

<div class="clear-float"></div>

---

## Strel Filter

![Strel Filter](images/PanelsMaskGeneratorStrel.png){align=left}

Generates a mask via morphological opening and black-and-white thresholding. <br>
Uses bottom-hat filtering ([imbothat](https://se.mathworks.com/help/releases/R2024b/images/ref/imbothat.html)
) if <span class="widget widget-checkbox">Black on white</span> is checked, 
or top-hat ([imtophat](https://se.mathworks.com/help/releases/R2024b/images/ref/imtophat.html)
) if unchecked, followed by thresholding.

<div class="clear-float"></div>

- **Strel size**: Sets the disk-type structural element size for `imtophat`/`imbothat`.
- <span class="widget widget-checkbox">Fill</span>: Fills holes in the resulting Mask.
- **B/W threshold**: Sets the black-and-white thresholding parameter.
- **Size limit**: Removes 2D objects smaller than this value from the Mask.
- <span class="widget widget-checkbox">Black on white</span>: Uses bottom-hat filtering when checked, top-hat when unchecked.

---

*Back to [MIB](../../../index.md) | [User Guide](../../index.md) | [Panels](../index.md)*