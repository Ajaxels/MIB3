# Acknowledgements

**Powered by MATLAB, [The MathWorks, Inc.](https://www.mathworks.com/)**

## Special Thanks

- **Radhakrishna Achanta**, Ecole Polytechnique Federale de Lausanne (EPFL), for the mex code for SLIC supervoxels and superpixels
- **Tom Boissonnet** (EMBL) and **Elena Bertseva** (University of Copenhagen), for extensive testing
- **John Heumann**, The Boulder Laboratory For 3-D Electron Microscopy of Cells, for help with Mattomo
- **Konstantin Kogan**, University of Helsinki, for assistance with Mac OS
- **David Legland**, INRA, France, for modification of the [Region Adjacency Graph (imRAG)](http://www.mathworks.com/matlabcentral/fileexchange/16938-region-adjacency-graph--rag-) function for detection of indices between watershed regions and help with few other functions
- **Vladimir Moltchanov**, for discussions on software architectures
- **Norman Rzepka**, Scalable Minds GmbH for implementation of Zarr2/3 libraries for MATLAB
- **Henrik P Sahlin Pettersen**, Norwegian University of Science and Technology/St. Olavs hospital, Trondheim, for driving DeepMIB for pathology
- **František Kitzberger** (Inst. of Parasitology, Biology Centre CAS) and **Leonhard Breitsprecher** (University of Osnabrueck) for beta testing of MIB3
- **Anthropic Claude** for help with MIB2 conversion to MIB3 and implementation of new tools in MIB3

Microscopy Image Browser team would like to acknowledge [the User Community of MATLAB-Central](https://se.mathworks.com/matlabcentral/) and the authors whose code was used during MIB development (see below).

## Code Sources

!!! note
    Throughout the historical development of MIB a variety of external code has been used -
    including functions that were only used in earlier releases (noted in the list below). See
    [Licenses → External licenses](licenses/licenses-ext.md) to check the exact versions.

Microscopy Image Browser adapts partially or completely codes from the following sources
(listed alphabetically):

- Inspired by [**IMAGEVIEWER**](http://www.mathworks.com/matlabcentral/fileexchange/13000-imageviewer) by Jiro Doke, MathWorks, 2010
- API documentation of classes was done using [**MTOC++ - Doxygen filter for MATLAB and tools**](http://www.mathworks.com/matlabcentral/fileexchange/33826-mtoc++-doxygen-filter-for-matlab-and-tools) written by Martin Drohmann (Universität Münster) and Daniel Wirtz (Universität Stuttgart), 2011-2013
- [**Accurate Fast Marching**](https://se.mathworks.com/matlabcentral/fileexchange/24531-accurate-fast-marching) function by Dirk-Jan Kroon, University of Twente, 2011, is utilized in the Membrane Click Tracker tool
- [**ANISODIFF**](http://www.csse.uwa.edu.au/~pk/Research/MatlabFns/#anisodiff) function written by Peter Kovesi, 2000-2002, is used for anisotropic diffusion filtering of images
- [**BIO-FORMATS**](http://www.loci.wisc.edu/software/bio-formats) by Melissa Linkert, Curtis Rueden et al., 2002-2013, is utilized for reading of proprietary microscopy image formats using the `Bio` checkbox
- [**BMxD**](http://www.cs.tut.fi/~foi/GCF-BM3D/) external filters by Kostadin Dabov et al., Tampere University of Technology, Finland, 2007-2014, can be used with MIB, when separately installed on the system to filter the images
- [**BWDISTSC**](https://se.mathworks.com/matlabcentral/fileexchange/15455-3d-euclidean-distance-transform-for-variable-data-aspect-ratio) for 3D Euclidean distance transform for variable data aspect ratio written by Yuriy Mishchenko (Toros University, 2007-2013) is used for separation of anisotropic objects in 3D and calculation of distance maps
- [**Custom GINPUT**](https://se.mathworks.com/matlabcentral/fileexchange/38703-custom-ginput) written by Jiro Doke (MathWorks, 2016) to get coordinates of a clicked point
- [**Cell migration in scratch wound assays**](https://se.mathworks.com/matlabcentral/fileexchange/67932-cell-migration-in-scratch-wound-assays) by Constantino Carlos Reyes-Aldasoro, City, University of London, was used for the wound healing assay tool
- [**DIPLIB**](http://www.diplib.org/) is a platform-independent scientific image processing library written in C, developed by Quantitative Imaging Group at the Faculty of Applied Sciences, Delft University of Technology. When installed, Microscopy Image Browser can use several additional methods for anisotropic diffusion filtering available from DipLib (used in MIB 0.x and 1.x)
- [**DnD_uifigure: drag & drop functionality for AppDesigner components**](https://se.mathworks.com/matlabcentral/fileexchange/80656-uifilednd) written by Xiangrui Li (The Ohio State University), 2020-2023
- [**Drag & Drop functionality for JAVA GUI components**](https://se.mathworks.com/matlabcentral/fileexchange/53511-drag-drop-functionality-for-java-gui-components) written by Maarten van der Seijs, Delft University of Technology, the Netherlands, 2015
- [**DRAWREGIONBOUNDARIES**](http://www.peterkovesi.com/projects/segmentation/) a function to draw boundaries of labeled regions in an image when working with brush, written by Peter Kovesi (Centre for Exploration Targeting, School of Earth and Environment, The University of Western Australia, 2013)
- [**DRIFTY_SHIFTY_DELUXE**](https://se.mathworks.com/matlabcentral/fileexchange/45453-drifty-shifty-deluxe-m) written by Joshua D. Sugar (Sandia National Laboratories, Livermore, CA, 2014); part of code from this function was adopted in `mibCalcShifts.m`
- **Elastic Distortion filter** is based on [**Elastic Distortion Transformation on an image**](https://se.mathworks.com/matlabcentral/fileexchange/66663-elastic-distortion-transformation-on-an-image) by David Franco (Catholic University of Parana)
- [**EXPORT_FIG**](http://www.mathworks.com/matlabcentral/fileexchange/23629-export-fig) function to add measurements to snapshots is written by Oliver Woodford and Yair Altman
- [**EXTREMA**](http://www.mathworks.com/matlabcentral/fileexchange/12275-extrema-m-extrema2-m) functions by Carlos Adrian Vargas Aguilera, Universidad de Guadalajara, 2006-2007 (used in MIB 0.x and 1.x)
- [**Fast 3D/2D Region Growing (MEX)**](http://www.mathworks.com/matlabcentral/fileexchange/41666-fast-3d-2d-region-growing--mex-) by Christian Wuerslin (Stanford University, 2013-2015) is used for the region growing tool
- [**Fast/Robust Template Matching**](http://www.mathworks.com/matlabcentral/fileexchange/24925-fastrobust-template-matching) (2009-2011) by Dirk-Jan Kroon, University of Twente, was used for alignment of datasets in MIB version 1.22 and earlier
- **Fiji Connect** is using [**MIJ**](http://bigwww.epfl.ch/sage/soft/mij/), a Java package for bi-directional communication and data exchange from MATLAB to ImageJ/Fiji, developed by Daniel Sage, Dimiter Prodanov, Jean-Yves Tinevez, and Johannes Schindelin, 2012
- [**FINDJOBJ**](http://www.mathworks.com/matlabcentral/fileexchange/14317-findjobj-find-java-handles-of-matlab-graphic-objects) - find java handles of MATLAB graphic objects by Yair Altman, 2007-2013
- [**FRANGI filter**](http://www.mathworks.com/matlabcentral/fileexchange/24409-hessian-based-frangi-vesselness-filter) by Marc Schrijver and Dirk-Jan Kroon (University of Twente, 2001-2009)
- [**FSTACK**](https://se.mathworks.com/matlabcentral/fileexchange/55115-extended-depth-of-field) extended depth-of-field image from focus sequence using noise-robust selective all-in-focus algorithm by Said Pertuz (Universitat Rovira i Virgili, Tarragona, Spain, 2013) is used in the intensity projection tool
- [**HistThresh toolbox**](https://github.com/carandraug/histthresh) by Antti Niemistö (Tampere University of Technology, Finland) is used for most of the global histogram-based thresholding methods
- [**Image Edge Enhancing Coherence Filter**](http://www.mathworks.com/matlabcentral/fileexchange/25449-image-edge-enhancing-coherence-filter-toolbox) by Dirk-Jan Kroon & Pascal Getreuer (University of Twente, 2009)
- [**Image Measurement Utility**](http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility) by Jan Neggers (Eindhoven University of Technology, 2009-2014) is used as a basis for the Measure Tool and re-written roiRegion class
- [**IMCLIPBOARD**](http://www.mathworks.com/matlabcentral/fileexchange/28708-imclipboard) function by Jiro Doke, MathWorks, 2010, is used in the snapshot tool and import from system clipboard
- [**IceImarisConnector**](http://www.scs2.net/next/index.php?id=110) written by Aaron C. Ponti (ETH Zurich) is used for connection to Imaris
- [**IMGAUSSIAN**](http://www.mathworks.com/matlabcentral/fileexchange/25397-imgaussian) by Dirk-Jan Kroon (University of Twente), implementation 2009, is used in the 3D Gaussian filter
- [**Local normalization**](http://www.mathworks.com/matlabcentral/fileexchange/8303-local-normalization) by Guanglei Xiong (xgl99@mails.tsinghua.edu.cn) at Tsinghua University, Beijing, China, 2005 (used in MIB 0.x and 1.x)
- [**MATGEOM**](https://github.com/mattools/matGeom/), a MATLAB geometry toolbox for 2D/3D geometric computing, is written by David Legland (INRA, France, 2013) is used in some functions
- [**MATTOMO**](http://bio3d.colorado.edu/PEET/index.html) is a part of PEET (Particle Estimation for Electron Tomography) package, developed at Boulder Laboratory for 3-D Electron Microscopy of Cells, is used for export of models to IMOD format
- [**MAXFLOW/MINCUT algorithm, v2.22**](http://pub.ist.ac.at/~vnk/software.html) written by Yuri Boykov (University of Western Ontario) and Vladimir Kolmogorov (Microsoft Research, Cambridge) is used in the Graphcut tool
- [**MAXFLOW/MINCUT MATLAB wrapper**](http://www.mathworks.com/matlabcentral/fileexchange/21310-maxflow) is written by Michael Rubinstein (Google) is used in the Graphcut tool
- [**MkDocs**](https://www.mkdocs.org) is acknowledged for documentation generation for MIB 2.91
- [**NUM2CLIP**](https://se.mathworks.com/matlabcentral/fileexchange/8472-num2clip-copy-numerical-arrays-to-clipboard) function by Grigor Browning, 2005, is used to copy column items to the system clipboard
- NRRD, Nearly Raw Raster Data format is implemented using [**Projects:MATLABSlicerExampleModule**](http://www.na-mic.org/Wiki/index.php/Projects:MATLABSlicerExampleModule) written by John Melonakos for NRRD reading using [TEEM](http://teem.sourceforge.net/) and [**VTKPNG.DLL**](https://vtk.org/about/) by Ken Martin, Will Schroeder, and Bill Lorensen; and a custom function for reading metadata based on [NRRD Format File Reader](http://www.mathworks.com/matlabcentral/fileexchange/34653-nrrd-format-file-reader) written by Jeff Mather, 2012
- [**OMERO MATLAB bindings**](http://www.openmicroscopy.org/site/products/omero/downloads) (included into the compiled version, but should be downloaded separately for the MATLAB version) are used for connection to OMERO servers
- [**P_JSON**](http://www.mathworks.com/matlabcentral/fileexchange/25713-highly-portable-json-input-parser), highly portable JSON parser function, is written by Nedialko, 2009, is used for work with HDF5 files
- [**PATCHNORMALS**](https://se.mathworks.com/matlabcentral/fileexchange/24330-patch-normals), by Dirk-Jan Kroon (University of Twente), implementation 2009, is used for calculation of normals during export of surfaces to Imaris
- [**POOLWAITBAR**](https://se.mathworks.com/matlabcentral/answers/465911-parfor-waitbar-how-to-do-this-more-cleanly) class is based on the code submitted by Edric Ellis
- [**Prettify MATLAB html**](https://se.mathworks.com/matlabcentral/fileexchange/78059-prettify-matlab-html) by Harry Dymond, University of Bristol, is used to prettify MIB documentation until MIB 2.91
- Random Forest Classifier is based on [**Verena Kaynig implementation**](http://www.kaynig.de/demos.html) with utilization of [randomforest-matlab](https://code.google.com/p/randomforest-matlab/) by Abhishek Jaiantilal
- [**Region Adjacency Graph (RAG)**](http://www.mathworks.com/matlabcentral/fileexchange/16938-region-adjacency-graph--rag-) function is written by David Legland (INRA, France, 2013) is used in the Graphcut tool
- [**REGIONPROPS3**](http://www.mathworks.com/matlabcentral/fileexchange/47578-regionprops3) function is written by Chaoyuan Yeh (University of Southern California, 2014) is used for quantifying some object properties in 3D
- [**RENDERTEXT**](http://www.mathworks.com/matlabcentral/fileexchange/26940-render-rgb-text-over-rgb-or-grayscale-image) function by Davide Di Gloria (Università di Genova, 2010) is utilized for addition of text to image
- Rendering with Fiji is based on [**Hardware accelerated 3D viewer for MATLAB**](http://www.mathworks.com/matlabcentral/fileexchange/32344-hardware-accelerated-3d-viewer-for-matlab) written by Jean-Yves Tinevez (Institut Pasteur, 2011)
- Rendering with MATLAB is using [**VIEW3D**](http://www.mathworks.com/matlabcentral/fileexchange/334-view3d-m) function written by Torsten Vogel, 1999
- SAM segmentation is using networks and code from [**Segment-anything**](https://segment-anything.com/) written by Kirillov A, Mintun E, Ravi N, Mao H, Rolland C, Gustafson L, Xiao T, Whitehead S, Berg AC, Lo W-Y, Dollar P, Girshick R, Meta AI, 2023
- SAM2 segmentation is using networks and code from [**Segment-anything-2**](https://ai.meta.com/sam2/) written by Ravi N, Gabeur V, Hu Y-T, Hu R, Ryali C, Ma T, Khedr H, Rädle R, Rolland C, Gustafson L, Mintun E, Pan J, Alwala KV, Carion N, Wu C-Y, Girshick R, Dollár P, Feichtenhofer C, Meta AI, 2024
- SAM segmentation is using networks and code from [**Segment-anything for Microscopy**](https://github.com/computational-cell-analytics/micro-sam) written by Archit A, Nair S, Khalid N, Hilt P, Rajashekar V, Freitag M, Gupta S, Dengel A, Ahmed S, Pape C, 2023
- [**SLIC (Simple Linear Iterative Clustering)**](https://www.epfl.ch/labs/ivrl/research/slic-superpixels) written by Radhakrishna Achanta, Appu Shaji, Kevin Smith, Aurelien Lucchi, Pascal Fua, and Sabine Süsstrunk, Ecole Polytechnique Federale de Lausanne (EPFL), Switzerland, 2015, is utilized for the superpixels mode of the Brush tool and for the Graphcut segmentation
- [**Sphinx**](https://www.sphinx-doc.org/), with the [**sphinxcontrib-matlabdomain**](https://github.com/sphinx-contrib/matlabdomain) extension and the [**sphinx-immaterial**](https://github.com/jbms/sphinx-immaterial) theme, is used for generating the MIB3 API reference documentation
- [**STLWRITE**](http://www.mathworks.com/matlabcentral/fileexchange/20922-stlwrite-filename--varargin-) by Sven Holcombe (University of Michigan, 2008-2015) for saving models using the STL format
- [**UIGETFILE_N_DIR**](https://se.mathworks.com/matlabcentral/fileexchange/32555-uigetfile_n_dir-select-multiple-files-and-directories) by Tiago / Peugas is used for selection of multiple directories
- [**VIEWER3D**](http://se.mathworks.com/matlabcentral/fileexchange/21993-viewer3d) by Dirk-Jan Kroon (Focal Machine Vision en Optical Systems) is used as a basis for the volume rendering of datasets
- [**Violin plot**](https://se.mathworks.com/matlabcentral/fileexchange/45134-violin-plot) by Holger Hoffmann, 2015, is used for visualization of results in some analysis functions
- [**XLWRITE: Generate XLS(X) files without Excel on Mac/Linux/Win**](https://se.mathworks.com/matlabcentral/fileexchange/38591-xlwrite--generate-xls-x--files-without-excel-on-mac-linux-win) by Alec de Zegher, NV Bekaert SA, 2013
- [**XLSWRITE**](http://www.mathworks.com/matlabcentral/fileexchange/27236-improved-xlswrite-m) mod by Barry Dillon (AON Insurance Brokers, 2010)
- [**XML2STRUCT**](http://www.mathworks.com/matlabcentral/fileexchange/28518-xml2struct) and [STRUCT2XML](http://www.mathworks.com/matlabcentral/fileexchange/28639-struct2xml) by Wouter Falkena (Delft University of Technology, 2010)
- [**zarr-matlab**](https://github.com/scalableminds/zarr-matlab) by Alessandro Motta (Max Planck Institute for Brain Research) and scalable minds, 2020-2025, is used for reading and writing Zarr2/3 datasets
- [**zensical**](https://github.com/zensical/zensical) by Zensical LLC, 2025-2026, is used for documentation generation for MIB3

## Color Palettes

Color palettes are generated with help of: 

- [Yasuyo G. Ichihara, Masataka Okabe, Koichi Iga, Yosuke Tanaka, Kohei Musha, Kei Ito](http://jfly.iam.u-tokyo.ac.jp/color/). Color Universal Design - The selection of four easily distinguishable colors for all color vision types. Proc Spie 6807 (2008)
- [Cynthia Brewer, Mark Harrower, Ben Sheesley, Andy Woodruff, David Heyman](http://colorbrewer2.org/). ColorBrewer 2.0
- [Sasha Trubetskoy](https://sashat.me/2017/01/11/list-of-20-simple-distinct-colors). List of 20 Simple, Distinct Colors

## Icons and Images

- Some icons used in MIB were provided by [Icons8.com](https://icons8.com), [license information](https://icons8.com/license)
- Some images were generated using [stable-diffusion image generative AI](https://stability.ai/blog/stable-diffusion-public-release)
- Puffin-pirate is a collabroration with Nano Banana 2 by [Google](https://labs.google)

---

*Back to [MIB](../index.md) | [Getting started](index.md)*