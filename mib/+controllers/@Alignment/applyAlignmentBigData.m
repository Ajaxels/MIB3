function result = applyAlignmentBigData(obj, parameters, tformInfo)
% APPLYALIGNMENTBIGDATA - Shared apply pipeline for BigData alignment.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.applyAlignmentBigData(parameters, tformInfo)
%
% Given per-slice level-0 transforms, streams a NEW aligned OME-Zarr v3 image
% store (and, when a BigData model exists, a sibling ``Labels_<stem>.zarr3``),
% then reopens and swaps the active buffer to it. The source store is left intact
% and acts as the backup (no ``mibModel.backup`` is taken in BigData paths).
%
% Pipeline:
%   1. Build per-slice level-0 transforms + the level-0 output canvas
%      (``extended`` growth or ``cropped`` original dims).
%   2. One shared level plan (``Zarr3Saver.computeLevelPlan``) so the image store
%      (built by ``saveStream``) and the labels store (built by ``createStore``)
%      share identical level sizes / scale factors / chunks.
%   3. Stream the image store via ``Zarr3Saver.saveStream`` +
%      :class:`io.savers.AlignedImageSliceProvider`.
%   4. Warp packed-63 labels/mask/selection (nearest-neighbour) into a new
%      ``MibBigDataLabels`` store; ``materializeAll`` + ``closeStore`` (persists
%      the level map).
%   5. Patch metadata (bounding box + per-level translation/scale).
%   6. Reopen + swap the active buffer (per ``CropDataset``).
%
% Input Arguments:
%   - **parameters** — struct from :meth:`continueBtn_Callback` (``outputPath``,
%     ``TransformationMode``, ``backgroundColor``, ...).
%   - **tformInfo** — struct describing the level-0 transforms:
%
%     - ``.mode`` — ``'translation'`` or ``'affine'``.
%     - ``.shiftX0`` / ``.shiftY0`` — [Nx1] integer level-0 shifts (translation mode).
%     - ``.tforms`` — ``{depth x 1}`` cell of ``affinetform2d`` (affine mode).
%     - ``.backgroundValue`` — numeric scalar image background fill.
%
% See also: io.savers.AlignedImageSliceProvider, io.savers.Zarr3Saver,
% core.MibBigDataLabels, controllers.Alignment.DriftCorrectionBigData_Alignment

result = 0;
id = obj.mibModel.getActiveId();
ds = obj.mibModel.I{id};

if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% Phase 1 supports native XY orientation only (BigData slides are XY).
if ds.orientation ~= 3
    utils.dlgs.showErrorDialog(parentFig, ...
        'BigData alignment currently supports XY (orientation 3) datasets only.', 'Alignment');
    return;
end

H0      = ds.image.height;
W0      = ds.image.width;
depth   = ds.image.depth;
nFrames = ds.image.time;
pixSize = ds.image.pixSize;
backgroundValue = tformInfo.backgroundValue;

% =====================================================================
% 1. Per-slice level-0 transforms + output canvas
% =====================================================================
switch tformInfo.mode
    case 'translation'
        shiftX0 = round(tformInfo.shiftX0(:));
        shiftY0 = round(tformInfo.shiftY0(:));
        minX = min(shiftX0);    maxX = max(shiftX0);
        minY = min(shiftY0);    maxY = max(shiftY0);

        if strcmp(parameters.TransformationMode, 'cropped')
            newH0 = H0;    newW0 = W0;
            txArr = shiftX0;    tyArr = shiftY0;   % slice 1 anchored, rest clipped
            originShiftX = 0;   originShiftY = 0;
        else   % extended
            newW0 = W0 + (abs(minX) + maxX);
            newH0 = H0 + (abs(minY) + maxY);
            txArr = shiftX0 - minX;   % >= 0
            tyArr = shiftY0 - minY;
            originShiftX = minX;      % <= 0 typically
            originShiftY = minY;
        end

        tforms = cell(depth, 1);
        for z = 1:depth
            tforms{z} = affinetform2d([1 0 txArr(z); 0 1 tyArr(z); 0 0 1]);
        end
        imageInterp = 'nearest';   % integer translation → exact, resample-free placement

    case 'affine'
        % Level-0 affine transforms are supplied by the caller (Phase 2).
        tforms = tformInfo.tforms(:);
        if isfield(tformInfo, 'outputSize') && ~isempty(tformInfo.outputSize)
            newH0 = tformInfo.outputSize(1);
            newW0 = tformInfo.outputSize(2);
        else
            newH0 = H0;    newW0 = W0;
        end
        if isfield(tformInfo, 'originShift') && ~isempty(tformInfo.originShift)
            originShiftX = tformInfo.originShift(1);
            originShiftY = tformInfo.originShift(2);
        else
            originShiftX = 0;    originShiftY = 0;
        end
        imageInterp = 'cubic';

    otherwise
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('Unknown BigData alignment mode "%s".', tformInfo.mode), 'Alignment');
        return;
