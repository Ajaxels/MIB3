function ThreeLandmarks_Alignment(obj, parameters)
% THREELANDMARKS_ALIGNMENT - Align a stack from a single pair of slices carrying 3+ landmarks.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.ThreeLandmarks_Alignment(parameters)
%
% Walks the stack until it finds the first pair of consecutive slices that
% both carry at least three connected components in the ``selection`` layer,
% treats those centroids as corresponding landmarks, fits an ``affine``
% transform with :func:`fitgeotrans`, and warps every slice from ``layer+1``
% to ``Depth`` with :func:`imwarp`. The warped tail is then concatenated to
% the unchanged head ``1:layer`` via :func:`utils.align.crossShiftStacks` so
% the canvas grows to fit both pieces.
%
% Cancellation: a :class:`core.PoolWaitbar` is constructed with
% ``Cancelable = true`` whenever ``BatchOpt.showWaitbar`` is set; the cancel
% state is polled at each phase boundary (landmark search, image warp,
% service-layer warps) and immediately before each irreversible write.
%
% Input Arguments:
%   - **parameters** — struct produced by :meth:`continueBtn_Callback`. Only
%     ``backgroundColor``, ``colorCh``, ``useBatchMode`` are read here.

% Updates
%

id = obj.mibModel.getActiveId();

% Parent figure for any dialogs — ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

[height, width, depth, ~] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Three-landmark alignment requires at least 2 slices.', 'Alignment');
    return;
end
if obj.mibModel.I{id}.enableSelection == 0
    utils.dlgs.showErrorDialog(parentFig, ...
        ['Three-landmark alignment uses the Selection layer for landmark detection ' ...
         'but the Selection layer is currently disabled.'], 'Alignment');
    return;
end

% --- Backup before any modification (full MibDataset snapshot)
backupOpt.id = id;
obj.mibModel.backup('mibDataset', 1, backupOpt);

% --- Set up cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(depth, 'Searching for landmark pair...', ...
        parentFig, 'Three-landmark alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Find the first slice pair with 3+ landmarks on both sides
optionsGetData = struct('blockModeSwitch', 0);
[tform, layerId, refSliceForBg] = findLandmarkPair(obj, depth, optionsGetData, pwb, parentFig);
if isempty(tform); return; end

% --- Resolve background fill value for the image warp
if isnumeric(parameters.backgroundColor)
    bgImage = double(parameters.backgroundColor);
elseif strcmp(parameters.backgroundColor, 'black')
    bgImage = 0;
elseif strcmp(parameters.backgroundColor, 'white')
    bgImage = double(obj.mibModel.I{id}.image.maxInt);
else    % 'mean'
    refSlice = cell2mat(obj.mibModel.getData2D('image', refSliceForBg, [], parameters.colorCh, optionsGetData));
    bgImage = mean(refSlice(:));
end

% --- Warp image tail [layer+1 : depth] and find canvas shifts from the warped frame
if ~isempty(pwb)
    if pwb.getCancelState(); return; end
    pwb.updateText(sprintf('Warping image slices %d..%d ...', layerId + 1, depth));
end

tailOpts          = optionsGetData;
tailOpts.z        = [layerId + 1, depth];
tailOpts.x        = [1, width];
tailOpts.y        = [1, height];
imageTail = cell2mat(obj.mibModel.getData4D('image', [], 0, tailOpts));   % 5D [h,w,d,c,t]
imageTail = imageTail(:,:,:,:,1);                                         % drop t → MIB3 4D [h,w,d,c]
[imageTailWarped, RBimg] = warpStack4D(imageTail, tform, 'cubic', bgImage);
if isempty(imageTailWarped); return; end

if RBimg.XWorldLimits(1) < 1
    shiftX = floor(RBimg.XWorldLimits(1));
else
    shiftX = ceil(RBimg.XWorldLimits(1));
end
if RBimg.YWorldLimits(1) < 1
    shiftY = floor(RBimg.YWorldLimits(1)) - 1;
else
    shiftY = ceil(RBimg.YWorldLimits(1)) - 1;
end
obj.shiftsX = shiftX;
obj.shiftsY = shiftY;

% --- Concatenate head [1:layerId] + warped tail via crossShiftStacks
headOpts          = optionsGetData;
headOpts.z        = [1, layerId];
headOpts.x        = [1, width];
headOpts.y        = [1, height];
imageHead = cell2mat(obj.mibModel.getData4D('image', [], 0, headOpts));   % 5D [h,w,d,c,t]
imageHead = imageHead(:,:,:,:,1);                                        % drop t → MIB3 4D [h,w,d,c]

stackOpts.backgroundColor = bgImage;
stackOpts.waitbar         = pwb;
stackOpts.modelSwitch     = 0;
[imageStacked, bbShiftXY] = utils.align.crossShiftStacks(imageHead, imageTailWarped, shiftX, shiftY, stackOpts);
if isempty(imageStacked); return; end
clear imageHead imageTail imageTailWarped;

% --- Replace the image canvas directly (setData4D cannot grow a fixed-size data{1})
img5D   = obj.mibModel.I{id}.image;
newH    = size(imageStacked, 1);
newW    = size(imageStacked, 2);
nColors = img5D.colors;
nTime   = img5D.time;
img5D.data{1}   = reshape(imageStacked, [newH, newW, depth, nColors, nTime]);
img5D.height    = newH;
img5D.width     = newW;
img5D.dim_yxzct = [newH, newW, depth, nColors, nTime];
clear imageStacked;

% --- Sync MibDataset metadata BEFORE any service-layer setData4D
ds = obj.mibModel.I{id};
ds.dim_yxzct = img5D.dim_yxzct;
oldSlices = ds.slices;
ds.slices{1} = [1, newH];
ds.slices{2} = [1, newW];
ds.slices{3} = 1:depth;
ds.slices{4} = [1, 1];
ds.slices{5} = [1, 1];
ds.slices{ds.orientation} = repmat(oldSlices{ds.orientation}(1), 1, 2);

% --- Warp + concatenate service layers (labels / mask / selection or packed everything)
serviceOpts.backgroundColor = 0;      % service layers always pad with zeros
serviceOpts.waitbar         = pwb;
serviceOpts.modelSwitch     = 1;      % service layers are 3-D [H, W, Z]

isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

if isLabels63
    if ~isempty(pwb); pwb.updateText('Warping selection / mask / labels...'); end
    everythingWarped = warpAndStackServiceLayer(obj, 'everything', tform, headOpts, tailOpts, serviceOpts);
    if isempty(everythingWarped); return; end
    obj.mibModel.I{id}.labels.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
    obj.mibModel.I{id}.labels.height    = newH;
    obj.mibModel.I{id}.labels.width     = newW;
    obj.mibModel.I{id}.labels.depth     = depth;
    obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, depth, 1, nTime];
    obj.mibModel.setData4D(everythingWarped, 'everything', [], 0);
