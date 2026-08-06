function LandmarkMultiPointColor_Alignment(obj, parameters)
% LANDMARKMULTIPOINTCOLOR_ALIGNMENT - Align one colour channel to another using per-slice landmarks.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.LandmarkMultiPointColor_Alignment(parameters)
%
% Performs a within-slice 2D alignment of a single colour channel
% (``parameters.colorCh``) onto a reference channel using corresponding
% annotation pairs placed on the same slice. Annotation values mark the
% role of each point:
%
% - ``value == 1`` - landmarks on the **reference (fixed) channel**.
% - ``value == 2`` - landmarks on the **channel to be transformed**.
%
% Corresponding landmarks must share the same annotation text label.
% Each slice is processed independently - no cumulative transform is
% propagated forward - and the warped channel is written back into its
% original slot.
%
% The minimum number of landmark pairs per slice depends on the
% transformation type:
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
% Only ``parameters.TransformationMode = 'cropped'`` is supported (matches
% MIB2 behaviour). Extended-canvas mode is rejected with an error dialog.
%
% Input Arguments:
%   - **parameters** - struct produced by :meth:`continueBtn_Callback`.
%     Reads ``TransformationType``, ``TransformationMode``, ``colorCh``,
%     ``backgroundColor``, ``transformationDegree``, ``useBatchMode``.

% Updates
%

id = obj.mibModel.getActiveId();

% Parent figure for any dialogs - ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% --- Reject extended mode up front (matches MIB2)
if ~strcmp(parameters.TransformationMode, 'cropped')
    utils.dlgs.showErrorDialog(parentFig, ...
        ['Colour-channel multi-point alignment supports only the "cropped" ' ...
         'transformation mode. Please switch TransformationMode and retry.'], ...
        'Alignment');
    return;
end

[height, width, depth, ~] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if obj.mibModel.I{id}.image.colors < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Colour-channel alignment requires a multi-channel image.', 'Alignment');
    return;
end

% --- Required landmark count per slice
switch parameters.TransformationType
    case 'nonreflectivesimilarity';            minLandmarks = 2;
    case {'similarity', 'affine'};             minLandmarks = 3;
    case {'projective', 'pwl'};                minLandmarks = 4;
    case {'polynomial', 'lwm'};                minLandmarks = 6;
    otherwise;                                 minLandmarks = 3;
end

% --- Check we have enough annotations overall (unless replaying shifts)
shiftsLoaded = ~isempty(obj.shiftsX) && iscell(obj.shiftsX);
if ~shiftsLoaded
    if obj.mibModel.I{id}.annotations.getLabelsNumber() < 2 * minLandmarks
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf(['Not enough landmark annotations.\n\n' ...
                    'Place at least %d corresponding pairs on each slice using the ' ...
                    'Annotation tool. Use the annotation text to identify ' ...
                    'corresponding points and the annotation value (1 or 2) to ' ...
                    'mark which colour channel they belong to ' ...
                    '(1 = reference, 2 = channel to transform).'], minLandmarks), ...
            'Alignment');
        return;
    end
end

% --- Backup the full MibDataset before any modification
backupOpt.id = id;
obj.mibModel.backup('mibDataset', 1, backupOpt);

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
    pwb = core.PoolWaitbar(depth * 2, 'Colour-channel landmark alignment...', ...
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
    [tformMatrix, ok] = fitPerSliceColorTransforms(obj, id, depth, minLandmarks, ...
        parameters.TransformationType, parameters.transformationDegree, ...
        tformMatrix, pwb, parentFig);
    if ~ok; return; end
end

% Verify we have at least one usable transform
anyTform = any(~cellfun(@isempty, tformMatrix));
if ~anyTform
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['No slice provided enough corresponding landmark pairs ' ...
                '(need at least %d pairs per slice, with annotation values ' ...
                '1 and 2 marking the two channels).'], minLandmarks), ...
        'Alignment');
    return;
end

