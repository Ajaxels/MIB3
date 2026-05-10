function LandmarkMultiPoint_Alignment(obj, parameters)
% LANDMARKMULTIPOINT_ALIGNMENT - Align a stack using 3+ corresponding landmarks per slice pair.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.LandmarkMultiPoint_Alignment(parameters)
%
% Fits a per-slice geometric transform (``parameters.TransformationType``) to
% the landmarks placed on consecutive slices and warps every slice in the
% stack with the cumulative transform. The number of required landmarks per
% slice pair is set by the transformation type:
%
% =========================  ============
% TransformationType          minLandmarks
% =========================  ============
% nonreflectivesimilarity     2
% similarity / affine         3
% projective / pwl            4
% polynomial / lwm            6
% =========================  ============
%
% Cancellation: a :class:`core.PoolWaitbar` is constructed with
% ``Cancelable = true`` whenever ``BatchOpt.showWaitbar`` is set; the cancel
% state is polled at each phase boundary (landmark search, image warp,
% canvas assembly, service-layer warp) and immediately before each write.
%
% Modes:
%   - ``parameters.TransformationMode = 'cropped'`` keeps the original
%     canvas — each slice is warped with ``imwarp(..., 'OutputView',
%     imref2d([H, W]))`` and written back to its slot via :meth:`setData2D`.
%   - ``parameters.TransformationMode = 'extended'`` grows the canvas to fit
%     the union of all warped slices; service layers are pre-resized to the
%     new canvas before :meth:`setData4D`.
%
% Input Arguments:
%   - **parameters** — struct produced by :meth:`continueBtn_Callback`. Reads
%     ``TransformationType``, ``TransformationMode``, ``transformationDegree``,
%     ``colorCh``, ``backgroundColor``, ``useBatchMode``.

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
        'Multi-point landmark alignment requires at least 2 slices.', 'Alignment');
    return;
end

% --- Determine source of landmarks (Annotations vs Selection)
shiftsLoaded   = ~isempty(obj.shiftsX) && iscell(obj.shiftsX);
useAnnotations = false;
if ~shiftsLoaded
    nAnnots = obj.mibModel.I{id}.annotations.getLabelsNumber();
    if ~parameters.useBatchMode && nAnnots > 5
        questOpt.Icon = 'puffin_question';
        questOpt.WindowStyle = 'modal';
        answer = utils.dlgs.inputQuestDlg(parentFig, ...
            'Were the corresponding landmarks placed with the Annotation tool, or with the Brush + Selection layer?', ...
            'Annotations or Selection?', ...
            'Annotations', 'Selection', 'Cancel', 'Annotations', questOpt);
        if isempty(answer) || strcmp(answer, 'Cancel'); return; end
        useAnnotations = strcmp(answer, 'Annotations');
    elseif parameters.useBatchMode
        % Batch mode defaults to annotations (matches MIB2)
        useAnnotations = nAnnots > 0;
    end
end
if ~useAnnotations && ~shiftsLoaded
    if obj.mibModel.I{id}.enableSelection == 0
        utils.dlgs.showErrorDialog(parentFig, ...
            ['Selection-based multi-point alignment requires the Selection layer ' ...
             'to be enabled (Preferences → User Interface).'], 'Alignment');
        return;
    end
end

% --- Backup the full MibDataset before any modification
backupOpt.id = id;
obj.mibModel.backup('mibDataset', 1, backupOpt);

% --- Required landmark count per slice pair
switch parameters.TransformationType
    case 'nonreflectivesimilarity';            minLandmarks = 2;
    case {'similarity', 'affine'};             minLandmarks = 3;
    case {'projective', 'pwl'};                minLandmarks = 4;
    case {'polynomial', 'lwm'};                minLandmarks = 6;
    otherwise;                                 minLandmarks = 3;
end

% --- Background fill for the image warp
img5D = obj.mibModel.I{id}.image;
optionsGetData = struct('blockModeSwitch', 0);
if isnumeric(parameters.backgroundColor)
    bgImage = double(parameters.backgroundColor);