else
    if obj.mibModel.I{id}.modelExist
        if ~isempty(pwb); pwb.updateText('Warping labels...'); end
        labelsWarped = warpAndStackServiceLayer(obj, 'labels', tform, headOpts, tailOpts, serviceOpts);
        if isempty(labelsWarped); return; end
        obj.mibModel.I{id}.labels.data{1}  = zeros([newH, newW, depth, nTime], class(obj.mibModel.I{id}.labels.data{1}));
        obj.mibModel.I{id}.labels.height    = newH;
        obj.mibModel.I{id}.labels.width     = newW;
        obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(labelsWarped, 'labels', [], NaN);
    end
    if obj.mibModel.I{id}.maskExist
        if ~isempty(pwb); pwb.updateText('Warping mask...'); end
        maskWarped = warpAndStackServiceLayer(obj, 'mask', tform, headOpts, tailOpts, serviceOpts);
        if isempty(maskWarped); return; end
        obj.mibModel.I{id}.mask.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
        obj.mibModel.I{id}.mask.height    = newH;
        obj.mibModel.I{id}.mask.width     = newW;
        obj.mibModel.I{id}.mask.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(maskWarped, 'mask', [], 0);
    end
    if obj.mibModel.I{id}.enableSelection
        if ~isempty(pwb); pwb.updateText('Warping selection...'); end
        selWarped = warpAndStackServiceLayer(obj, 'selection', tform, headOpts, tailOpts, serviceOpts);
        if isempty(selWarped); return; end
        obj.mibModel.I{id}.selection.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
        obj.mibModel.I{id}.selection.height    = newH;
        obj.mibModel.I{id}.selection.width     = newW;
        obj.mibModel.I{id}.selection.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(selWarped, 'selection', [], NaN);
    end
end

% --- Bounding box shift (orientations: 3 = XY, 1 = ZX, 2 = ZY)
maxXshift = bbShiftXY(1);
maxYshift = bbShiftXY(2);
maxZshift = 0;
switch ds.orientation
    case 3
        maxXshift = maxXshift * ds.image.pixSize.x;
        maxYshift = maxYshift * ds.image.pixSize.y;
    case 2
        maxZshift = maxXshift * ds.image.pixSize.z;
        maxYshift = maxYshift * ds.image.pixSize.y;
        maxXshift = 0;
    case 1
        maxZshift = maxXshift * ds.image.pixSize.z;
        maxXshift = maxYshift * ds.image.pixSize.x;
        maxYshift = 0;
end
obj.mibModel.I{id}.updateBoundingBox([], [maxXshift, maxYshift, maxZshift]);

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'Aligned using Three landmark points (split at slice %d)', layerId));

% --- keepBackup=true so the 'mibDataset' snapshot stored by backup() above
%     is not wiped by listener_newDataset.
notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
notify(obj.mibModel, 'ShowImage');
end

