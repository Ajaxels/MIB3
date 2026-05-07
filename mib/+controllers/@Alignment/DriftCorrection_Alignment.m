function DriftCorrection_Alignment(obj, parameters)
% DRIFTCORRECTION_ALIGNMENT - In-memory drift correction / template matching.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.DriftCorrection_Alignment(parameters)
%
% Computes per-slice X/Y shifts via :func:`utils.align.calcShifts` and applies
% them to the image stack with :func:`utils.align.crossShiftStack`. Mask,
% selection, and labels layers are realigned with the same shifts so the
% whole dataset stays consistent.
%
% Cancellation: a :class:`core.PoolWaitbar` is constructed with
% ``Cancelable = true`` whenever ``BatchOpt.showWaitbar`` is set; the cancel
% state is polled at the top of every loop and immediately before any
% irreversible write back to the model.
%
% Input Arguments:
%   - **parameters** — struct produced by :meth:`continueBtn_Callback` with the
%     fields ``method``, ``colorCh``, ``backgroundColor``, ``refFrame``,
%     ``IntensityGradient``, ``Subarea``, ``minX/maxX/minY/maxY``,
%     ``UseParallelComputing``, ``useBatchMode``.

id = obj.mibModel.getActiveId();
if obj.mibModel.I{id}.image.depth < 2
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'Drift correction requires at least 2 slices in Z.', 'Alignment');
    return;
end

% Backup the entire image + service layers before any write
backupOpt.id = id;
obj.mibModel.backup('mibDataset', 1, backupOpt);

[~, ~, depth, ~] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));

