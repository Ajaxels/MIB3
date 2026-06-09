# Multi-Rename Tool

---

The **Multi-Rename Tool** plugin in **Microscopy Image Browser (MIB)** is a utility for batch renaming files, such as images or datasets, using customizable templates. It simplifies organizing large file sets by applying consistent naming rules.

## Overview

![Image converter](images/multi-rename-tool.png){.on-glb align=left width="300"}

The plugin enables efficient renaming of multiple files with options for templates, 
counters, and text replacement. It’s ideal for preparing datasets for MIB analysis or 
ensuring standardized naming conventions.

[:fontawesome-brands-youtube:{.red-color} Multi Rename Tool demo](https://youtu.be/pl9Vdv-qjkE)

<div class="clear-float"></div>

## Key Features

- Apply customizable templates to define filename structures.
- Add counters with specified digits, start values, and increments.
- Search and replace text within filenames.
- Adjust filename case (uppercase, lowercase, or unchanged).
- Standardize numbers by adding leading zeros to match a digit count.

<!-- Note: Main snapshot (main_snapshot.png) omitted as placeholder -->

## Usage

Access the plugin via:
`Ribbon → Plugins → File Processing → Multi Rename Tool`.

Follow these steps to rename files:

<div class="h4-like">Select Files</div>

![Image converter](images/multi-rename-tool-select.png){align=left} 
Click <span class="widget widget-button">Select files…</span> to choose files for renaming.
Selected filenames appear in the file list table, showing original and proposed names.
<div class="clear-float"></div>

<div class="h4-like">Context Menu for File List</div>
![Image converter](images/multi-rename-tool-context.png){align=left} 
Right-click the file list table to open a context menu:

- `Remove from the list`: remove selected files.

<div class="clear-float"></div>

<div class="h4-like">Define Filename Template</div>
Use the <span class="widget widget-edit">Filename template</span> edit box to set a naming pattern with placeholders:

- `[C]`: adds a counter (configured in Counter Settings).
- `[E]`: keeps the original file extension (e.g., `tif`, `jpg`).
- `[N]`: includes the original filename (without extension).
- `[P]`: adds the parent folder name.

??? abstract "Example"

    A template like `custom_[N]_[C]` with extension `txt` might rename `image.doc` to `custom_image_001.txt`.
    ![Image converter](images/multi-rename-tool-define-template.png)
    <div class="clear-float"></div>


!!! info
       Configure counter settings (digits, start, step) to control `[C]` behavior.

<div class="h4-like">Set Extension Template</div>

Use the <span class="widget widget-edit">Extension template</span> edit box to change 
file extensions (e.g., to `jpg`) or use `[E]` to retain originals.

<div class="h4-like">Configure Counter Settings</div>

Adjust in the Counter Settings panel:

- <span class="widget widget-edit">Digits</span>: number of digits (e.g., 3 for `001`).
- <span class="widget widget-edit">Start</span>: starting value (e.g., 1).
- <span class="widget widget-edit">Step</span>: increment (e.g., 1 for `001`, `002`; 2 for `001`, `003`).

<div class="h4-like">Search and Replace</div>
![Image converter](images/multi-rename-tool-search.png)

Fine-tune filenames:

- <span class="widget widget-edit">Search</span>: text pattern to find.
- <span class="widget widget-edit">Replace</span>: replacement the found pattern with a new text.
- <span class="widget widget-checkbox">Match Case</span>: enable for case-sensitive search.
- <span class="widget widget-dropdown">Letter Case</span>: select `unchanged`, `UPPERCASE`, or `lowercase` to change letter case.

<div class="h4-like">Fix Numbers</div>

![Image converter](images/multi-rename-tool-fixnum.png)

   - Enable <span class="widget widget-checkbox">Fix numbers by adding leading zeros</span> to standardize numbers (e.g., `1` to `001` for 3 digits).
   - Use <span class="widget widget-edit">Exclude prefixes</span> to skip numbers following specific prefixes.
   <!-- Note: Snapshot (snap05.png) omitted as placeholder -->

<div class="h4-like">Preview Results</div>

Click <span class="widget widget-button">Preview</span> to update the table with proposed filenames.
!!! note
       Review the preview to avoid errors. Adjust settings and re-preview if needed.

!!! tip
       Use the <span class="widget widget-checkbox">auto preview</span> checkbox to interactively follow the changes.

<div class="h4-like">Rename Files</div>

Press <span class="widget widget-button">Rename</span> to apply changes to the files.

---

*Back to [MIB](../../../index.md) | [User Interface](../../index.md) | [Plugins](../index.md) | [File processing](index.md)*