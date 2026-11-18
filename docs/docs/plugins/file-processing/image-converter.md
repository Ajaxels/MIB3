# Image Converter

---

The **Image Converter** plugin in **Microscopy Image Browser (MIB)** enables batch conversion of images from any [MIB-supported format](https://mib.helsinki.fi/features_all_fileformats.html) (e.g., NRRD, HDF5) to AM, JPG, PNG, TIF, or XML-header formats. It streamlines dataset preparation for analysis or compatibility with other tools.

## Overview

![Image converter](images/image-converter.png){.on-glb align=left width="300"}

The plugin provides a graphical interface to convert multiple image files efficiently.<br>

<div class="h4-like">Key features include:</div>

- Support for various input and output formats.
- Optional use of Bio-Formats for advanced file reading.
- Generation of pyramidal TIFs for large datasets.
- Parallel processing to speed up conversions.
- Customizable filename prefixes and suffixes.

<div class="clear-float"></div>

## Usage

Access the plugin via:

- `Ribbon → Plugins → File Processing → Image Converter`.

[:fontawesome-brands-youtube:{.red-color} demonstration](https://www.youtube.com/watch?v=Xu1waZ913bE)

!!! note
    Ensure input files are in a supported format. Check the [supported formats list](https://mib.helsinki.fi/features_all_fileformats.html) for compatibility.

### Steps
1. **Select Input Directory**:

    - Choose the folder containing images to convert <span class="widget widget-button">...</span>.
    - Enable <span class="widget widget-checkbox">Include Subfolders</span> to process 
    nested directories.
   
2. **Specify Input Format**:

    - Select the input image extension (e.g., NRRD, HDF5).
    - Use <span class="widget widget-checkbox">Bio-Formats reader</span> for complex formats, 
    specifying the format and series index if needed.
   
3. **Select Output Directory**:

    - Choose where converted images will be saved.

4. **Configure Output**:

    - Select the output format (e.g., TIF, PNG).
    - Add optional <span class="widget widget-edit">Prefix</span> or <span class="widget widget-edit">Suffix</span> to output filenames.
    - Enable <span class="widget widget-checkbox">Discard colormap</span> to remove colormap data.
??? warning "TIF->XML convertion"
     TIF->XML convertion is only implemented for Zeiss Atlas Fibics TIF files
     to make sure that the XML files are generated at the same location as images:
   
     - Include subfolders is selected
     - Output directory is directing to the parent folder of the one selected as the Input directory
     - Add prefix or suffix
      
5. **Pyramidal TIF Options** (if TIF output):

    - Check <span class="widget widget-checkbox">Generate pyramidal TIFs</span> for multi-resolution output.
    - Set <span class="widget widget-edit">Levels</span>  (e.g., "1, 2, 3, 4") and 
    <span class="widget widget-edit">TIF Compression</span> type.
   
6. **Enable Parallel Processing**:

    - Speed up conversion for large datasets (optional).
   
7. **Convert**:

    - Click <span class="widget widget-button">Convert</span> to start the process.


## GUI Components

### Input Panel

![Image converter -> Input](images/image-converter-input.png)
 
<span class="widget widget-button">...</span> Input directory, specify path to source images.<br>

<span class="widget widget-checkbox">Include subfolder</span>, check to process subdirectories.

<span class="widget widget-dropdown">Image filename extension</span>, input format dropdown for standard image formats.
Select `model` to convert MIB models (`.model`) without opening them in MIB; they are converted as labels
with their material names and colors.

<span class="widget widget-checkbox">Bio-Formats reader</span>, enable Bio-Formats reader to read variety of microscopy image formats.

  - <span class="widget widget-dropdown">Bio-Formats Input format extension</span> a separate dropdown to specify input image format.
  - <span class="widget widget-edit">Bio-Formats index</span> series index for multi-series files.

### Output Panel for standard image format

![Image converter -> Output](images/image-converter-output.png)

<span class="widget widget-button">...</span> Output directory, path for converted images. 
In case when <span class="widget widget-checkbox">Include subfolder</span> the structure of the input
directories will be preserved in the output directory

<span class="widget widget-dropdown">Output Format</span>, output format dropdown to define format 
for resulting images:
    
- JPG, Joint Photographic Experts Group format    
- PNG, Portable Network Graphics format
- TIF, Tag Image File Format
- ZARR, OME-ZARR version 2 or version 3 chunked format for large datasets, see below
- XML, Extensible Markup Language suitable for metadata extraction

<span class="widget widget-edit">Filename Prefix</span> customize prefix text to be added before the original filename

<span class="widget widget-edit">Filename Suffix</span> customize suffix text to be added after the original filename

<span class="widget widget-checkbox">Discard colormap</span>, remove colormap from output files.

<span class="widget widget-checkbox">Parallel processing</span>, enable multi-core file conversion. It uses the running
parallel pool (Home -> Preferences -> Parallel pool); without one, a pool of the number of workers set in the
preferences is started.

<span class="widget widget-checkbox">Generate pyramidal TIFs</span>, create multi-resolution TIFs.

<span class="widget widget-edit">Levels</span> pyramidal downsampling factors levels for TIF output.

??? info "Scale labels to downsampling scale"
    
    The scale level in the pyramid is calculated as `scaleFactor = 1/2^(levelsVec-1);`

<span class="widget widget-dropdown">TIF compression</span> compression type for TIFs.

### Output Panel for OME-Zarr

![Image converter -> Output](images/image-converter-output-zarr.png)

In this mode, MIB can convert files from variety formats into [OME-Zarr](https://zarr.readthedocs.io/en/stable/).

The output directory becomes the Zarr dataset: select an empty or a new directory. An existing Zarr
dataset there is overwritten after confirmation.

??? note "Requirements and limitations"
    - MIB version 2.92 (beta 7) or newer
    - each input file may hold one image or a whole volume (e.g. `.am`, `.mrc`); the files are
      stacked along Z in name order, and each volume must fit into memory
    - memory grows with the image width × height and the Z of <span class="widget widget-edit">Chunk sizes</span>
      (times the Z of <span class="widget widget-edit">Shard X factors</span> when sharding).
      TIF images too large for the memory are converted in bands of rows automatically; for other
      formats MIB warns before starting - reduce these Z values for very large images
    - with <span class="widget widget-checkbox">Parallel processing</span> every worker converts its
      own part of the stack, so the memory need is multiplied by the number of workers
    - a cancelled, failed or interrupted conversion leaves an incomplete dataset; MIB warns when it
      is opened. Press <span class="widget widget-button">Convert</span> again with the same settings
      and choose **Resume** to continue where it stopped. A changed source file or Zarr setting
      requires converting again from the start

??? note "Loading of OME-Zarr in MIB"
    It is possible to open OME-Zarr version 2 or version 3 (MIB version 2.92 beta 8 or newer). 

    To open the dataset:

    - make sure that the directory has `.zarr`, `.zarr2`, `.zarr3` ending
    - select the directory using the <mouse class="left"></mouse> in the [Directory contents](../../user-interface/panels/dircontents/index.md) panel
    - open the OME-Zarr dataset using the `Combine selected datasets` option available via <mouse class="right"></mouse>

<span class="widget widget-dropdown">Zarr version</span>, defines which version of the Zarr format to use for writing the dataset.

- 'Zarr v2' - legacy Zarr format, widely supported (e.g. MoBIE, OME-Zarr v0.4).
- 'Zarr v3' - newer Zarr format with sharding support, but fewer tools support it.

Both are written by the bundled native engine, so neither needs Python. Selecting 'Zarr v2' clears
<span class="widget widget-checkbox">Use sharding</span>, which is a Zarr v3 feature.

<span class="widget widget-dropdown">Image type</span>, specifies the type of data stored in the Zarr array.

- 'image' - intensity/volumetric image data (microscopy, CT, etc).
- 'labels' - segmentation or annotation data (integer label maps).

<span class="widget widget-edit">Chunk sizes</span>, the chunk size for storing data, written as a comma-separated list in the order \[X, Y, Z, C, T\]. 
Each chunk forms a file with these dimensions, for Zarr version 3, the chunks are merged into shards to minimize number of files. This parameter controls input/output performance:
the smaller chunks give faster random access, while the larger chunks give faster sequential access. 

??? note "Example"

    Example: '256, 256, 16, 1, 1' (default) - chunks of 256×256×16 voxels per channel per timepoint.

<span class="widget widget-edit">Shard X factors</span>, sharding factor for Zarr v3 (how many chunks are grouped together into a shard). Written as \[X, Y, Z, C, T\].
Reduces overhead when dealing with many small chunks, improves cloud performance.

??? note "Example"

    Example: '4, 4, 1, 1, 1' (default) - each shard groups 4×4×1 chunks in XYZ per color channel and timepoint

    **Note:** Only relevant if Zarr version = 3. A Z factor above 1 makes the conversion need more memory.

The stopwatch button next to <span class="widget widget-edit">Chunk sizes</span> finds the chunk and shard sizes with which MIB browses
the converted dataset fastest. The window writes small test datasets of your input files with each candidate
setting and reads them back the way the image view does; the test files are deleted afterwards.

- <span class="widget widget-edit">Test folder</span> - a folder on the drive that will hold the dataset; a
  network drive and a local disk give different results.
- <span class="widget widget-dropdown">Use case</span> - **2D** when the dataset is browsed in XY only, **3D**
  when it is also viewed in ZX and ZY, **Hybrid** for occasional ZX/ZY views. It fills the candidates and the
  <span class="widget widget-edit">XY share, %</span>.
- <span class="widget widget-edit">Files weight</span> - how much a large number of files counts against a
  candidate; 0 ignores it.

Press <span class="widget widget-button">Time candidates</span>, select the best row (listed first) and press
<span class="widget widget-button">Use selected</span> to copy its chunk and shard sizes to the Zarr settings.
Every run opens in its own tab, so runs with test folders on different drives can be compared.

<span class="widget widget-button">Heat map...</span> times all reasonable chunk sizes from 16 to 1024 pixels in X and Y
and from 1 to 256 slices in Z, without shards and with two shard sizes. Sizes that are too small, too large or too
deep for the memory of the conversion are skipped. The run takes several minutes, much longer on a network drive.
It suggests the best setting whose neighbours are also good, rather than the single fastest one, which is often
chance; click a cell to select another setting.

<span class="widget widget-edit">Downsample limit</span>, definition of the smallest volume size until which the dataset is downsampled. 
For anisotropic datasets, the downsampling procedure brings the volume first to the isotropic voxels and after that downsamples all dimensions evenly.

??? note "Example"

    Example: '512, 512, 256' - if dataset is larger than this, downsampled levels will be generated until each axis fits within the limit.

<span class="widget widget-dropdown">Downsample strategy</span>, how the coarser levels treat Z:

- **Auto** - Anisotropy-preserving when the Z voxel is at least 1.5 times the XY voxel, otherwise XY only.
- **XY only** - Z is never downsampled.
- **Anisotropy-preserving** - Z is downsampled once the XY voxel reaches the Z voxel size.
- **Anisotropy-preserving + isotropic level** - in addition, the pyramid contains the level where all three voxel sizes are equal.

<span class="widget widget-dropdown">Compression</span>, compression algorithm used to store chunk data: **zstd**, **gzip** or **none**. 

<span class="widget widget-edit">Compression level</span>, compression level settings: **1..9** - compression levels, the higher the value the more compression output is expected, but with the slowest computation times; **0** - the default level of the algorithm.

<span class="widget widget-edit">Voxel size</span>, physical voxel size of the dataset in order \[X, Y, Z\], given in the specified units. 

??? note "Example"

    Example: '0.013, 0.013, 0.030' - voxel size 13 nm x 13 nm x 30 nm if units = micrometers.

<span class="widget widget-edit">Bounding box shift</span>, offset (translation) applied to the dataset bounding box along \[X, Y, Z\]. 
Useful when aligning multiple datasets into a common coordinate system.

??? note "Example"

    Example: '0, 0, 0' (no shift).

<span class="widget widget-dropdown">Units</span>, units for physical voxel size:

??? note "Possible values"

    - 'nanometers'
    - 'micrometers'
    - 'millimeters'
    - 'pixels' (unitless)

When the source files were saved by MIB (TIF, AM, or HDF5), the voxel size, bounding box shift, and
units are filled in from their bounding box as soon as the input or the Zarr output is selected,
so the converted dataset keeps its original position. Check them before converting a subset of a
saved stack.

### Buttons

![Image converter -> Buttons](images/image-converter-butons.png)

<span class="widget widget-button">Help</span>  open the Help page.

<span class="widget widget-button">Convert</span> start the conversion process.

<span class="widget widget-button">Close</span> exit the plugin.

---

*Back to [MIB](../../index.md) | [User Interface](../../user-interface/index.md) | [Plugins](../index.md) | [File processing](index.md)*