end

% =====================================================================
% 2. Saver options + shared level plan — matched to the SOURCE pyramid so the
%    aligned store keeps the same chunking / level count / downsampling strategy
%    / sharding as the input (image and labels share ONE plan for co-registration).
% =====================================================================
srcPyr = ds.image.pyramid;
axisOrder = 'yxz';
if isfield(srcPyr, 'axisOrder') && ~isempty(srcPyr.axisOrder)
    axisOrder = char(srcPyr.axisOrder);
end

% level-0 chunk shape as [y x z]
chunkYXZ = [256 256 16];
if isfield(srcPyr, 'chunkSizes') && ~isempty(srcPyr.chunkSizes) && ~isempty(srcPyr.chunkSizes{1})
    chunkYXZ = mapAxisVec(double(srcPyr.chunkSizes{1}), axisOrder, chunkYXZ);
end

% same number of pyramid levels as the source (explicit → no auto MinLevelSize cut)
srcLevels = 1;
if isfield(srcPyr, 'levelImageSizes') && ~isempty(srcPyr.levelImageSizes)
    srcLevels = size(srcPyr.levelImageSizes, 1);
end

% downsample strategy: 'Anisotropy-preserving' if the source pyramid ever halves Z
downsampleStrategy = 'XY only';
if isfield(srcPyr, 'levelScaleFactors') && size(srcPyr.levelScaleFactors, 1) >= 2 ...
        && any(diff(srcPyr.levelScaleFactors(:, 3)) > 0)
    downsampleStrategy = 'Anisotropy-preserving';
end

saverOpts = struct();
saverOpts.silent             = true;             % skip the interactive export dialog
saverOpts.ChunkSize          = chunkYXZ;
saverOpts.DownsampleStrategy = downsampleStrategy;
saverOpts.DownsampleMethod   = 'bilinear';
saverOpts.Levels             = srcLevels;        % reproduce the source level count exactly

% sharding: only when the source shard genuinely spans more than one chunk
if isfield(srcPyr, 'shardSizes') && ~isempty(srcPyr.shardSizes) && ~isempty(srcPyr.shardSizes{1})
    shardYXZ = mapAxisVec(double(srcPyr.shardSizes{1}), axisOrder, chunkYXZ);
    if any(shardYXZ > chunkYXZ)
        saverOpts.ShardSize = shardYXZ;
    end
end

% GUI mode: offer the export-to-zarr3 options dialog, PRE-FILLED with the source
% settings above (silent/batch runs keep the source-matched defaults directly).
if ~parameters.useBatchMode
    preset = struct('Levels', srcLevels, 'ChunkSize', chunkYXZ, ...
        'DownsampleStrategy', downsampleStrategy, 'DownsampleMethod', 'bilinear');
    if isfield(saverOpts, 'ShardSize'); preset.ShardSize = saverOpts.ShardSize; end
    datasetInfo = struct('Y', newH0, 'X', newW0, 'Z', depth, 'pixSize', pixSize);
    dlg = io.savers.Zarr3Saver.optionsDialog(parentFig, obj.mibModel.mibPath, false, datasetInfo, preset);
    if isempty(dlg)                                   % cancelled → abort, nothing written
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    % Merge the user's choices over the source-matched base. The dialog omits
    % Levels when 'auto' (0) and ShardSize when 'off', so drop those first to let
    % auto / no-sharding take effect; silent + method stay ours where not set.
    saverOpts = rmfield(saverOpts, intersect(fieldnames(saverOpts), {'Levels', 'ShardSize'}));
    saverOpts.MinLevelSize = 256;   % auto fallbacks used only when Levels is absent
    saverOpts.MaxLevels    = 8;
    for f = reshape(fieldnames(dlg), 1, [])
        saverOpts.(f{1}) = dlg.(f{1});
    end
    chunkYXZ = saverOpts.ChunkSize;   % labels follow the (possibly changed) chunk
end

plan    = io.savers.Zarr3Saver.computeLevelPlan(newH0, newW0, depth, pixSize, saverOpts);
nLevels = numel(plan);

