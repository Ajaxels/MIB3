function DriftCorrectionBigData_Alignment(obj, parameters)
% DRIFTCORRECTIONBIGDATA_ALIGNMENT - Drift correction / template matching for BigData datasets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.DriftCorrectionBigData_Alignment(parameters)
%
% Two-pass streaming alignment for disk-backed pyramidal (BigData) stores:
%
%   - **Pass 1** reads the stack at the analysis pyramid level
%     ``parameters.pyramidLevel`` and computes per-slice X/Y shifts via
%     :func:`utils.align.calcShifts`. The math operates on the small level-L
%     arrays, so the existing helpers are reused unchanged.
%   - Shifts are scaled to level 0 (``shift0 = round(shiftL * scale)``) - integer
%     shifts give resample-free placement - and handed to
%     :meth:`applyAlignmentBigData` with ``mode = 'translation'``, which streams a
%     NEW aligned OME-Zarr v3 image (+ ``Labels_<stem>.zarr3``) and swaps the
%     active buffer to it. The source store is never modified.
%
% Input Arguments:
%   - **parameters** - struct built by :meth:`continueBtn_Callback`; BigData
%     fields: ``isBigData`` (true), ``pyramidLevel`` (1-based analysis level),
%     ``outputPath`` (target ``.zarr3`` store), plus ``method``, ``colorCh``,
%     ``backgroundColor``, ``refFrame``, ``IntensityGradient``, ``Subarea``,
%     ``minX/maxX/minY/maxY``, ``TransformationMode``, ``useBatchMode``.
%
% See also: controllers.Alignment.applyAlignmentBigData,
% controllers.Alignment.DriftCorrection_Alignment, utils.align.calcShifts

id = obj.mibModel.getActiveId();
ds = obj.mibModel.I{id};

if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

if ds.image.depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Drift correction requires at least 2 slices in Z.', 'Alignment');
    return;
end
if ds.orientation ~= 3
    utils.dlgs.showErrorDialog(parentFig, ...
        'BigData alignment currently supports XY (orientation 3) datasets only.', 'Alignment');
    return;
end
if ismember(parameters.Subarea, {'Mask', 'Selection'})
    utils.dlgs.showErrorDialog(parentFig, ...
        ['Subarea by Mask / Selection is not yet supported for BigData drift ' ...
         'correction. Use "Full image" or "Manually specified".'], 'Alignment');
    return;
end

% --- Analysis pyramid level and its full-res scale factors
L  = parameters.pyramidLevel;
sf = ds.image.pyramid.levelScaleFactors(L, :);   % [yScale xScale zScale]
scaleY = sf(1);
scaleX = sf(2);
depth  = ds.image.depth;

% --- Cancelable progress
pwb = [];
useWaitbar = obj.BatchOpt.showWaitbar;
if useWaitbar
    pwb = core.PoolWaitbar(depth, sprintf('Calculating drifts at pyramid level %d...', L), ...
        parentFig, 'BigData alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% =====================================================================
% Pass 1 - read the level-L stack and compute shifts
% =====================================================================
if isempty(obj.shiftsX)
    % getData interprets options.x/y/z in FULL-RESOLUTION coordinates and scales
    % them to the requested level, so Manual-subarea limits are passed as-is.
    getOpt = struct('pyramidLevel', L);
    if strcmp(parameters.Subarea, 'Manually specified')
        getOpt.x = [parameters.minX, parameters.maxX];
        getOpt.y = [parameters.minY, parameters.maxY];
        getOpt.z = [1, depth];
    end
    I = squeeze(ds.image.getData('image', 3, parameters.colorCh, getOpt));   % [Yl Xl Z]
    if ndims(I) > 3; I = squeeze(I(:, :, :, 1)); end

    % Optional intensity-gradient pre-processing (Sobel), same as in-memory path
    if parameters.IntensityGradient
        if ~isempty(pwb); pwb.updateText('Calculating intensity gradient...'); end
        hy = fspecial('sobel');   hx = hy';
        gradient = zeros(size(I), class(I));
        for sliceIdx = 1:size(I, 3)
            if ~isempty(pwb) && pwb.getCancelState(); return; end
            slice = double(I(:, :, sliceIdx));
            Iy = imfilter(slice, hy, 'replicate');
            Ix = imfilter(slice, hx, 'replicate');
            gradient(:, :, sliceIdx) = sqrt(Ix.^2 + Iy.^2);
        end
        I = gradient;
        clear gradient;
    end

    calcOpts.method   = parameters.method;
    calcOpts.refFrame = parameters.refFrame;
    calcOpts.waitbar  = pwb;
    [shiftXL, shiftYL] = utils.align.calcShifts(I, calcOpts);
    if isempty(shiftXL); return; end   % cancelled

    % Scale level-L shifts to level 0 immediately, so obj.shiftsX/Y - the vectors
    % previewed, running-averaged, applied AND written to file - always hold
    % LEVEL-0 shifts. This keeps save/load symmetric and analysis-level-independent
    % (a file saved from one dataset replays correctly on another regardless of the
    % pyramid level chosen), mirroring the in-memory path where obj.shiftsX already
    % is the applied shift.
    shiftX = shiftXL(:) * scaleX;
    shiftY = shiftYL(:) * scaleY;

    % --- Preview / running-average (GUI only); operates on the level-0 vectors
    if ~parameters.useBatchMode
        obj.BatchOpt.SubtractRunningAverage = false;
        previewShiftsBigData(shiftX, shiftY);
        questOpt.Icon = 'puffin_question';
        questOpt.WindowStyle = 'normal';
        questOpt.WindowWidth = 520;
        choice = utils.dlgs.inputQuestDlg(parentFig, ...
            sprintf(['Align the stack using the detected displacements?\n' ...
            '(shifts computed at pyramid level %d, scaled x%.3g to full resolution)'], L, scaleX), ...
            'Align BigData dataset', ...
            'Apply current values', 'Fix drifts', 'Quit alignment', ...
            'Apply current values', questOpt);
        if isempty(choice) || strcmp(choice, 'Quit alignment')
            if ~isdeployed
                assignin('base', 'shiftX', shiftX);
                assignin('base', 'shiftY', shiftY);
                fprintf('Level-0 shifts exported to workspace (shiftX, shiftY).\n');
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
            parentFig, shiftX, shiftY, halfwidth, excludePeaks, parameters.useBatchMode);
        if isempty(shiftX); return; end
        if halfwidth > 0
            obj.BatchOpt.SubtractRunningAverage             = true;
            obj.BatchOpt.SubtractRunningAverageStep{1}      = halfwidth;
            obj.BatchOpt.SubtractRunningAverageExcludePeaks{1} = excludePeaks;
        end
    end

    obj.shiftsX = shiftX;
    obj.shiftsY = shiftY;
