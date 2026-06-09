# Current Release Notes

This page lists the current and potentially beta-version release notes for **Microscopy Image Browser (MIB)**, detailing new features, improvements, and fixes across versions.<br> 
For the latest updates, visit [MIB website](https://mib.helsinki.fi/downloads.html) or check the [Current release notes](index.md).
For the downloads visit [MIB website](https://mib.helsinki.fi/downloads.html) for the development history click [here](release-notes-history.md).

???+ info "RELEASE 2.9103 / 03.06.2025 (SAM2 3D segmentation, updated alignment, new architectures)"
    - [:fontawesome-brands-youtube:{.red-color}](https://youtu.be/o9k8mBgItiA) Added Segment-anything-2 and 2.1 models for manual/semi-automatic segmentation
    - [:fontawesome-brands-youtube:{.red-color}](https://www.youtube.com/watch?v=o9k8mBgItiA&t=2108s)Added Interactive 3D mode for Segment-anything-2 models
    - Added a new version of automatic alignment (Automatic feature-based v2)    
    - [Updated documentation](https://mib.helsinki.fi/help/main2/index.html)
    - [:fontawesome-brands-youtube:{.red-color}](https://youtu.be/sae--XHIjwc) Added loading of part of dataset using BioFormats reader
    - Added modification of the Info box into freeline of Measure Tool    
    - [:fontawesome-brands-youtube:{.red-color}](https://youtu.be/pl9Vdv-qjkE) Added Multi-rename tool for batch renaming of files: Plugins->File processing->Multi rename tool
    - Added option of returning back to a slice: use Alt+scroll wheel to change slice; release Alt to return back to the slice when Alt+scroll wheel was triggered
    - [:fontawesome-brands-youtube:{.red-color}](https://youtu.be/l1RkVkq59To) Added operations with materials: add, insert, rename, reorder, swap, remove, export, save
    - Added swap of colors in the model from the segmentation panel
    - Added SIFT feature detector for automatic alignment
    - Added shortcuts (++shift+d++, ++ctrl+d++) for two favorite segmentation tools
    - Added presets for segmentation tool (++shift++ + ++1++/++2++/++3++ stored the current state and ++1++/++2++/++3++ restores it)
    - Added warning dialog when loading files, while a model exists
    - Added use of annotations to perform single landmark point alignment
    - Added automatic interpolation of annotations when they added using shift+mouse click
    - Added new rendering modes for volumes (CinematicRendering, LightScattering) and overlays (LabelOverlay, VolumeOverlay, GradientOverlay) in MIB rendering
    - Added rotation around selected object, ambient and diffuse lights in MIB 3D volume rendering
    - Added pattern rename of annotations
    - Fixed adding a model in the rotated view when the blockMode is on
    - Fixed 3D rendering of the selected material
    - Replaced ++alt+shift++ + <mouse class="right"></mouse> with ++alt+shift+ctrl++ + <mouse class="right"></mouse> to pan the view using Wacom pen eraser
    - **\[DeepMIB\]** Added U-net +Encoder architecture into 2D and 2.5D semantic segmentation workflows    
    - **\[DeepMIB\]** Rearranged selection of the encoder network
    - **\[DeepMIB\]** Added weights preview in the Activation explorer
    - **\[DeepMIB\]** Added image downsampling parameter for automatic resizing of images for prediction
    - **\[DeepMIB\]** Added automatic saving of the custom training plot as PNG and MATLAB-FIG
    - **\[DeepMIB\]** Added saving of MIB version into the mibCfg and mibDeep files
    - **\[DeepMIB\]** Fixed Explore activations when images for prediction are not under Images directory
    - **\[DeepMIB\]** Fixed training of 2.5D networks without augmentations
    - **\[DeepMIB\]** Fixed correct handling of random numbers in the augmentation patches preview
    - **\[DeepMIB\]** Fixed accidental appearance of Deep.AugOpt2D.ImageNoise field in augmentation preferences
    - \[2.9102\] Added an option to automatically show a dialog to provide information about an added measurement into the Measure Tool
    - \[2.9102\] Fixed the Graphcut tool in the 2D current slice mode
    - \[2.9103\] Bug fixes

???+ info "RELEASE 2.92 beta / 02.09.2025 (OME-Zarr)"
    - \[2.9104\] Fix mibVolRenAppController to import overlays for R2024a, update BioFormats to 8.2.0
    - \[2.9105\] added Select Image Frame to Batch processing, bug fixes, updated syntax of BatchOpt parameters for radio-groups
    - \[2.9106\] added image conversion to OME-ZARR v2/v3 into Plugins->File processing->Image converter, added Future compatibility flag for GPU Devices
	- \[2.9108\] added loading of OME-Zarr v2 and v3 via Combine selected dataset option available via RMB (virtual mode, requires [zarr-python](https://mib.helsinki.fi/downloads_systemreq.html#zarr))
    - \[2.9109\] added generation of centered grid for Stereology
    - \[2.9110\] changed image resize from width in pixels to downsampling factor in Automatic feature-based v2 alignment
    - \[2.9111\] update BioFormats to 8.3.0, bug fixes

*Back to [MIB](../../index.md) | [Getting started](../index.md)*