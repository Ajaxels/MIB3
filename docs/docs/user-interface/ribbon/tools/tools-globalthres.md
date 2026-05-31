# Global Black-and-White Thresholding

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Tools](index.md)*

Tools for performing global black-and-white thresholding on datasets in Microscopy Image Browser (MIB).

---

## Overview

![Global thresholding interface](images/menuToolsSemiautoSegmAutomaticThresholding.png){.on-glb}

The **Global black-and-white thresholding** tool in MIB applies various algorithms to segment images 
into binary (black-and-white) regions based on pixel intensity. This tool is accessible 
via `Ribbon → Tools → Semi-automatic segmentation → Global thresholding` and supports multiple thresholding methods, 
each suited to different image characteristics.

<div class="h3-like">Demonstration</div>:  
[:fontawesome-brands-youtube:{.red-color} Global black and white thresholding in MIB](https://youtu.be/mzfgxLvkGTI)

---

## Algorithms for global black and white thresholding

### CONCAVITY algorithm

<div class="h3-like">Details</div> 

- Suitable when images lack distinct objects and background, rendering MINIMUM and INTERMODES algorithms ineffective
- Identifies a threshold at the histogram's shoulder using concavity analysis
- Constructs the convex hull *H* of the histogram *y*
- Finds local maxima of *|H - y|*
- Sets threshold *t* to the value of *j* maximizing the balance measure *bj = Aj(An - Aj)*
- Works well in many cases but may produce unusable thresholds in some scenarios

!!! abstract "References and Acknowledgements"

     - A. Rosenfeld and P. De La Torre, "Histogram concavity analysis as an aid in threshold selection," *IEEE Trans. Systems Man Cybernet.*, vol. 13, pp. 231-235, 1983
     - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### ENTROPY algorithm

<div class="h3-like">Details</div>

- A maximum entropy method that splits the histogram into two probability distributions: objects and background
- Chooses threshold *t* to maximize the sum of entropies of these distributions
- Defines partial sums:  
  *Ej = Σ(i=0 to j) yi · log(yi)*, for *j = 0, ..., n*
- Sets *t* to the value of *j* maximizing:  
  *(Ej / Aj) - log(Aj) + ((En - Ej) / (An - Aj)) - log(An - Aj)*
    
!!! abstract "References and Acknowledgements"  
    
    - J. N. Kapur, P. K. Sahoo, and A. K. C. Wong, "A new method for gray-level picture thresholding using the entropy of the histogram," *Comput. Vision Graphics Image Process.*, vol. 29, pp. 273-285, 1985
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### INTERMEANS ITER algorithm

<div class="h3-like">Details</div> 

- An iterative algorithm similar to OTSU but less computationally intensive
- Starts with an initial guess for threshold *t*
- Calculates means *μt* and *νt* for the two classes
- Updates *t = [(μt + νt) / 2]* and recalculates *μt* and *νt*
- Repeats until *t* stabilizes across iterations
- Results may depend heavily on the initial *t* value
- Use MEAN for comparable object and background areas; use INTERMODES for small objects relative to the background

!!! abstract "References and Acknowledgements"

    - T. Ridler and S. Calvard, "Picture thresholding using an iterative selection method," *IEEE Trans. Systems Man Cybernet.*, vol. 8, pp. 630-632, 1978  
    - H. J. Trussell, "Comments on ‘Picture thresholding using an iterative selection method’," *IEEE Trans. Systems Man Cybernet.*, vol. 9, p. 311, 1979
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### INTERMODES algorithm

<div class="h3-like">Details</div>

- An alternative to MINIMUM, assuming a bimodal histogram
- Identifies two peaks (local maxima) *yj* and *yk*
- Sets *t = (j + k) / 2*
- Refines *t = [(μt + νt) / 2]* and recalculates *μt* and *νt*
- Unsuitable for histograms with extremely unequal peaks

!!! abstract "References and Acknowledgements"

    - J. M. S. Prewitt and M. L. Mendelsohn, "The analysis of cell images," *Ann. New York Acad. Sci.*, vol. 128, pp. 1035-1053, 1966
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### MEAN algorithm

<div class="h3-like">Details</div>

- Similar to MEDIAN but uses the mean instead
- Sets *t* to the integer part of the mean of all pixel values: *t = Bn / An*
- Ignores histogram shape, often yielding suboptimal results

!!! abstract "References and Acknowledgements"

    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### MEDIAN and PERCENTILE algorithms

<div class="h3-like">Details</div>

- Assumes a known percentage of object pixels
- Sets *t* to the highest gray-level mapping at least *(100 - p)%* of pixels to the object category
- Not ideal if object area is unknown
- Parametric issue resolved by setting *p = 50*, making *t* the median of pixel values

!!! abstract "References and Acknowledgements"

    - W. Doyle, "Operation useful for similarity-invariant pattern recognition," *J. Assoc. Comput. Mach.*, vol. 9, pp. 259-267, 1962
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### MINERROR algorithm

<div class="h3-like">Details</div>

- Similar to OTSU, treating the histogram as a probability density function of a mixture population
- Assumes a Gaussian mixture model with normal distributions for objects and background, allowing different means and variances
- Defines statistics:  
      *pt = At / An*, *qt = (An - At) / An*  
      *σt² = (Ct / At) - μt²*, *τt² = ((Cn - Ct) / (An - At)) - νt²*
- Sets *t* to minimize:  
      *pj log(σj / pj) + qj log(τj / qj)*

!!! abstract "References and Acknowledgements"

    - J. Kittler and J. Illingworth, "Minimum error thresholding," *Pattern Recognition*, vol. 19, pp. 41-47, 1986
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### MINERROR ITER algorithm

<div class="h3-like">Details</div>

- An iterative, less intensive version of MINERROR
- Initializes *t* using MEAN
- Solves:  
      *x² (1/σ² - 1/τ²) - 2x (μ/σ² + ν/τ²) + (μ²/σ² - ν²/τ² + log(σ²q² / τ²p²)) = 0*
- Sets *t = (w1 + √(w1² - w0w2)) / w0*, where *w0*, *w1*, and *w2* are the equation terms
- Recalculates and repeats until convergence
- Fails if the quadratic equation lacks a real solution

!!! abstract "References and Acknowledgements"

    - J. Kittler and J. Illingworth, "Minimum error thresholding," *Pattern Recognition*, vol. 19, pp. 41-47, 1986
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### MINIMUM algorithm

<div class="h3-like">Details</div>

- Assumes a bimodal histogram
- Smooths the histogram with a three-point mean filter until only two local maxima remain
- Chooses *t* where *yt-1 > yt < yt+1*
- Unsuitable for histograms with unequal peaks or broad, flat valleys

!!! abstract "References and Acknowledgements"

    - J. M. S. Prewitt and M. L. Mendelsohn, "The analysis of cell images," *Ann. New York Acad. Sci.*, vol. 128, pp. 1035-1053, 1966
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### MOMENTS algorithm

<div class="h3-like">Details</div>

- Sets *t* to preserve the first three moments of the gray-level image in the binary result
- Calculates *t* where *At / An* is closest to *x0*:  
      *x0 = ½ - (Bn/An + x2/2) / √(x2² - 4x1)*  
      *x1 = (BnDn - Cn²) / (AnCn - Bn²)*, *x2 = (BnCn - AnDn) / (AnCn - Bn²)*, *Dn = Σ(i=0 to n) i²yi*

!!! abstract "References and Acknowledgements"

    - W. Tsai, "Moment-preserving thresholding: a new approach," *Comput. Vision Graphics Image Process.*, vol. 29, pp. 377-393, 1985
    - Based on the [HistThresh Toolbox](https://github.com/carandraug/histthresh) by Antti Niemistö, Tampere University of Technology, Finland

---

### OTSU algorithm

<div class="h3-like">Details</div>

- Implements MATLAB’s Otsu algorithm via [graythresh](https://se.mathworks.com/help/releases/R2024b/images/ref/graythresh.html)
- Calculates an optimal threshold *t* to minimize intra-class variance

!!! abstract "References and Acknowledgements"

    - N. Otsu, "A Threshold Selection Method from Gray-Level Histograms," *IEEE Transactions on Systems, Man, and Cybernetics*, vol. 9, no. 1, pp. 62-66, 1979

---

## Programming tips

This tool supports batch scripting for automation.

??? abstract "Example of usage"

    Define parameters in a structure, using field names from widget tooltips (some are optional), and start the controller:

    ```matlab
    BatchOpt.colChannel = 2;         % define color channel for thresholding
    BatchOpt.Mode = '3D, Stack';     % mode to use
    BatchOpt.Method = 'Otsu';        % thresholding algorithm
    BatchOpt.Destination = 'selection'; % [optional] destination layer, 'mask' or 'selection'
    BatchOpt.t = [1 1];              % [optional] time points, [t1, t2]
    BatchOpt.z = [10 20];            % [optional] slices, [z1, z2]
    BatchOpt.x = [10 120];           % [optional] part of the image, [x1, x2]
    BatchOpt.Orientation = 4;        % [optional] dataset orientation
    obj.startController('mibHistThresController', [], BatchOpt); % start thresholding
    ```
---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Tools](index.md)*
