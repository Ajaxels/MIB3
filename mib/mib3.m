function controller = mib3()
% @mainpage Microscopy Image Browser
% @section intro Introduction
% @b Microscopy @b Image @b Browser is is a high-performance software package for advanced image processing, segmentation and visualization of multidimensional (2D-4D) datasets.
% Microscopy Image Browser is written in Matlab, but has a user friendly graphical interface that does not require knowledge of Matlab and can be used by anybody.
% @section features Key Features
% - Works as a Matlab program under Windows/Linux/MacOS Matlab, or as a standalone application (Windows 64bit);
% - Open source, no license/fee required;
% - Extendable with custom plugins;
% - Generation of multidimensional image stacks;
% - Alignment of 3D stacks and images within these stacks;
% - Brightness, contrast, gamma, image mode adjustments, resize, crop functions;
% - Automatic/manual image segmentation with help of filters and interpolation in XY, XZ, or YZ planes;
% - Quantification and statistics for 2D/3D objects;
% - Export of images or models to Matlab, Amira, IMOD, TIF, NRRD formats;
% - Direct 3D visualization using Matlab isosurfaces or Fiji 3D viewer;
% - Log of performed actions;
% - Customizable Undo option
% - Colorblind friendly default color modeling scheme
% @section description Description
% Recent years witnessed a rapid development of 3D electron microscopy
% imaging techniques applied for the life science research. In addition to electron tomography
% (ET) that is effective on a sub cellular level, several other alternative methods that extend the
% imaging up to the tissue level have been developed. Among these are new scanning electron microscopy (SEM)
% techniques that allow automated sequential imaging of a freshly cut block face of resin-embedded specimens
% using a back scatter detector. A fresh block face is created by an ultramicrotome inserted in the imaging
% chamber (Serial-Block Face SEM) or by focused ion beam (FIB-SEM). As a result, the amount and volumes of
% 3D datasets increases extensively raising a question of effective image processing and modeling.
% With development of Microscopy Image Browser (MIB) we address this problem and present a free,
% open-source software package, which can be used for image processing, analysis, segmentation and
% visualization of multidimensional datasets.
%
% @page install Download and installation
% Please follow instructions on Microscopy Image Browser web page:
% http://mib.helsinki.fi

% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% Date: 2010-2026

% add path to other directories
tic

% ATTENTION! it is important to have the version number between "ver." and "/" 
% Release syntax example: "ver. 2025.11 / 04.11.2025"
% Beta syntax example: "ver. 2025.11 (beta 4) / 04.11.2025"
mibVersion = 'ver. 2026.0703 / 03.07.2025 (preview)';  

% MAKE SURE THAT cpuParallelLimitMax DOES NOT EXCEED NUMBER OF CPUs
% WHEN COMPILING
% max number of parallel workers is computed lazily on the first access of
% MibModel.cpuParallelLimitMax (utils.getMaxParpoolWorkers queries the slow
% parcluster profile); pass an explicit value here to override
cpuParallelLimitMax = [];

% Enable GPU Future compatibility
% https://se.mathworks.com/help/parallel-computing/parallel.gpu.enablecudaforwardcompatibility.html
% define system environment: MW_CUDA_FORWARD_COMPATIBILITY=1 to preserve forward compatibility between MATLAB sessions.
parallel.gpu.enableCUDAForwardCompatibility(true);
setenv("CUDA_CACHE_MAXSIZE ", "536870912");

% Configure figures for deployment
if isdeployed()
    s = settings;
    % Make sure that documents are docked in the compiled application
    s.matlab.ui.figure.DockFigureInDeployment.TemporaryValue = true;