% --- Set up cancelable progress
pwb = [];
useWaitbar = obj.BatchOpt.showWaitbar;
if useWaitbar
    pwb = core.PoolWaitbar(depth, 'Calculating drifts...', obj.view.gui, ...
        'Alignment and drift correction', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Calculate shifts (skip when pre-loaded via loadShiftsCheck)
if isempty(obj.shiftsX)
    [shiftX, shiftY] = computeShifts(obj, parameters, pwb);
    if isempty(shiftX); return; end

    % Optional preview / running-average dialog
    if ~parameters.useBatchMode
        previewShifts(shiftX, shiftY);
        questOpt.Icon = 'puffin_question';
        questOpt.WindowStyle = 'modal';
        choice = utils.dlgs.inputQuestDlg(obj.view.gui, ...
            'Align the stack using the detected displacements?', 'Align dataset', ...
            'Apply current values', 'Fix drifts', 'Quit alignment', ...
            'Apply current values', questOpt);
        if isempty(choice) || strcmp(choice, 'Quit alignment')
            if ~isdeployed
                assignin('base', 'shiftX', shiftX);
                assignin('base', 'shiftY', shiftY);
                fprintf(['Shifts between images were exported to MATLAB workspace ' ...
                    '(shiftX, shiftY).\n']);
            end
            return;
        end
        applyRunningAverage = strcmp(choice, 'Fix drifts');
    else
        applyRunningAverage = false;
    end

    if applyRunningAverage || obj.BatchOpt.SubtractRunningAverage
        halfwidth    = obj.BatchOpt.SubtractRunningAverageStep{1};
        excludePeaks = obj.BatchOpt.SubtractRunningAverageExcludePeaks{1};
        [shiftX, shiftY, halfwidth, excludePeaks] = utils.align.subtractRunningAverage( ...
            obj.view.gui, shiftX, shiftY, halfwidth, excludePeaks, parameters.useBatchMode);
        if isempty(shiftX); return; end
        if halfwidth > 0
            obj.BatchOpt.SubtractRunningAverage             = true;
            obj.BatchOpt.SubtractRunningAverageStep{1}      = halfwidth;
            obj.BatchOpt.SubtractRunningAverageExcludePeaks{1} = excludePeaks;
        end
    end

    if ~isdeployed
        assignin('base', 'shiftX', shiftX);
        assignin('base', 'shiftY', shiftY);
    end

    obj.shiftsX = shiftX;
    obj.shiftsY = shiftY;
end

% --- Apply shifts to the image stack
if ~isempty(pwb)
    if pwb.getCancelState(); return; end
    pwb.updateText('Applying shifts to the image stack...');
end

shiftOpts.backgroundColor = parameters.backgroundColor;
shiftOpts.waitbar         = pwb;

imageStack = cell2mat(obj.mibModel.getData4D('image', [], NaN));
imageStackOut = utils.align.crossShiftStack(imageStack, obj.shiftsX, obj.shiftsY, shiftOpts);
if isempty(imageStackOut); return; end
obj.mibModel.setData4D(imageStackOut, 'image', [], NaN);
clear imageStack imageStackOut;

% --- Apply shifts to service layers (mask / selection / labels)
serviceShiftOpts.backgroundColor = 0;       % service layers always pad with zeros
serviceShiftOpts.waitbar         = pwb;

isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

if isLabels63
    if ~isempty(pwb); pwb.updateText('Applying shifts to selection / mask / labels...'); end
    layer = cell2mat(obj.mibModel.getData4D('everything', [], 0));
    shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
    if isempty(shifted); return; end
    obj.mibModel.setData4D(shifted, 'everything', [], 0);
else
    if obj.mibModel.I{id}.modelExist
        if ~isempty(pwb); pwb.updateText('Applying shifts to labels...'); end
        layer = cell2mat(obj.mibModel.getData4D('labels', [], NaN));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.setData4D(shifted, 'labels', [], NaN);
    end
    if obj.mibModel.I{id}.maskExist
        if ~isempty(pwb); pwb.updateText('Applying shifts to mask...'); end
        layer = cell2mat(obj.mibModel.getData4D('mask', [], 0));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.setData4D(shifted, 'mask', [], 0);
    end
    if obj.mibModel.I{id}.enableSelection
        if ~isempty(pwb); pwb.updateText('Applying shifts to selection...'); end
        layer = cell2mat(obj.mibModel.getData4D('selection', [], NaN));
        shifted = utils.align.crossShiftStack(layer, obj.shiftsX, obj.shiftsY, serviceShiftOpts);
        if isempty(shifted); return; end
        obj.mibModel.setData4D(shifted, 'selection', [], NaN);
    end
end

% --- Sync MibDataset metadata to the new (enlarged) canvas
ds = obj.mibModel.I{id};
ds.image.height = size(ds.image.data{1}, 1);
ds.image.width  = size(ds.image.data{1}, 2);
ds.dim_yxzct    = [ds.image.height, ds.image.width, ds.image.depth, ds.image.colors, ds.image.time];
oldSlices = ds.slices;
ds.slices{1} = [1, ds.image.height];
ds.slices{2} = [1, ds.image.width];
ds.slices{3} = 1:ds.image.depth;
ds.slices{4} = [1, 1];
ds.slices{5} = [1, 1];
ds.slices{ds.orientation} = repmat(oldSlices{ds.orientation}(1), 1, 2);

% --- Bounding box shift (orientations: 3 = XY, 1 = ZX, 2 = ZY)
maxXshift = min(obj.shiftsX);
maxYshift = min(obj.shiftsY);
maxZshift = 0;
switch ds.orientation
    case 3   % XY
        maxXshift = maxXshift * ds.image.pixSize.x;
        maxYshift = maxYshift * ds.image.pixSize.y;
    case 2   % ZY
        maxZshift = maxXshift * ds.image.pixSize.z;
        maxYshift = maxYshift * ds.image.pixSize.y;
        maxXshift = 0;
    case 1   % ZX
        maxZshift = maxXshift * ds.image.pixSize.z;
        maxXshift = maxYshift * ds.image.pixSize.x;
        maxYshift = 0;
end
obj.mibModel.I{id}.updateBoundingBox([], [maxXshift, maxYshift, maxZshift]);

% --- Action log
if obj.BatchOpt.SubtractRunningAverage
    obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
        'Aligned using %s; refFrame=%d; running-average halfwidth=%d, excludePeaks=%d', ...
        obj.BatchOpt.Algorithm{1}, parameters.refFrame, ...
        obj.BatchOpt.SubtractRunningAverageStep{1}, ...
        obj.BatchOpt.SubtractRunningAverageExcludePeaks{1}));
