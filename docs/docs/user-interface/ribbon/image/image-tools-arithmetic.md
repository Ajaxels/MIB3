# Image Arithmetics

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

## Description

![Image Arithmetics](images/menuImageToolsArithmetics.png){.on-glb align=left width="360"}

Apply custom arithmetic expressions using MATLAB syntax to modify the Image, Model, 
Mask, or Selection layers of the dataset.

<div class="h3-like">Demonstrations</div>

- [:fontawesome-brands-youtube:{.red-color} MIB 2.60 and newer](https://youtu.be/sDwvnJGLi8Q)
- [:fontawesome-brands-youtube:{.red-color} MIB 2.52 and older](https://youtu.be/-puVxiNYGsI)

!!! warning "Limitations"

    Only in MIB for MATLAB

<div class="clear-float"></div>

Enter a MATLAB expression in the <span class="widget widget-edit">Expression</span> field to 
perform arithmetic operations on the dataset’s layers. 

Specify input datasets 
in the <span class="widget widget-edit">Input variables</span> field and the output 
destination in the <span class="widget widget-edit">Output variable</span> field. 

!!! tip 
    Use the <span class="widget widget-dropdown">Previous expression</span> dropdown to
    recall past successful expressions. 

Click the <span class="widget widget-button">Run expression</span> 
button to execute the operation, or use the <span class="widget widget-button">Close</span> 
button to close the dialog without changes.

## Parameters and options

<div class="h4-like">Conventions:</div>

- `I, I1, I2 ...`: image layer; number indicates MIB container (`I` is for the current dataset).
- `O, O1, O2 ...`: model layer (`O` is for the current model).
- `M, M1, M2 ...`: mask layer (`M` is for the current mask).
- `S, S1, S2 ...`: selection layer (`S` is for the current selection).

- <span class="widget widget-edit">Input variables</span>: list datasets used in the 
expression (e.g., `I1, I2` for images from containers 1 and 2).
- <span class="widget widget-edit">Output variable</span>: specify the layer or 
container to store the result (e.g., `I1` for image in container 1).
- <span class="widget widget-dropdown">Previous expression</span>: select from a 
list of previously executed expressions to populate the expression field.
- <span class="widget widget-edit">Expression</span>: enter the arithmetic operation to 
perform (see examples below).

??? examples "Examples of arithmetic operations"

    - `I = I * 2`: increase intensity of all pixels in the current image by 2x.
    - `I2 = I2 + 100`: increase intensity of all pixels in image 2 by 100.
    - `I1 = I1 + I2`: add image from container 2 to container 1, returning result to container 1.
    - `I3 = I3 + mean(I3(:))`: add mean value of image 3 to image 3.
    - `I1 = I1 - min(I1(:))`: decrease intensity in image 1 by its minimum value.
    - `I(:,:,2,:) = I(:,:,2,:)*1.4`: increase intensity of the second color channel by 1.4x.
    - `I(I==0) = I(I==0)+100`: increase intensity of black areas by 100.
    - `disp(sum(abs(single(I1(:))-single(I2(:)))))`: find the difference between images in containers 1 and 2, printing to console (or use `msgbox(num2str())` for a message box).
    - `M2 = M1`: copy mask layer from image 1 to image 2.
    - Replace intensity of the second color channel in the masked area with 0.
    ```matlab
    for z=1:size(I, 4)
        slice = I(:,:,2,z);
        mask = M(:,:,z);
        slice(mask==1) = 0;
        I(:,:,2,z) = slice;
    end
    ```


---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
