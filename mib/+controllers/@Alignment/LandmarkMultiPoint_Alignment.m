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
%     canvas - each slice is warped with ``imwarp(..., 'OutputView',
%     imref2d([H, W]))`` and written back to its slot via :meth:`setData2D`.
%   - ``parameters.TransformationMode = 'extended'`` grows the canvas to fit
%     the union of all warped slices; service layers are pre-resized to the
%     new canvas before :meth:`setData4D`.
%
% Input Arguments:
%   - **parameters** - struct produced by :meth:`continueBtn_Callback`. Reads
%     ``TransformationType``, ``TransformationMode``, ``transformationDegree``,
%     ``colorCh``, ``backgroundColor``, ``useBatchMode``.

% Updates
%

id = obj.mibModel.getActiveId();

% Parent figure for any dialogs - ``obj.view`` is empty in batch mode
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

% --- Preview the detected transforms and confirm (freshly computed, interactive;
% loaded coefficients were already previewed at Apply by previewConfirmLoadedShifts)
if ~shiftsLoaded && ~parameters.useBatchMode
    if ~confirmDetectedTransforms(parentFig, 'tforms', ...
            struct('tforms', {tformMatrix}), 'Detected multi-point landmark transforms')
        return;
    end
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
        case 1   % ZX: horizontal X, vertical Z
            maxZshift = maxYshift * ds.image.pixSize.z;
            maxXshift = maxXshift * ds.image.pixSize.x;
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
    saveTformsToFile(obj, id, parameters.useBatchMode, parentFig, 'landmark alignment');
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
        % Compose with the previously broadcast transform - only meaningful
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
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
