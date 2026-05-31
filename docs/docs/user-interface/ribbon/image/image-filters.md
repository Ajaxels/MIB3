# Image Filters Dialog

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

## Overview

![Image Filters dialog](images/menuImageImageFilters.png){.on-glb align=left width="400"} 

Collection of image filters arranged into four categories:

- Basic image filtering in the spatial domain
- Edge-preserving filtering
- Contrast adjustment
- Image binarization

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Image filters demo](https://youtu.be/QZU3jSoEXJM)
 
<div class="clear-float"></div>

---

## Options

Prior to filtering images, the following options may be tweaked:

- <span class="widget widget-dropdown">Dataset type</span>: specify whether filtering applies to the shown slice, current 3D stack, or the whole dataset.
- <span class="widget widget-dropdown">Source layer</span>: select the layer to be filtered (e.g., Image, Selection, Mask, Model).
- <span class="widget widget-dropdown">Color channel</span>: choose a specific color channel, all shown channels, or all channels in the image.
- <span class="widget widget-edit">Material index</span>: index of material to filter (available when *Source layer* is *Model*).
- <label class="widget widget-checkbox">3D</label>: apply a 3D filter.

The filtered image can be post-processed using a dropdown at the bottom of the dialog:

- **Filter image**: filter and display the result.
- **Filter and subtract**: filter and subtract the result from the unfiltered image.
- **Filter and add**: filter and add the result to the unfiltered image.

---

## Basic image filtering in the spatial domain

**Average filter**<br>  
  ![Average Filter](images/image_filters_average.jpg){.on-glb align=left width="300"}  
  Averages image signal using a rectangular filter. Uses MATLAB’s [imfilter](https://www.mathworks.com/help/images/ref/imfilter.html) with the `average` filter from [fspecial](https://www.mathworks.com/help/images/ref/fspecial.html).  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Circular averaging filter (pillbox)**<br>  
  ![Circular Averaging Filter](images/image_filters_average.jpg){.on-glb align=left width="300"}  
  Averages image signal using a disk-shaped filter. Uses [imfilter](https://www.mathworks.com/help/images/ref/imfilter.html) with the `disk` filter from [fspecial](https://www.mathworks.com/help/images/ref/fspecial.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Distance map filter**  
  ![Distance Map Filter](images/image_filters_distancemap.jpg){.on-glb align=left width="300"}  

  Calculates a distance map from seeds in the *Source Layer* (Selection, Mask, or Material).<br>
  2D uses [bwdist](https://www.mathworks.com/help/images/ref/bwdist.html) with four options for distance calculations;<br>
  3D uses [bwdistsc](https://se.mathworks.com/matlabcentral/fileexchange/15455-3d-euclidean-distance-transform-for-variable-data-aspect-ratio) "euclidean" only, by Yuriy Mishchenko.
  <br>*Supports*: 2D/3D 
  <div class="clear-float"></div>

**Elastic distortion filter**  
  ![Elastic Distortion Filter](images/image_filters_elasticdist.jpg){.on-glb align=left width="300"}  
  Applies elastic distortion based on Simard et al., "Best Practices for Convolutional Neural Networks Applied to Visual Document Analysis" ([link](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.160.8494&rep=rep1&type=pdf)). See also [StackOverflow](https://stackoverflow.com/questions/39308301/expand-mnist-elastic-deformations-matlab) and [Elastic Distortion Transformation](https://se.mathworks.com/matlabcentral/fileexchange/66663-elastic-distortion-transformation-on-an-image) by David Franco.  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Entropy filter**  
  ![Entropy Filter](images/image_filters_entropy.jpg){.on-glb align=left width="300"}  
  Local entropy filter; each pixel shows entropy (`-sum(p.*log2(p))`, where `p` is normalized histogram counts) of its neighborhood. See [entropyfilt](https://www.mathworks.com/help/images/ref/entropyfilt.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Frangi filter**  
  ![Frangi Filter](images/image_filters_frangi.jpg){.on-glb align=left width="300"}  
  Enhances elongated or tubular structures using Hessian-based multiscale filtering. Uses [fibermetric](https://www.mathworks.com/help/images/ref/fibermetric.html).  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Gaussian smoothing filter**  
  ![Gaussian Filter](images/image_filters_gaussian.jpg){.on-glb align=left width="300"}  
  Rotationally symmetric Gaussian lowpass filter with size (*Hsize*) and standard deviation (*Sigma*). 2D uses [imgaussfilt](https://www.mathworks.com/help/images/ref/imgaussfilt.html); 3D uses [imgaussfilt3](https://www.mathworks.com/help/images/ref/imgaussfilt3.html).  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Gradient filter**  
  ![Gradient Filter](images/image_filters_gradient.jpg){.on-glb align=left width="300"}  
  Calculates image gradient using [gradient](https://www.mathworks.com/help/images/ref/gradient.html). Result combines X, Y, Z components as `sqrt(X^2 + Y^2 + Z^2)`.  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Laplacian of Gaussian filter**  
  ![LoG Filter](images/image_filters_LoG.jpg){.on-glb align=left width="300"}  
  Highlights edges using the Laplacian of Gaussian filter. Converted to unsigned integers with a *NormalizationFactor*. Uses [imfilter](https://www.mathworks.com/help/images/ref/imfilter.html) with the `log` filter from [fspecial](https://www.mathworks.com/help/images/ref/fspecial.html).  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Mathematical operations**  
  ![Math Ops](images/image_filters_MathOps.jpg){.on-glb align=left width="300"}  
  Applies standard operations (add, subtract, multiply, divide) to the image, with optional class conversion.  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Mode filter (R2020a or newer)**  
  ![Mode Filter](images/image_filters_mode.jpg){.on-glb align=left width="300"}  
  Each pixel shows the mode (most frequent value) in its neighborhood. Uses [modefilt](https://se.mathworks.com/help/releases/R2020a/images/ref/modefilt.html).  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Motion filter**  
  ![Motion Filter](images/image_filters_motion.jpg){.on-glb align=left width="300"}  
  Applies motion blur. Uses [imfilter](https://www.mathworks.com/help/images/ref/imfilter.html) with the `motion` filter from [fspecial](https://www.mathworks.com/help/images/ref/fspecial.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Prewitt filter**  
  ![Prewitt Filter](images/image_filters_prewitt.jpg){.on-glb align=left width="300"}  
  Enhances edges using the Prewitt method. Uses [imfilter](https://www.mathworks.com/help/images/ref/imfilter.html) with the `prewitt` filter from [fspecial](https://www.mathworks.com/help/images/ref/fspecial.html).  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Range filter**  
  ![Range Filter](images/image_filters_range.jpg){.on-glb align=left width="300"}  
  Local range filter; each pixel shows the range (max - min) of its neighborhood. See [rangefilt](https://www.mathworks.com/help/images/ref/rangefilt.html).  
  *Supports*: 2D/3D  
  <div class="clear-float"></div>

**Salt and pepper filter**  
  ![Salt and Pepper Filter](images/image_filters_salt_and_pepper.jpg){.on-glb align=left width="300"}  
  Removes salt & pepper noise using a median filter, then removes pixels above an *IntensityThreshold* based on the difference.  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Sobel filter**  
  ![Sobel Filter](images/image_filters_sobel.jpg){.on-glb align=left width="300"}  
  Enhances edges using the Sobel method. Uses [imfilter](https://www.mathworks.com/help/images/ref/imfilter.html) with the `sobel` filter from [fspecial](https://www.mathworks.com/help/images/ref/fspecial.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Std filter**  
  ![Std Filter](images/image_filters_std.jpg){.on-glb align=left width="300"}  
  Local standard deviation filter; each pixel shows the standard deviation of its neighborhood with symmetric padding. See [stdfilt](https://www.mathworks.com/help/images/ref/stdfilt.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

---

## Edge-preserving filtering

Remove noise while preserving object edges using one of the following filters.


**Anisotropic diffusion filter**  
  ![Anisotropic Diffusion](images/image_filters_ani_diff.jpg){.on-glb align=left width="300"}  
  Edge-preserving anisotropic diffusion with the Perona-Malik algorithm. Uses [imdiffusefilt](https://www.mathworks.com/help/images/ref/imdiffusefilt.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Bilateral filter**  
  ![Bilateral Filter](images/image_filters_bilateral.jpg){.on-glb align=left width="300"}  
  Edge-preserving bilateral filtering with Gaussian kernels. Uses [imbilatfilt](https://www.mathworks.com/help/images/ref/imbilatfilt.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**DNNdenoise filter**  
  ![DNNdenoise Filter](images/image_filters_dnn_denoise.jpg){.on-glb align=left width="300"}  
  Denoises using a deep neural network. Uses [denoiseImage](https://www.mathworks.com/help/images/ref/denoiseimage.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Median filter**  
  ![Median Filter](images/image_filters_median.jpg){.on-glb align=left width="300"}  
  Median filtering; each pixel shows the median value in its neighborhood. 2D uses [medfilt2](https://www.mathworks.com/help/images/ref/medfilt2.html); 3D uses [medfilt3](https://www.mathworks.com/help/images/ref/medfilt3.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Non-local means filter**  
  ![Non-local Means](images/image_filters_non_local_means.jpg){.on-glb align=left width="300"}  
  Uses [imnlmfilt](https://www.mathworks.com/help/images/ref/imnlmfilt.html) for non-local means filtering.  
  *Supports*: 2D  
  <div class="clear-float"></div>

**BMxD filter**  
  ![BMxD Filter](images/image_filters_BMxD.jpg){.on-glb align=left width="300"}  
  Uses block-matching (BM3D v2.01) and 3D collaborative ((BM4D v3.2)) filtering. Licensed for non-profit use only. 
  See installation details in [System requirements](https://mib.helsinki.fi/downloads_systemreq.html#BMxD).  
  *Supports*: 2D  
  <div class="clear-float"></div>
!!! info "BM3D and BM4D References"

    * [**BM3D**] K. Dabov, A. Foi, V. Katkovnik, and K. Egiazarian, Image Denoising by Sparse 3D Transform-Domain Collaborative Filtering, 
      [IEEE Transactions on Image Processing](https://ieeexplore.ieee.org/document/4271520), vol. 16, no. 8, August, 2007.
      preprint at [http://www.cs.tut.fi/~foi/GCF-BM3D](http://www.cs.tut.fi/~foi/GCF-BM3D).
    * [**BM4D**] M. Maggioni, V. Katkovnik, K. Egiazarian, A. Foi, "A Nonlocal Transform-Domain Filter for Volumetric Data Denoising and
      Reconstruction", IEEE Trans. Image Process., vol. 22, no. 1, pp. 119-133, January 2013.  [doi:10.1109/TIP.2012.2210725](https://ieeexplore.ieee.org/document/6253256)
    * [**BM4D**] M. Maggioni, A. Foi, "Nonlocal Transform-Domain Denoising ofVolumetric Data With Groupwise Adaptive Variance Estimation", 
      [Proc. SPIE Electronic Imaging](https://www.spiedigitallibrary.org/conference-proceedings-of-spie/8296/1/Nonlocal-transform-domain-denoising-of-volumetric-data-with-groupwise-adaptive/10.1117/12.912109.short) 2012, San Francisco, CA, USA, Jan. 2012.

---

## Contrast adjustment

Filters intended to adjust image contrast.

**Add noise filter**  
  ![Add Noise](images/image_filters_addnoise.jpg){.on-glb align=left width="300"}  
  Adds noise using [imnoise](https://www.mathworks.com/help/images/ref/imnoise.html). Options:  
  - *Gaussian*: Gaussian white noise  
  - *Poisson*: Poisson noise from the data  
  - *Salt & pepper*: Adds salt and pepper noise  
  - *Speckle*: Multiplicative noise (`J = I + n*I`, `n` is uniform random noise, mean 0, variance 0.05)  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Fast Local Laplacian filter**  
  ![Fast Local Laplacian](images/image_filters_fast_loc_lap.jpg){.on-glb align=left width="300"}  
  Enhances contrast, removes noise, or smooths details. Uses [locallapfilt](https://www.mathworks.com/help/images/ref/locallapfilt.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Flat-field correction**  
  ![Flat-field Correction](images/image_filters_flatfield.jpg){.on-glb align=left width="300"}  
  Corrects grayscale or RGB images using Gaussian smoothing (*sigma*) to approximate shading. Uses [imflatfield](https://www.mathworks.com/help/images/ref/imflatfield.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Local Brighten filter**  
  ![Local Brighten](images/image_filters_local_bright.jpg){.on-glb align=left width="300"}  
  Brightens low-light images. Uses [imlocalbrighten](https://www.mathworks.com/help/images/ref/imlocalbrighten.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Local Contrast filter**  
  ![Local Contrast](images/image_filters_loc_contrast.jpg){.on-glb align=left width="300"}  
  Edge-aware local contrast manipulation. Uses [localcontrast](https://www.mathworks.com/help/images/ref/localcontrast.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Reduce Haze filter**  
  ![Reduce Haze](images/image_filters_reducehaze.jpg){.on-glb align=left width="300"}  
  Reduces atmospheric haze. Uses [imreducehaze](https://www.mathworks.com/help/images/ref/imreducehaze.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

**Unsharp mask filter**  
  ![Unsharp Mask](images/image_filters_unsharpmask.jpg){.on-glb align=left width="300"}  
  Sharpens by subtracting a blurred version from the original. Uses [imsharpen](https://www.mathworks.com/help/images/ref/imsharpen.html).  
  *Supports*: 2D  
  <div class="clear-float"></div>

---

## Image binarization

Filters that process the image and generate a bitmap mask, assignable to the Selection or Mask layers via the <span class="widget widget-dropdown">DestinationLayer</span>.

**Edge filter**  
  ![Edge Filter](images/image_filters_edge.jpg){.on-glb align=left width="300"}  
  Finds edges in intensity images using [edge](https://www.mathworks.com/help/images/ref/edge.html).<br>
  *Supports*: 2D  

<div class="clear-float"></div>

<div class="h3-like">Options:</div>  
  - *Approxcanny*: Faster, less precise Canny approximation  
  - *Canny*: Uses two thresholds for strong/weak edges, less noise-sensitive  
  - *Log*: Finds zero-crossings with Laplacian of Gaussian  
  - *Prewitt*: Uses Prewitt derivative approximation  
  - *Roberts*: Uses Roberts derivative approximation  
  - *Sobel*: Uses Sobel derivative approximation


**SLIC clustering filter**  
  ![SLIC Clustering](images/image_filters_slic.jpg){.on-glb align=left width="300"}  
  Clusters pixels by intensity using the [SLIC algorithm](https://www.epfl.ch/labs/ivrl/research/slic-superpixels).<br> 
  *Supports*: 2D 

<div class="clear-float"></div>
  
<div class="h3-like">Options:</div>  
  - <span class="widget widget-edit">Cluster size</span>: approximate size of each cluster in pixels  
  - <span class="widget widget-edit">Compactness</span>: 100 (square) to 0 (flexible)  
  - <span class="widget widget-edit">ChopX</span>: number of horizontal blocks for memory efficiency  
  - <span class="widget widget-edit">ChopY</span>: number of vertical blocks

!!! info "SLIC References"

    * Radhakrishna Achanta, Appu Shaji, Kevin Smith, Aurelien Lucchi, Pascal Fua, and Sabine Süsstrunk, SLIC Superpixels Compared to State-of-the-art Superpixel Methods, [IEEE Transactions on Pattern Analysis and Machine Intelligence](https://infoscience.epfl.ch/record/177415), vol. 34, num. 11, p. 2274 – 2282, May 2012.
    * Radhakrishna Achanta, Appu Shaji, Kevin Smith, Aurelien Lucchi, Pascal Fua, and Sabine Süsstrunk, SLIC Superpixels, [EPFL Technical Report](https://infoscience.epfl.ch/record/149300) no. 149300, June 2010.

**Watershed clustering filter**  
  ![Watershed Clustering](images/image_filters_watershed.jpg){.on-glb align=left width="300"}  
  Clusters pixels based on ridges using the [watershed algorithm](https://se.mathworks.com/help/images/ref/watershed.html). <br>
  *Supports:* 2D
  
<div class="clear-float"></div>
  
<div class="h3-like">Options:</div> 
  - <span class="widget widget-dropdown">DestinationLayer</span>: assign results to MIB layers  
  - <span class="widget widget-edit">ClusterSize</span>: larger values yield bigger clusters  
  - <span class="widget widget-dropdown">TypeOfSignal</span>: "black-on-white" (electron microscopy) or "white-on-black" (light microscopy)  
  - <span class="widget widget-dropdown">GapPolicy</span>: preserve or fill ridge gaps  
  - <span class="widget widget-dropdown">ResultingShape</span>: "clusters" or "ridges"  
  


---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