else
    % add folders to path in case mib3 was started without the project
    func_name='mib3.m';
    func_dir=which(func_name);
    func_dir=fileparts(func_dir);
    addpath(func_dir);
    addpath(fullfile(func_dir, 'external'));
    addpath(fullfile(func_dir, 'external', 'bioformats'));
    addpath(fullfile(func_dir, 'external', 'CellMigration'));
    addpath(fullfile(func_dir, 'external', 'export_fig'));
    addpath(fullfile(func_dir, 'external', 'FastMarching'));
    addpath(fullfile(func_dir, 'external', 'HistThresh'));
    addpath(fullfile(func_dir, 'external', 'matGeom', 'geom2d'));
    addpath(fullfile(func_dir, 'external', 'matGeom', 'geom3d'));
    addpath(fullfile(func_dir, 'external', 'MatTomo'));
    addpath(fullfile(func_dir, 'external', 'nrrd'));
    addpath(fullfile(func_dir, 'external', 'RegionGrowing'));
    addpath(fullfile(func_dir, 'external', 'RandomForest'));
    addpath(fullfile(func_dir, 'external', 'RandomForest', 'MembraneDetection'));
    addpath(fullfile(func_dir, 'external', 'RandomForest', 'RF_Class_C'));
    addpath(fullfile(func_dir, 'external', 'RandomForest', 'RF_Reg_C'));
    addpath(fullfile(func_dir, 'external', 'Supervoxels'));
    addpath(fullfile(func_dir, 'external', 'Zarr3Matlab'));
    addpath(fullfile(func_dir, 'legacy'));    
    addpath(fullfile(func_dir, 'assets'));    
    addpath(fullfile(func_dir, 'assets', 'icons'));
    addpath(fullfile(func_dir, 'assets', 'images'));
end

if false
    % Forces MATLAB Compiler to include dynamically-referenced views.
    % This function is NEVER called at runtime.
    views.AboutGUI %#ok<*UNRCH>
    views.ActionLogGUI;
    views.AlignmentGUI;
    views.AmiraImportGUI;
    views.AnnotationsGUI;
    views.BatchProcessingGUI;
    views.BoundingBoxGUI;
    views.ChunkingExportGUI;
    views.ChunkingImportGUI;
    views.ContentAwareFillGUI;
    views.ContrastClaheGUI;
    views.ContrastNormalizationGUI;
    views.CropDatasetGUI;
    views.CropObjectsGUI;
    views.DatasetInfoGUI;
    views.DebrisRemovalGUI;
    views.DisplayAdjustGUI;
    views.GlobalThresholdingGUI;
    views.GraphcutGUI;
    views.ImageArithmeticsGUI;
    views.ImageFiltersGUI;
    views.ImageFrameGUI;
    views.Lines3dDialog;
    views.MakeMovieGUI;
    views.MeasureToolGUI;
    views.MibDeepActivationsGUI;
    views.MibDeepAugmentSettingsGUI;
    views.MibDeepGUI;
    views.MorphOpsGUI;
    views.MorphOpsImagesGUI;
    views.ObjectSeparatorGUI;
    views.PreferencesGUI;
    views.QuantificationGUI;
    views.QuantificationPropertiesGUI;
    views.RenameRestoreGUI;
    views.RenameShuffleGUI;
    views.ResampleDatasetGUI;
    views.SelectHDFSeriesGUI;
    views.SelectLociSeriesGUI;
    views.SelectModelTypeGUI;
    views.SnapshotGUI;
    views.StereologyGUI;
    views.StitchingGUI;
    views.TipsAppGUI;
    views.VolRenAppGUI;
    views.VolRenAppViewerGUI;
    views.WhiteBalanceGUI;
    views.WoundHealingGUI;
end

mibPath = utils.getInstallationPath('mib3');
fprintf('MIB installation path: %s\n', mibPath);

%try
    model = models.MibModel(cpuParallelLimitMax, mibPath, mibVersion);     % initialize the model
    controller = controllers.MibController(model, mibVersion);  % initialize controller
%catch err
%    utils.dlgs.showErrorDialog([], err, 'MIB Error');
%end

toc