function saveInstanceLabelsParFor(fn, imageFilename, instanceLabelMap, compressModels)
% SAVEINSTANCELABELSPARFOR - Save a preprocessed 2D instance label map from inside a ``parfor`` loop.
%
% Syntax:
%   .. code-block:: matlab
%
%      saveInstanceLabelsParFor(fn, imageFilename, instanceLabelMap, compressModels)
%
% Used by ``mibDeepController.processImagesForInstanceSegmentation``;
% ``save`` cannot be called directly inside ``parfor``.
%
% For 2D instance segmentation the label map (each object painted with its own unique
% index, background 0) is stored as a compact 2D array. Training crops native-resolution
% patches from it on-the-fly (see deepmib.readInstancePatch), which is far more
% memory-efficient than storing a full ``H×W×N`` binary mask stack - essential for
% large / whole-slide microscopy images.
%
% Input Arguments:
%   - **fn** - [string] full output filename
%   - **imageFilename** - [string] corresponding source image filename
%   - **instanceLabelMap** - ``[H×W uint16]`` label map, one unique index per object instance
%   - **compressModels** - [logical] ``true`` to enable MAT-file compression

if nargin < 4; compressModels = true; end

if compressModels
    save(fn, 'imageFilename', 'instanceLabelMap', '-mat', '-v7.3');
else
    save(fn, 'imageFilename', 'instanceLabelMap', '-nocompression', '-mat', '-v7.3');
end
end
