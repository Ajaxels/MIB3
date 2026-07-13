# Configuration Files

MIB stores its configuration parameters in files that are created automatically when MIB is closed.
This page is reference material — you do not need it to start using MIB.

## Where MIB stores its settings

**MIB3** (current) uses separate files for machine-specific preferences and user statistics:

| File | Location | Notes |
|------|----------|-------|
| `mib3.mat` | Windows: `C:\Users\Username\Matlab\` <br> macOS: `/Users/username/Matlab/` <br> Linux: `/home/username/Matlab/` | Main preferences (display settings, last-used path, etc.). Falls back to the system TEMP directory if `Matlab/` cannot be created. |
| `mib_user.mat` | Windows: `C:\Users\Username\AppData\Roaming\MathWorks\MIB\` <br> macOS: `~/Library/Application Support/MIB/` <br> Linux: `~/.local/share/MIB/` | User statistics (tier data). Stored in the OS roaming profile so it syncs automatically across workstations (**Note** the location can be defined from the Personal stats dialog from *Home->Help*). Falls back to the same `Matlab/` folder as `mib3.mat` if the roaming directory is unavailable. |

??? info "Legacy configuration files (MIB2 and older)"
    **MIB2** (2.60 and newer) stored a single `mib.mat` in:

    - **Windows**: `C:\Users\Username\MATLAB\` (fallback: `C:\Users\Username\AppData\Local\Temp\`)
    - **macOS**: `/Users/username/MATLAB/` (fallback: local TEMP)
    - **Linux**: `/home/username/MATLAB/` (fallback: local TEMP)

    **MIB2** (2.52 and older) used `im_browser.mat` in:

    - **Windows**: `c:\temp\im_browser.mat` (fallback: `C:\Users\Username\AppData\Local\Temp\im_browser.mat`)
    - **Linux**: script directory or `/tmp/`

!!! tip
    If MIB does not start, check the MATLAB path and/or delete the configuration file (`mib3.mat` or the legacy equivalent) listed above, then restart.

---

## Overriding default settings

Administrators can preconfigure MIB with custom default settings by placing an *override file* into the MIB program directory (the folder that contains `mib3.m`, or the installation folder of the standalone version). This is useful for deploying the same configuration to multiple workstations, for example in a core facility.

Two kinds of override files are supported:

| File | Scope |
|------|-------|
| `mib3_prefs_override.mat` | **Global** — applies to every workstation |
| `mib3_prefs_override_COMPUTERNAME.mat` | **Workstation-specific** — applies only to the computer with the matching name |

### Creating an override file

1. Start MIB and configure all required settings
2. *For a workstation-specific override:* open **Home → Help → About MIB** and note the **Computer name** shown at the bottom of the dialog
3. Close MIB — this saves `mib3.mat` to the user directory (the location is reported in the MATLAB command window upon MIB startup)
4. Copy `mib3.mat` to the MIB program directory
5. Rename the copy to `mib3_prefs_override.mat` (global) or `mib3_prefs_override_COMPUTERNAME.mat` (workstation-specific), replacing `COMPUTERNAME` with the name from step 2

### Load priority at startup

When MIB starts, it looks for a configuration file in this order:

1. `mib3.mat` in the user directory — **used immediately if found**
2. `mib3_prefs_override_COMPUTERNAME.mat` — workstation-specific override
3. `mib3_prefs_override.mat` — global override
4. Built-in defaults — used if none of the above are found

!!! note
    If `mib3.mat` already exists in the user directory, override files are ignored entirely. To force reloading from an override file, delete `mib3.mat` first.

User statistics (tier data stored in `mib_user.mat`) are never taken from an override file — each user keeps their own.

---

## Previous versions

This documentation describes **MIB3** - the current release. Previous releases are hosted on GitHub and include their own documentation and release notes:

| Version | Repository | Notes                                                        |
|---------|-----------|--------------------------------------------------------------|
| **MIB2** | [github.com/Ajaxels/MIB2](https://github.com/Ajaxels/MIB2) | Controller-View-Model architecture; recommended for MATLAB releases: R2014b - R2024b   |
| **MIB** | [github.com/Ajaxels/MIB](https://github.com/Ajaxels/MIB) | original release, recommended for MATLAB releases: R2011a - R2017a |

!!! tip
    If you are running MATLAB older than R2026a, use **MIB2** from the link above.

---

*Back to [MIB](../../index.md) | [Getting started](../index.md)*
