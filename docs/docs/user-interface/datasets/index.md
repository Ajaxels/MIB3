# Datasets Panel

The **Datasets panel** manages all open datasets in MIB.
It provides numbered buffer buttons to switch between datasets, a sets dropdown to organise buffers into named groups,
and a dataset-type selector that controls how each dataset is stored in memory.

---

## Overview

The panel contains three areas from top to bottom:

1. **Sets** — named groups of buffers, with controls to add and manage them.
2. **Buffers 1–10** — individual dataset slots within the active set.
3. **Dataset type** — memory/access mode for the dataset in the active buffer.

---

## Sets

A **set** is a named group of 10 buffers, each capable of holding one dataset.
Multiple sets allow you to organise unrelated groups of datasets independently.
Each set corresponds to one [Image Document](../image-document/index.md) tab in the main workspace.

### Sets dropdown

<span class="widget widget-dropdown">Set 1</span>
Selects the active set. Switching sets also switches the visible Image Document tab.

<mouse class="right"></mouse> the dropdown to open the sets context menu:

| Menu item | Action |
|-----------|--------|
| **Add set** | Create a new set (prompts for a name) |
| **Rename set** | Rename the currently active set |
| **Sort sets** | Sort all sets alphabetically |
| **Remove set** | Close all datasets in the set and remove it |

!!! warning
    **Remove set** closes all datasets in that set without additional confirmation per buffer.

### Add set button

<span class="widget widget-button">+</span>
Shortcut to add a new set, equivalent to *Sets context menu → Add set*.

---

## Buffer buttons

Ten numbered buttons (**1** through **10**) represent the dataset containers (buffers) within the active set.
Button color indicates the state of each buffer:

| Color | Meaning |
|-------|---------|
| Bright green | Active buffer — currently displayed in the Image Document |
| Light green | Buffer contains a loaded dataset |
| Default | Buffer is empty |

Hover over any button to see the filename of the dataset loaded in that buffer.

**Click** a button to make it the active buffer — its dataset is shown in the Image Document.

### Buffer context menu

<mouse class="right"></mouse> any buffer button for per-buffer operations:

| Menu item | Action |
|-----------|--------|
| **Duplicate** | Copy this dataset to another buffer (prompts for destination set and buffer) |
| **Sync XY** | Copy view position and zoom from another buffer |
| **Sync XYZ** | Copy view position, zoom, and current Z-slice from another buffer |
| **Sync XYZT** | Copy view position, zoom, Z-slice, and time frame from another buffer |
| **Link view with… \[Unlinked\]** | Link this buffer's view to another buffer — scrolling one updates the other |
| **\[Linked: A ↔ B\] press to unlink** | Unlink the currently linked pair |
| **Close** | Close the dataset in this buffer (resets it to an empty placeholder) |
| **Close Set** | Close all datasets in the entire current set |

#### Duplicate

Copies the full dataset (image, labels, mask, selection, annotations) to a destination buffer.
A dialog lets you choose the destination set and buffer number.

!!! warning
    Duplicating to a non-empty buffer overwrites the existing dataset after a confirmation prompt.

#### Sync views

All three sync modes align the view of one buffer to match another:

| Mode | Dimensions synced |
|------|------------------|
| **Sync XY** | Pan position + zoom |
| **Sync XYZ** | Pan + zoom + Z slice |
| **Sync XYZT** | Pan + zoom + Z slice + time frame |

Both datasets must be in the same orientation (XY, ZX, or ZY) for sync to work.

#### Link views

When two buffers are linked, navigating in one (slice, zoom, pan) automatically mirrors the same
view state in the other. Useful for comparing two registered datasets side by side.

!!! info
    Both buffers must be in the same orientation before linking.
    Linked-view state is shown in the button tooltip and in the context menu label.

---

## Dataset type

<span class="widget widget-dropdown">Standard</span>
Sets the memory/access mode for the dataset in the active buffer.
Changing this type closes the current dataset — a confirmation dialog is shown first.

| Type | Description |
|------|-------------|
| **Standard** | The entire dataset is loaded into RAM. Best performance for small to medium datasets. |
| **Virtual** | Data is read from disk slice by slice on demand. Suitable for datasets too large to fit in RAM. |
| **BigData** | Reserved for pyramidal/chunked formats. *(Future development.)* |

---

*Back to [MIB](../../index.md) | [User interface](../index.md) | [Panels](../panels/index.md)*
