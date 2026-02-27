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
mibVersion = 'ver. 2025.12 / 05.12.2025 (alpha)';  

% MAKE SURE THAT cpuParallelLimitMax DOES NOT EXCEED NUMBER OF CPUs 
% WHEN COMPILING
% define max number of parallel workers for deployed versions
% define workers for parallel pools
cpuParallelLimitMax = utils.getMaxParpoolWorkers();

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