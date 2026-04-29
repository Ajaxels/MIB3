function saveInstanceLabelsParFor(fn, imageFilename, instanceBoxes, instanceNames, instanceMasks, compressModels)
% SAVEINSTANCELABELSPARFOR - Save preprocessed instance-segmentation labels from inside a ``parfor`` loop.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      saveInstanceLabelsParFor(fn, imageFilename, instanceBoxes, instanceNames, instanceMasks, compressModels)
%
% Used by ``mibDeepController.processImagesForInstanceSegmentation``;
% ``save`` cannot be called directly inside ``parfor``.
%
% Input Arguments:
%   - **fn** — [string] full output filename
%   - **imageFilename** — [string] corresponding source image filename
%   - **instanceBoxes** — ``[N×4 double]`` bounding-box coordinates (one row per object)
%   - **instanceNames** — ``[N×1 categorical]`` object class labels
%   - **instanceMasks** — ``[H×W×N logical]`` binary mask stack (one slice per object)
%   - **compressModels** — [logical] ``true`` to enable MAT-file compression
%     represents individual object that should match the corresponding entry in
%     instanceBoxes and instanceNames
%   - **compressModels** — logical switch to use of not compression for images
%

if nargin < 6; compressModels = true; end

if compressModels     % saving images
    save(fn, 'imageFilename', 'instanceBoxes', 'instanceNames', 'instanceMasks', '-mat', '-v7.3');   % save image file
else
    save(fn, 'imageFilename', 'instanceBoxes', 'instanceNames', 'instanceMasks', '-nocompression', '-mat', '-v7.3');
end
end
