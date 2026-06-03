# Override Parameters File

This file allows you to override MIB's global configuration settings - 
either for all workstations or for a specific one.

---

## Option 1: Global Override

Applies the same settings to every workstation.

**Required file:** `mib3_prefs_override.mat`

**Steps:**
1. Start MIB and configure all required settings
2. Close MIB - this saves `mib3.mat` to the user directory (**Note** The user directory reported upon MIB startup)
3. Copy `mib3.mat` to this folder
4. Rename the copy to `mib3_prefs_override.mat`

---

## Option 2: Workstation-Specific Override

Applies settings only to a named workstation.

**Required file:** `mib3_prefs_override_COMPUTERNAME.mat`

**Steps:**
1. Start MIB
2. Open **Home → Help → About MIB**
3. Note the **Computer name** shown at the bottom of the dialog
4. Configure all required settings, then close MIB - this saves `mib3.mat` to the user directory
5. Copy `mib3.mat` to this folder
6. Rename the copy to `mib3_prefs_override_COMPUTERNAME.mat`, replacing `COMPUTERNAME` with the name from step 3

---

## Load Priority at Startup

When MIB starts, it looks for a configuration file in this order:

1. `mib3.mat` in the user directory - **used immediately if found**
2. `mib3_prefs_override_COMPUTERNAME.mat` - workstation-specific override
3. `mib3_prefs_override.mat` - global override
4. Built-in defaults - used if none of the above are found

> **Note:** If `mib3.mat` already exists in the user directory, override files are ignored entirely.
