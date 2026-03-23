function clearSelection(obj, sel_switch, BatchOptIn)
% function clearSelection(obj, sel_switch, BatchOptIn)
% Clear the Selection layer for the current dataset
%
% Clears all pixels in the Selection layer for the current slice,
% the whole z-stack, or the entire 4D dataset, depending on the
% requested scope.  Supports batch-processing mode via BatchOptIn.
%
% Parameters:
% sel_switch: [@em optional] string defining the clear scope
% @li '2D, Slice'   - clear the currently shown slice only (default)
% @li '3D, Stack'   - clear the full z-stack at the current time point(s)
% @li '4D, Dataset' - clear the entire dataset (all z and t)
% BatchOptIn: [@em optional] structure for batch processing mode; when
%   NaN, returns default options via the "SyncBatch" event
% @li .DatasetType  - cell {value, {choices}} selecting the clear scope
% @li .showWaitbar  - logical, show or not the progress bar
% @li .id           - dataset index 1-9; default = obj.id
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code obj.mibModel.clearSelection('2D, Slice');              // clear current slice @endcode
% @code obj.mibModel.clearSelection('3D, Stack');              // clear current z-stack @endcode
% @code obj.mibModel.clearSelection('4D, Dataset');            // clear full dataset @endcode
% @code
% BatchOpt.DatasetType = {'3D, Stack'};
% BatchOpt.showWaitbar = false;
% obj.mibModel.clearSelection([], BatchOpt);                  // batch / scripted call @endcode

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
BatchOpt.id = obj.id;
BatchOpt.mibBatchTooltip.DatasetType = 'Select to remove selection from the current slice, stack, or dataset';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
BatchOpt.mibBatchActionName  = 'Clear selection';

%% Batch mode check
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)    % return default options for batch editor
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.Title   = 'BatchOpt Error';
            ErrorDlgOpt.String  = 'A structure as the 3rd parameter is required!';
            ErrorDlgOpt.Icon    = 'puffin_error';
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

id = BatchOpt.id;

%% Perform the clear
switch BatchOpt.DatasetType{1}
    case '2D, Slice'
        % backup current slice
        backupOptions.id = id;
        obj.backup('selection', 0, backupOptions);
        % clear only the current slice using block mode (visible portion)
        obj.I{id}.clearLayer('selection', '2D');

    case '3D, Stack'
        % backup the full z-stack
        backupOptions.id = id;
        obj.backup('selection', 1, backupOptions);

        t1 = obj.I{id}.slices{5}(1);
        t2 = obj.I{id}.slices{5}(2);
        if BatchOpt.showWaitbar
            wb = uiprogressdlg(obj.mibGUI, 'Title', 'Clearing selection', ...
                'Message', 'Clearing Selection layer for the current z-stack...', ...
                'Indeterminate', 'on');
        end
        obj.I{id}.clearLayer('selection', '3D');
        if BatchOpt.showWaitbar; delete(wb); end

    case '4D, Dataset'
        % backup the full dataset
        backupOptions.id = id;
        obj.backup('selection', 1, backupOptions);

        if BatchOpt.showWaitbar
            wb = uiprogressdlg(obj.mibGUI, 'Title', 'Clearing selection', ...
                'Message', 'Clearing Selection layer for the whole dataset...', ...
                'Indeterminate', 'on');
        end
        obj.I{id}.clearLayer('selection', '4D');
        if BatchOpt.showWaitbar; delete(wb); end
end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
