# Fiji Connect Panel

---

## Overview

![Fiji Connect Panel](images/PanelsFiji.png){align=left}

The **Fiji Connect Panel** enables communication with [Fiji](http://fiji.sc/Fiji), 
an image processing software, using the [MIJ](http://bigwww.epfl.ch/sage/soft/mij/) 
Java package for bidirectional data exchange between MATLAB and ImageJ/Fiji. 
MIJ is developed by Daniel Sage, Dimiter Prodanov, Jean-Yves Tinevez, and Johannes Schindelin.
Ensure Fiji is installed and MIJ is integrated (see [System Requirements](https://mib.helsinki.fi/downloads_systemreq.html#fiji)).

<div class="clear-float"></div>

[:fontawesome-brands-youtube:{.red-color} Visualization of datasets and models using Fiji](https://youtu.be/DZ1Tj3Fh2HM?list=PLGkFvW985wz8cj8CWmXOFkXpvoX_HwXzj)

---

## <span class="widget widget-button">Start Fiji</span> and <span class="widget widget-button">Stop Fiji</span> buttons

![Fiji Connect Panel](images/PanelsFiji-startFiji-buttons.png){align=left}

<span class="widget widget-button">Start Fiji</span>: launches Fiji from MATLAB, 
required for communication. 
??? warning 
    Press this button first before any actions!

<div class="clear-float"></div>

<span class="widget widget-button">Stop Fiji</span> closes Fiji when it is not needed anymore.

---

## Image Type and Import/Export buttons

![Fiji Connect Panel](images/PanelsFiji-image-type.png){align=left}

<span class="widget widget-dropdown">Image Type</span> dropdown

Specifies the layer (e.g., Image, Model, Mask, Selection) to exchange with Fiji.<br>
!!! tip "Example"

    For example, selecting **Image** and pressing 
    <span class="widget widget-button">Export</span> sends the current image to Fiji. 
    See *Finding Edges using Fiji* below for details.

<span class="widget widget-button">Export</span>: sends the current dataset 
(based on <span class="widget widget-dropdown">Image Type</span>) to Fiji for processing 
or analysis.

<span class="widget widget-button">Import</span>: iImports datasets from Fiji into 
MIB’s Image, Model, Mask, or Selection layers, as set by 
<span class="widget widget-dropdown">Image Type</span>.<br>
Ensure Model, Mask, and Selection sizes match the Image layer in MIB.

---

---

## Run macro or send a command to Fiji

![Fiji Connect Panel](images/PanelsFiji-macro.png){align=left}

<div class="clear-float"></div>

<span class="widget widget-edit">Run macro</span> edit box
Enter a Fiji macro command (e.g., `<span class="code">run('Flip Z')</span>` to flip 
the Z-dimension). A template is shown by default.<br> 
Alternatively, input a path to a text file with multiple macros, 
selected via <span class="widget widget-button">Select file...</span>.<br> 
Check [Miji](http://fiji.sc/Miji) for syntax.

<span class="widget widget-button">Select file...</span> button: opens 
a dialog to choose a text file containing macro commands for execution
with <span class="widget widget-button">Run</span>.<br> 
See [Miji](http://fiji.sc/Miji) for syntax.

<span class="widget widget-button">Run</span> button: executes the macro in 
<span class="widget widget-edit">Run macro</span>. 
If a file path is provided, it runs all macros in that script.

---

## Help button

<span class="widget widget-button">?</span>: opens the help documentation for detailed instructions.

---

## Example: Finding edges using Fiji

This example shows how to detect edges in a 3D grayscale dataset and import a binary mask into MIB.

???+ info "Steps (assuming Fiji is installed and configured)"
    1. Get a test dataset from `Ribbon → Home -> Example datasets -> SBEM -> Huh7 and model`.
    2. Open the dataset in MIB.
    3. Press <span class="widget widget-button">Start Fiji</span> to launch Fiji.
    4. To send the image to Fiji, select **Image** in <span class="widget widget-dropdown">Image Type</span> 
    and press <span class="widget widget-button">Export</span>.
    5. Name the dataset in the dialog that appears.
    6. In Fiji, find edges: `Menu -> Process -> Find Edges`.
    7. Generate a binary image: `Menu -> Image -> Adjust -> Auto Threshold`, set **Method** to **Mean**, 
    check <span class="widget widget-checkbox">Stack</span>, and press <span class="widget widget-button">OK</span>.
    8. In MIB, select **Mask** in <span class="widget widget-dropdown">Image Type</span> and press <span class="widget widget-button">Import</span>.
    9. MIB now has a new Mask layer from Fiji.

---

*Back to [MIB](../../../index.md) | [User Guide](../../index.md) | [Panels](../index.md)*