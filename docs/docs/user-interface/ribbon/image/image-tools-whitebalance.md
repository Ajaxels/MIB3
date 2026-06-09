# White Balance Correction

---

## Description

![White Balance Correction](images/menuImageToolsWhiteBalanceCorrection.png){.on-glb align=left width="380"}

Corrects the white balance of the dataset to ensure accurate color representation. 

Start by selecting an area that should be white or gray, assigning it to the **Mask** or 
**Selection** layers, 
or use **Manual** mode to specify an RGB value for correction.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} White balance correction demo](https://youtu.be/Fdm-W4e6kHA)

<div class="clear-float"></div>

Select the source for the reference white point using the 
<span class="widget widget-radio">Picked region</span> radio buttons, 
choosing **Selected areas**, **Masked areas**, or **Manual**.

For **Manual** mode, 
enter an RGB value in the <span class="widget widget-edit">Manual white value</span> 
field (e.g., `[255, 255, 255]` for white). Specify the color space with the 
<span class="widget widget-dropdown">Color space</span> dropdown, 
selecting **sRGB**, **Adobe RGB 1998**, or **linear RGB**. 

Choose the chromatic adaptation method via the 
<span class="widget widget-dropdown">Chromatic adaptation</span> dropdown, 
with options **Bradford**, **von Kries**, or **simple**.

Select the correction scope using the <span class="widget widget-radio">Correction scope</span>
radio buttons, opting for **Current slice** or **All slices**.

Click the <span class="widget widget-button">Correct current</span> button to adjust the 
dataset’s color balance for the currently shown slice, or the
<span class="widget widget-button">Correct all</span> button to process all images.

!!! info "References"
    
    * [chromadapt](https://se.mathworks.com/help/images/ref/chromadapt.html) function at Mathworks.com
    * Lindbloom, Bruce. "Chromatic Adaptation." [http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html](http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html)

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