% =============================================================================
function [tform, layerId, refSliceForBg] = findLandmarkPair(obj, depth, optionsGetData, pwb, parentFig)
% Walk slices and return an affine transform fit to the first pair of
% consecutive slices that both carry 3+ landmark centroids (connected
% components in the selection layer). Returns ``tform = []`` on failure.

tform         = [];
layerId       = 0;
refSliceForBg = 1;

for layer = 1:depth - 1
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.increment();
    end
    currSel = cell2mat(obj.mibModel.getData2D('selection', layer, [], NaN, optionsGetData));
    if sum(currSel(:)) == 0; continue; end
    CC1 = bwconncomp(currSel);
    if CC1.NumObjects < 3; continue; end

    CC2 = bwconncomp(cell2mat(obj.mibModel.getData2D('selection', layer + 1, [], NaN, optionsGetData)));
    if CC2.NumObjects < 3; continue; end

    STATS1 = regionprops(CC1, 'Centroid');
    STATS2 = regionprops(CC2, 'Centroid');

    X1 = reshape([STATS1.Centroid], [2, numel(STATS1)])';   % fixed   — slice ``layer``
    X2 = reshape([STATS2.Centroid], [2, numel(STATS2)])';   % moving  — slice ``layer+1``
    idx = controllers.Alignment.findMatchingPairs(X2, X1);

    fixedPoints  = X1;
    movingPoints = zeros(numel(STATS1), 2);
    for objId = 1:numel(STATS1)
        movingPoints(objId, :) = STATS2(idx(objId)).Centroid;
    end

    tform         = fitgeotrans(movingPoints, fixedPoints, 'affine');
    layerId       = layer;
    refSliceForBg = layer;
    return;
end

utils.dlgs.showErrorDialog(parentFig, ...
    ['No slice pair with at least three Selection-layer landmark blobs was found.' newline ...
     'Place 3+ disconnected landmarks on each of two consecutive slices and retry.'], ...
    'Three-landmark alignment');
end

% =============================================================================
function [out, R] = warpStack4D(in4D, tform, interp, fillValue)
% Warp every slice of a 4-D MIB3 stack ``[h, w, d, c]`` with the same 2-D
% affine, returning a stack in the same layout and the shared spatial
% reference ``R``. Caller is responsible for cancel polling around this call.

[h, w, d, c] = size(in4D, 1:4);
if d == 0; out = []; R = []; return; end

% Warp the first slice (all colors at once) to discover the output canvas.
% Reshape a single ``[h, w, 1, c]`` slab to a ``[h, w, c]`` 2-D / 3-D array
% — imwarp accepts both and applies the same 2-D transform across colors.
slice = reshape(in4D(:,:,1,:), h, w, c);
[firstWarped, R] = imwarp(slice, tform, interp, 'FillValues', fillValue);
outH = size(firstWarped, 1);
outW = size(firstWarped, 2);
out  = zeros(outH, outW, d, c, class(in4D));
out(:,:,1,:) = reshape(firstWarped, outH, outW, 1, c);
for k = 2:d
    slice = reshape(in4D(:,:,k,:), h, w, c);
    warped = imwarp(slice, tform, interp, 'FillValues', fillValue, 'OutputView', R);
    out(:,:,k,:) = reshape(warped, outH, outW, 1, c);
end
end

% =============================================================================
function imgOut = warpAndStackServiceLayer(obj, layerType, tform, headOpts, tailOpts, serviceOpts)
% Fetch a service-layer head + tail, warp the tail with ``tform`` (nearest
% neighbour) and concatenate via crossShiftStacks. Service layers are 3-D
% ``[H, W, Z]`` — modelSwitch=1 in the helper. Returns ``[]`` on cancel.

if strcmp(layerType, 'everything')
    colArg = 0;
else
    colArg = NaN;
    if strcmp(layerType, 'mask'); colArg = 0; end
end

tail = cell2mat(obj.mibModel.getData4D(layerType, [], colArg, tailOpts));
head = cell2mat(obj.mibModel.getData4D(layerType, [], colArg, headOpts));

% Service-layer getData4D returns 5-D [h, w, d, c, t]; collapse to 3-D [h, w, d]
tail3D = squeeze(tail);
head3D = squeeze(head);

% Warp each slice of the tail
tailD = size(tail3D, 3);
[firstWarped, R] = imwarp(tail3D(:,:,1), tform, 'nearest', 'FillValues', 0);
tailWarped = zeros(size(firstWarped, 1), size(firstWarped, 2), tailD, class(tail3D));
tailWarped(:,:,1) = firstWarped;
for k = 2:tailD
    tailWarped(:,:,k) = imwarp(tail3D(:,:,k), tform, 'nearest', 'FillValues', 0, 'OutputView', R);
end

[imgOut, ~] = utils.align.crossShiftStacks(head3D, tailWarped, ...
    obj.shiftsX, obj.shiftsY, serviceOpts);
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