elseif strcmp(parameters.backgroundColor, 'black')
    bgImage = 0;
elseif strcmp(parameters.backgroundColor, 'white')
    bgImage = double(img5D.maxInt);
else    % 'mean'
    firstSlice = cell2mat(obj.mibModel.getData2D('image', 1, [], parameters.colorCh, optionsGetData));
    bgImage = mean(firstSlice(:));
end

% --- Set up cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(depth * 2, 'Multi-point landmark alignment...', ...
        parentFig, 'Alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Allocate transform / spatial-reference arrays
if shiftsLoaded
    tformMatrix = obj.shiftsX;
    rbMatrix    = obj.shiftsY;
else
    tformMatrix = cell(depth, 1);
    rbMatrix    = cell(depth, 1);
end

% --- Fit per-slice transforms (skipped when loaded from file)
if ~shiftsLoaded
    if ~isempty(pwb); pwb.updateText('Step 1/2: extracting landmarks...'); end
    [tformMatrix, ok] = fitPerSliceTransforms(obj, id, depth, useAnnotations, ...
        minLandmarks, parameters.TransformationType, parameters.transformationDegree, ...
        tformMatrix, optionsGetData, pwb, parentFig);
    if ~ok; return; end
end

% Verify we have at least one usable transform
anyTform = any(~cellfun(@isempty, tformMatrix));
if ~anyTform
    utils.dlgs.showErrorDialog(parentFig, ...
        ['No slice pair provided enough corresponding landmarks (need at least ' ...
        num2str(minLandmarks) ').'], 'Alignment');
    return;
end

% --- Apply the transforms
refImgSize = imref2d([height, width]);
if strcmp(parameters.TransformationMode, 'cropped')
    % --- Cropped: original canvas preserved
    if ~isempty(pwb); pwb.updateText('Step 2/2: warping (cropped)...'); end
    applyCroppedMode(obj, id, depth, tformMatrix, refImgSize, bgImage, pwb);
    rbMatrix(:) = {refImgSize};      % spatial reference is the original frame
    dxCanvas = 0;
    dyCanvas = 0;
else
    % --- Extended: canvas grows to fit the union of warped slices
    if ~isempty(pwb); pwb.updateText('Step 2/2: warping (extended)...'); end
    [dxCanvas, dyCanvas, rbMatrix] = applyExtendedMode(obj, id, depth, ...
        tformMatrix, rbMatrix, bgImage, pwb);
    if isempty(dxCanvas); return; end
end

% --- Transform annotations in place
if obj.mibModel.I{id}.annotations.getLabelsNumber() > 0
    relocateAnnotations(obj, id, depth, tformMatrix, rbMatrix, ...
        strcmp(parameters.TransformationMode, 'cropped'), dxCanvas, dyCanvas);
end

% --- Bounding box shift (extended mode only; cropped keeps the original canvas)
if strcmp(parameters.TransformationMode, 'extended')
    maxXshift = dxCanvas;
    maxYshift = dyCanvas;
    maxZshift = 0;
    ds = obj.mibModel.I{id};
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
end

% --- Persist transforms back to obj.shiftsX / obj.shiftsY (the cell-array form
%     used by loadShiftsCheck) so subsequent runs / save-shifts pick them up.
obj.shiftsX = tformMatrix;
obj.shiftsY = rbMatrix;

% --- Save tforms / rbMatrix to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveTformsToFile(obj, id, parameters.useBatchMode, parentFig);
end

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'Aligned using %s; type=%s, mode=%s', ...
    obj.BatchOpt.Algorithm{1}, parameters.TransformationType, parameters.TransformationMode));

% keepBackup=true so the 'mibDataset' snapshot stored by backup() above is
% not wiped by listener_newDataset.
notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
notify(obj.mibModel, 'ShowImage');
end

% =============================================================================
function [tformMatrix, ok] = fitPerSliceTransforms(obj, id, depth, useAnnotations, ...
    minLandmarks, transformType, transformDegree, tformMatrix, optionsGetData, pwb, parentFig)
