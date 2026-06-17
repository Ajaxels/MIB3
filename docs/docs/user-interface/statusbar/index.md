# Status Bar

The **Status Bar** runs along the bottom of the MIB window and provides quick access to the working directory, live pixel information, operation progress, and zoom control.

It replaces the **Path panel** from MIB2, consolidating those controls into a compact always-visible strip.

---

## Overview

The status bar is divided into four groups, arranged from left to right:

| Group | Position | Contents |
|-------|----------|----------|
| [Working directory](#working-directory) | left | directory picker, path field, copy and browser buttons |
| [Pixel info](#pixel-info) | center | live cursor coordinates and intensity |
| [Progress](#progress) | right | progress bar for long-running operations |
| [Zoom](#zoom) | far right | current magnification edit field |

---

## Working directory

The working directory group sets the folder whose contents are listed in the
[Directory Contents panel](../panels/dircontents/index.md).

### Select directory button

:octicons-file-directory-16:{.orange-color} Opens the system directory picker dialog.
After confirmation the path field and file list update automatically.

### Path field

<span class="widget widget-edit">C:\path\to\data</span>
Displays the active working directory. You can also type or paste a path directly and press ++enter++ to apply it.

- If a file path is typed instead of a folder, the parent directory is used automatically.
- Invalid paths are rejected and the field reverts to the previous value.

### Copy path button

:octicons-copy-16:{.orange-color} Copies the current working directory path to the system clipboard.

### Open in file browser button

:octicons-browser-16:{.orange-color} Opens the current working directory in the native OS file browser:

- **Windows** — Windows Explorer
- **macOS** — Finder
- **Linux** — Caja file manager (falls back to `xterm` if Caja is unavailable)

---

## Pixel info

Displays the pixel coordinates and intensity values under the mouse cursor as it moves over the [Image Document](../image-document/index.md):

```
Pixel: X:Y (R:G:B) / [material index]
```

- Updates in real time.
- Shows the material index at the cursor position when a model is loaded.

!!! info
    Equivalent to the **Pixel Info field** from the MIB2 Path panel.

---

## Progress

A progress bar that fills during long-running operations (file loading, batch processing, filtering, etc.).
It resets to zero automatically when the operation completes.

---

## Zoom

<span class="widget widget-edit">100 %</span>
Shows the current image magnification. Type a percentage value and press ++enter++ to apply it.

The zoom field is also available as a **Batch Processing** action
(*Quick access bar → Change magnification*) with the following modes:

| Mode | Effect |
|------|--------|
| Set magnification | Applies the typed percentage value |
| Fit to screen | Scales the image to fill the Image View panel |
| 100% | Resets magnification to 1:1 |
| Zoom in | Doubles the current magnification |
| Zoom out | Halves the current magnification |

!!! tip
    The same zoom controls are also available via the [Quick Access Bar](../quick-access-bar/index.md)
    buttons and keyboard shortcuts ++q++ (zoom out) and ++w++ (zoom in).

---

*Back to [MIB](../../index.md) | [User interface](../index.md)*
