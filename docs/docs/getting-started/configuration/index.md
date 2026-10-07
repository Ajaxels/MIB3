# Configuration Files

MIB stores its configuration parameters in files that are created automatically when MIB is closed.
This page is reference material - you do not need it to start using MIB.

## Where MIB stores its settings

**MIB3** (current) uses separate files for machine-specific preferences and user statistics:

| File | Location | Notes |
|------|----------|-------|
| `mib3.mat` | Windows: `C:\Users\Username\Matlab\` <br> macOS: `/Users/username/Matlab/` <br> Linux: `/home/username/Matlab/` | Main preferences (display settings, last-used path, etc.). Falls back to the system TEMP directory if `Matlab/` cannot be created. |
| `mib_user_COMPUTERNAME.mat` | Windows: `C:\Users\Username\AppData\Roaming\MathWorks\MIB\` <br> macOS: `~/Library/Application Support/MIB/` <br> Linux: `~/.local/share/MIB/` | User statistics (tier data). Each computer writes its own file, and MIB adds up every file it finds in the folder - see [Sharing your statistics between computers](#sharing-your-statistics-between-computers). Falls back to the same `Matlab/` folder as `mib3.mat` if the directory above is unavailable. |
| `mib3_VERSION.mat` | next to `mib3.mat` | Appears only when an older MIB is started after a newer one - see [Using several versions of MIB](#using-several-versions-of-mib). |

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

## Using several versions of MIB

Settings written by an older MIB are always understood by a newer one, so upgrading needs no action: your preferences carry over and anything the new version added starts at its default.

Going back to an **older** MIB is the case that needs care, because the older version cannot know what the newer one added. When that happens MIB tells you so at startup and:

- restores the settings the older version does have;
- ignores the newer ones instead of guessing;
- keeps the newer preferences in a separate file (`mib3_VERSION.mat`, e.g. `mib3_2026.09.mat`), so that closing the older MIB cannot discard them.

Start the newer version again and it picks that file back up, including any change you made while working in the older one. Both versions can be used side by side; only the file names in the table above ever appear.

---

## Sharing your statistics between computers

By default your statistics stay on the computer that recorded them. On Windows the default folder sits under `AppData\Roaming`, but that name is misleading: the folder only travels to other computers if your administrator set up a *roaming profile* for your account, which is rarely the case. Neither OneDrive nor Windows settings sync ever copies `AppData`.

To make your statistics follow you, put them in a folder that all your computers can reach:

1. The first time MIB starts on a computer it asks where to keep your statistics and offers the locations it found - typically your OneDrive folder and, on a university machine, your network home directory.
2. Pick the same folder on every computer you use. You can change the choice later from **Home → Help → Your stats → Set stats folder...**

Each computer writes its own file into that folder and MIB adds them all up, so nothing is ever overwritten and no points are lost when you use two computers on the same day. A computer that is temporarily offline simply does not contribute until its file syncs again.

!!! note
    Choosing a shared folder brings the statistics of that computer with it and picks up whatever your other computers have already stored there. If the folder already holds a file of this computer, for example after switching back to a folder used before, that file is kept and updated rather than replaced. Files left in the previous folder are not deleted.

### Coming from MIB2

The points you collected in MIB2 are taken over the first time MIB3 runs on that computer. MIB2 keeps its own file and goes on using it, so both programs remain usable - but the handover happens once, and points earned in MIB2 afterwards are not added to MIB3.

---

## Overriding default settings

Administrators can give the new users of a workstation a starting configuration that differs from the MIB defaults, for example in a core facility.

### Creating an override file

1. Start MIB and change the settings that new users should start with
2. Press **Home → Preferences ▾ → Make override default settings file**
3. Choose whether the file is for all computers that use this MIB installation or only for this computer
4. Save the file into the MIB program directory: the folder that contains `mib3.m`, or the installation folder of the standalone version

| File | Scope |
|------|-------|
| `mib3_prefs_override.json` | **Global** - every computer that uses this MIB installation |
| `mib3_prefs_override_COMPUTERNAME.json` | **Workstation-specific** - only the computer with the matching name, shown in **Home → Help → About MIB** |

The file lists only the settings that differ from the MIB defaults; all other settings keep their default values. Recent directories, user statistics and the email password of DeepMIB reports are never written to it.

The file is plain text and can be edited: delete a setting to return it to the default. The `_comment` entries describe the settings next to them and their allowed values.

Override files created in earlier versions of MIB by copying `mib3.mat` and renaming it to `mib3_prefs_override.mat` or `mib3_prefs_override_COMPUTERNAME.mat` still work.

### Load priority at startup

When MIB starts, it looks for a configuration file in this order:

1. `mib3.mat` in the user directory - **used immediately if found**
2. `mib3_prefs_override_COMPUTERNAME.json`, then `mib3_prefs_override_COMPUTERNAME.mat` - workstation-specific override
3. `mib3_prefs_override.json`, then `mib3_prefs_override.mat` - global override
4. Built-in defaults - used if none of the above are found

!!! note
    If `mib3.mat` already exists in the user directory, override files are ignored entirely. To force reloading from an override file, delete `mib3.mat` first.

User statistics (tier data stored in `mib_user_COMPUTERNAME.mat`) are never taken from an override file - each user keeps their own.

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
