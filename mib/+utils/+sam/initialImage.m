function initialImage = initialImage(mibModel, dataset, cacheName, layerName, timePoint, materialIndex, getDataOptions, zRange, targetSize)
% INITIALIMAGE - Return a layer of the dataset as it was before the current SAM interaction started.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      initialImage = utils.sam.initialImage(mibModel, dataset, cacheName, layerName, timePoint, materialIndex, getDataOptions, zRange)
%      initialImage = utils.sam.initialImage(mibModel, dataset, cacheName, layerName, timePoint, materialIndex, getDataOptions, zRange, targetSize)
%
% The interactive SAM tools segment an object with a series of clicks: the
% first click creates the object and each Shift/Ctrl-click re-runs the model
% with an extra positive/negative seed. Both the layer the results are added to
% and the material the results are restricted to have to be taken as they were
% **before** the first click, because every run overwrites what the previous
% one produced:
%
%   - ``'initialImageAddTo'`` — the destination layer; merging with its current
%     state instead would keep the discarded parts of the previous run and make
%     the negative seeds useless
%   - ``'initialImageSelected'`` — the "fix selection to material" mask; using
%     its current state instead would exclude the area already taken by the
%     object itself (the first click moved those pixels out of the restricting
%     material), so every second click would erase the object and the next one
%     would bring it back
%
% Those states are cached in ``mibModel.sessionSettings.SAMsegmenter`` by
% ``controllers.MibImageDocument.gui_WindowButtonDownFcn`` on the first click,
% together with the shown block they were taken from (field
% ``<cacheName>Box``, see :func:`utils.sam.blockBox`). A cache is used as-is
% while the block is unchanged; after a zoom, a pan or a new seeded slice it is
% re-mapped onto the current block by :func:`utils.sam.alignInitialImage` and,
% when the block has grown, stored back so that the following clicks keep the
% pre-interaction state over the wider area.
%
% Input Arguments:
%   - **mibModel** — [models.MibModel] the model, keeps the caches in ``sessionSettings``
%   - **dataset** — [core.MibDataset] dataset that is being segmented
%   - **cacheName** — [char] name of the cached field:
%     ``'initialImageAddTo'`` or ``'initialImageSelected'``
%   - **layerName** — [char] layer to fetch: ``'selection'``, ``'mask'`` or ``'labels'``
%   - **timePoint** — [numeric] index of the time point to fetch
%   - **materialIndex** — [numeric] index of the material to fetch
%   - **getDataOptions** — struct with options for :func:`models.MibModel.getData3D`;
%     ``.blockModeSwitch`` and ``.z`` are set by this function
%   - **zRange** — [numeric] ``[zMin, zMax]`` range of slices of the current run
%   - **targetSize** *(optional)* — [numeric] size of the segmentation result the
%     returned image has to be combined with; the image is cropped or zero-padded
%     to it. Guards against the one-pixel differences between the image and the
%     model blocks of the pyramidal datasets
%
% Output Arguments:
%   - **initialImage** — [uint8] the requested layer as it was before the current
%     SAM interaction started, cropped to the shown block over **zRange**,
%     ``[height, width, depth]``
%
% Usage:
%
%   **Example 1** — merge the results of the current run with the initial state
%
%   .. code-block:: matlab
%
%      initialImage = utils.sam.initialImage(obj.mibModel, dataset, 'initialImageAddTo', 'labels', t, selMaterialIndex, getDataOpt, [z1 z2], size(imgDataset));
%      obj.mibModel.setData3D({bitor(initialImage, imgDataset)}, 'labels', t, dataset.orientation, selMaterialIndex, getDataOpt);
%
%   **Example 2** — restrict the results to the selected material
%
%   .. code-block:: matlab
%
%      materialMask = utils.sam.initialImage(obj.mibModel, dataset, 'initialImageSelected', 'labels', t, selectedFixToMaterial, getDataOpt, [z1 z2], size(imgDataset));
%      imgDataset = bitand(imgDataset, materialMask);
%