else
    obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
        'Aligned using %s; refFrame=%d', ...
        obj.BatchOpt.Algorithm{1}, parameters.refFrame));
end

% --- Save shifts to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveShiftsToFile(obj, id, parameters.useBatchMode);
end

% Trigger a redraw
notify(obj.mibModel, 'NewDataset');
notify(obj.mibModel, 'ShowImage');

% --- Suppress unused warnings for ports of code paths reused by other algorithms
%#ok<*UNRCH>
end

% =============================================================================
function [shiftX, shiftY] = computeShifts(obj, parameters, pwb)
% Helper: load image data (with optional sub-area / mask / gradient pre-processing)
% then call utils.align.calcShifts. Returns ``[]`` if the user cancelled.

shiftX = [];
shiftY = [];
sliceMaskBoxes = [];

id = obj.mibModel.getActiveId();
optionsGetData = struct('blockModeSwitch', 0);

if strcmp(parameters.Subarea, 'Manually specified')
    optionsGetData.x = [parameters.minX parameters.maxX];
    optionsGetData.y = [parameters.minY parameters.maxY];
    optionsGetData.z = [1 obj.mibModel.I{id}.image.depth];
end
I = squeeze(cell2mat(obj.mibModel.getData4D('image', [], parameters.colorCh, optionsGetData)));

if strcmp(parameters.Subarea, 'Manually specified')
    optionsGetData = rmfield(optionsGetData, {'x','y','z'});
end

% --- Mask / Selection sub-area extraction
if ismember(parameters.Subarea, {'Mask', 'Selection'})
    if ~isempty(pwb); pwb.updateText('Extracting masked areas...'); end
    layerName = lower(parameters.Subarea);
    img  = zeros(size(I), class(I));
    sliceMaskBoxes = nan(size(I, 3), 4);
    for sliceIdx = 1:size(I, 3)
        if ~isempty(pwb) && pwb.getCancelState(); return; end
        mask = cell2mat(obj.mibModel.getData2D(layerName, sliceIdx, [], NaN, optionsGetData));
        stats = regionprops(mask, 'BoundingBox');
        if isempty(stats); continue; end
        bb = ceil(stats(1).BoundingBox);
        mask = mask(bb(2):bb(2)+bb(4)-1, bb(1):bb(1)+bb(3)-1);
        currImg = I(bb(2):bb(2)+bb(4)-1, bb(1):bb(1)+bb(3)-1, sliceIdx);
        intensityShift = mean(currImg(:));
        currImg(~mask) = intensityShift;
        img(:,:,sliceIdx) = intensityShift;
        img(1:bb(4), 1:bb(3), sliceIdx) = currImg;
        sliceMaskBoxes(sliceIdx, :) = bb;
        if ~isempty(pwb); pwb.increment(); end
    end
    sliceIndices = find(~isnan(sliceMaskBoxes(:, 1)));
    if isempty(sliceIndices)
        utils.dlgs.showErrorDialog(obj.view.gui, ...
            sprintf('No %s areas were found.', parameters.Subarea), ...
            sprintf('Missing %s layer', parameters.Subarea));
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    I = img(1:max(sliceMaskBoxes(:, 4)), 1:max(sliceMaskBoxes(:, 3)), sliceIndices);
    clear img;
end

