# Directory Contents Panel

---

## Overview

![Directory Contents Panel](images/PanelsDirContents.png){.on-glb width="400" align=left}

This panel displays a list of files in the selected directory and provides the option to filter them based on known image and video formats.


<div class="clear-float"></div>

---

## Multiple buffer buttons

![Buffer Buttons Popup](images/PanelsDirContentsBuffers.png){.on-glb align=left }

Multiple buffer buttons at the upper part of the panel provide fast access to several 
datasets stored in memory. Each button represents a dataset, and the green color 
indicates that a dataset is loaded in that buffer.<br> 
When you hover your cursor over a button, a tooltip with the full file name of the loaded dataset appears, helping you identify the dataset.

<div class="clear-float"></div>

You can switch between datasets by clicking <mouse class="left"></mouse> on the desired buffer button.

<div class="h4-like">Clicking <mouse class="left"></mouse> on a buffer button opens a popup menu with the following options:</div> 

- **Duplicate dataset**: creates a duplicate of the currently shown dataset and places it in an available buffer.
- **Sync view, (xy) with**: synchronizes the view with another dataset in XY coordinates.
- **Sync view, (xyz) with**: synchronizes the view with another dataset in XYZ coordinates, for 4D-5D datasets.
- **Sync view, (xyzt) with**: synchronizes the view with another dataset in XYZT coordinates, for 5D datasets.
- **Link view with**: links views in two MIB buffers; shifts in one view automatically shift the other. Toggle buffers with <span class="widget widget-button">Ctrl</span> + <span class="widget widget-button">E</span>.  
  [:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/DvSBBSuEiDo)
- **Close dataset**: removes the selected dataset from memory.
- **Close all stored datasets**: removes all stored datasets from memory.

These buffer buttons and options provide convenient ways to manage and interact with multiple datasets in MIB.

---

## File list box

![File List Context Menu](images/PanelsDirContentsFileList-up.png){align=left}

The major part of the panel is occupied by a list box that displays files in the selected directory, 
chosen from the [Path panel](../path/index.md). 
<br>Files are filtered based on the specified filter.
Selecting <span class="widget widget-dropdown">Filter: all known</span> displays all readable formats.

<div class="h3-like">Navigating folders</div>

- Double-clicking <span class="widget widget-dropdown">\[.\]</span> changes the folder to the top level of the current logical drive.
- Double-clicking <span class="widget widget-dropdown">\[..\]</span> changes the folder to one level up.
- Double-clicking <span class="widget widget-dropdown">\[DIR NAME\]</span> navigates MIB into the clicked directory and shows files inside it
<br>(`MIB_Algn` folder in the snapshot)

<div class="h3-like">Selecting and loading datasets</div>

- Double-<mouse class="left"></mouse> a file loads it into MIB and displays it in the
[Image View panel](../imview/index.md).
- Select individual datasets by holding <span class="widget widget-button">Shift</span> or 
<span class="widget widget-button">Ctrl</span> and clicking <mouse class="left"></mouse> on files. 
Load them via the context menu (<mouse class="left"></mouse> options below).

<div class="h3-like">Context menu options</div>

![File List Context Menu](images/PanelsDirContentsFileList.png){.on-glb align=left width="250"}

The context menu, accessed with <mouse class="right"></mouse>, provides these operations on 
selected datasets

<div class="clear-float"></div>

- **Combine selected datasets**: combine selected datasets into a single 3D stack.

??? info "Working with OME-Zarr"

    It is possible to open OME-Zarr version 2 or version 3 (MIB version 2.92 beta 8 or newer). 

    To open the dataset:

    - make sure that the directory has `.zarr`, `.zarr2`, `.zarr3` ending
    - select the directory using the <mouse class="left"></mouse>
    - open the OME-Zarr dataset using the `Combine selected datasets` option 
    
    ??? note "Notes and requirements"
        - installed Python environment with [zarr-python](https://mib.helsinki.fi/downloads_systemreq.html#zarr)
        - virtual mode of MIB switched on

- **Load part of the dataset (AM, TIF, BioFormats)**: load a specific part of a larger dataset, defining start/end points, z-step, and XY binning
(available for Amira Mesh, TIF, and BioFormats-readable datasets) [:fontawesome-brands-youtube:{.red-color} demo](https://youtu.be/sae--XHIjwc).
- **Load each N-th dataset**: assemble every N-th file into a 3D stack.
- **Insert into the open dataset**: insert selected files into the currently open dataset.
- **Combine as color channels**: combine selected datasets into a single 2D slice, each assigned to 
a color channel.
- **Add as a new color channel**: add images as a new color channel to the existing dataset. 
Select channels in the [View Settings panel](../viewsettings/index.md).
- **Add each N-th dataset as a new color channel**: add images with an N-step as a new color channel to the existing dataset.
- **Rename selected file**: rename the selected file.
- **Delete selected files**: permanently delete selected files from the disk.
- **File properties**: show file details like date/time and size in bytes.

!!! note
    <mouse class="right"></mouse> above the scroll bar scrolls the list to the top.

---

## Filter

![Filter Dropdown](images/PanelsDirContents_Filters.png){align=left}

The <span class="widget widget-dropdown">Filter</span> dropdown allows filtering the file list 
based on available image type filters. 
<br>Available extensions depend on whether the standard 
or [Bio-Formats reader](https://www.openmicroscopy.org/bio-formats/) is used and if 
virtual mode is enabled, resulting in four filter configurations.

<div class="clear-float"></div>

??? info "Modify extensions in the filter list"
    ![Register TIF as an extension available for the BioFormats reader in the standard mode](images/PanelsDirContentsFileList-regext.png){.on-glb align=left width="260"}    
    
    To modify file extensions the list of filters:

    - <mouse class="right"></mouse> click over <span class="widget widget-dropdown">Filter</span>.
    - Choose an option:
        - **Register extension**: add extensions to the filter list.
        - **Remove selected extension**: remove a selected extension from the filter list.

---

## Update button

The <span class="widget widget-button">Update</span> button refreshes the file list in the Directory Contents panel.

---

## Left interchangeable panels

![Left interchangeable panels](images/PanelsDirContentsFileList-leftpanels.png){align=left}

The selected panel appears in the lower-left part of MIB:

- [Segmentation panel](../segm/index.md)
- [ROI panel](../roi/index.md)

---

## Right interchangeable panels

![Left interchangeable panels](images/PanelsDirContentsFileList-rightpanels.png){align=left}

The selected panel appears in the bottom-right part of MIB:

- [Image Filters panel](../imfilters/index.md)
- [Mask Generators panel](../maskgen/index.md)
- [Fiji Connect panel](../fijiconnect/index.md)

---

## Bio checkbox

When <span class="widget widget-checkbox">Bio</span> is checked, 
the [Bio-Formats reader](http://openmicroscopy.org/info/bio-formats) loads datasets. 
<br>MIB supports specific biological image formats (native to various microscopes) via the 
Bio-Formats Java library, stored in 
the `MIB\ImportExportTools\BioFormats` directory.

!!! note
    Performance of the Bio-Formats reader may be slower than standard native readers due to Java-related overheads.

---

## Help button

The <span class="widget widget-button">?</span> button links to this help page.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md)*