% --- Preview the detected transforms and confirm (freshly computed, interactive;
% loaded coefficients were already previewed at Apply by previewConfirmLoadedShifts)
if ~shiftsLoaded && ~parameters.useBatchMode
    if ~confirmDetectedTransforms(parentFig, 'tforms', ...
            struct('tforms', {tformMatrix}), 'Detected colour-channel landmark transforms')
        return;
    end
end

% --- Apply each slice transform to the selected colour channel (cropped only)
if ~isempty(pwb); pwb.updateText('Step 2/2: warping colour channel...'); end
refImgSize = imref2d([height, width]);
for layer = 1:depth
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.increment();
    end
    if isempty(tformMatrix{layer}); continue; end

    slice2D = cell2mat(obj.mibModel.getData2D('image', layer, [], parameters.colorCh, optionsGetData));
    [warped, rb] = imwarp(slice2D, tformMatrix{layer}, 'cubic', ...
        'OutputView', refImgSize, 'FillValues', double(bgImage));
    obj.mibModel.setData2D(warped, 'image', layer, [], parameters.colorCh, optionsGetData);
    rbMatrix{layer} = rb;
end

% --- Persist transforms so subsequent runs / save-shifts pick them up
obj.shiftsX = tformMatrix;
obj.shiftsY = rbMatrix;

% --- Save tforms / rbMatrix to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveTformsToFile(obj, id, parameters.useBatchMode, parentFig);
end

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'Aligned colour channel %d using %s; type=%s, mode=%s', ...
    parameters.colorCh, obj.BatchOpt.Algorithm{1}, ...
    parameters.TransformationType, parameters.TransformationMode));

% keepBackup=true so the 'mibDataset' snapshot stored by backup() above is
% not wiped by listener_newDataset.
notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
notify(obj.mibModel, 'ShowImage');
end

% =============================================================================
function [tformMatrix, ok] = fitPerSliceColorTransforms(obj, id, depth, ...
    minLandmarks, transformType, transformDegree, tformMatrix, pwb, parentFig)
% Walk every slice, split its annotations by value (1 = fixed channel,
% 2 = channel to transform), pair them by annotation text and fit a single
% within-slice transform. Returns ``ok = false`` (with an error dialog
% already shown) when no slice produced enough landmark pairs.

ok = false;
hasInputPnts = false;
for layer = 1:depth
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.increment();
    end

    [labelsList, labelValues, labelPositions] = obj.mibModel.I{id}.getSliceLabels(layer);
    if isempty(labelsList); continue; end

    isFixed   = labelValues == 1;
    isMoving  = labelValues == 2;
    labelsFixed   = labelsList(isFixed);
    labelsMoving  = labelsList(isMoving);
    posFixed      = labelPositions(isFixed,  :);   % columns [z x y]
    posMoving     = labelPositions(isMoving, :);
    if numel(labelsFixed)  < minLandmarks; continue; end
    if numel(labelsMoving) < minLandmarks; continue; end

    % Pair landmarks by their text label
    outputPnts = posFixed(:, 2:3);              % reference (channel 1) [x y]
    inputPnts  = zeros(size(outputPnts));
    movingXY   = posMoving(:, 2:3);
    missingPair = false;
    for labelIdx = 1:numel(labelsFixed)
        j = find(ismember(labelsMoving, labelsFixed{labelIdx}), 1);
        if isempty(j); missingPair = true; break; end
        inputPnts(labelIdx, :) = movingXY(j, :);
    end
    if missingPair || size(inputPnts, 1) < minLandmarks; continue; end

    % --- Fit the within-slice transform
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

    tformMatrix{layer} = tform2;
    hasInputPnts = true;
end

if ~hasInputPnts
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['Landmark points are missing or unpaired.\n\nPlace at least ' ...
                '%d corresponding annotation pairs on a slice with values ' ...
                '1 (reference channel) and 2 (channel to transform), using ' ...
                'matching annotation text to identify each pair.'], minLandmarks), ...
        'Colour-channel landmark alignment');
    return;
end

ok = true;
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
fprintf('Saving colour-channel alignment transforms to file: %s ... ', fullPath);
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