% --- Optional intensity gradient pre-processing (Sobel)
if parameters.IntensityGradient
    if ~isempty(pwb)
        pwb.updateText(sprintf('Calculating intensity gradient (channel %d)...', parameters.colorCh));
    end
    hy = fspecial('sobel');
    hx = hy';
    gradient = zeros(size(I), class(I));
    for sliceIdx = 1:size(I, 3)
        if ~isempty(pwb) && pwb.getCancelState(); return; end
        slice = double(I(:,:,sliceIdx));
        Iy = imfilter(slice, hy, 'replicate');
        Ix = imfilter(slice, hx, 'replicate');
        gradient(:,:,sliceIdx) = sqrt(Ix.^2 + Iy.^2);
        if ~isempty(pwb); pwb.increment(); end
    end
    I = gradient;
    clear gradient;
end

% --- Compute shifts
calcOpts.method   = parameters.method;
calcOpts.refFrame = parameters.refFrame;
calcOpts.waitbar  = pwb;
[shiftX, shiftY] = utils.align.calcShifts(I, calcOpts);
if isempty(shiftX); return; end

% Re-expand the shift vector when mask/selection skipped slices
if ismember(parameters.Subarea, {'Mask', 'Selection'})
    Depth = obj.mibModel.I{id}.image.depth;
    [shiftX, shiftY] = expandMaskedShifts(shiftX, shiftY, sliceMaskBoxes, Depth);
end
end

% =============================================================================
function [shX, shY] = expandMaskedShifts(shiftX, shiftY, sliceBoxes, Depth)
% Expand the per-mask-slice shifts to a full Depth-long vector, propagating
% shifts across slices that had no mask (matches the MIB2 logic).

if size(sliceBoxes, 1) == numel(shiftX)
    difX = cumsum([0; diff(sliceBoxes(:,1))]);
    difY = cumsum([0; diff(sliceBoxes(:,2))]);
    shX = shiftX - difX;
    shY = shiftY - difY;
    return;
end

shX = zeros(Depth, 1);
shY = zeros(Depth, 1);
index = 1;
breakBegin = false;
for k = 2:Depth
    if isnan(sliceBoxes(k, 1))
        shX(k) = shX(k-1);
        shY(k) = shY(k-1);
        breakBegin = true;
    else
        if breakBegin
            shX(k) = shX(k-1);
            shY(k) = shY(k-1);
            breakBegin = false;
        else
            if index > 1
                shX(k) = shX(k-1) + shiftX(index) - shiftX(index-1) - (sliceBoxes(k,1) - sliceBoxes(k-1,1));
                shY(k) = shY(k-1) + shiftY(index) - shiftY(index-1) - (sliceBoxes(k,2) - sliceBoxes(k-1,2));
            else
                shX(k) = shX(k-1) + shiftX(index) - (sliceBoxes(k,1) - sliceBoxes(k-1,1));
                shY(k) = shY(k-1) + shiftY(index) - (sliceBoxes(k,2) - sliceBoxes(k-1,2));
            end
        end
        index = index + 1;
    end
end
end

% =============================================================================
function previewShifts(shiftX, shiftY)
figure(155); clf;
plot(1:length(shiftX), shiftX, '.-', 1:length(shiftY), shiftY, '.-');
legend('Shift X', 'Shift Y', 'Location', 'best'); grid on;
xlabel('Frame number'); ylabel('Displacement');
title('Detected shifts (before alignment)');
end

% =============================================================================
function saveShiftsToFile(obj, id, useBatchMode)
if useBatchMode
    fn = obj.mibModel.I{id}.image.sliceName('Filename');
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
elseif isfield(obj.view.handles, 'saveShiftsXYpath')
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
else
    return;
end
shiftsX = obj.shiftsX;
shiftsY = obj.shiftsY;
fprintf('Saving alignment shifts to file: %s ... ', fullPath);
try
    save(fullPath, 'shiftsX', 'shiftsY');
    fprintf('done!\n');
catch ME
    fprintf('failed.\n');
    utils.dlgs.showErrorDialog(obj.view.gui, ME, 'Save shifts');
end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
