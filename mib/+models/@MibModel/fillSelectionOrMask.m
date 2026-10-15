function fillSelectionOrMask(obj, targetLayer, BatchOptIn)
% FILLSELECTIONORMASK - Fill holes in the selection or mask layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.fillSelectionOrMask(targetLayer, BatchOptIn)
%
% Applies imfill('holes') slice-by-slice across the chosen scope.
% Optionally the filled result is clipped to the pixels belonging to a
% specific model material (restrictSelectionToMaterial).
%
% Parallel 2D filling is supported via parfor when the Parallel Computing
% Toolbox is available; use core.PoolWaitbar for thread-safe progress.
%
% **Cancel.** The progress dialog is cancelable. The slices of a time point are
% filled into a local array in batches (one slice sequentially, 4 per worker in
% parallel - workers cannot see the dialog, so Cancel is polled between batches)
% and written only when the time point is complete: Cancel discards the time
% point in progress and a 3D stack is left unchanged. When earlier time points
% of a 4D dataset were already written, a dialog says which; the Undo backup
% holds only the current time point and cannot revert them. In batch mode a
% Cancel also stops the protocol (``StopProtocol``).
%
% **Memory.** A 3D/4D fill holds one time point of the layer (and of the
% material when clipping) in a local array, in the sequential mode too.
%
% Input Arguments:
%   - **targetLayer** - *(optional)* char with the targer layer, 'mask', or 'selection',
%     when [] - 'selection'
%   - **BatchOptIn** - *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the "SyncBatch" event.
%     When called from MibSelection.fillSelection the DatasetType and
%     TargetLayer fields are already populated.
%
%     - ``.TargetLayer`` - cell string, ``{'selection','mask'}`` layer to fill
%     - ``.DatasetType`` - cell string, ``{'2D, Slice','3D, Stack','4D, Dataset'}`` scope
%     - ``.SelectedMaterial`` - string, material index used when
%       restrictSelectionToMaterial=true; ``'-1'`` mask, ``'0'`` exterior, ``'1'``, ``'2'``...
%     - ``.restrictSelectionToMaterial`` - logical, clip filled result to the
%       pixels of the selected model material
%     - ``.Use2DParallelComputing`` - logical, use parfor for slice-by-slice fill
%     - ``.showWaitbar`` - logical, show or not the progress dialog
%     - ``.id`` - *(optional)* dataset index 1-9, default = obj.id
%
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** - fill selection on current slice
%
%   .. code-block:: matlab
%
%      obj.mibModel.fillSelectionOrMask();
%
%   **Example 2** - fill the mask layer across the full z-stack
%
%   .. code-block:: matlab
%
%      BatchOpt.TargetLayer = {'mask'};
%      BatchOpt.DatasetType = {'3D, Stack'};
%      BatchOpt.restrictSelectionToMaterial = false;
%      BatchOpt.showWaitbar = true;
%      obj.mibModel.fillSelectionOrMask(BatchOpt);
%
%   **Example 3** - return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.fillSelectionOrMask(NaN);
%

% Updates
% 15.10.2026 - cancelable progress dialog; the slice loop runs in batches that
%              write each time point once (sequential path merged into it); the
%              material clip moved after the loop

if nargin < 3; BatchOptIn = struct(); end

%% Default BatchOpt
BatchOpt = struct();
if isempty(targetLayer)
    BatchOpt.TargetLayer = {'selection'};
else
    BatchOpt.TargetLayer = {targetLayer};
end
BatchOpt.TargetLayer{2} = {'selection', 'mask'};
BatchOpt.DatasetType = {'2D, Slice'};
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.SelectedMaterial            = num2str(obj.I{obj.id}.getSelectedMaterialIndex());
BatchOpt.restrictSelectionToMaterial = logical(obj.I{obj.id}.restrictSelectionToMaterial);
BatchOpt.Use2DParallelComputing      = false;
BatchOpt.id          = obj.getActiveId();
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
BatchOpt.mibBatchActionName  = 'Fill selection';

BatchOpt.mibBatchTooltip.TargetLayer  = 'Layer to fill holes in';
BatchOpt.mibBatchTooltip.DatasetType  = 'Specify whether to fill the current slice (2D, Slice), the stack (3D, Stack) or complete dataset (4D, Dataset)';
BatchOpt.mibBatchTooltip.SelectedMaterial = 'Index of the selected material; -1 for mask, 0 for exterior, 1,2,3... model materials';
BatchOpt.mibBatchTooltip.restrictSelectionToMaterial = 'When checked, clip the filled result to pixels of the selected model material';
BatchOpt.mibBatchTooltip.Use2DParallelComputing = 'Use parallel processing for slice-by-slice hole filling';
BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress dialog during execution';

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isscalar(BatchOptIn) && isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    else
        ErrorDlgOpt.winTitle       = 'BatchOpt Error';
        ErrorDlgOpt.optionalPrefix = 'Error in MibModel.fillSelectionOrMask';
        ErrorDlgOpt.err            = 'A structure as the 2nd parameter is required!';
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

% Update batch section name for mask target
if strcmp(BatchOpt.TargetLayer{1}, 'mask')
    BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
    BatchOpt.mibBatchActionName  = 'Fill mask';
end

%% Guard: selection disabled
if obj.I{BatchOpt.id}.enableSelection == 0
    notify(obj, 'StopProtocol');
    return;
end

tic;

