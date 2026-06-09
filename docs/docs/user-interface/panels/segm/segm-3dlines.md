# The 3D Lines Tool

---

## 3D Lines overview

![3D Lines Tool](images/PanelsSegmentationTools3DLines.png){align=left}

The **3D lines** tool allows drawing lines in 3D space, arranging them as graphs or skeletons. It consists of nodes (vertices) connected by edges (lines). Nodes represent points, and edges represent connections, forming trees—distinct sets of 3D lines—for better organization.

- [:fontawesome-brands-youtube:{.red-color} Use of 3D lines for skeletons and measurements](https://youtu.be/DNRUePJiCbE)

Modify nodes with mouse clicks, extended by key modifiers (<span class="widget widget-button">Shift</span>, <span class="widget widget-button">Ctrl</span>, <span class="widget widget-button">Alt</span>) for various actions (see below).

<div class="clear-float"></div>

???+ info "Available actions"
    - <span class="widget widget-dropdown">Add node</span> add a new node to the active tree, connecting it to the active point (shown in red).
    - <span class="widget widget-dropdown">Assign active node</span> assign the closest node to the mouse click as the new active node.
    - <span class="widget widget-dropdown">Connect to node</span> connect the active node to another existing node.
    - <span class="widget widget-dropdown">Delete node</span> remove the closest node, rearranging edges to prevent tree splitting.
    - <span class="widget widget-dropdown">Insert node after active</span> insert a new node after the active node.
    - <span class="widget widget-dropdown">Modify active node</span> move the active node to a new position with a mouse click.
    - <span class="widget widget-dropdown">New tree</span> add a node to a new, unconnected tree.
    - <span class="widget widget-dropdown">Split tree</span> split a tree by deleting the closest node.

    Use <span class="widget widget-checkbox">Show lines</span> to toggle visibility of edges in the [Image View panel](../imview/index.md).  
    Press <span class="widget widget-button">Table view</span> to open a window with tables describing the 3D lines (see below).

##Lines 3D View

### List of trees table

![Lines 3D View](images/PanelsSegmentationTools3DLinesDlg.png){.on-glb align=left}

**Table with the list of trees**  
The upper table in the **Lines 3D View** window lists trees and their node counts. Each tree must have a unique name.
<br>
<div class="h4-like">Right-click a tree for options:</div>

- **Rename selected tree**: rename the tree (must be unique).
- **Find tree by node**: find a tree by node index.
- **Visualize in 3D selected tree(s)**: plot selected trees in 3D.
- **Save/export selected tree(s)**: export to MATLAB or save to a file (formats listed in Tools panel below).
- **Delete selected tree(s)**: remove selected trees.

<div class="clear-float"></div>

### Space between the tables

- **Active tree** index of the active tree.
- **Active node** index of the active node.
- <span class="widget widget-dropdown">Table</span> select *Nodes* or *Edges* for the lower table.
- <span class="widget widget-dropdown">Field</span> add an extra field (*Radius* or *Weights* by default) to the lower table.
- <span class="widget widget-checkbox">Auto jump</span> jump to the selected node and show it in the [Image View panel](../imview/index.md).
- <span class="widget widget-checkbox">Auto refresh</span> automatically refresh tables (may be slow with many nodes).

### Nodes table

![Lines 3D View nodes table](images/PanelsSegmentation-3dlines-nodes.png){.on-glb align=left width="360"}

Lists nodes with actions via a popup menu:  

- <span class="widget widget-dropdown">Jump to the node</span> center the selected node in the [Image View panel](../imview/index.md).
- <span class="widget widget-dropdown">Set as active node</span> make the selected node active.
- <span class="widget widget-dropdown">Rename selected nodes</span> assign a new name.
- <span class="widget widget-dropdown">Show coordinates in pixels</span> show node coordinates in pixels 
(default is physical units per [bounding box](../../ribbon/dataset/index.md#bounding-box)).
- <span class="widget widget-dropdown">New annotations from nodes</span> generate new annotations from node positions.
- <span class="widget widget-dropdown">Add nodes to annotations</span> add selected nodes to existing annotations.
- <span class="widget widget-dropdown">Delete nodes from annotations</span> remove selected nodes from annotations.
- <span class="widget widget-dropdown">Delete nodes</span> delete selected nodes.

### Edges table

![Lines 3D View edges table](images/PanelsSegmentation-3dlines-edges.png){align=left}

Lists edges with actions via a popup menu:

- <span class="widget widget-dropdown">Jump to the node ▼</span>: center the selected node in the [Image View panel](../imview/index.md).
- <span class="widget widget-dropdown">Set as active node ▼</span>: make the selected node active.


### Tools panel

![Lines 3D View edges table](images/PanelsSegmentation-3dlines-tools.png){align=left}

<div class="clear-float"></div>

- <span class="widget widget-button">Load</span>: load 3D lines from a MATLAB-compatible *.lines3d file.
- <span class="widget widget-button">Save</span>: export to MATLAB or save as:
    - **MATLAB format, *.lines3d**: recommended format.
    - **Amira Spatial graph, *.am**: Amira-compatible (binary or ASCII).
    - **Excel format, *.xls**: export Nodes and Edges tables.
- <span class="widget widget-button">Refresh</span>: refresh the tables.
- <span class="widget widget-button">Delete all</span>: delete all 3D lines.
- <span class="widget widget-button">Visualize in 3D</span>: plot all trees in 3D.
- <span class="widget widget-button">Settings</span>: modify color and thickness of 3D lines.

---
## Presets
Use the following key shortcuts to define and restore presets

- ++shift+1++, ++shift+2++, ++shift+3++ - store preset 1, 2, or 3 correspondingly
- ++1++, ++2++, ++3++ - restore preset 1, 2, or 3 correspondingly

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Panels](../index.md) | [Segmentation](index.md)*