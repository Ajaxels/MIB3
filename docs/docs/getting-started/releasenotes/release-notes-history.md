# Hitrory of Releases

---

This page lists the release history for **Microscopy Image Browser (MIB)**, detailing new features, improvements, and fixes across versions.<br> 
For the latest updates, visit [MIB website](https://mib.helsinki.fi/downloads.html) or check the [current release notes](index.md).


??? abstract "2.9012 / 24.07.2024 (SAM segmentation, Multi-GPU training, 2.5D CNNs)"
    - To comply with dependencies the MIB license was updated from GPLv2 to GPLv3
    - Added Segment anything (Standard and Microscopy) models for manual/semi-automatic segmentation
    - Added Rename materials to batch processing operations
    - Added possibility to skip loading of metadata
    - Added the Cancel button to the progress bar upon loading of images
    - Added recoloring of materials for models with 65535+ materials
    - Added crop of 3D volumes from 2D objects detected using the Get Statistics window
    - Added options to change thickness of model and mask contour lines (Menu->File->Preferences->Colors and styles->Contours)
    - Added drag and drop *.mask files to the Image view panel to load them
    - Added drag and drop *.ann files to the Image view panel or the Segmentation table to load annotations
    - Added paste of annotation values from clipboard
    - Added auto fill switch to the Selection panel to fill the shapes after use of brush
    - Added jitter coordinates option into crop out patches for annotations and objects
    - Added \[F\] template for exporting statistics via batch processing
    - Added saving of projects, copy to clipboard and open in file explorer for directories in Rename and Shuffle->Restore
    - Added possibility to load measurements (*.measure) from multiple files and added filename to export of measurement in the Excel format
    - Added possibility update colors of annotations into the Annotation list window
    - Added key shortcuts to zoom in to 100% and fit to view
    - Added key shortcut to rename materials (default F2)
    - Added key shortcuts to change the brush size (default '\[' and '\]')
    - Added possibility to hide the Path and the bottom panels via a dropdown menu
    - Added filename identifier when exporting object quantification
    - Added filename identifier when exporting annotations to Excel or CSV
    - Added "Center-top" and "Center-bottom" locations to Add frame
    - Added "Set value" to the batch modify selected annotations
    - Added interpolation operation to the List of Annotations
    - Added options to add annotation names and coordinates to filenames when generating patches
    - Added automatic selection of materials from selected rows in the segmentation table
    - Added option to add multiple empty slices
    - Added selection of colors for materials into the segmentation table
    - Added fusing of a larger model into a smaller dataset crop
    - Added possibility to define black and white points lower and higher than the image class
    - Added possibility show masks as filled shapes
    - Added an option to add annotation name when exporting to PSI format
    - Added measurements to Rename and Shuffle
    - Added save of models and masks to PNG format
    - Added the Threshold button to the BW thresholding tool
    - Added user tiers
    - Improved calculation of DistanceMaps in 3D for isotropic voxels
    - Changed usage of the Object picker tool
    - Changed how the object id values are displayed in the Statistics window
    - Fixed Add frame when dX or dY is 0
    - Fixed Resize of models that have more than 255 materials
    - Updated Bio-Formats to 7.2.0
    - **\[DeepMIB\]** Added 2.5D network architectures for semantic segmentation
    - **\[DeepMIB\]** Added training using Multi-GPU configuration
    - **\[DeepMIB\]** Added prediction using Multi-GPU configuration
    - **\[DeepMIB\]** Added new dialog to specify augmentation settings
    - **\[DeepMIB\]** Added drag-and-drop of "mibCfg" project files
    - **\[DeepMIB\]** Added duplication operation to make a copy of a trained network
    - **\[DeepMIB\]** Added padding parameter to symmetrically pad the image
    - **\[DeepMIB\]** Added symmetric padding for prediction
    - **\[DeepMIB\]** Added export of the trained network to TensorFlow format
    - **\[DeepMIB\]** Added 'MATLAB non-compressed format (range 0-1)'
    - **\[DeepMIB\]** Added possibility to predict images that are not under Images subfolder
    - **\[DeepMIB\]** Added an option to calculate loss excluding Exterior
    - **\[DeepMIB\]** Added sending of email notifications about training progress
    - **\[DeepMIB\]** Added preview of a network stored in mibDeep file
    - **\[DeepMIB\]** Added possibility to mask-away areas without preprocessing
    - **\[DeepMIB\]** Improved handling of directories
    - **\[DeepMIB\]** Extended the Evaluate segmentation plot
    - \[2.9002\] Updated GUI windows
    - \[2.9003\] Added 'mib_prefs_override.mat' file to override default settings
    - \[2.9004\] Fix accidental incompatibility augmentation settings bug
    - \[2.9005\] Added update on zoom for snapshot and movie maker tools
    - \[2.9006\] Added usage of a reference slice for contrast normalization
    - \[2.9007\] Fixed import of older DeepMIB configs
    - \[2.9008\] Fixed selection of 2D objects in Get Statistics
    - \[2.9009\] Added SAM for YZ and XZ orientations
    - \[2.9010\] Fix of file check during transfer learning
    - \[2.9011\] Added "add, +next material" to SAM
    - \[2.9012\] Added currently selected material to move layers; fixed indices for annotations; added import of landmarkAscii and landmarkBin

??? abstract "2.84 / 09.12.2022 (new 3D viewer and HDD alignment)"
    - Added Example datasets
    - Added new Volume renderer
    - Added export images to OME-TIFF 5D format
    - Added alignment of datasets without loading
    - Added white balance correction
    - Added modification of annotation size
    - Added \[F\] template for saving images
    - Added showWaitbar option to Batch Processing
    - Added resizing of panels to batch processing
    - Added erosion of models with parallel processing
    - Added dilation of models
    - Added linking of views
    - Added calculation of DistanceMaps relative to model, masks, or selections
    - Added basic mathematical operations to image filters
    - Added destination "Current" to Intensity Projection
    - Updated Bio-Formats to 6.11.0
    - Updated Plugins->TripleAreaIntensity to highlight connected objects
    - Fixed bug in shape interpolation
    - Fixed slow update of selected directory
    - Fixed application of MorphOps
    - Fixed loading of some jpg files
    - **\[DeepMIB\]** Added prediction of 3D stacks with 2D models
    - **\[DeepMIB\]** Added possibility to specify patch size during augmentation
    - **\[DeepMIB\]** Added 'DeepLabV3 Xception' and 'DeepLabV3 Inception-ResNet-v2'
    - **\[DeepMIB\]** Added swish activation layer
    - **\[DeepMIB\]** Added a function to balance classes
    - **\[DeepMIB\]** Added network preview for deployed version
    - **\[DeepMIB\]** Added saving of custom training plot
    - **\[DeepMIB\]** Added scaling of loss function plot
    - **\[DeepMIB\]** Fixed generation of score maps

??? abstract "2.831 / 21.06.2022; 2.83 / 19.06.2022 (blockedImage and 2D patch-wise)"
    - Added generation of image 2D and 3D patches around annotation labels
    - Added possibility to load part of the dataset for TIF files
    - Added Info field to measurements
    - Added generation of pyramidal TIF files
    - Added the "show prompt" option to Annotations tool
    - Added \[InheritLastDIR\] tag to inherit directory name
    - Added "end" tag to crop operation
    - Added Drag-and-drop model files
    - \[2.831\] Added Destination: Current to Crop
    - Correction of pixel size for pyramidal formats
    - Fixed loading of partial AM files
    - Fixed loading of TIF files with YCbCr color space
    - \[2.831\] MATLAB versions compatibility bug fixes
    - Updated Bio-Formats to 6.10.0
    - **\[DeepMIB\]** Rearranged Architecture into Workflow
    - **\[DeepMIB\]** Optimized to work without preprocessing
    - **\[DeepMIB\]** Added blockedImage mode
    - **\[DeepMIB\]** Added dynamic masking
    - **\[DeepMIB\]** Added 2D Patch-wise mode
    - **\[DeepMIB\]** Added Resnet18, Resnet50, Resnet101, Xception networks
    - **\[DeepMIB\]** Added alternative arrangement of files
    - **\[DeepMIB\]** Added "Load models" to Options tab
    - **\[DeepMIB\]** Added frequency of saving checkpoint networks
    - **\[DeepMIB\]** Added percentage parameter to overlapping tiles
    - **\[DeepMIB\]** Added possibility to select a single augmentation
    - **\[DeepMIB\]** Added new 3D augmentations
    - **\[DeepMIB\]** Added DeepLabV3-Resnet50
    - **\[DeepMIB\]** Fixed preview of patches

??? abstract "2.82 / 12.04.2022 (DeepLabV3, kymographs, key callbacks)"
    - Added generation of kymographs
    - Added indexing of objects in a model
    - Added main window keypress callbacks
    - Added reading of pixel size from Zeiss SmartSEM
    - Added automatic extraction of metadata
    - Added "Selected files" option
    - Added 'ndpi' format
    - Added new options for faster measurements
    - Added Esc key shortcut
    - Added Shift+Alt+RMB key shortcut
    - Fixed loading of selected series
    - Fixed starting of Fiji volume viewer
    - Fixed usage of Shift+LMB operations
    - Fixed delete operation of a single tree
    - Fixed resize in batch processing
    - Bug fixes
    - **\[DeepMIB\]** Added 2D DeepLabV3-Resnet18 architecture
    - **\[DeepMIB\]** Added selection of output format
    - **\[DeepMIB\]** Added return of trained network
    - **\[DeepMIB\]** Added indicator of iteration
    - **\[DeepMIB\]** Fixed probability of augmented patch
    - \[MCcalc\] Added calculation of areas
    - \[MCcalc\] Added calculation contacts

??? abstract "2.81 / 14.10.2021"
    - Added contrast adjustment for 16-bit
    - Added import of annotations from CSV
    - Added conversion of annotations to mask
    - Added save of models to mibCat format
    - Added automatic closing of Fiji windows
    - Added information about "Call4Help"
    - Fixed bug in Stereology tool
    - Fixed automatic feature-based alignment
    - Updated Bio-Formats to 6.7.0
    - **\[DeepMIB\]** Added counting of labels
    - **\[DeepMIB\]** Fixed bug with Multi GPU

??? abstract "2.802 / 01.06.2021"
    - Added HDD mode to align datasets
    - Added new preference dialog
    - Added exclusion of Stretch and Shear peaks
    - Added re-ordering of annotations
    - Added precision edit box
    - Added "Extra depth to show annotations"
    - Added saving of models as 2D sequence
    - Added Mode filter
    - Added "File and Directory operations"
    - Added plugin for converting images
    - Added plugin detection of contacts
    - Added shift of color channels
    - Added check for new version
    - **\[DeepMIB\]** Added selection of GPU/CPU
    - **\[DeepMIB\]** Added GPU Info window
    - **\[DeepMIB\]** Added training without preprocessing
    - **\[DeepMIB\]** Added parallel pre-processing
    - **\[DeepMIB\]** Added compatibility with TIF and PNG
    - **\[DeepMIB\]** Added masking
    - **\[DeepMIB\]** Added 19 2D augmentation operations
    - **\[DeepMIB\]** Added configurable preview
    - **\[DeepMIB\]** Added configurable preview during training
    - **\[DeepMIB\]** Added selection of activation layers
    - **\[DeepMIB\]** Added Transfer Learning
    - **\[DeepMIB\]** Added setting of mini-batch size
    - **\[DeepMIB\]** Added export of prediction scores
    - **\[DeepMIB\]** Added Sørensen-Dice similarity
    - **\[DeepMIB\]** Added export to CSV
    - **\[DeepMIB\]** Added export to ONNX format
    - Updated reading of NRRD files
    - Updated export statistics
    - Updated Bio-Formats to 6.6.1
    - Updated for MATLAB R2021a
    - Fixed missing "Add to" checkbox
    - Fixed loading of AM files
    - Fixed preview behavior
    - Fixed 3d backup operation
    - Fixed vertical flip of MRC datasets
    - Replaced quantile function
    - Bug fixes

??? abstract "2.70 / 18.05.2020"
    - Added Deep MIB for training
    - Added 2D Elastic Distortion filter
    - Added resizing of Image Arithmetics
    - Added selection of a seed
    - Fixed issues with importing

??? abstract "2.66 / 25.04.2020"
    - Added direct conversion from Mask to Model
    - Added drag-and-drop for *.model files

??? abstract "2.651 / 25.04.2020"
    - Added smoothing of multiple materials
    - Fixed definition of starting point
    - Fixed setData method

??? abstract "2.65 / 23.03.2020"
    - Added Drag and drop files
    - Added dialog with 30 new image filters
    - Added dataset alignment using AMST
    - Added wound healing assay
    - Added transformation of Z to C
    - Added additional options to batch processing
    - Added backup of mibImage class
    - Added full backup for dataset operations
    - Added squeezing of material indices
    - Added a new key shortcut ('n')
    - Added saving snapshots in PNG
    - Added measurements to restore shuffled datasets
    - Updated resampling
    - Updated Bio-Formats to 6.4.0
    - Swapped Log and Info buttons
    - Tweaked names of plugins
    - Optimized handling of Java classes
    - Plugins: Surface Area 3D
    - Plugins: Spacial Control Points
    - Plugins: Cell Wall Thickness

??? abstract "2.601 / 04.11.2019"
    - Deployed version with R2019b
    - Added Batch mode
    - Added visualization of models
    - Added Drag & Drop materials
    - Added alignment of color channels
    - Added content-aware fill
    - Added debris removal tool
    - Added ORB points
    - Added correction for instant jumps
    - Added export of quantitation results
    - Added export to CSV
    - Added copy to clipboard
    - Added batch modification
    - Added 4D options
    - Added calculation of quantile
    - Added "Ctrl+e" key shortcut
    - Added export of graphs
    - Rewritten Image arithmetics
    - Updated use of xlswrite
    - Updated data conversion
    - Updated Bio-Formats to 6.2.1
    - Bug fixes
    - Added export of annotations to CSV

??? abstract "2.51 / 13.03.2019"
    - Added automatic global thresholding
    - Added selection of materials
    - Added focus stacking
    - Added saving of HDF5
    - Added saving of AmiraMesh
    - Added display of orthoslice
    - Added tip of the day
    - Added H-maxima and H-minima
    - Added Single Mask object
    - Added export of supervoxels
    - Improved performance
    - Improved Image arithmetics
    - Updated BioFormats reader
    - Updated sorting
    - Fixed initialization of 3D rendering
    - Fixed pixel size
    - Fixed adding icons

??? abstract "2.501 / 21.12.2018"
    - Added swap slices option
    - Fixed rendering of combined image
    - Fixed Copy Slice

??? abstract "2.50 / 17.12.2018"
    - Added hardware accelerated 3D rendering
    - Added automatic image alignment
    - Added 20 distinct colors palette
    - Added center point marker
    - Added shuffling of annotations
    - Added delete multiple materials
    - Added change default filters
    - Added contrast normalization
    - Added fuse of annotations
    - Added auto removal of spaces
    - Added loading of masks
    - Added alternative way to specify frame
    - Improved Lasso mode
    - Updated Bio-Formats to 5.9.2
    - Fixed compatibility issues
    - Fixed bug in object separator
    - Fixed scale bar instructions
    - Fixed update of color channel
    - Fixed conversion to grayscale
    - Fixed insert of datasets
    - Fixed scroll wheel
    - Fixed combine files
    - Fixed missing values
    - Fixed computation of statistics
    - Fixed cropping of selection
    - Fixed alignment

??? abstract "2.40 / 31.08.2018"
    - Added virtual mode
    - Added shift of annotations
    - Added Segment All function
    - Improved performance
    - Updated BioFormats to 5.9.1
    - Bug fixes

??? abstract "2.302 / 18.05.2018 (03.07.2018)"
    - Added Lines3D class
    - Added Image arithmetics dialog
    - Added Rename and Shuffle tool
    - Added alignment using landmarks
    - Added modification of Imaris path
    - Added calculation of 3D skeleton
    - Added export to MATLAB VolumeViewer
    - Added quantitation of objects
    - Added insert an empty slice
    - Added recentering the view
    - Added export of TransformationMatrix
    - Fix of cropping objects
    - \[2.301\] Added filter for filenames
    - \[2.302\] Fixed export of 3D lines
    - \[2.302\] Fixed recalculation of pixels

??? abstract "2.22 / 16.03.2018"
    - Added value field for annotations
    - Added deep neural network denoising
    - Added Simplify button
    - Added rendering with Imaris
    - Added rendering snapshots
    - Added rendering of annotations
    - Added Get Statistics
    - Added external BMxD filters
    - Added Add Frame tool
    - Added renaming of annotations
    - Improved movie rendering
    - Updated Image Filter panel
    - Fix of error in Morph Closing
    - Fix callback
    - Fix of opening of AmiraMesh

??? abstract "2.211 / 21.12.2017"
    - Updated TripleAreaIntensity plugin
    - Fix, replaced contains with ismember
    - Fix of lost key press callbacks
    - Fix of loading hdf5 datasets
    - Minor bug fixes

??? abstract "2.21 / 04.12.2017"
    - Added model with 4294967295 materials
    - Improved object picker
    - Fix compiling of certain function
    - Fix of 'Fix selection to material'
    - Fix connection to Omero

??? abstract "2.20 / 14.11.2017"
    - Added 3D Grid mode to Graphcut
    - Added denoise of image
    - Added export annotations to Imaris
    - Added possibility to skip intensity profiles
    - Added buttons to magnify snapshots
    - Added reading of material names
    - Added insert of dataset
    - Added utilization of block mode
    - Rearranged Graphcut, Watershed
    - Updated Crop tool
    - Updated calculation of curve lengths
    - Updated connection to Imaris
    - Updated BioFormats to 5.7.1
    - Updated inputdlg
    - Updated measure line/freehand
    - Fixed disabling of selection
    - Fixed movement of measurements
    - Fixed recalculation of voxels
    - Fixed resampling
    - Fixed incorrect reading
    - Moved mibController.connImaris

??? abstract "2.12 / 18.09.2017"
    - Added tool to detect frame
    - Added auto-update mode
    - Added possibility to count annotations
    - Added export of selected annotations
    - Added saving of annotations
    - Added sorting of annotations
    - Added remove branches
    - Added clipping with Mask
    - Added shift of annotations
    - Added material names parameter
    - Improved performance
    - Improved resizing
    - Improved update of graphcut
    - Modified use of 'E' key
    - Fixed reading of metadata
    - Fixed loading of models
    - Fixed use of block mode
    - Fixed erode and dilate
    - Fixed backup before interpolation
    - Fixed access to Class Reference
    - Fixed import of annotations
    - Fixed export of TIF images

??? abstract "2.10 / 01.06.2017"
    - Added materials with 65535 materials
    - Added export to Excel
    - Added automatic mode for interpolation
    - Added Median3D filter
    - Added generation of new models
    - Added running average correction
    - Added find and select material
    - Added pasting of selection
    - Added indication of material index
    - Added possibility to save models
    - Modified use of Ctrl+C/Ctrl+V
    - Fixed export of models
    - Fixed singleton running

??? abstract "2.01 / 11.04.2017"
    - Added selection of model type
    - Added 'Recalculate selected measurements'
    - Added possibility to exclude intensities
    - Added imresize3 function
    - Added calculation of annotation labels
    - Moved mibView.disableSegmentation

??? abstract "2.00 / 20.03.2017 Official Release, 2.002 (02.04.2017)"
    - Rewritten to utilize Controller-View-Model
    - Added "Copy to clipboard"
    - Added adaptive black and white thresholding
    - Many other improvements
    - Added offset shift
    - Renamed Area to Volume
    - Bug fixes

---

*Back to [MIB](../../index.md) | [Getting started](../index.md) | [Current release notes](index.md)*