%% Demote 4D to 3D when only one time point
if strcmp(BatchOpt.DatasetType{1}, '4D, Dataset') && obj.I{BatchOpt.id}.image.time == 1
    BatchOpt.DatasetType{1} = '3D, Stack';
end

selcontour   = str2double(BatchOpt.SelectedMaterial);
selectedOnly = BatchOpt.restrictSelectionToMaterial;

getDataOptions.id = BatchOpt.id;

%% Pre-compute dims, parallel setup, and waitbar (3D/4D only)
if ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice')
    %% Time-point range
    if strcmp(BatchOpt.DatasetType{1}, '4D, Dataset')
        t1 = 1;
        t2 = obj.I{BatchOpt.id}.image.time;
    else
        t1 = obj.I{BatchOpt.id}.slices{5}(1);
        t2 = obj.I{BatchOpt.id}.slices{5}(2);
    end

    orient    = obj.I{BatchOpt.id}.orientation;
    max_size  = obj.I{BatchOpt.id}.dim_yxzct(orient);
    max_size2 = max_size * (t2 - t1 + 1);

    % Auto-enable parallel if a pool is already running (non-batch)
    if ~batchModeSwitch
        if ~isempty(gcp('nocreate')); BatchOpt.Use2DParallelComputing = true; end
    end

    if BatchOpt.Use2DParallelComputing
        parforArg = obj.preferences.System.cpuParallelLimit;
        if isempty(gcp('nocreate')); parpool(parforArg); end
    else
        parforArg = 0;
    end

    % pwb must exist even without a waitbar: it is a parfor broadcast variable,
    % and on a running pool parfor refuses an undefined one
    pwb = [];
    if BatchOpt.showWaitbar
        pwb = core.PoolWaitbar(max_size2, ...
            sprintf('Filling holes in %s\nPlease wait...', BatchOpt.TargetLayer{1}), ...
            obj.getProgressBarParent(), 'Filling holes...', true);
        pwb.setIncrement(10);
    end
    showWaitbar = BatchOpt.showWaitbar;
end
cancelledAt = [];   % time point at which Cancel was pressed

%% Backup (skipped in batch mode)
if ~batchModeSwitch
    do3Dbackup = ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice');
    obj.backup(BatchOpt.TargetLayer{1}, do3Dbackup, getDataOptions);
end

%% ================================================================
%  2D Slice - single slice, no loop needed
%% ================================================================
if strcmp(BatchOpt.DatasetType{1}, '2D, Slice')
    slice = cell2mat(obj.getData2D(BatchOpt.TargetLayer{1}, [], [], [], getDataOptions));
    slice = imfill(slice, 'holes');
    if selectedOnly
        clip = cell2mat(obj.getData2D('labels', [], [], selcontour, getDataOptions));
        slice = slice & clip;
    end
    obj.I{BatchOpt.id}.setData2D(slice, BatchOpt.TargetLayer{1}, [], [], [], getDataOptions);

%% ================================================================
%  3D / 4D - slice-by-slice loop (parallel or sequential)
%% ================================================================
else
    % Sequential and parallel alike, the slices of a time point are filled
    % into a local stack in batches (parfor with parforArg = 0 runs on the
    % client) and the stack is written once the time point is complete.
    % Cancel is polled between batches - pool workers cannot see the dialog -
    % so a cancelled time point stays unchanged. A batch is one slice
    % sequentially, 4 per worker in parallel.
    if parforArg > 0; batchSize = 4 * parforArg; else; batchSize = 1; end

    for t = t1:t2
        getDataOptions.t = [t, t];
        stack = cell2mat(obj.getData3D(BatchOpt.TargetLayer{1}, t, orient, [], getDataOptions));

        for batchStart = 1:batchSize:max_size
            if showWaitbar
                drawnow limitrate;   % deliver the progress updates and the Cancel click
                if pwb.getCancelState(); cancelledAt = t; break; end
            end
            batchEnd = min(batchStart + batchSize - 1, max_size);
            parfor (layer_id = batchStart:batchEnd, parforArg)
                if showWaitbar && mod(layer_id, 10) == 0; pwb.increment(); end %#ok<PFBNS>
                slice = stack(:, :, layer_id);
                if max(slice(:)) < 1; continue; end
                stack(:, :, layer_id) = imfill(slice, 'holes');
            end
        end
        if ~isempty(cancelledAt); break; end

        % restrict to the material after the loop: indexed inside parfor, an
        % empty model ([] when not restricting) is a sliced variable that the
        % pool fails to slice, even when the branch never runs
        if selectedOnly
            model = cell2mat(obj.getData3D('labels', t, orient, selcontour, getDataOptions));
            stack(~model) = 0;
        end

        obj.I{BatchOpt.id}.setData3D(stack, BatchOpt.TargetLayer{1}, t, orient, [], getDataOptions);
    end

    if showWaitbar; pwb.deletePoolWaitbar(); end
end

%% Cancelled: the time point in progress was discarded
if ~isempty(cancelledAt)
    if cancelledAt > t1
        % earlier time points of a 4D dataset were already written
        ErrorDlgOpt.winTitle       = 'Filling cancelled';
        ErrorDlgOpt.optionalPrefix = '';
        ErrorDlgOpt.err            = sprintf(['Filling was cancelled: time points %d-%d were filled, ' ...
            'time points %d-%d are unchanged.'], t1, cancelledAt - 1, cancelledAt, t2);
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        notify(obj, 'ShowImage');
    end
    if batchModeSwitch; notify(obj, 'StopProtocol'); end
    return;
end

if ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice'); toc; end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
