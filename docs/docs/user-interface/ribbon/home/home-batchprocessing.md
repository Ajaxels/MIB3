# Batch Processing

---

## Overview

The **Batch Processing** mode in Microscopy Image Browser (MIB) automates image processing steps, allowing you to create a protocol that can be applied to multiple images.

![Batch Processing Dialog](images/menuFileBatchMode.png){.on-glb align=left width="300"}

This tool supports automation of workflows, from image loading to processing and saving, with options to manually define steps or automatically detect actions performed in MIB.

<div class="h3-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} General Batch Processing Demo](https://youtu.be/P6Rivp713qM)
- [:fontawesome-brands-youtube:{.red-color} File and Directory Operations Demo](https://youtu.be/8VlfR_CZNT4)

<div class="clear-float"></div>

---


## Introduction

Batch Processing offers two primary modes of operation: when actions are automatically recorded from users operations and
when user defines operations manually.

### Automatic Detection

When <label class="widget widget-checkbox">Listen for MIB actions</label> is checked, MIB records 
detectable operations (e.g., image adjustments) as protocol steps.<br> 
If <label class="widget widget-checkbox">Auto add to protocol</label> is also checked, 
these steps are automatically added to the protocol. 

!!! info "Attention!"
    Some actions (e.g., loading/saving images) are not automatically recorded and thus must be added manually.

### Manual Selection

Use the <span class="widget widget-dropdown">Protocol steps->Section</span> and 
<span class="widget widget-dropdown">Protocol steps->Action</span> dropdowns to manually 
select and configure steps, which can then be added to the protocol.

### Service Steps
The <span class="widget widget-dropdown">Service steps</span> section includes special actions like:

- **STOP EXECUTION**: Pauses the protocol for manual intervention.
- **Directory/File Loops**: Sequentially processes multiple images from directories or files.

### Start the protocol

Start the protocol with <span class="widget widget-button">Run protocol</span> or from a specific step 
using <span class="widget widget-button">Start from selected</span>.<br><br>
In addition, green arrow buttons can be used to

* <span style="color: #00AA00">:material-arrow-right-circle:</span> to perform the selected action
* <span style="color: #00AA00">:material-arrow-down-circle:</span> to perform the selected action and progress to the next one
<br>[see below](home-batchprocessing.md#controls)
---

## Protocol Panel

![Protocol Panel](images/menuFileBatchMode_2.png){align=left}

This panel displays and manages the protocol steps.

<div class="clear-float"></div>

### Right-Click Menu

  * **Show settings**: Displays and edits parameters in the lower Protocol steps panel.
  * **Duplicate**: Copies the selected step below it.
  * **Insert STOP EXECUTION event**: Adds a pause step.
  * **Move up/down**: Reorders steps.
  * **Delete from protocol**: Removes the selected step.

### Controls

![Protocol Panel controls](images/menuFileBatchMode_3.png){align=left}

  - ![Run Step](images/menuFileBatchMode_runstep.png): executes the selected step.
  - ![Run and Advance](images/menuFileBatchMode_runstep_advance.png): executes and moves to the next step.
  - <label class="widget widget-checkbox">Listen for MIB actions</label>: enables automatic detection.
  - <label class="widget widget-checkbox">Auto add to protocol</label>: auto-adds detected actions.
  - <label class="widget widget-checkbox">Show parameters on click</label>: displays parameters on selection (otherwise use the **Show settings** action from the popup menu).
  - ![Load/Save/Delete](images/menuFileBatchMode_load_save_delete.png): manages protocol files (supports Excel export).
  - <span class="widget widget-button">Undo</span> / <span class="widget widget-button">Redo</span>: reverts or reapplies changes.

<div class="clear-float"></div>

---

## Protocol Steps Panel

![Protocol Steps Panel](images/menuFileBatchMode_protocol-steps.png){.on-glb align=left width="350"}

This panel configures individual protocol steps.<br>
This table displays settings of the selected protocol action. 

<div class="clear-float"></div>

In order to modify parameters:

* Select parameter to change
* Modify it using controls on the right-hand side
* Press <span class="widget widget-button">Update protocol</span> to 
update the selected action with the updated settings

### Options

* <span class="widget widget-dropdown">Section</span>: selects a group of actions; 
in general each group combines operations that can be found in the corresponding section of MIB GUI. 
    
!!! info "Loops"
    Loops require a *LOOP START* followed by *LOOP STOP*.

* <span class="widget widget-dropdown">Action</span>: chooses a specific action within the section.
* **Parameters Table**: shows and edits action options using widgets (e.g., <span class="widget widget-edit">value</span>, <span class="widget widget-dropdown">option</span>).
* <span class="widget widget-button">Update protocol</span>: applies changes to the selected step.
* <span class="widget widget-button">Add to protocol</span>: appends the step to the protocol.
* <span class="widget widget-button">Insert into protocol</span>: inserts the step at the highlighted position.

---

## Usage Tips

??? info "Adding Loops"
    To process multiple images:

    1. Select <span class="widget widget-dropdown">Service steps</span> → *LOOP START* (e.g., for directories).
    2. Add processing steps (e.g., image filters).
    3. End with *LOOP STOP*.
    See the [File and Directory Demo :fontawesome-brands-youtube:{.red-color}](https://youtu.be/8VlfR_CZNT4) for an example.

??? warning "Limitations"
    Not all MIB actions are automatically detectable. Manual addition is required for operations like file loading or saving.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Home](index.md)*

