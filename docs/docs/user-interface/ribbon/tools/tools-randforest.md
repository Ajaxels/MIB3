# Random Forest Classifier

Tools for automatic image segmentation using a train-and-predict scheme based on random forest classification.


---

## Overview

The **Random Forest Classifier** in Microscopy Image Browser (MIB) is a powerful method for automatic image segmentation, employing a train-and-predict approach. This implementation is based on [Random Forest for Membrane Detection](http://www.kaynig.de/demos.html) by Verena Kaynig and utilizes the [randomforest-matlab](https://code.google.com/p/randomforest-matlab/) library by Abhishek Jaiantilal. It excels in segmenting complex datasets where traditional methods like global thresholding fail due to varying background intensities.

---

## Dataset and segmentation goal

![Example dataset of endoplasmic reticulum](images/random_forest_1.jpg)

This example features a time-lapse dataset (movie) of endoplasmic reticulum captured using wide-field light microscopy. The goal is to segment the endoplasmic reticulum from the background in flat cellular regions. Global black-and-white thresholding is ineffective here due to intensity gradients across the background, making the random forest classifier a suitable alternative.

---

## Training the classifier

Training involves manually defining regions of interest (object and background) to build a classifier that can later predict segmentation across the dataset.

* Start a new model in the [Segmentation panel](../../panels/segm/index.md) by clicking <span class="widget widget-button">Create</span>
* Add two materials using <span class="widget widget-button">+</span> in the [Segmentation panel](../../panels/segm/index.md)
* Rename the materials:
      - Highlight the first material, right-click, and select *Rename* from the context menu to name it *Object*
      - Rename the second material to *Background* similarly

??? abstract "Snapshot"
    ![Model setup with Object and Background materials](images/random_forest_2.jpg){.on-glb}

* Use the Brush tool to mark areas:
    - Select endoplasmic reticulum profiles and add them to the *Object* material (set *Add to* to `1` and press <span class="widget widget-button">A</span>)
    - Mark background areas and add them to the *Background* material (set *Add to* to `2` and press <span class="widget widget-button">A</span>)

??? abstract "Snapshot"
    ![Manual segmentation of Object and Background](images/random_forest_3.jpg){.on-glb}

* Launch the classifier via `Ribbon → Tools → Classifier → Membrane detection`

??? abstract "Snapshot"
    ![Random Forest Classifier interface](images/random_forest_4.jpg){.on-glb}

By default, the classifier creates a temporary directory (`RF_Temp`) next to the dataset location to store processed images and the classifier file. You can modify the temporary directory name and classifier filename in the <span class="widget widget-edit">Temp dir</span> and <span class="widget widget-edit">Classifier filename</span> fields.

* Configure the classifier:
    - Set <span class="widget widget-dropdown">Object</span> to *Object*
    - Set <span class="widget widget-dropdown">Background</span> to *Background*
    - Adjust <span class="widget widget-edit">Context size</span>: smaller values suit short or highly curved membrane profiles
    - Set <span class="widget widget-edit">Membrane thickness</span>: enter the approximate thickness of the membrane in pixels
    - Review the *Votes* section: adjust the threshold, enable export to MATLAB, or enforce closed membrane profiles

* Click <span class="widget widget-button">Train Classifier</span> to process the current slice and train the classifier based on segmented areas

??? abstract "Snapshot"
    ![Training result on a single slice](images/random_forest_5.jpg){.on-glb}

* If the prediction isn’t satisfactory, segment additional areas (across multiple slices if needed) and retrain. Once satisfied, proceed to step 2 in the workflow and click <span class="widget widget-button">Save classifier</span>

---

## Prediction of the whole dataset

After training and saving the classifier, predict segmentation across the entire dataset.

* In the classifier window, go to step **Predict dataset...**

??? abstract "Snapshot"
    ![Prediction dialog](images/random_forest_6.jpg){.on-glb}

* Test the prediction on any slice by selecting it and clicking <span class="widget widget-button">Predict</span>. If results are acceptable, click <span class="widget widget-button">Predict dataset</span> to process the entire dataset

The prediction results are stored in the *Selection* layer. Transfer them to the *Model* or *Mask* layer for further refinement or saving to disk.

---

## Wiping the temp directory

The classifier generates large temporary files in the `RF_Temp` directory during prediction. Remove them by clicking <span class="widget widget-button">Wipe Temp dir</span> or manually delete the folder using a file explorer.

!!! warning
    Ensure you no longer need the temporary files before wiping the directory, as this action is irreversible

---

## References

- [Random Forest for Membrane Detection](http://www.kaynig.de/demos.html) by Verena Kaynig
- [randomforest-matlab](https://code.google.com/p/randomforest-matlab/) by Abhishek Jaiantilal

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Menu](../index.md) | [Tools](index.md)*