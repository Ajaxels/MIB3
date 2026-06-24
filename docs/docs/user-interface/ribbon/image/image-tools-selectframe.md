# Select Image Frame

---

## Description

![Select Frame](images/menuImageTools-borderdetection.png){.on-glb align=left width="300"}

Detects a frame (an area of uniform intensity touching the image edge) in a 4D dataset. 
The detected frame can be assigned to the **Selection** or **Mask** layers as a binary 
mask or replaced with a new intensity in the **Image** layer.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Select image frame demonstration](https://youtu.be/sWjipmeU5eA)

<div class="clear-float"></div>

Select the dataset type and color channel for frame detection using 
the <span class="widget widget-dropdown">Dataset type</span> and 
<span class="widget widget-dropdown">Color channel</span> dropdowns. 

Specify the intensity of the frame to detect in the 
<span class="widget widget-edit">Frame intensity</span> field. 

Optionally, threshold detected regions by discarding those below a size specified in the 
<span class="widget widget-edit">Minimal size for objects</span> field. 
Choose the target layer with the <span class="widget widget-radio">Destination</span> radio 
buttons. When the **Image** layer is selected, set a new intensity value in 
the <span class="widget widget-edit">New frame intensity</span> field. 

Click the <span class="widget widget-button">Continue</span> button to execute the operation, 
or use the <span class="widget widget-button">Cancel</span> button to close the dialog
without changes.

!!! tip
    It is possible to threshold the detected regions and discard regions below the value specified in the <span class="widget widget-edit">Minimal size for objects</span> edit box.

!!! info
    When Destination layer is Image, it is possible to provide a new frame intensity value using <span class="widget widget-edit">New frame intensity</span>.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