end

% =====================================================================
% obj.shiftsX/Y hold LEVEL-0 shifts (freshly computed above OR pre-loaded from a
% .coefXY file via loadShiftsCheck). Round for resample-free integer placement.
% =====================================================================
shiftX0 = round(obj.shiftsX(:));
shiftY0 = round(obj.shiftsY(:));

% When shifts are pre-loaded (align another dataset via loadShiftsCheck) their
% count must match this dataset's depth, or the per-slice placement below indexes
% out of bounds.
if numel(shiftX0) ~= depth || numel(shiftY0) ~= depth
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['The loaded shifts describe %d slices but this dataset has %d. ' ...
                 'Load a matching .coefXY file.'], numel(shiftX0), depth), 'Alignment');
    return;
end

% --- Resolve the image background fill value (numeric) for the whole-canvas warp
if isnumeric(parameters.backgroundColor)
    backgroundValue = double(parameters.backgroundColor);
elseif strcmpi(parameters.backgroundColor, 'white')
    backgroundValue = double(ds.image.maxInt);
elseif strcmpi(parameters.backgroundColor, 'mean') && exist('I', 'var')
    backgroundValue = mean(double(I(:)));
else   % 'black', or 'mean' when shifts were pre-loaded (level-L stack not read)
    backgroundValue = 0;
end

if ~isempty(pwb); pwb.updateText('Writing the aligned BigData store...'); end

tformInfo = struct();
tformInfo.mode            = 'translation';
tformInfo.shiftX0         = shiftX0;
tformInfo.shiftY0         = shiftY0;
tformInfo.backgroundValue = backgroundValue;

% Save shifts to file if requested (level-0 shifts)
if obj.BatchOpt.SaveShiftsToFile
    saveShiftsBigData(obj, id, shiftX0, shiftY0, parameters.useBatchMode, parentFig);
end

obj.applyAlignmentBigData(parameters, tformInfo);

end

% =============================================================================
function previewShiftsBigData(shiftX, shiftY)
figure(155); clf;
plot(1:numel(shiftX), shiftX, '.-', 1:numel(shiftY), shiftY, '.-');
legend('Shift X', 'Shift Y', 'Location', 'best'); grid on;
xlabel('Frame number'); ylabel('Displacement (full-resolution pixels)');
title('Detected shifts (before alignment)');
end

% =============================================================================
function saveShiftsBigData(obj, id, shiftsX, shiftsY, useBatchMode, parentFig)
if useBatchMode || isempty(obj.view) || ~isfield(obj.view.handles, 'saveShiftsXYpath')
    fn = obj.mibModel.I{id}.image.filename;
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
else
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
end
fprintf('Saving level-0 alignment shifts to file: %s ... ', fullPath);
try
    save(fullPath, 'shiftsX', 'shiftsY');
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
