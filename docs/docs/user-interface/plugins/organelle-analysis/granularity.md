# Granularity

---

## Overview

![Granularity plugin](images/granularity.png){.on-glb align=left width="300"}

The **Granularity** plugin in **Microscopy Image Browser (MIB)** performs 
analysis of endoplasmic reticulum (ER) models to quantify the granularity of structures, 
*i.e.* ratio between sheets and tubules.<br> 
It supports customizable subarea selection, structuring element configuration, 
and export of results for further analysis.

<div class="clear-float"></div>

## Usage

Access the plugin via:<br>
`Ribbon → Plugins → Organelle Analysis → Granularity`.

Follow these steps to analyze granularity:

**Load Images and models of ER**
![Dataset and model of ER](images/granularity-loadedmodel.png){.on-glb align=right width="300"}

**Start the plugin**:<br>`Ribbon → Plugins → Organelle Analysis → Granularity`.

<div class="clear-float"></div>

**Select Analysis Mode**:
![Mode](images/granularity-mode.png){align=right}

   - `2D, current slice only` - use to preview 2D mode on the current slice
   - `2D, time-lapse` - apply 2D analysis for the whole dataset
   - `3D, volume` - apply 3D strel elements to do calculations in 3D space
   
**Define Subarea**:
![Subarea settings](images/granularity-subarea.png){align=right}

- Use <span class="widget widget-button">Current View</span> to update the <span class="widget widget-edit">X</span> and <span class="widget widget-edit">Y</span> 
   fields using the currently shown area.
- Click <span class="widget widget-button">Subarea from Selection</span> to restrict analysis to a selected area 
  (drawn via MIB’s `Selection` tools).
- Adjust coordinates manually in the subarea edit boxes or click <span class="widget widget-button">Reset Dimensions</span> to revert 
  to the full image.

**Select Materials**:
![Select material](images/granularity-selmat.png){align=right}

- Click <span class="widget widget-button">Update Materials</span> to 
   get the list of materials from the current model and update the 
   <span class="widget widget-dropdown">Select material</span> dropdown.
- Use <span class="widget widget-dropdown">Select material</span> to select material


**Configure Structuring Element (Strel)**
![Configure Structuring Element](images/granularity-strel.png){align=right}

- Use <span class="widget widget-dropdown">Strel Type</span> to select type of the structural element to use
- Set <span class="widget widget-edit">Size XY</span> (XY plane) and <span class="widget widget-edit">Z</span>
 (for 3D) to define the shape of the structural element.
- Specify <span class="widget widget-edit">Strel Rotations</span> for number of strel rotations to use.
!!! info

     Higher values ensure better results, but with increase of computation time.

- Click `Preview Strel` to visualize the structuring element before analysis.

**Export Results**:
![Configure Structuring Element](images/granularity-export.png){align=right}

   - Check <span class="widget widget-checkbox">MATLAB</span> to export results to the main MATLAB workspace as a structure.
   - Check <span class="widget widget-checkbox">Save to a file</span> to save results in MATLAB of EXCEL formats
   - Click <span class="widget widget-button">...</span> to choose an output file (`.xlsx` for Excel or `.mat` for MATLAB).
   
**Run Analysis**:

![Dataset and model of ER](images/granularity-results1.png){.on-glb align=right width="300"}

- Click <span class="widget widget-button">Calculate</span> to
    compute granularity metrics.
- Results are displayed in the [Image View](../../panels/selection_imview/imview.md) panel.

<div class="clear-float"></div>

![Visualization of sheets (red) and tubules (yellow) compartments of ER](images/granularity-results2.jpg){.on-glb align=left }

<div class="clear-float"></div>

## Credits

- **Author**: Ilya Belevich, University of Helsinki ([ilya.belevich@helsinki.fi](mailto:ilya.belevich@helsinki.fi))
- **Part of**: Microscopy Image Browser ([https://mib.helsinki.fi](https://mib.helsinki.fi))

---

*Back to [MIB](../../../index.md) | [User Interface](../../index.md) | [Plugins](../index.md) | [Organelle Analysis](index.md)*