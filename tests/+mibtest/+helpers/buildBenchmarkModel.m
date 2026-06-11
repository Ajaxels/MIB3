function [mibModel, groundTruth] = buildBenchmarkModel(imageVolume, labelVolume)
% BUILDBENCHMARKMODEL - headless MibModel with 3 datasets for benchmarking.
%
% Mirrors the dataset layout expected by benchmarkGetSetData:
%   I{1} — labels63  (packed uint8: bits 1-6 material, 7 mask, 8 selection)
%   I{2} — 255-material  (separate layers, uint8)
%   I{3} — 65535-material (separate layers, uint16)
%
% No-arg call: synthetic [64 64 16] volumes.
% With args: supply imageVolume [h w z 1] uint8 and labelVolume [h w z] uint8.
%
% groundTruth.image  [h w z 1] uint8
% groundTruth.labels {3×1 cell} — uint8 for ids 1-2, uint16 for id 3
% groundTruth.mask   [h w z]   uint8
% groundTruth.selection [h w z] uint8

if nargin == 0
    rng(0, 'twister');
    imageVolume = reshape(uint8(randi(255, [64 64 16])), [64 64 16 1]);
    labelVolume = uint8(randi([0 6], [64 64 16]));
end

height = size(imageVolume, 1);
width  = size(imageVolume, 2);
depth  = size(imageVolume, 3);

if nargin == 0
    groundTruth.mask      = uint8(rand([height width depth]) > 0.7);
    groundTruth.selection = uint8(rand([height width depth]) > 0.9);
else
    groundTruth.mask      = zeros([height width depth], 'uint8');
    groundTruth.selection = zeros([height width depth], 'uint8');
end

groundTruth.image     = imageVolume;
groundTruth.labels    = {labelVolume; labelVolume; uint16(labelVolume)};

testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
mibFolder   = fullfile(fileparts(testsFolder), 'mib');
mibModel    = models.MibModel(1, mibFolder);

datasetIds = [1 2 3];
modelTypes = {255, 65535};   % id1 stays labels63; ids 2-3 get createModel

for id = datasetIds
    mibModel.I{id} = core.MibDataset(imageVolume, dictionary(), 'Standard', 'labels63');
    mibModel.I{id}.updateBoundingBox([], [0 0 0]);
    if id > 1
        mibModel.I{id}.createModel(modelTypes{id-1});
    end
    setOptions = struct('id', id, 'blockModeSwitch', 0);
    mibModel.setData3D(groundTruth.labels{id}, 'labels',    1, 3, [], setOptions);
    mibModel.setData3D(groundTruth.mask,       'mask',      1, 3, [], setOptions);
    mibModel.setData3D(groundTruth.selection,  'selection', 1, 3, [], setOptions);
end
end
