# Starting MIB

Once MIB is [installed](../installation/index.md), you can launch it either from inside MATLAB or
as a standalone application. This page covers both, plus what to expect on the first launch.

!!! info "Requirements"
    The MATLAB version of MIB3 requires **MATLAB R2025a or newer** (**R2026a is recommended**).
    If you run an older MATLAB, use **MIB2** instead - see [Configuration files → Previous versions](../configuration/index.md#previous-versions).

---

## Launch from MATLAB

Add the `mib` folder to the MATLAB path (or `cd` into it) and run the entry point:

```matlab
% C:\Matlab\MIB3\ is the location where MIB3 was downloaded and unzipped
cd C:\Matlab\MIB3\mib
mib3
```

Adjust the path to wherever you unpacked MIB. The first run may take a few extra seconds while
MATLAB initialises the required libraries.

!!! tip
    Add `C:\Matlab\MIB3\mib` to the MATLAB search path, and `mib3` will start from any folder:

    `MATLAB -> Home tab -> Set Path -> Add Folder... -> Save`

---

## Launch the standalone app

The standalone version does not require a MATLAB license - only the matching **MATLAB Runtime**,
which the installer sets up for you.

- Start MIB from the **Start menu** / desktop shortcut created during installation.
- Or run the installed `MIB.exe` directly.

!!! tip "Start compiled MIB on Linux "
    On Linux, start MIB from a terminal. MIB prints progress and diagnostic messages there, so you
    can follow what it is doing while it runs.

See the [Installation](../installation/index.md) page for download and setup details.

---

## On first launch

MIB opens its main window - the ribbon along the top, the image document in the centre, and the
side panels for directory contents, segmentation, and view settings.

![MIB3 user interface](../../user-interface/images/mib3_gui.png){.on-glb width="700"}

For a guided tour of every part of the window, see the [User Interface](../../user-interface/index.md)
section. When you are ready to open an image, continue to [First dataset](../first-dataset/index.md).

??? failure "If MIB does not start"
    Check that the `mib` folder is on the MATLAB path. If it is, delete the configuration file
    (`mib3.mat`) and restart. See [Configuration files](../configuration/index.md) for its location.

---

*Back to [MIB](../../index.md) | [Getting started](../index.md)*
