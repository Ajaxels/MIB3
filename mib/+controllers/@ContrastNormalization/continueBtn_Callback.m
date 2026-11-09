function continueBtn_Callback(obj, useBatchMode)
% CONTINUEBTN_CALLBACK - Validate, back up, and dispatch to the target-specific normalization method.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.continueBtn_Callback()
%      obj.continueBtn_Callback(useBatchMode)
%
% Checks preconditions (virtual mode, indexed color type, mask presence),
% creates a backup for single-frame operations, then dispatches to the
% appropriate low-level normalization method based on ``obj.BatchOpt.Target``.
% A BigData dataset goes to ``normalizeBigData`` instead (new store, no backup).
% On completion the image is re-displayed and the batch controller is notified.
%
% The progress dialog is cancelable and every slice polls it. A cancel, or an
% empty mask layer, stops the run without the action log entry, the user
% points or the BatchOpt hand-over, and stops a running batch protocol. When
% the stop comes after the first slice was written the image is partially
% normalized, and the user is told so: a single time point was backed up
% beforehand (when undo is enabled) and can be restored with Ctrl+Z, a time
% series has no backup and cannot. The method does not run the undo itself,
% because with undo disabled that would restore an older, unrelated state.
%
% Input Arguments:
%   - **useBatchMode** *(optional)* - logical; ``true`` when invoked via
%     the batch processor (no GUI). Default ``false``.

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ContrastNormalization.continueBtn_Callback: triggered\n');
end
if nargin < 2; useBatchMode = false; end

id = obj.mibModel.getActiveId();
obj.BatchOpt.id = id;

% Resolve parent figure for dialogs
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% --- Guard: virtual stacking mode (a BigData dataset is normalized into a new store, below)
if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 2;
    utils.dlgs.inputUniversalDlg(parentFig, ...
        'Contrast normalization is not available in virtual stacking mode.', {''}, ...
        {'Switch to memory-resident mode and try again.'}, 'Not implemented', dlgOpt);
    notify(obj.mibModel, 'StopProtocol');
    return;
end

% --- Guard: indexed color type
if strcmp(obj.mibModel.I{id}.image.colorType, 'indexed')
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Please convert to grayscale or truecolor first!\nMenu -> Image -> Mode -> ...'), ...
        'Indexed color type');
    notify(obj.mibModel, 'StopProtocol');
    return;
end

% --- Guard: mask layer must exist for Masked area / Background targets
if ismember(obj.BatchOpt.Target{1}, {'Masked area', 'Background'})
    if strcmp(obj.BatchOpt.MaskLayer{1}, 'mask') && obj.mibModel.I{id}.maskExist == 0
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('No mask information found!\n\nPlease draw a Mask for each slice of the dataset and try again.'), ...
            'Missing mask');
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
end

% ---- Resolve color channels ----
dataset = obj.mibModel.I{id};
switch obj.BatchOpt.ColChannel{1}
    case 'All channels'
        colorChannel = 1:dataset.image.colors;
    case 'Shown channels'
        colorChannel = dataset.slices{4};
    otherwise
        colorChannel = str2double(obj.BatchOpt.ColChannel{1}(7:end));
end

% ---- BigData: read-only image, normalized into a new store ----
if strcmp(dataset.datasetType, 'BigData')
    obj.normalizeBigData(colorChannel, parentFig);   % parentFig [] headless: errors are raised
    return;
end

% ---- Resolve Z and time ranges ----
maxZ = dataset.image.depth;
maxT = dataset.image.dim_yxzct(5);

currentTimePoint = dataset.slices{5}(1);
currentSlice     = dataset.slices{3}(1);

t1 = currentTimePoint;
t2 = currentTimePoint;
z1 = 1;
z2 = maxZ;

if strcmp(obj.BatchOpt.Target{1}, 'Time series') && maxT > 1
    if strcmp(obj.BatchOpt.TimeSeriesNormalization{1}, 'Based on current 2D slice')
        z1 = currentSlice;
        z2 = currentSlice;
    end
    t1 = 1;
    t2 = maxT;
end

% ---- Backup ----
if t1 == t2
    backupOpt.id = id;
    obj.mibModel.backup('image', 1, backupOpt);
end

% ---- Open progress dialog ----
waitbarHandle = [];
if obj.BatchOpt.showWaitbar
    waitbarHandle = uiprogressdlg(parentFig, ...
        'Title',   'Contrast Normalization', ...
        'Message', sprintf('Normalizing %s...\nPlease wait.', obj.BatchOpt.Target{1}), ...
        'Value',   0, ...
        'Cancelable', 'on');
end

% ---- Build shared options struct passed to per-target methods ----
normOpt.id           = id;
normOpt.t            = [currentTimePoint, currentTimePoint];
normOpt.t1           = t1;
normOpt.t2           = t2;
normOpt.z1           = z1;
normOpt.z2           = z2;
normOpt.currentZ     = currentSlice;
normOpt.parentFig    = parentFig;
normOpt.waitbar      = waitbarHandle;
normOpt.waitbarOffset = 0;
normOpt.totalSteps   = numel(colorChannel) * maxZ * max(1, t2 - t1 + 1);
normOpt.meanValsStr  = '';
normOpt.stdValsStr   = '';
normOpt.cancelled    = false;   % the user pressed Cancel
normOpt.failed       = false;   % stopped by an error that was already reported
normOpt.modified     = false;   % at least one slice was written

% ---- Dispatch to target-specific method ----
switch obj.BatchOpt.Target{1}
    case 'Z stack'
        normOpt = obj.normalizeZStack(colorChannel, normOpt);

    case 'Time series'
        normOpt = obj.normalizeTimeSeries(colorChannel, normOpt);

    case 'Masked area'
        normOpt = obj.normalizeMaskedArea(colorChannel, normOpt);

    case 'Background'
        normOpt = obj.normalizeBackground(colorChannel, normOpt);
end

% ---- Close waitbar ----
if ~isempty(waitbarHandle); close(waitbarHandle); end

% ---- Stopped by Cancel or by an error ----
if normOpt.cancelled || normOpt.failed
    if normOpt.modified
        if t1 == t2 && obj.mibModel.Backup.enableSwitch
            restoreText = 'Press Ctrl+Z to restore the original image.';
        else
            restoreText = 'This cannot be undone: reload the dataset to get the original image back.';
        end
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(parentFig, ...
            'Contrast normalization was stopped before it finished.', {''}, ...
            {sprintf('Part of the image is already normalized.\n%s', restoreText)}, ...
            'Normalization stopped', dlgOpt);
    end
    notify(obj.mibModel, 'StopProtocol');
    notify(obj.mibModel, 'ShowImage');
    return;
end

% ---- Update the session settings with any Manual mode values ----
if strcmp(obj.BatchOpt.Mode{1}, 'Manual')
    obj.mibModel.sessionSettings.ContNorm.Mean = obj.BatchOpt.Mean;
    obj.mibModel.sessionSettings.ContNorm.Std  = obj.BatchOpt.Std;
end

% ---- Write action log ----
logText = sprintf('ContrastNorm: %s, Mode: %s, Ch: %s, Mean: %s, Std: %s', ...
    obj.BatchOpt.Target{1}, obj.BatchOpt.Mode{1}, ...
    num2str(colorChannel), normOpt.meanValsStr, normOpt.stdValsStr);
obj.mibModel.I{id}.image.updateActionLog(logText);

% ---- Count user's points ----
obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments = obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments + 1;
notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));    % scale scoring by factor 2

% ---- Notify ----
obj.returnBatchOpt();
notify(obj.mibModel, 'ShowImage');

end