% Walk slices 2..Depth, fit a transform on each slice pair and broadcast it
% forward in ``tformMatrix``. Returns ``ok = false`` (with an error dialog
% already shown) when no slice pair produced enough landmarks.

ok = false;
hasInputPnts = false;
for layer = 2:depth
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.increment();
    end

    if useAnnotations
        [labelsList1, ~, X1] = obj.mibModel.I{id}.getSliceLabels(layer - 1);
        if isempty(labelsList1) || numel(labelsList1) < minLandmarks; continue; end
        [labelsList2, ~, X2] = obj.mibModel.I{id}.getSliceLabels(layer);
        if isempty(labelsList2) || numel(labelsList2) < minLandmarks; continue; end

        % Annotation positions: columns [z, x, y]
        outputPnts = X1(:, 2:3);            % reference [x, y] on slice ``layer-1``
        X2xy       = X2(:, 2:3);
        inputPnts  = zeros(size(outputPnts));
        missingPair = false;
        for labelIdx = 1:numel(labelsList1)
            j = find(ismember(labelsList2, labelsList1{labelIdx}), 1);
            if isempty(j); missingPair = true; break; end
            inputPnts(labelIdx, :) = X2xy(j, :);
        end
        if missingPair || size(inputPnts, 1) < minLandmarks; continue; end
    else
        prevSel = cell2mat(obj.mibModel.getData2D('selection', layer - 1, [], NaN, optionsGetData));
        if sum(prevSel(:)) == 0; continue; end
        CC1 = bwconncomp(prevSel);
        if CC1.NumObjects < minLandmarks; continue; end

        CC2 = bwconncomp(cell2mat(obj.mibModel.getData2D('selection', layer, [], NaN, optionsGetData)));
        if CC2.NumObjects < minLandmarks; continue; end

        STATS1 = regionprops(CC1, 'Centroid');
        STATS2 = regionprops(CC2, 'Centroid');
        X1 = reshape([STATS1.Centroid], [2, numel(STATS1)])';
        X2 = reshape([STATS2.Centroid], [2, numel(STATS2)])';

        % Lift the centroids through the cumulative tform of the previous
        % slice so the matching is done in the *already-aligned* frame.
        if ~isempty(tformMatrix{layer - 1})
            [X1(:,1), X1(:,2)] = transformPointsForward(tformMatrix{layer - 1}, X1(:,1), X1(:,2));
            [X2(:,1), X2(:,2)] = transformPointsForward(tformMatrix{layer - 1}, X2(:,1), X2(:,2));
        end

        idxMatch = controllers.Alignment.findMatchingPairs(X2, X1);
        outputPnts = reshape([STATS1.Centroid], [2, numel(STATS1)])';
        inputPnts  = zeros(size(outputPnts));
        for objId = 1:numel(STATS1)
            inputPnts(objId, :) = STATS2(idxMatch(objId)).Centroid;
        end
    end

    if isempty(outputPnts); continue; end

    % --- Fit the transform and broadcast it forward
    try
        if strcmp(transformType, 'polynomial')
            tform2 = fitgeotrans(inputPnts, outputPnts, transformType, transformDegree);
        else
            tform2 = fitgeotrans(inputPnts, outputPnts, transformType);
        end
    catch ME
        utils.dlgs.showErrorDialog(parentFig, ME, 'fitgeotrans');
        return;
    end

    if isempty(tformMatrix{layer})
        tformMatrix(layer:end) = {tform2};
    else
        % Compose with the previously broadcast transform — only meaningful
        % when both carry a ``.T`` matrix (affine / similarity / projective).
        if isprop(tform2, 'T') && isprop(tformMatrix{layer}, 'T')
            tform2.T = tform2.T * tformMatrix{layer}.T;
        end
        tformMatrix(layer:end) = {tform2};
    end
    hasInputPnts = true;
end

if ~hasInputPnts
    utils.dlgs.showErrorDialog(parentFig, ...
        ['Landmark points are missing. Place at least ' num2str(minLandmarks) ...
         ' corresponding landmarks on each of two consecutive slices.'], ...
        'Multi-point landmark alignment');
    return;
