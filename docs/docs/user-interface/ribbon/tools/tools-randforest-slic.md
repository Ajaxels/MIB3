# Classifier of Superpixels/Supervoxels

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Menu](../index.md) | [Tools](index.md)*

Tools for automatic image segmentation using a train-and-predict scheme based on superpixel/supervoxel classification.

---

## Overview

The **Classifier of superpixels/supervoxels** in Microscopy Image Browser is an effective method for automatic image segmentation, employing a train-and-predict approach. It utilizes the [SLIC (Simple Linear Iterative Clustering) algorithm](http://ivrl.epfl.ch/supplementary_material/RK_SLICSuperpixels/index.html) by Radhakrishna Achanta et al. from Ecole Polytechnique Federale de Lausanne (EPFL), Switzerland, to cluster pixels into superpixels (2D) or supervoxels (3D). These clusters are then characterized, and their features are used for classification, simplifying the segmentation process.

---

## Dataset and the aim of the segmentation

![Example dataset for cell outline segmentation](images/superpix_01.jpg){align=left}

This example features a light microscopy dataset where the goal is to segment cell 
outlines (highlighted in green).<br>
Due to varying cell intensities, black-and-white 
thresholding is ineffective, making superpixel/supervoxel classification 
a suitable approach.

<div class="clear-float"></div>

---

## Training the classifier

Training involves manually defining regions of interest (object and background) to build a classifier for predicting segmentation.

* Start a new model in the [Segmentation panel](../../panels/segm/index.md) by clicking <span class="widget widget-button">Create</span>
* Add two materials using <span class="widget widget-button">+</span> in the [Segmentation panel](../../panels/segm/index.md)
* Rename the materials:
   - Highlight the first material, right-click, and select *Rename* from the context menu to name it *Object*
   - Rename the second material to *Background* similarly

??? abstract "Snapshot"
    ![Model setup with Object and Background materials](images/random_forest_2.jpg){.on-glb}

* Use the Brush tool to mark areas:
   - Select cell outlines and add them to the *Object* material (set *Add to* to `1` and press <span class="widget widget-button">A</span>)
   - Mark background areas and add them to the *Background* material (set *Add to* to `2` and press <span class="widget widget-button">A</span>)

??? abstract "Snapshot"
    ![Manual segmentation of Object and Background](images/superpix_02.jpg){.on-glb}

* Launch the classifier via **Ribbon → Tools → Classifier → Superpixel classification**
* Specify a temporary directory (default: `RF_Temp` next to the dataset)

??? abstract "Snapshot"
    ![Superpixel classifier interface](images/superpix_03.jpg){.on-glb}

* Configure the classifier:
   - Select mode: <span class="widget widget-dropdown">2D</span> for 2D images and superpixels, or *3D* for 3D datasets and supervoxels
   - Choose superpixel type: <span class="widget widget-dropdown">SLIC</span> for intensity-distinct objects, or *Watershed* for boundary-defined objects
   - Select <span class="widget widget-dropdown">Color channel</span> for superpixel generation
   - Set <span class="widget widget-dropdown">Size</span> and <span class="widget widget-dropdown">Compactness</span> (for SLIC), or *Size* factor and *Black on white* (for Watershed: `0` for bright boundaries on dark background, >0 otherwise)
   - Optionally adjust the processing area using the *Subarea panel*
* Click <span class="widget widget-button">Calculate superpixels</span> to generate superpixels
* Click <span class="widget widget-button">Preview superpixels</span> to review them

??? abstract "Snapshot"
    ![Superpixel generation and preview](images/superpix_04.jpg){.on-glb}

* If superpixels are satisfactory, click <span class="widget widget-button">Calculate features</span> to extract features
* Click <span class="widget widget-button">Train & Predict</span> to access classification settings

??? abstract "Snapshot"
    ![Training and prediction settings](images/superpix_05.jpg){.on-glb}

* In the training window:
    - Load a previous classifier with <span class="widget widget-button">Load classifier</span>, or train a new one if labels exist
    - Set <span class="widget widget-dropdown">Object</span> to *Object*
    - Set <span class="widget widget-dropdown">Background</span> to *Background*
    - Choose a classifier type in <span class="widget widget-dropdown">Classifier</span>
    - Click <span class="widget widget-button">Train classifier</span> to start training
    - Click <span class="widget widget-button">Predict dataset</span> to predict segmentation
* Check results in the [Image View panel](../../panels/imview/index.md). refine by adding more markers and repeating training and prediction

??? abstract "Snapshot"
    ![Segmentation results](images/superpix_06.jpg){.on-glb}

---

## Wiping the temp directory

The classifier generates temporary files in the `RF_Temp` directory during prediction. Remove them by clicking <span class="widget widget-button">Wipe Temp dir</span> or manually delete the folder using a file explorer.

!!! warning
    Ensure temporary files are no longer needed before wiping, as this action is irreversible

---

## References

- [SLIC (Simple Linear Iterative Clustering) algorithm](http://ivrl.epfl.ch/supplementary_material/RK_SLICSuperpixels/index.html) by Radhakrishna Achanta et al., Ecole Polytechnique Federale de Lausanne (EPFL), Switzerland

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Menu](../index.md) | [Tools](index.md)*