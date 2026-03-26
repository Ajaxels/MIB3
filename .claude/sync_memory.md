# Memory Sync Setup

Claude Code memory is stored on OneDrive and shared across workstations via a Windows directory junction.

Run this **once** on each new workstation (from PowerShell):

```powershell
& "$(([System.IO.DriveInfo]::GetDrives() | Where-Object { Test-Path "$($_.Name)OneDrive - University of Helsinki\Matlab\MIB_OneDrive\.CLAUDE\setup_memory_junction.ps1" } | Select-Object -First 1).Name)OneDrive - University of Helsinki\Matlab\MIB_OneDrive\.CLAUDE\setup_memory_junction.ps1"
```

This auto-detects the OneDrive drive letter and runs the setup script.

After that, memory syncs automatically on every session — no further steps needed.