end

ok = true;
end

% =============================================================================
function applyCroppedMode(obj, id, depth, tformMatrix, refImgSize, bgImage, pwb)
% Warp the image + service layers in place, keeping the original canvas size.

optionsGetData = struct('blockModeSwitch', 0);
isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

for layer = 2:depth
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.increment();
    end
    if isempty(tformMatrix{layer}); continue; end

    % image — all channels, same tform applied per slice
    slice2D = cell2mat(obj.mibModel.getData2D('image', layer, [], NaN, optionsGetData));
    warped  = imwarp(slice2D, tformMatrix{layer}, 'cubic', ...
        'OutputView', refImgSize, 'FillValues', double(bgImage));
    obj.mibModel.setData2D(warped, 'image', layer, [], NaN, optionsGetData);

    if isLabels63
        layerData = cell2mat(obj.mibModel.getData2D('everything', layer, [], 0, optionsGetData));
        layerData = imwarp(layerData, tformMatrix{layer}, 'nearest', ...
            'OutputView', refImgSize, 'FillValues', 0);
        obj.mibModel.setData2D(layerData, 'everything', layer, [], 0, optionsGetData);
    else
        if obj.mibModel.I{id}.modelExist
            lab = cell2mat(obj.mibModel.getData2D('labels', layer, [], NaN, optionsGetData));
            lab = imwarp(lab, tformMatrix{layer}, 'nearest', ...
                'OutputView', refImgSize, 'FillValues', 0);
            obj.mibModel.setData2D(lab, 'labels', layer, [], NaN, optionsGetData);
        end
        if obj.mibModel.I{id}.maskExist
            mk = cell2mat(obj.mibModel.getData2D('mask', layer, [], 0, optionsGetData));
            mk = imwarp(mk, tformMatrix{layer}, 'nearest', ...
                'OutputView', refImgSize, 'FillValues', 0);
            obj.mibModel.setData2D(mk, 'mask', layer, [], 0, optionsGetData);
        end
        if obj.mibModel.I{id}.enableSelection
            sel = cell2mat(obj.mibModel.getData2D('selection', layer, [], NaN, optionsGetData));
            sel = imwarp(sel, tformMatrix{layer}, 'nearest', ...
                'OutputView', refImgSize, 'FillValues', 0);
            obj.mibModel.setData2D(sel, 'selection', layer, [], NaN, optionsGetData);
        end
    end
end
end

% =============================================================================
function [dx, dy, rbMatrix] = applyExtendedMode(obj, id, depth, tformMatrix, ...
    rbMatrix, bgImage, pwb)
% Warp image slices without OutputView so the canvas grows, then assemble a
% new image stack and pre-resize / write the service layers. Returns the
% canvas offsets (``dx``, ``dy``) used to update the bounding box.

dx = []; dy = [];
optionsGetData = struct('blockModeSwitch', 0);
ds       = obj.mibModel.I{id};
img5D    = ds.image;
nColors  = img5D.colors;
nTime    = img5D.time;
imgClass = class(img5D.data{1});
isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

% Step A: warp every slice's image. Slices without a tform use the original
% size and an identity-like rbMatrix anchored at [1, W; 1, H].
iMatrix    = cell(depth, 1);
identityRb = imref2d([img5D.height, img5D.width]);
for layer = 1:depth
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.increment();
    end
    if ~isempty(tformMatrix{layer})
        slice2D = cell2mat(obj.mibModel.getData2D('image', layer, [], NaN, optionsGetData));
        [iMatrix{layer}, rbMatrix{layer}] = imwarp(slice2D, tformMatrix{layer}, 'cubic', ...
            'FillValues', double(bgImage));
    else
        iMatrix{layer}  = cell2mat(obj.mibModel.getData2D('image', layer, [], NaN, optionsGetData));
        rbMatrix{layer} = identityRb;
    end
end

