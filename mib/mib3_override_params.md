# Override Parameters File

This file allows you to override MIB's default settings for new users -
either for all workstations or for a specific one.

---

## Creating the file

1. Start MIB and change the settings that new users should start with
2. Press **Home → Preferences ▾ → Make override default settings file**
3. Choose whether the file is for all computers or only for this computer
4. Save the file into this folder

| File | Scope |
|------|-------|
| `mib3_prefs_override.json` | **Global** - every computer that uses this MIB installation |
| `mib3_prefs_override_COMPUTERNAME.json` | **Workstation-specific** - only the named computer (see **Home → Help → About MIB**) |

The file lists only the settings that differ from the MIB defaults; all other settings keep their
default values. It is plain text and can be edited: delete a setting to return it to the default.
The `_comment` entries describe the neighbouring settings and their allowed values.

Recent directories, user statistics and the email password of DeepMIB reports are never written.

Override files made in earlier versions by copying `mib3.mat` and renaming it to
`mib3_prefs_override.mat` or `mib3_prefs_override_COMPUTERNAME.mat` still work.

---

## Load Priority at Startup

When MIB starts, it looks for a configuration file in this order:

1. `mib3.mat` in the user directory - **used immediately if found**
2. `mib3_prefs_override_COMPUTERNAME.json`, then `mib3_prefs_override_COMPUTERNAME.mat` - workstation-specific override
3. `mib3_prefs_override.json`, then `mib3_prefs_override.mat` - global override
4. Built-in defaults - used if none of the above are found

> **Note:** If `mib3.mat` already exists in the user directory, override files are ignored entirely.
