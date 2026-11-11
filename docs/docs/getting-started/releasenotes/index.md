# Current Release Notes

This page lists the current and potentially beta-version release notes for **Microscopy Image Browser (MIB)**, detailing new features, improvements, and fixes across versions.<br> 
For the latest updates, visit [MIB website](https://mib.helsinki.fi/downloads.html) or check the [Current release notes](index.md).
For the downloads visit [MIB website](https://mib.helsinki.fi/downloads.html) for the development history click [here](release-notes-history.md).

<!-- mib.helsinki.fi/downloads.html shows this block as the "GitHub nightly version" notes: it reads the
     built docs/html copy of this page from GitHub master and picks the collapsible block whose title
     starts with "NEXT RELEASE". Keep that title prefix while the block exists; renaming it at a release
     hides the box on the website. -->

???+ info "NEXT RELEASE (in development)"
    - **OME-Zarr pyramids**: every coarser level is now exactly half the size of the level above, so
      all levels line up with the full-resolution image, also in other OME-Zarr viewers. The same
      data gives the same pyramid whether it is converted to BigData, saved as OME-Zarr, or written
      by the Image converter. Pyramids written by earlier versions can differ slightly at the coarser
      levels when the image width or height is an odd number.
    - **Image converter, OME-Zarr output**:
        - faster; with **Parallel processing** the workers share the conversion
        - an interrupted or cancelled conversion can be resumed with the same settings
        - TIF images too large for the memory are converted in parts
        - the memory needed is checked before the conversion starts
        - a failed conversion is reported as failed, and MIB warns when an incomplete dataset is opened
        - the output directory must be empty or hold a previous Zarr dataset
    - **DeepMIB, StarDist**: a new architecture of the 2D Instance workflow for round and oval objects
      such as nuclei, round cells or vesicles, also when they are packed densely. Fine-tune the
      pretrained `2D_versatile_fluo` model (downloaded on first use) or train a new network; no
      Python is needed, also in the standalone version. Includes a test of whether the objects suit
      StarDist and tuning of the detection thresholds after training.
      See [2D Instance Segmentation](../../deepmib/deepmib-instance.md#stardist)
    - **DeepMIB, evaluation of 2D Instance predictions**: *Evaluate segmentation* matches the
      predicted objects with the ground-truth objects and reports precision, recall, F1 and panoptic
      quality over a range of IoU thresholds, per image and for the whole set; export to MATLAB,
      Excel or CSV. See [Evaluating the predictions](../../deepmib/deepmib-instance.md#evaluating-the-predictions)
    - **DeepMIB, OME-Zarr images**: OME-Zarr images (v2 and v3) are predicted directly, at a chosen
      pyramid level. With the *Zarr3 (BigData model)* output, the result opens as an editable BigData
      model
    - **BigData instance model**: a new 16383-material model for BigData datasets, one index per
      object; 63-material BigData models can be converted to it, into a new model store
    - **Close model**: new entry of the buffer context menu in the Datasets panel; closes the model and
      keeps the dataset open, ++ctrl+z++ brings the model back
    - **Chunk dataset**: a downsampled pyramid level of a BigData or OME-Zarr dataset can be chunked;
      a model segmented on these tiles is fused back into the matching level of the BigData model
    - **Stitching**: the inspector handles mosaics of Z-stacks; the *Fix Z* table lists the section
      or slice boundaries, each opened in the Fix Z boundary view
    - **Resize dataset** can be cancelled; downloads show their progress
    - **Resize dataset**: *max pooling* and *min pooling* methods for images and labels keep thin
      structures, such as membranes in a probability map, when the dataset is made smaller
    - **Sharpness and noise**: a new tool in *Image tools* that measures the resolution and noise of selected
      areas, detects astigmatism and gives focus scores; results of different images collect in one
      table for comparison.
      See [Sharpness and noise](../../user-interface/ribbon/image/image-tools-sharpness.md)
    - **BigData image processing**: the image tools now work on BigData datasets too large for the
      memory, reading them from disk:
        - [Image filters](../../user-interface/ribbon/image/image-filters.md#bigdata-datasets),
          [Image Arithmetics](../../user-interface/ribbon/image/image-tools-arithmetic.md#bigdata-datasets),
          [MorphOps](../../user-interface/ribbon/image/image-morphops.md#bigdata-datasets),
          [White balance](../../user-interface/ribbon/image/image-tools-whitebalance.md#bigdata-datasets)
          and [Normalize layers](../../user-interface/ribbon/image/normalize.md#bigdata-datasets)
          write the result to a new OME-Zarr store or to a Standard dataset in memory; Image filters
          and Image Arithmetics can also overwrite the image on disk
        - [Global thresholding](../../user-interface/ribbon/tools/tools-globalthres.md#bigdata-datasets)
          and the Edge filters write into the mask or selection
        - Image filters can be limited to the ROIs and can run on parallel workers; the pool is
          started and stopped from *Home ribbon -> Preferences -> Parallel pool*
        - a cancelled run to a new store can be kept and resumed later
    - **BigData locks**: the image and the labels of a BigData dataset can be locked against
      accidental changes; a loaded model opens locked by default.
      See [BigData datasets](../dataset-types/index.md#bigdata)
    - **Restrict to ROI**: a new checkbox of the
      [Selection panel](../../user-interface/panels/selection_imview/selection.md#additional-controls)
      limits the ROI-aware tools to the selected ROI, or to all ROIs
    - **Selection in Standard datasets**: moving a 3D selection to the model or mask and clearing it
      take time and undo memory according to the size of the selection, not of the whole volume
    - **Snapshot**: outlines and labels of the ROIs can be added to the snapshot
    - **Preferences, Fine-tuning**: a new category for small adjustments of existing actions, such
      as the zoom step of the ++q++ / ++w++ keys.
      See [Fine-tuning](../../user-interface/ribbon/home/home-preferences.md#fine-tuning)
    - **Amira Mesh, RLE compression**: reading and writing RLE-compressed AM files is faster
    - **Fixes**:
        - MATLAB no longer crashes at exit after ZARR files were opened in a session that also used
          Computer Vision Toolbox features
        - Image converter: OME-Zarr conversion of AmiraMesh volumes
        - DeepMIB: *Export network*
        - the installation directory of MIB on macOS is detected correctly

???+ info "RELEASE 2026.09 / 03.06.2025 (MIB3 release)"
    - Release

*Back to [MIB](../../index.md) | [Getting started](../index.md)*