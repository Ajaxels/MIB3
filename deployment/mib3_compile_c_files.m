% This script will compile all the C/C++ mex files for MIB3.
% Run from the MATLAB command window; mib3.m must be on the path.
mibDir = fileparts(which('mib3'));   % C:\Matlab\MIB3\mib

progressBar = waitbar(0, sprintf('Starting compilation\nPlease wait...'), 'Name', 'Compiling C/C++ files for MIB3');

%% Volume rendering  — NOT present in MIB3 (no external/volren directory)
% currDir = fullfile(mibDir, 'external', 'volren');
% cd(currDir);
% mex -compatibleArrayDims -v affine_transform_2d_double.c image_interpolation.c;

%% Frangi vesselness filter  — NOT present in MIB3 (no external/Frangi directory)
% waitbar(0.05, progressBar, sprintf('Compiling Frangi\nPlease wait...'));
% currDir = fullfile(mibDir, 'external', 'Frangi');
% cd(currDir);
% mex -compatibleArrayDims -v eig3volume.c
% mex -compatibleArrayDims -v imgaussian.c

%% Fast marching
waitbar(0.05, progressBar, sprintf('Compiling Fast Marching\nPlease wait...'));
currDir = fullfile(mibDir, 'external', 'FastMarching', 'functions');
cd(currDir);
mex -compatibleArrayDims -v msfm2d.c
mex -compatibleArrayDims -v msfm3d.c

currDir = fullfile(mibDir, 'external', 'FastMarching', 'shortestpath');
cd(currDir);
mex -compatibleArrayDims -v rk4.c

%% Membrane detection
waitbar(0.3, progressBar, sprintf('Compiling Membrane Detection\nPlease wait...'));
currDir = fullfile(mibDir, 'external', 'RandomForest', 'MembraneDetection');
cd(currDir);
mex('meanvar.c', '-v');
mex('transformImageFast.c', '-v');

%% SLIC superpixels and maxflow
waitbar(0.5, progressBar, sprintf('Compiling SLIC and Maxflow\nPlease wait...'));
currDir = fullfile(mibDir, 'external', 'Supervoxels');
cd(currDir);
mex('slicmex.c', '-v');
mex('slicomex.c', '-v');
mex('slicsupervoxelmex.c', '-v');
mex('slicsupervoxelmex_byte.c', '-v');
mex -v -largeArrayDims maxflowmex_v222.cpp maxflow-v2.22/adjacency_list_new_interface/graph.cpp maxflow-v2.22/adjacency_list_new_interface/maxflow.cpp

%% GetExeLocation — acquires path to deployed MIB3 executable
waitbar(0.75, progressBar, sprintf('Compiling GetExeLocation\nPlease wait...'));
currDir = fullfile(mibDir, '+utils');
cd(currDir);
mex('GetExeLocation.c', '-v');

%% Region growing
waitbar(0.85, progressBar, sprintf('Compiling Region Growing\nPlease wait...'));
currDir = fullfile(mibDir, 'external', 'RegionGrowing');
cd(currDir);
mex('RegionGrowing_mex.cpp', '-v');

%% NRRD reader
waitbar(0.95, progressBar, sprintf('Compiling NRRD reader\nPlease wait...'));
currDir = fullfile(mibDir, 'external', 'nrrd');
cd(currDir);
mex('nrrdLoadWithMetadata.c', '-v');

waitbar(1, progressBar);
delete(progressBar);

forestPath1 = fullfile(mibDir, 'external', 'RandomForest', 'RF_Class_C');
forestPath2 = fullfile(mibDir, 'external', 'RandomForest', 'RF_Reg_C');
warndlg(sprintf('!!! Warning !!!\n\nThe following files have to be compiled manually:\nRandom Forest Classifier (Linux)\n%s\n%s', forestPath1, forestPath2));
disp('!!!!!!!!!!!!!!!!!!! Warning !!!!!!!!!!!!!!!!!!!')
disp('The following files have to be compiled manually:')
disp('Random Forest Classifier (Linux):')
disp(forestPath1)
disp(forestPath2)