% Updates
%

if nargin < 9; targetSize = []; end

currentBox = utils.sam.blockBox(dataset, zRange);

cachedImage = [];
cachedBox = [];
if isfield(mibModel.sessionSettings, 'SAMsegmenter')
    if isfield(mibModel.sessionSettings.SAMsegmenter, cacheName)
        cachedImage = mibModel.sessionSettings.SAMsegmenter.(cacheName);
    end
    if isfield(mibModel.sessionSettings.SAMsegmenter, [cacheName 'Box'])
        cachedBox = mibModel.sessionSettings.SAMsegmenter.([cacheName 'Box']);
    end
end

% the shown block and the z-range are the same as when the cache was taken
if ~isempty(cachedImage) && isequal(cachedBox, currentBox)
    initialImage = cachedImage;
else
    % the view was zoomed/panned or the z-range has grown: fetch the layer over
    % the current block and restore the initial state on top of it
    getDataOptions.blockModeSwitch = true;
    getDataOptions.z = zRange;
    currentImage = uint8(cell2mat(mibModel.getData3D(layerName, timePoint, dataset.orientation, materialIndex, getDataOptions)));
    initialImage = utils.sam.alignInitialImage(cachedImage, cachedBox, currentImage, currentBox);

    % Grow the cache to the wider block. The part that has just been fetched has
    % not been touched by this interaction yet, so it is the initial state of the
    % new area; without storing it, the next click would fetch it again — but by
    % then it would already contain the result of the current run.
    % Only growing blocks are stored: a smaller block (a zoom in, or the
    % slice-by-slice loop of the 'Interactive' method) would throw the rest of
    % the cached area away.
    if isSupersetBox(currentBox, cachedBox)
        mibModel.sessionSettings.SAMsegmenter.(cacheName) = initialImage;
        mibModel.sessionSettings.SAMsegmenter.([cacheName 'Box']) = currentBox;
    end
end

initialImage = fitToSize(initialImage, targetSize);

end

function isSuperset = isSupersetBox(currentBox, cachedBox)
% ISSUPERSETBOX - check that the current block completely covers the cached one.
%
% Input Arguments:
%   - **currentBox** — struct with the current block, see :func:`utils.sam.blockBox`
%   - **cachedBox** — struct with the cached block; can be empty
%
% Output Arguments:
%   - **isSuperset** — [logical] ``true`` when the current block covers the cached one
%

isSuperset = false;
if isempty(cachedBox) || ~isstruct(cachedBox); isSuperset = true; return; end
if cachedBox.orientation ~= currentBox.orientation; return; end
if abs(cachedBox.magFactor - currentBox.magFactor) > 1e-6; return; end

isSuperset = currentBox.x(1) <= cachedBox.x(1) && currentBox.x(2) >= cachedBox.x(2) && ...
    currentBox.y(1) <= cachedBox.y(1) && currentBox.y(2) >= cachedBox.y(2) && ...
    currentBox.z(1) <= cachedBox.z(1) && currentBox.z(2) >= cachedBox.z(2);

end

function image = fitToSize(image, targetSize)
% FITTOSIZE - crop or zero-pad an image to the requested size.
%
% Input Arguments:
%   - **image** — [numeric] image to fit, ``[height, width, depth]``
%   - **targetSize** — [numeric] requested size; when empty the image is returned as is
%
% Output Arguments:
%   - **image** — [numeric] image of the requested size
%

if isempty(targetSize); return; end

targetSize = [targetSize, ones(1, 3-numel(targetSize))];
targetSize = targetSize(1:3);
if isequal([size(image, 1), size(image, 2), size(image, 3)], targetSize); return; end

fittedImage = zeros(targetSize, 'like', image);
rows = 1:min([size(image, 1) targetSize(1)]);
cols = 1:min([size(image, 2) targetSize(2)]);
slices = 1:min([size(image, 3) targetSize(3)]);
fittedImage(rows, cols, slices) = image(rows, cols, slices);
image = fittedImage;

end
