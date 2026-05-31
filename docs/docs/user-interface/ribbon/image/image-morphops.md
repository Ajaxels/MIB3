# Image Morphological Operations

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

## Description

![Morphological Operations](images/menuImageMorphOps.png){.on-glb align=left width="400"}

Applies morphological operations to enhance or modify the dataset’s images,
updating the Image layer. 

The processed image can be added to or subtracted from 
the existing image, as specified in the operation settings.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Morphological operations demonstration](https://youtu.be/itbVLFm0FKQ)

<div class="clear-float"></div>

Select the morphological operation from the 
<span class="widget widget-dropdown">Operation type</span> dropdown. 
Configure the structuring element size and shape for applicable operations
(e.g., dilation, erosion) in the 
<span class="widget widget-edit">Size or H-value</span> and <span class="widget widget-dropdown">Strel shape</span> 
fields. 

Choose how to handle the result using radio buttons in the **Action to the result**
selecting:

- **None**, the resulting image will be direct result of the applied morphological operation
- **Add to the image**, add the resulting image to the current image
- **Subtract from the  image**, remove the resulting image from the current image 

!!! info
    It is possible to enhance the resulting image by multiplying it using a factor provided
    in the <span class="widget widget-edit">Multiply results</span> edit box.<br>
    The resulting image can also be smoothed with 
    <span class="widget widget-edit">Smoothing HSize</span> and <span class="widget widget-edit">Sigma</span>.

Click the <span class="widget widget-button">Preview</span> button to preview the result,  
or use the <span class="widget widget-button">Continue</span> button to apply the selected
morphops to all images.

!!! tip
    use <span class="widget widget-checkbox">Auto preview</span> to interactively follow
    results.
    

## List of available morphological operations

### Bottom-hat Filtering

Computes morphological closing (`imclose`) and subtracts it from the original image, highlighting dark features smaller than the structuring element:

This operation is useful for enhancing dark regions or detecting small dark objects against 
a lighter background, such as pores or shadows in microscopy images.

??? abstract "Reference"
    [imbothat](https://se.mathworks.com/help/images/ref/imbothat.html) at Mathworks.com

### Clear Border

Suppresses light structures connected to the image border, removing unwanted edge artifacts:

Ideal for cleaning up datasets with bright boundary effects, ensuring focus on 
internal features.

??? abstract "Reference"
    [imclearborder](https://se.mathworks.com/help/images/ref/imclearborder.html) at Mathworks.com

### Morphological Closing

Performs dilation followed by erosion, smoothing objects and closing small gaps:

This operation helps connect broken structures or fill small holes, 
maintaining object shapes in noisy datasets.

??? abstract "Reference"
    [imclose](https://se.mathworks.com/help/images/ref/imclose.html) at Mathworks.com

### Dilate Image

Dilates the image, expanding bright regions and shrinking dark areas:

Useful for emphasizing or enlarging features, such as cell boundaries or bright spots, 
in preparation for further analysis.

??? abstract "Reference"
    [imdilate](https://se.mathworks.com/help/images/ref/imdilate.html) at Mathworks.com

### Erode Image

Erodes the image, shrinking bright regions and expanding dark areas:

Effective for removing small bright noise or thinning structures, enhancing contrast 
in dense datasets.

??? abstract "Reference"
    [imerode](https://se.mathworks.com/help/images/ref/imerode.html) at Mathworks.com

### Fill Regions

Fills holes (dark areas surrounded by lighter pixels), creating uniform regions:

This operation is suited for correcting dark spots within objects, such as voids
in cells or artifacts in solid structures.

??? abstract "Reference"
    [imfill](https://se.mathworks.com/help/images/ref/imfill.html) at Mathworks.com

### H-maxima Transform

Suppresses maxima with height less than a specified H value, reducing minor peaks:

Useful for simplifying datasets by eliminating small bright spots while preserving significant maxima, aiding in feature detection.

??? abstract "Reference"
    [imhmax](https://se.mathworks.com/help/images/ref/imhmax.html) at Mathworks.com

### H-minima Transform

Suppresses minima with depth less than a specified H value, reducing minor valleys:

Helps clean up dark noise or small depressions, enhancing the visibility of deeper minima in intensity profiles.

??? abstract "Reference"
    [imhmin](https://se.mathworks.com/help/images/ref/imhmin.html) at Mathworks.com

### Morphological Opening

Performs erosion followed by dilation, removing small bright objects and smoothing boundaries:

This operation is effective for noise reduction and shape simplification, preserving 
larger structures.

??? abstract "Reference"

    [imopen](https://se.mathworks.com/help/images/ref/imopen.html) at Mathworks.com

### Top-hat Filtering

Computes morphological opening (`imopen`) and subtracts it from the original image, 
highlighting bright features smaller than the structuring element:

Ideal for detecting small bright objects, such as particles or highlights, against a darker background.

??? abstract "Reference"
    [imtophat](https://se.mathworks.com/help/images/ref/imtophat.html) at Mathworks.com


---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