outputImagePath = char(parameters.outputPath);

% Output canvas reference — same for image and labels so both co-register.
% translation/affine callers bake the origin offset into their tforms and use a
% default (unit-pixel) view; landmark callers pass a world-limited view instead.
if isfield(tformInfo, 'outputView') && ~isempty(tformInfo.outputView)
    ref0 = tformInfo.outputView;
else
    ref0 = imref2d([newH0 newW0]);
end

% =====================================================================
% 3. Write the aligned image store (streamed, memory ≈ one slice)
% =====================================================================
imgProvider = io.savers.AlignedImageSliceProvider( ...
    ds.image, tforms, ref0, backgroundValue, [], imageInterp, depth, nFrames);
meta  = struct('pixSize', pixSize);
saver = io.savers.Zarr3Saver(struct('ParentFigure', parentFig));
fnOut = saver.saveStream(imgProvider, meta, outputImagePath, saverOpts);
if isempty(fnOut)                         % cancelled during image write
    if isfolder(outputImagePath); rmdir(outputImagePath, 's'); end
    notify(obj.mibModel, 'StopProtocol');
    return;
end

% =====================================================================
% 4. Write the aligned labels store (packed-63 nearest-neighbour warp)
% =====================================================================
hasModel = ds.modelExist && isa(ds.labels, 'core.MibBigDataLabels') && ds.labels.exists;
srcMaterialNames  = {};
srcMaterialColors = [];
srcMaterialsCount = 0;
modelStorePath    = '';
if hasModel
    srcMaterialNames  = ds.labels.materialNames;
    srcMaterialColors = ds.labels.materialColors;
    srcMaterialsCount = ds.labels.materialsCount;

    [parentDir, stem, ext] = fileparts(outputImagePath);
    modelStorePath = fullfile(parentDir, ['Labels_' stem ext]);

    % Build the labels pyramid from the shared plan so it mirrors the image.
    newLevelSizes   = zeros(nLevels, 3);
    newScaleFactors = zeros(nLevels, 3);
    for L = 1:nLevels
        newLevelSizes(L, :)   = [plan(L).Yl, plan(L).Xl, plan(L).Zl];
        newScaleFactors(L, :) = [plan(L).cumXYFactor, plan(L).cumXYFactor, plan(L).cumZFactor];
    end
    newPyramid = struct();
    newPyramid.levelImageSizes   = newLevelSizes;
    newPyramid.levelScaleFactors = newScaleFactors;
    newPyramid.axisOrder = axisOrder;
    % Chunk the labels pyramid like the image (final chunkYXZ — source-matched or
    % dialog-adjusted), laid out in axisOrder for every level. createStore clamps
    % each level's chunk to that level's size.
    chunkAxis = zeros(1, numel(axisOrder));
    yIdx = strfind(axisOrder, 'y');  xIdx = strfind(axisOrder, 'x');  zIdx = strfind(axisOrder, 'z');
    if ~isempty(yIdx); chunkAxis(yIdx) = chunkYXZ(1); end
    if ~isempty(xIdx); chunkAxis(xIdx) = chunkYXZ(2); end
    if ~isempty(zIdx); chunkAxis(zIdx) = chunkYXZ(3); end
    newPyramid.chunkSizes = repmat({chunkAxis}, nLevels, 1);

    newLabels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
    newLabels.createStore([newH0 newW0 depth], modelStorePath, newPyramid);

    % Carry the source material names/colours onto the new store so they persist
    % to disk (mibMaterials attribute, written below) — createStore starts with an
    % empty material list, so without this the aligned model reopens unnamed/greyed.
    newLabels.materialNames  = srcMaterialNames;
    newLabels.materialColors = srcMaterialColors;
    newLabels.materialsCount = srcMaterialsCount;

    labelSizes = newLabels.modelLevelSizes;      % [y x z] per level
    nLabelLev  = size(labelSizes, 1);
    % Z chunk of the label store: createStore uses [256 256 16] by default (no
    % per-level chunkSizes are passed in newPyramid). Batching the Z writes at the
    % chunk depth turns each chunk's compress/decompress from up to 16 partial
    % read-modify-writes into a single write — the labels store previously wrote
    % one slice at a time (setData63) and was ~15x slower than the image stream.
    chunkZ = 16;

    % Progress dialog only when a valid parent figure exists (headless/batch
    % runs pass an empty mibGUI — skip the dialog rather than crash).
    wbL = [];
    if ~isempty(parentFig) && isvalid(parentFig)
        wbL = uiprogressdlg(parentFig, 'Title', 'BigData alignment', ...
            'Message', 'Warping labels / mask / selection...', 'Indeterminate', 'off', 'Cancelable', 'on');
    end

    % --- Pass A: warp each source slice into the finest level (1), written in
    % Z-chunk strips. Memory stays ~one chunk (newH0 x newW0 x chunkZ). ---
    labelsCancelled = false;
    for z0 = 1:chunkZ:depth
        if ~isempty(wbL) && wbL.CancelRequested; labelsCancelled = true; break; end
        z1 = min(depth, z0 + chunkZ - 1);
        strip = zeros(newH0, newW0, z1 - z0 + 1, 'uint8');
        for z = z0:z1
            packed = ds.labels.getData63('everything', 3, [], struct('pyramidLevel', 1, 'z', [z z]));
            packed = reshape(packed, size(packed, 1), size(packed, 2));
            strip(:, :, z - z0 + 1) = imwarp(packed, tforms{z}, 'nearest', ...
                'OutputView', ref0, 'FillValues', 0);
        end
        newLabels.writePackedLevel(1, strip, [1 newH0], [1 newW0], [z0 z1]);
        if ~isempty(wbL); wbL.Value = 0.5 * (z1 / depth); end
    end

    % --- Pass B: build every coarser level from level 1 in one bulk nearest pass.
    % Global index maps (identical to propagateRegion's inline formula) make the
    % downsample strip-independent and an exact packed-byte copy — bits 1-6/7/8
    % transport together with no averaging. This replaces the per-slice EAGER
    % cross-level propagation that setData63('everything') did on every write. ---
    if ~labelsCancelled
        for L = 2:nLabelLev
            ty = labelSizes(L, 1); tx = labelSizes(L, 2); tz = labelSizes(L, 3);
            yMap = min(newH0, max(1, floor((0:ty-1) * newH0 / ty) + 1));
            xMap = min(newW0, max(1, floor((0:tx-1) * newW0 / tx) + 1));
            zMap = min(depth,  max(1, floor((0:tz-1) * depth  / tz) + 1));
            for tz0 = 1:chunkZ:tz
                if ~isempty(wbL) && wbL.CancelRequested; labelsCancelled = true; break; end
                tz1  = min(tz, tz0 + chunkZ - 1);
                zsrc = zMap(tz0:tz1);
                strip = newLabels.readPackedLevel(1, [1 newH0], [1 newW0], [zsrc(1) zsrc(end)]);
                block = strip(yMap, xMap, zsrc - zsrc(1) + 1);
                newLabels.writePackedLevel(L, block, [1 ty], [1 tx], [tz0 tz1]);
                if ~isempty(wbL)
                    wbL.Value = 0.5 + 0.5 * ((L - 2) + tz1 / tz) / max(1, nLabelLev - 1);
                end
            end
            if labelsCancelled; break; end
        end
    end

    if labelsCancelled
        newLabels.closeStore(); delete(wbL);
        if isfolder(outputImagePath); rmdir(outputImagePath, 's'); end
        if isfolder(modelStorePath); rmdir(modelStorePath, 's'); end
        notify(obj.mibModel, 'StopProtocol');
        return;
    end

    % Every level was written explicitly, so mark the whole volume authoritative
    % at the finest level: getData63 then reads any level directly (materializeAll
    % is unnecessary — all coarser levels already hold correct data). closeStore
    % persists the level map.
    newLabels.markTiles([1 newH0], [1 newW0], [1 depth], 1);
    newLabels.writeMaterialMetadata();   % persist names/colours (mibMaterials attr)
    newLabels.closeStore();
    if ~isempty(wbL); delete(wbL); end
end

% =====================================================================
% 5. Patch metadata: bounding box + per-level translation/scale
% =====================================================================
srcBB = ds.image.boundingBox;
if isempty(srcBB) || numel(srcBB) < 6
    srcBB = [0, (W0-1)*pixSize.x, 0, (H0-1)*pixSize.y, 0, (depth-1)*pixSize.z];
end
xOrigin = srcBB(1) + originShiftX * pixSize.x;
yOrigin = srcBB(3) + originShiftY * pixSize.y;
zOrigin = srcBB(5);
newBB = [xOrigin, xOrigin + (newW0-1)*pixSize.x, ...
         yOrigin, yOrigin + (newH0-1)*pixSize.y, ...
         zOrigin, zOrigin + (depth-1)*pixSize.z];
io.savers.Zarr3Saver.patchMetadata(outputImagePath, pixSize, newBB);

% =====================================================================
% 6. Reopen the new store and swap the active buffer in place
% =====================================================================
lo = struct('datasetMode', 'BigData');
zarr3Loader = io.loaders.Zarr3VirtualSetupLoader(lo);
[imgInfo, files] = zarr3Loader.loadMetadata({outputImagePath}, lo);
[img, imgInfo]   = zarr3Loader.loadImages(files, imgInfo, lo);
obj.mibModel.I{id}.initialize(img, imgInfo, 'BigData');
obj.mibModel.I{id}.enableSelection = obj.mibModel.preferences.System.EnableSelection;

% initialize() leaves the viewing slices at [1 1]; reset them to the new full
% extent so the display region is valid (mirrors MibDataset.cropDataset). The
% GUI's listener_newDataset does NOT reset slices — the creating op must.
newDs = obj.mibModel.I{id};
current_layer = newDs.slices{newDs.orientation}(1);
newDs.dim_yxzct = newDs.image.dim_yxzct;
newDs.slices{1} = [1, newDs.image.height];
newDs.slices{2} = [1, newDs.image.width];
newDs.slices{3} = [1, newDs.image.depth];
newDs.slices{5} = repmat(min([newDs.slices{5}(1), newDs.image.time]), 1, 2);
newDs.slices{newDs.orientation} = repmat( ...
    min(newDs.dim_yxzct(newDs.orientation), current_layer), 1, 2);

% Defensive: if the pan window is uninitialised (NaN) — e.g. a programmatic
% swap into a never-displayed buffer — seed it to the full extent so the
% block-mode display read has a valid region. In the GUI the active buffer
% already has a valid window (listener_newDataset zoom-to-fits), so this is
% a no-op there.
if isempty(newDs.axesX) || any(isnan(newDs.axesX))
    newDs.axesX = [1, newDs.image.width];
end
if isempty(newDs.axesY) || any(isnan(newDs.axesY))
    newDs.axesY = [1, newDs.image.height];
end

if hasModel && isfolder(modelStorePath)
    reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
    reopened.openStore(modelStorePath);
    reopened.filename       = modelStorePath;
    reopened.materialNames  = srcMaterialNames;
    reopened.materialColors = srcMaterialColors;
    reopened.materialsCount = srcMaterialsCount;
    obj.mibModel.I{id}.labels     = reopened;
    obj.mibModel.I{id}.modelExist = true;
    obj.mibModel.I{id}.enableSelection = true;
end

% Sync Sets.datasetTypes for the swapped buffer
targetSet     = floor((id - 1) / obj.mibModel.Sets.datasetsInSet) + 1;
targetLocalId = mod(id - 1, obj.mibModel.Sets.datasetsInSet) + 1;
obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = obj.mibModel.I{id}.datasetType;

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'BigData alignment (%s); new store: %s', tformInfo.mode, outputImagePath));

