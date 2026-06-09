# Path Panel

Specifies the current directory of image datasets in Microscopy Image Browser.

---

## Overview

![Path panel](images/PanelsPath.png)

The **Path Panel** allows users to define the path to image datasets and provides additional tools 
for navigation and dataset information.

---

## Logical drive dropdown

<span class="widget widget-dropdown">Logical drive</span>: quickly selects available logical drives, 
initialized at MIB startup.
!!! info "Only in Windows OS"
    This dropdown is available only in MIB on Windows

## Directory selection button

<span class="widget widget-button">'...'</span>: opens a dialog to select the current directory.

## Current path edit box

<span class="widget widget-edit">Current path</span>: displays the current folder path, with 
its contents shown in the [Directory Contents panel](../dircontents/index.md).  

Right-click for a context menu:  

![Path context menu](images/PanelsPathDropdown.png){align=left}

- **Copy to clipboard**: copies the path to the system clipboard  
- **Open directory in the file explorer**: opens the folder in the system file explorer  

## List of recently used directories
![Recently used directories](images/PanelsPath-recentdirs.png){align=left}

Shows recently loaded dataset directories.  
[:fontawesome-brands-youtube:{.red-color} MIB in brief: list of recent directories](https://youtu.be/xx7pGehTJXA)

<div class="clear-float"></div> 

## Pixel Info field

![Jump to point](images/PanelsPathJumpTo.png){align=left}

Displays pixel location and intensity under the mouse cursor in 
the [Image View panel](../imview/index.md), formatted as
<br>`X, Y (Red:Green:Blue) / [material index]`.<br>

<div class="clear-float"></div> 
!!! info
    - Updates in real-time as the cursor moves over the image, aiding pixel value analysis and navigation.  
    - Use <mouse class="right"></mouse> to access a jump-to-point menu.

## Log button

![Log window](images/PanelsPathLog.png){.on-glb width="400" align=left}

<span class="widget widget-button">Log</span>: shows a log of actions performed on the current dataset, stored in the `ImageDescription` field of TIF files with date/time stamps.  
[:fontawesome-brands-youtube:{.red-color} MIB in brief: Log of performed actions](https://youtu.be/1ql4cRxZ334)   

<div class="clear-float"></div> 

<div class="h4-like">Actions:</div>  
- **Print to MATLAB**: outputs the log to the MATLAB command window  
- **Copy to Clipboard**: copies the log for pasting (++ctrl+v++ on Windows)  
- **Insert after**: adds a new entry after the selected one  
- **Modify**: edits the selected entry  
- **Delete**: removes the selected entry  
- **Update**: manually refreshes the log if not updated automatically

## Info button

![Info window](images/PanelsPathInfo.png){.on-glb width="320" align=left}

<span class="widget widget-button">Info</span>: opens a tree list of dataset parameters.<br><br> 
XY resolution is in `XResolution`, `YResolution`, and `BoundingBox` within `ImageDescription`. 
<br>Includes a search field for metadata.

<div class="clear-float"></div> 

## Zoom edit box

![Zoom field](images/PanelsPathZoom.png){align=left}

<span class="widget widget-edit">Zoom</span> sets the desired zoom level.  


<div class="clear-float"></div> 

## Help

Links to this help page.

## Right-click dropdown menu
![Dropdown menu](images/PanelsPath_dropdown.png)
<div class="clear-float"></div> 

Do <mouse class="right"></mouse> at an empty area opens a menu to hide/show panels, 
expanding the Image View panel space. 
!!! warning
    It may be tricky to find an "empty" space as most space is occupied with other widgets. 
    However, it is possible to call the same operation by <mouse class="right"></mouse> at empty space
    in the [Image View](../imview/index.md) panel.

---

*Back to [MIB](../../index.md) | [User interface](../index.md) | [Panels](../index.md)*