% Step B: compute the union canvas
xmin = zeros(depth, 1);
xmax = zeros(depth, 1);
ymin = zeros(depth, 1);
ymax = zeros(depth, 1);
for layer = 1:depth
    xmin(layer) = floor(rbMatrix{layer}.XWorldLimits(1));
    xmax(layer) = floor(rbMatrix{layer}.XWorldLimits(2));
    ymin(layer) = floor(rbMatrix{layer}.YWorldLimits(1));
    ymax(layer) = floor(rbMatrix{layer}.YWorldLimits(2));
end
dx      = min(xmin);
dy      = min(ymin);
newW    = max(xmax) - dx;
newH    = max(ymax) - dy;

% Step C: assemble the new image canvas in MIB3 layout [h, w, d, c]
Iout = zeros(newH, newW, depth, nColors, imgClass) + cast(bgImage, imgClass);
for layer = 1:depth
    rbL = rbMatrix{layer};
    x1  = xmin(layer) - dx + 1;
    y1  = ymin(layer) - dy + 1;
    x2  = x1 + rbL.ImageSize(2) - 1;
    y2  = y1 + rbL.ImageSize(1) - 1;
    % iMatrix{layer} is [h', w'] (grayscale) or [h', w', c]; reshape into
    % the [h', w', 1, c] slab that fits the MIB3 [h, w, d, c] canvas.
    Iout(y1:y2, x1:x2, layer, :) = reshape(iMatrix{layer}, ...
        rbL.ImageSize(1), rbL.ImageSize(2), 1, nColors);
end
clear iMatrix;

% Step D: replace the image canvas directly (setData4D cannot grow data{1})
img5D.data{1}   = reshape(Iout, [newH, newW, depth, nColors, nTime]);
img5D.height    = newH;
img5D.width     = newW;
img5D.dim_yxzct = [newH, newW, depth, nColors, nTime];
clear Iout;

% Sync MibDataset metadata BEFORE any service-layer setData4D
ds.dim_yxzct = img5D.dim_yxzct;
oldSlices = ds.slices;
ds.slices{1} = [1, newH];
ds.slices{2} = [1, newW];
ds.slices{3} = 1:depth;
ds.slices{4} = [1, 1];
ds.slices{5} = [1, 1];
ds.slices{ds.orientation} = repmat(oldSlices{ds.orientation}(1), 1, 2);

% Step E: warp + assemble service layers
if isLabels63
    if ~isempty(pwb); pwb.updateText('Warping selection / mask / labels...'); end
    everythingOut = assembleServiceCanvas(obj, 'everything', tformMatrix, ...
        rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, 0);
    if isempty(everythingOut); return; end
    obj.mibModel.I{id}.labels.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
    obj.mibModel.I{id}.labels.height    = newH;
    obj.mibModel.I{id}.labels.width     = newW;
    obj.mibModel.I{id}.labels.depth     = depth;
    obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, depth, 1, nTime];
    obj.mibModel.setData4D(everythingOut, 'everything', [], 0);
else
    if obj.mibModel.I{id}.modelExist
        if ~isempty(pwb); pwb.updateText('Warping labels...'); end
        labelsOut = assembleServiceCanvas(obj, 'labels', tformMatrix, ...
            rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, NaN);
        if isempty(labelsOut); return; end
        obj.mibModel.I{id}.labels.data{1}  = zeros([newH, newW, depth, nTime], class(obj.mibModel.I{id}.labels.data{1}));
        obj.mibModel.I{id}.labels.height    = newH;
        obj.mibModel.I{id}.labels.width     = newW;
        obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(labelsOut, 'labels', [], NaN);
    end
    if obj.mibModel.I{id}.maskExist
        if ~isempty(pwb); pwb.updateText('Warping mask...'); end
        maskOut = assembleServiceCanvas(obj, 'mask', tformMatrix, ...
            rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, 0);
        if isempty(maskOut); return; end
        obj.mibModel.I{id}.mask.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
        obj.mibModel.I{id}.mask.height    = newH;
        obj.mibModel.I{id}.mask.width     = newW;
        obj.mibModel.I{id}.mask.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(maskOut, 'mask', [], 0);
    end
    if obj.mibModel.I{id}.enableSelection
        if ~isempty(pwb); pwb.updateText('Warping selection...'); end
        selOut = assembleServiceCanvas(obj, 'selection', tformMatrix, ...
            rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, NaN);
        if isempty(selOut); return; end
        obj.mibModel.I{id}.selection.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
        obj.mibModel.I{id}.selection.height    = newH;
        obj.mibModel.I{id}.selection.width     = newW;
        obj.mibModel.I{id}.selection.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(selOut, 'selection', [], NaN);
    end
