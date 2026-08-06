function [mibModel, groundTruth] = buildSyntheticModel(options)
% BUILDSYNTHETICMODEL - headless MibModel with one synthetic dataset.
%
% Returns a fresh MibModel (I{1} replaced with a synthetic dataset) and a
% groundTruth struct holding the raw arrays that the accessors should reproduce.
% Call once per test method - MibModel/MibDataset are handle objects and must
% not be shared between test methods.
%
% Options:
%   modelType : 'labels63' (default) | 'labels255' | 'labels65535'
%   dims      : [h w z]  (default [64 64 16])
%   numColors : number of color channels (default 1)
%
% groundTruth fields:
%   .image     [h w z numColors] uint8
%   .labels    [h w z]   uint8 (labels63/labels255) | uint16 (labels65535)
%   .mask      [h w z]   uint8 binary
%   .selection [h w z]   uint8 binary

arguments
    options.modelType  (1,:) char   = 'labels63'
    options.dims       (1,3) double = [64 64 16]
    options.numColors  (1,1) double = 1
end

rng(0, 'twister');   % determinism - never remove; tests depend on this seed

height    = options.dims(1);
width     = options.dims(2);
depth     = options.dims(3);
numColors = options.numColors;

groundTruth.image     = uint8(randi(255, [height width depth numColors]));
groundTruth.labels    = uint8(randi([0 6], [height width depth]));
groundTruth.mask      = uint8(rand([height width depth]) > 0.7);
groundTruth.selection = uint8(rand([height width depth]) > 0.9);

% Path derivation: +helpers/ -> +mibtest/ -> tests/ -> repo root -> mib/
testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
mibFolder   = fullfile(fileparts(testsFolder), 'mib');

% mibPath MUST be the absolute path to mib/ (Phase 0 finding: empty mibPath
% fails in clean sessions because datasetsSetsOps.m resolves assets relative
% to mibPath and imread('assets/images/default.png') fails without it).
mibModel = models.MibModel(1, mibFolder);

mibModel.I{1} = core.MibDataset(groundTruth.image, dictionary(), 'Standard', 'labels63');
mibModel.I{1}.updateBoundingBox([], [0 0 0]);

switch options.modelType
    case 'labels255'
        mibModel.I{1}.createModel(255);
    case 'labels65535'
        mibModel.I{1}.createModel(65535);
        groundTruth.labels = uint16(groundTruth.labels);   % must match accessor return class
end

setOptions = struct('id', 1, 'blockModeSwitch', 0);
mibModel.setData3D(groundTruth.labels,    'labels',    1, 3, [], setOptions);
mibModel.setData3D(groundTruth.mask,      'mask',      1, 3, [], setOptions);
mibModel.setData3D(groundTruth.selection, 'selection', 1, 3, [], setOptions);
end
