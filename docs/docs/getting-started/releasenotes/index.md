i# Current Release Notes

This page lists the current and potentially beta-version release notes for **Microscopy Image Browser (MIB)**, detailing new features, improvements, and fixes across versions.<br> 
For the latest updates, visit [MIB website](https://mib.helsinki.fi/downloads.html) or check the [Current release notes](index.md).
For the downloads visit [MIB website](https://mib.helsinki.fi/downloads.html) for the development history click [here](release-notes-history.md).

???+ info "NEXT RELEASE (in development)"
    - **OME-Zarr pyramids**: every coarser level is now exactly half the size of the level above, so
      all levels line up with the full-resolution image, also in other OME-Zarr viewers. The same
      data gives the same pyramid whether it is converted to BigData, saved as OME-Zarr, or written
      by the Image converter. Pyramids written by earlier versions can differ slightly at the coarser
      levels when the image width or height is an odd number.
    - **Image converter, OME-Zarr output**:
        - faster; with **Parallel processing** the workers share the conversion
        - an interrupted or cancelled conversion can be resumed with the same settings
        - TIF images too large for the memory are converted in parts
        - the memory needed is checked before the conversion starts
        - a failed conversion is reported as failed, and MIB warns when an incomplete dataset is opened
        - the output directory must be empty or hold a previous Zarr dataset

???+ info "RELEASE 2026.09 / 03.06.2025 (MIB3 release)"
    - Release

*Back to [MIB](../../index.md) | [Getting started](../index.md)*