end
end

% =============================================================================
function out3D = assembleServiceCanvas(obj, layerType, tformMatrix, ...
    rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, colArg)
% Build the new ``[H, W, Z]`` service-layer canvas by warping each slice
% (nearest neighbour) and placing it at the right offset. Returns the 3-D
% array — caller handles setData4D and the container pre-resize.

% Pull all slices in one shot, then warp slice by slice.
src = obj.mibModel.getData4D(layerType, [], colArg);
src = squeeze(cell2mat(src));            % [H, W, Z] (single time-point)
out3D = zeros(newH, newW, depth, class(src));
for layer = 1:depth
    if ~isempty(tformMatrix{layer})
        warped = imwarp(src(:,:,layer), tformMatrix{layer}, 'nearest', 'FillValues', 0);
    else
        warped = src(:,:,layer);
    end
    rbL = rbMatrix{layer};
    x1  = xmin(layer) - dx + 1;
    y1  = ymin(layer) - dy + 1;
    x2  = x1 + rbL.ImageSize(2) - 1;
    y2  = y1 + rbL.ImageSize(1) - 1;
    out3D(y1:y2, x1:x2, layer) = warped;
end
end

% =============================================================================
function relocateAnnotations(obj, id, depth, tformMatrix, rbMatrix, ...
    isCropped, dxCanvas, dyCanvas)
% Apply ``transformPointsForward`` to every annotation on the slices that
% had a tform; in extended mode also shift positions by the canvas offset
% so the annotations follow the assembled image.

for layer = 1:depth
    [labelsList, labelValues, labelPositions, indices] = obj.mibModel.I{id}.getSliceLabels(layer);
    if isempty(labelsList); continue; end
    if isempty(tformMatrix{layer})
        if isCropped
            continue;                    % cropped + no tform = identity
        end
        % Extended + no tform: shift original positions by the canvas offset
        rbL = rbMatrix{layer};
        x1  = floor(rbL.XWorldLimits(1)) - dxCanvas + 1;
        y1  = floor(rbL.YWorldLimits(1)) - dyCanvas + 1;
        labelPositions(:,2) = labelPositions(:,2) + x1 - 1;
        labelPositions(:,3) = labelPositions(:,3) + y1 - 1;
    else
        [labelPositions(:,2), labelPositions(:,3)] = transformPointsForward( ...
            tformMatrix{layer}, labelPositions(:,2), labelPositions(:,3));
        if ~isCropped
            labelPositions(:,2) = labelPositions(:,2) - dxCanvas - 1;
            labelPositions(:,3) = labelPositions(:,3) - dyCanvas - 1;
        end
    end
    obj.mibModel.I{id}.annotations.updateLabels(indices, labelsList, labelPositions, labelValues);
end
end

% =============================================================================
function saveTformsToFile(obj, id, useBatchMode, parentFig)
% Persist (tformMatrix, rbMatrix) to a ``.coefXY`` file so the user can
% replay the alignment via loadShiftsCheck.

if useBatchMode
    fn = obj.mibModel.I{id}.image.sliceName('Filename');
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
elseif ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'saveShiftsXYpath')
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
else
    return;
end
tformMatrix = obj.shiftsX;
rbMatrix    = obj.shiftsY;
fprintf('Saving landmark alignment transforms to file: %s ... ', fullPath);
try
    save(fullPath, 'tformMatrix', 'rbMatrix');
    fprintf('done!\n');
catch ME
    fprintf('failed.\n');
    utils.dlgs.showErrorDialog(parentFig, ME, 'Save shifts');
end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
