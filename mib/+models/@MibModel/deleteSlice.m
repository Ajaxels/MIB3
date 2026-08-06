function deleteSlice(obj, orientation, sliceNumber, BatchOptIn)
% DELETESLICE - Delete one or more slices (or time-frames) from the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.deleteSlice(orientation)
%       obj.deleteSlice(orientation, sliceNumber)
%       obj.deleteSlice(orientation, sliceNumber, BatchOptIn)
%
% Batch-compatible dispatcher.  Shows an interactive dialog when called
% without ``BatchOptIn``.  Delegates to ``MibDataset.deleteSlice``.
%
% Input Arguments:
%   - **orientation** - *(optional)* initial dimension:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z),
%     ``5`` = time (t). Default: ``obj.orientation`` of the active dataset
%   - **sliceNumber** - *(optional)* index/indices of slices to delete; ``[]``
%     uses the current slice position
%   - **BatchOptIn** - *(optional)* struct for batch processing mode; when
%     ``NaN``, returns default options via the ``SyncBatch`` event.
%
%     - ``.Dimension`` - [cell] deletion dimension (default: ``{'depth'}``).
%       Allowed values: ``{'height', 'width', 'depth', 'time'}``
%     - ``.DeletePosition`` - [string] slice indices, e.g. ``'5'`` or ``'1,5:10'``;
%       ``'0'`` deletes the last slice/frame
%     - ``.showWaitbar`` - [logical] show the progress dialog (default: ``true``)
%     - ``.id`` - *(optional)* dataset index 1-9, default = ``obj.getActiveId()``
%
% Usage:
%   **Example 1** - delete the currently visible z-slice
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.deleteSlice(3);
%
%   **Example 2** - delete a specific time-frame
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.deleteSlice(5, 3);
%
%   **Example 3** - batch: delete z-slices 2 through 10
%
%   .. code-block:: matlab
%
%
%     BatchOpt.Dimension      = {'depth'};
%     BatchOpt.DeletePosition = '2:10';
%     obj.mibModel.deleteSlice([], [], BatchOpt);
%

% Updates
%

if nargin < 3; sliceNumber  = []; end
if nargin < 2; orientation  = []; end

%% populate BatchOpt with default values
BatchOpt    = struct();
BatchOpt.id = obj.getActiveId();

if isempty(orientation); orientation = obj.I{BatchOpt.id}.orientation; end
if orientation == 0;     orientation = obj.I{BatchOpt.id}.orientation; end

switch orientation
    case 1; BatchOpt.Dimension = {'height'};
    case 2; BatchOpt.Dimension = {'width'};
    case 3; BatchOpt.Dimension = {'depth'};
    case 5; BatchOpt.Dimension = {'time'};
    otherwise
        utils.dlgs.showErrorDialog(obj.getProgressBarParent(), ...
            sprintf('MibModel.deleteSlice: unsupported orientation %d', orientation), 'Error');
        notify(obj, 'StopProtocol');
        return;
end
BatchOpt.Dimension{2} = {'height', 'width', 'depth', 'time'};

if isempty(sliceNumber)
    if strcmp(BatchOpt.Dimension{1}, 'time')
        BatchOpt.DeletePosition = num2str(obj.I{BatchOpt.id}.getCurrentTimePoint());
    else
        BatchOpt.DeletePosition = num2str(obj.I{BatchOpt.id}.getCurrentSliceNumber());
    end
else
    BatchOpt.DeletePosition = num2str(sliceNumber);
end
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
BatchOpt.mibBatchActionName  = 'Slice -> Delete slice/frame';
BatchOpt.mibBatchTooltip.Dimension      = 'Dimension from where to delete slices';
BatchOpt.mibBatchTooltip.DeletePosition = 'Indices of slices to delete, for example: "1,79:85"; 0 = last slice/frame';
BatchOpt.mibBatchTooltip.showWaitbar    = 'Show or not the progress bar during execution';

if nargin == 4  % batch mode
    if isstruct(BatchOptIn) == 0
        if isscalar(BatchOptIn) && isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        else
            ErrorDlgOpt.winTitle       = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.deleteSlice';
            ErrorDlgOpt.err            = 'A structure as the 4th parameter is required!';
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% define parameters
switch BatchOpt.Dimension{1}
    case 'height'; orientation = 1;
    case 'width';  orientation = 2;
    case 'depth';  orientation = 3;
    case 'time';   orientation = 5;
end
maxSlice = obj.I{BatchOpt.id}.dim_yxzct(orientation);

%% interactive dialog
if nargin < 4
    dlgOpt.WindowHeight = 180;
    answer = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
        sprintf('Slice/frame range: 1:%d; 0 = last', maxSlice), ...
        {'Dimension:', 'Slice index(es) to delete (e.g. 5, 7, 10:20, 0 = last):'}, ...
        {[BatchOpt.Dimension{2}, find(ismember(BatchOpt.Dimension{2}, BatchOpt.Dimension{1}), 1)], ...
         BatchOpt.DeletePosition}, ...
        'Delete slice/frame', dlgOpt);
    if isempty(answer); return; end

    if isnan(str2num(answer{2})) %#ok<ST2NM>
        utils.dlgs.showErrorDialog(obj.getProgressBarParent(), 'Wrong number format!', 'Error');
        return;
    end

    BatchOpt.Dimension(1)    = answer(1);
    BatchOpt.DeletePosition  = answer{2};
end

%%
deletePositions = str2num(BatchOpt.DeletePosition); %#ok<ST2NM>
deletePositions(deletePositions == 0) = maxSlice;   % 0 = last slice/frame

dsOpts.showWaitbar  = BatchOpt.showWaitbar;
dsOpts.ParentFigure = obj.mibGUI;
result = obj.I{BatchOpt.id}.deleteSlice(deletePositions, orientation, dsOpts);
if result == 0; notify(obj, 'StopProtocol'); return; end

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'NewDataset', core.ToggleEventData(struct('index', obj.getActiveId(), 'keepBackup', true)));
notify(obj, 'ShowImage');
end
