function clearMask(obj, sel_switch, BatchOptIn)
% CLEARMASK - Clear the Mask layer for the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.clearMask(sel_switch, BatchOptIn)
%
% Clears all pixels in the Mask layer for the current slice, the whole
% z-stack, or the entire 4D dataset, depending on the requested scope.
% Supports batch-processing mode via BatchOptIn.
%
% Input Arguments:
%   - **sel_switch** — *(optional)* string defining the clear scope
%
%     - ``'2D, Slice'``   — clear the currently shown slice only *(default)*
%     - ``'3D, Stack'``   — clear the full z-stack at the current time point
%     - ``'4D, Dataset'`` — clear the entire dataset (all z and t)
%
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when
%     NaN, returns default options via the "SyncBatch" event
%
%     - ``.DatasetType`` — cell ``{value, {choices}}`` selecting the clear scope
%     - ``.showWaitbar`` — logical, show or not the progress bar
%     - ``.id``          — dataset index 1-9; default = currently active dataset
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** — clear current slice
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearMask('2D, Slice');
%
%   **Example 2** — clear current z-stack
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearMask('3D, Stack');
%
%   **Example 3** — clear full dataset
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearMask('4D, Dataset');
%

% Updates

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
BatchOpt.mibBatchTooltip.DatasetType = 'Select to remove the mask from the current slice, stack, or dataset';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
BatchOpt.mibBatchActionName  = 'Clear mask';

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

% do nothing if no mask layer exists
if ~obj.I{BatchOpt.id}.maskExist; return; end

% render waitbar
if BatchOpt.showWaitbar && ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice')
    wb = uiprogressdlg(obj.mibGUI, 'Title', 'Clearing mask', ...
        'Message', 'Clearing Mask layer...', ...
        'Indeterminate', 'on');
end

id = BatchOpt.id;
%% Perform the clear
switch BatchOpt.DatasetType{1}
    case '2D, Slice'
        backupOptions.id = id;
        obj.backup('mask', 0, backupOptions);
        obj.I{id}.clearLayer('mask', '2D');

    case '3D, Stack'
        backupOptions.id = id;
        obj.backup('mask', 1, backupOptions);
        obj.I{id}.clearLayer('mask', '3D');
        if BatchOpt.showWaitbar; delete(wb); end

    case '4D, Dataset'
        backupOptions.id = id;
        obj.backup('mask', 1, backupOptions);
        obj.I{id}.clearLayer('mask', '4D');
        if BatchOpt.showWaitbar; delete(wb); end
end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
