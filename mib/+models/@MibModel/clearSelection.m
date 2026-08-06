function clearSelection(obj, sel_switch, BatchOptIn)
% CLEARSELECTION - Clear the Selection layer for the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.clearSelection(sel_switch, BatchOptIn)
%
% Clears all pixels in the Selection layer for the current slice,
% the whole z-stack, or the entire 4D dataset, depending on the
% requested scope.  Supports batch-processing mode via BatchOptIn.
%
% Input Arguments:
%   - **sel_switch** - *(optional)* string defining the clear scope
%   - '2D, Slice'   - clear the currently shown slice only (default)
%   - '3D, Stack'   - clear the full z-stack at the current time point(s)
%   - '4D, Dataset' - clear the entire dataset (all z and t)
%   - **BatchOptIn** - *(optional)* structure for batch processing mode; when
%     NaN, returns default options via the "SyncBatch" event
%   - .DatasetType  - cell {value, {choices}} selecting the clear scope
%   - .showWaitbar  - logical, show or not the progress bar
%   - .id           - dataset index 1-9; default = obj.id
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** - clear current slice
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearSelection('2D, Slice');
%
%   **Example 2** - clear current z-stack
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearSelection('3D, Stack');
%
%   **Example 3** - clear full dataset
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearSelection('4D, Dataset');
%

% Updates
%

% do nothing if selection is disabled
if obj.I{obj.id}.enableSelection == 0; return; end

if nargin < 3; BatchOptIn = struct(); end
if nargin < 2; sel_switch = []; end

%% Build default BatchOpt
BatchOpt = struct();
if ~isempty(sel_switch)
    BatchOpt.DatasetType = {sel_switch};
else
    BatchOpt.DatasetType = {'2D, Slice'};
end
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();
BatchOpt.mibBatchTooltip.DatasetType = 'Select to remove selection from the current slice, stack, or dataset';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
BatchOpt.mibBatchActionName  = 'Clear selection';

%% Batch mode check
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isscalar(BatchOptIn) && isnan(BatchOptIn)    % return default options for batch editor
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle       = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.clearSelection';
            ErrorDlgOpt.err            = 'A structure as the 3rd parameter is required!';
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

% render waitbar
if BatchOpt.showWaitbar && ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice')
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Title', 'Clearing selection', ...
        'Message', 'Clearing Selection layer...', ...
        'Indeterminate', 'on');
end

id = BatchOpt.id;
%% Perform the clear
switch BatchOpt.DatasetType{1}
    case '2D, Slice'
        backupOptions.id = id;
        if isa(obj.I{id}.labels, 'core.MibBigDataLabels')
            orient   = obj.I{id}.orientation;
            selBB    = obj.I{id}.labels.selectionBBoxFull;
            curSlice = obj.I{id}.slices{orient}(1);
            curTime  = obj.I{id}.slices{5}(1);
            if orient == 3 && ~isempty(selBB)
                % XY view with known selection footprint: scope backup and clear to
                % the footprint only - avoids allocating the full gigapixel slice.
                % setData63 resets selectionBBoxFull once the region contains no
                % more selection bits.
                backupOptions.y = [selBB(1), selBB(2)];
                backupOptions.x = [selBB(3), selBB(4)];
                obj.backup('selection', 0, backupOptions);
                obj.I{id}.clearLayer('selection', ...
                    [selBB(1), selBB(2)], [selBB(3), selBB(4)], ...
                    [curSlice, curSlice], [curTime, curTime], false);
            else
                % Non-XY view or unknown footprint: scope to visible window only.
                backupOptions.blockModeSwitch = true;
                obj.backup('selection', 0, backupOptions);
                obj.I{id}.clearLayer('selection', '2D', [], [], [], true);
            end
        else
            obj.backup('selection', 0, backupOptions);
            obj.I{id}.clearLayer('selection', '2D');
        end

    case '3D, Stack'
        % backup the full z-stack
        backupOptions.id = id;
        obj.backup('selection', 1, backupOptions);

        t1 = obj.I{id}.slices{5}(1);
        t2 = obj.I{id}.slices{5}(2);
        
        obj.I{id}.clearLayer('selection', '3D');
        if BatchOpt.showWaitbar; delete(wb); end

    case '4D, Dataset'
        % backup the full dataset
        backupOptions.id = id;
        obj.backup('selection', 1, backupOptions);

        
        obj.I{id}.clearLayer('selection', '4D');
        if BatchOpt.showWaitbar; delete(wb); end
end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