% Re-add annotations warped into the new canvas frame (the swap re-initialises
% the dataset, so any source annotations were captured + warped by the caller
% and passed in tformInfo.annotations). Positions are already in new-canvas
% level-0 coordinates.
if isfield(tformInfo, 'annotations') && ~isempty(tformInfo.annotations) ...
        && ~isempty(tformInfo.annotations.labelText)
    an = tformInfo.annotations;
    obj.mibModel.I{id}.annotations.replaceLabels( ...
        an.labelText, an.labelPositions, an.labelValues);
    notify(obj.mibModel, 'UpdateAnnotations');
end

result = 1;

notify(obj.mibModel, 'NewDataset');
notify(obj.mibModel, 'ShowImage');
notify(obj.mibModel, 'UpdateFileList');
end

% =============================================================================
function outYXZ = mapAxisVec(vec, axisOrder, defaultYXZ)
% Map a per-axis vector (in axisOrder, e.g. 'yxz' or 'tczyx') to [y x z],
% falling back to defaultYXZ for any axis not present in the vector.
outYXZ = defaultYXZ;
yIdx = strfind(axisOrder, 'y');
xIdx = strfind(axisOrder, 'x');
zIdx = strfind(axisOrder, 'z');
if ~isempty(yIdx) && yIdx <= numel(vec); outYXZ(1) = vec(yIdx); end
if ~isempty(xIdx) && xIdx <= numel(vec); outYXZ(2) = vec(xIdx); end
if ~isempty(zIdx) && zIdx <= numel(vec); outYXZ(3) = vec(zIdx); end
end
