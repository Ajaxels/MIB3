function expandSelectionToMaskBorder(obj, BatchOptIn)
% EXPANDSELECTIONTOMASKBORDER - Snap each selection blob to its enclosing mask region.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.expandSelectionToMaskBorder(BatchOptIn)
%
% For each connected component in the Selection layer, finds the mask connected
% component that contains (or overlaps) it, and replaces the selection blob with
% the full extent of that mask region.  Uses a labelmatrix lookup for O(N_sel)
% efficiency rather than the O(N_sel x N_mask) linear scan in MIB2.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the "SyncBatch" event.
%
%     - ``.DatasetType`` — cell string, ``{'3D, Stack','4D, Dataset'}`` scope
%     - ``.showWaitbar`` — logical, show or not the progress dialog
%     - ``.id`` — *(optional)* dataset index 1-9, default = obj.id
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** — expand selection to mask border on current stack
%
%   .. code-block:: matlab
%
%      obj.mibModel.expandSelectionToMaskBorder();
%
%   **Example 2** — batch mode across full 4D dataset
%
%   .. code-block:: matlab
%
%      BatchOpt.DatasetType = {'4D, Dataset'};
%      BatchOpt.showWaitbar = false;
%      obj.mibModel.expandSelectionToMaskBorder(BatchOpt);
%
%   **Example 3** — return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.expandSelectionToMaskBorder(NaN);
%

% Updates
%

if nargin < 2; BatchOptIn = struct(); end

%% Default BatchOpt
BatchOpt = struct();
BatchOpt.DatasetType = {'3D, Stack'};
BatchOpt.DatasetType{2} = {'3D, Stack', '4D, Dataset'};
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Selection';
BatchOpt.mibBatchActionName  = 'Expand to mask border';

BatchOpt.mibBatchTooltip.DatasetType = 'Scope: current z-stack or all time frames';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress dialog during execution';

%% Batch mode check
if isstruct(BatchOptIn) == 0
    if isscalar(BatchOptIn) && isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    else
        ErrorDlgOpt.winTitle       = 'BatchOpt Error';
        ErrorDlgOpt.optionalPrefix = 'Error in MibModel.expandSelectionToMaskBorder';
        ErrorDlgOpt.err            = 'A structure as the 1st parameter is required!';
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

%% Guard: virtual stacking mode not supported
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
        '!!! Warning !!!', {''}, ...
        {'This action is not yet available in the virtual stacking mode!\nPlease switch to the memory-resident mode and try again.'}, ...
        'Not implemented', dlgOpt);
    return;
end

%% Guard: selection disabled
if obj.I{BatchOpt.id}.enableSelection == 0
    notify(obj, 'StopProtocol');
    return;
end

tic;

%% Time-point range
if strcmp(BatchOpt.DatasetType{1}, '4D, Dataset')
    t1 = 1;
    t2 = obj.I{BatchOpt.id}.image.time;
else
    t1 = obj.I{BatchOpt.id}.slices{5}(1);
    t2 = obj.I{BatchOpt.id}.slices{5}(2);
end

getDataOptions.id = BatchOpt.id;
getDataOptions.blockModeSwitch = 0;

%% Backup (only for single-time datasets — multi-time backups are too large)
if obj.I{BatchOpt.id}.image.time == 1
    obj.backup('selection', true, getDataOptions);
end

%% Waitbar
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', 'Expanding selection to mask border...', ...
        'Title', 'Expand to Mask Border');
end

%% Main loop over time points
for t = t1:t2
    if BatchOpt.showWaitbar
        wb.Value = (t - t1) / max(t2 - t1, 1);
    end

    getDataOptions.t = [t, t];

    selectionVolume = cell2mat(obj.getData3D('selection', t, 3, [], getDataOptions));
    maskVolume      = cell2mat(obj.getData3D('mask',      t, 3, [], getDataOptions));

    selCC  = bwconncomp(selectionVolume, 26);
    maskCC = bwconncomp(maskVolume, 26);

    newSelection = zeros(size(selectionVolume), 'uint8');

    if selCC.NumObjects > 0 && maskCC.NumObjects > 0
        maskLabels = labelmatrix(maskCC);
        for selObj = 1:selCC.NumObjects
            pixelIndex = selCC.PixelIdxList{selObj}(1);
            maskLabel  = maskLabels(pixelIndex);
            if maskLabel > 0
                newSelection(maskCC.PixelIdxList{maskLabel}) = 1;
            end
        end
    end

    obj.I{BatchOpt.id}.setData3D(newSelection, 'selection', t, 3, [], getDataOptions);
end

if BatchOpt.showWaitbar; delete(wb); end
toc;

%% Notify
BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'ShowImage');
end
