# Image Shuffling

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*

---

## Overview

The **Image Shuffling** tool in Microscopy Image Browser (MIB) shuffles files for blind modeling or classification,
ensuring users don't know which file corresponds to which condition. 
Models from shuffled files can later be restored to their original filenames for analysis.

![Image Shuffling workflow overview](images/menuFileRandomize.png){.on-glb}
![Image Shuffling Workflow](images/Rename_and_Shuffle.jpg){.on-glb}

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Image Shuffling Demo](https://youtu.be/be3p7FZc-X8)

<div class="clear-float"></div>

---

## Shuffle Images

![Shuffle images dialog](images/menuFileRandomizeDlg.png){.on-glb align=left width="300"}

This mode renames and shuffles files from input directories into multiple output subdirectories.

<div class="clear-float"></div>

???+ warning "Prerequisites"
    - Files for each condition must be in separate folders.
    - Images in each folder must have the same width and height.
    - Recommended: Each file contains a single image (no stacking).
    - For models, masks, or annotations: Only one file per type per directory (e.g., one `*.model`, `*.mask`, or `*.ann` file).
    - For models: All model files must contain the same materials.

### Setup

Copy images from different conditions into separate directories 
(e.g., `Control` for control images, another folder for treatment images). 
There may be multiple conditions processed at the same time. 
The only requirement is to have separate conditions in their own directory.

### Settings

- <span class="widget widget-button">Add folders</span>: populate the list of input directories with images from different conditions.
- <span class="widget widget-button">Remove folders</span>: remove a selected directory from the list.
- <label class="widget widget-checkbox">Include model</label>: shuffle existing models (one `*.model` file per folder).
- <label class="widget widget-checkbox">Include mask</label>: shuffle existing masks (one `*.mask` file per folder).
- <label class="widget widget-checkbox">Include annotations</label>: shuffle existing annotations (one `*.ann` file per folder).
- <label class="widget widget-checkbox">Include measurements</label>: shuffle existing measurements (one `*.measure` file per folder).
- <span class="widget widget-edit">Random seed</span>: a positive number setting the random number generator seed; same value ensures consistent shuffling.
- <span class="widget widget-edit">Filename extension</span>: specify the extension for image filenames (e.g., `TIF`).
- <span class="widget widget-edit">Filename template</span>: define the naming pattern for shuffled images.
- <span class="widget widget-edit">Output directory</span>: set the destination directory for shuffled files. Use <span class="widget widget-button">...</span> to browse.
- <span class="widget widget-edit">Number of output sub-directories</span>: number of subdirectories (e.g., `Subset_001`, `Subset_002`) to create under the output directory.
- <label class="widget widget-checkbox">generate Excel file with shuffling details</label>: in addition to 
the automatically generated `.mibShuffle` MATLAB-compatible file with shuffling
details, generate an Excel sheet where the shuffling order is stored in human-readable format.
- <span class="widget widget-button">Rename and Shuffle</span>: start the shuffling process. An automatically generated `.mibShuffle` MATLAB-compatible file with sorting details is saved to the output directory.

---

## Restore Order

![Restore order dialog](images/menuFileRandomizeRestoreDlg.png){.on-glb align=left width="300"}

This mode restores shuffled models and masks to match their original image filenames.

<div class="clear-float"></div>

???+ warning "Prerequisites"
    - Images in each folder must have the same width and height.
    - For models, masks, or annotations: only one file per type per directory.

### Steps

* Press <span class="widget widget-button">...</span> to select the project file (`Project file (*.mibShuffle)`), saved in the original shuffle output directory.
* The **Directories with shuffled images** and **Destination directories** lists populate automatically.

![Additional options to correct directories](images/menuFileRenameShuffle-dirs.png){.on-glb align=right width="300"}

* Right-click on any directory entry for a context menu with options to:
    - **Update directory**: manually set a new path for the selected entry
    - **Update parent folder for selected directories**: remap all selected entries under a new parent folder
    - **Copy path to clipboard**: copy the directory path
    - **Open directory in file explorer**: browse the directory in Windows Explorer

<div class="clear-float"></div>

* Optionally, save updated directory settings with <span class="widget widget-button">Save as</span>.
* Select which layer types to restore: <label class="widget widget-checkbox">Include model</label>, <label class="widget widget-checkbox">Include mask</label>, <label class="widget widget-checkbox">Include annotations</label>, <label class="widget widget-checkbox">Include measurements</label>.
* Press <span class="widget widget-button">Restore shuffled</span> to start.

#### Output
- Restored models: `Labels_RestoreRand_YYMMDD.model` (e.g., `Labels_RestoreRand_250405.model` for April 5, 2025).
- Restored masks: `Mask_RestoreRand_YYMMDD.mask`.
- `YYMMDD` reflects the restoration date.

---

## Usage Tips

??? info "Shuffling for Blind Analysis"
    To anonymize files:

    1. Organize conditions into separate folders (e.g., `Control`, `Treatment`).
    2. Set <span class="widget widget-edit">Number of output sub-directories</span> (e.g., 3 for `Subset_001` to `Subset_003`).
    3. Shuffle with a consistent <span class="widget widget-edit">Random seed</span>.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*
