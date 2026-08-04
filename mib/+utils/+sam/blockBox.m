function box = blockBox(dataset, zRange)
% BLOCKBOX - Describe the currently shown block used by the SAM segmenters.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      box = utils.sam.blockBox(dataset)
%      box = utils.sam.blockBox(dataset, zRange)
%
% The interactive SAM tools read and write the destination layer in the block
% mode, i.e. only the part of the dataset that is currently visible in the
% image view. The extent of that block changes as soon as the user zooms or
% pans, so any image cached between two clicks has to be tagged with the block
% it was taken from. This function returns that tag; it mirrors the cropping
% performed by :func:`core.MibDataset.getData3D` when
% ``options.blockModeSwitch = true``.
%
% Input Arguments:
%   - **dataset** — [core.MibDataset] dataset that is being segmented
%   - **zRange** *(optional)* — [numeric] ``[zMin, zMax]`` range of slices of the
%     block; when missing or empty, the currently shown slice is used
%
% Output Arguments:
%   - **box** — struct describing the shown block:
%
%     - ``.x`` — ``[xMin, xMax]`` horizontal extent in the dataset coordinates
%     - ``.y`` — ``[yMin, yMax]`` vertical extent in the dataset coordinates
%     - ``.z`` — ``[zMin, zMax]`` range of slices
%     - ``.orientation`` — orientation of the dataset the block was taken in
%     - ``.magFactor`` — scaling between the dataset coordinates and the pixels
%       of the fetched block: ``1`` for the memory-resident datasets and
%       ``dataset.magFactor`` for the pyramidal (BigData, Virtual) datasets,
%       where the block is fetched at the displayed pyramid level
%
% Usage:
%
%   **Example 1** — tag a cached image with the block it was taken from
%
%   .. code-block:: matlab
%
%      box = utils.sam.blockBox(dataset, [z1 z2]);
%

% Updates
%

if nargin < 2; zRange = []; end

getDimensionsOptions.blockModeSwitch = 0;
[fullHeight, fullWidth, fullDepth] = dataset.getDatasetDimensions('image', [], getDimensionsOptions);

% the block mode crops to the shown part of the dataset, see MibDataset.getData3D
[axesX, axesY] = dataset.getAxesLimits();
box.x = [max([1 ceil(axesX(1))]), min([ceil(axesX(2)) fullWidth])];
box.y = [max([1 ceil(axesY(1))]), min([ceil(axesY(2)) fullHeight])];

if isempty(zRange)
    currentSlice = dataset.getCurrentSliceNumber();
    zRange = [currentSlice currentSlice];
end
box.z = [max([1 zRange(1)]), min([zRange(2) fullDepth])];

box.orientation = dataset.orientation;

% pyramidal datasets are fetched at the displayed resolution, so the block
% pixels are magFactor times larger than the dataset coordinates
box.magFactor = 1;
if any(dataset.datasetType(1) == ['V' 'B']); box.magFactor = dataset.magFactor; end

end
