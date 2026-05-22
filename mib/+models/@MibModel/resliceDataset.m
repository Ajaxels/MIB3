function resliceDataset(obj, sliceNumbers, orientation, BatchOptIn)
% RESLICEDATASET - Keep only specified slices; remove all others (stride-reslicing).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.resliceDataset()
%       obj.resliceDataset(sliceNumbers)
%       obj.resliceDataset(sliceNumbers, orientation)
%       obj.resliceDataset(sliceNumbers, orientation, BatchOptIn)
%
% Batch-compatible dispatcher.  Shows an interactive dialog when called
% without ``BatchOptIn``.  Accepts MATLAB range expressions such as
% ``'1:10:end'`` in the ``SliceNumbers`` field.  Delegates to
% ``MibDataset.resliceDataset``.
%
% Input Arguments:
%   - **sliceNumbers** — *(optional)* index vector of slices to keep, or
%     ``[]`` for interactive input
%   - **orientation** — *(optional)* dimension to reslice:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z).
%     Default: ``obj.orientation`` of the active dataset
%   - **BatchOptIn** — *(optional)* struct for batch processing mode; when
%     ``NaN``, returns default options via the ``SyncBatch`` event.
%
%     - ``.Dimension`` — [cell] reslice dimension (default: ``{'depth'}``).
%       Allowed values: ``{'height', 'width', 'depth'}``
%     - ``.SliceNumbers`` — [string] MATLAB index expression; ``'end'`` is
%       substituted with the actual maximum (default: ``'1:2:end'``)
%     - ``.showWaitbar`` — [logical] show the progress dialog (default: ``true``)
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%
% Usage:
%   **Example 1** — interactive
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.resliceDataset();
%
%   **Example 2** — keep every 10th z-slice via batch
%
%   .. code-block:: matlab
%
%
%     BatchOpt.Dimension    = {'depth'};
%     BatchOpt.SliceNumbers = '1:10:end';
%     obj.mibModel.resliceDataset([], [], BatchOpt);
%

% Updates
%

if nargin < 3; orientation  = []; end
if nargin < 2; sliceNumbers = []; end

%% populate BatchOpt with default values
BatchOpt    = struct();
BatchOpt.id = obj.getActiveId();

if isempty(orientation); orientation = obj.I{BatchOpt.id}.orientation; end
if orientation == 0;     orientation = obj.I{BatchOpt.id}.orientation; end

switch orientation
    case 1; BatchOpt.Dimension = {'height'};
    case 2; BatchOpt.Dimension = {'width'};
    case 3; BatchOpt.Dimension = {'depth'};
    otherwise
        utils.dlgs.showErrorDialog(obj.mibGUI, ...
            sprintf('MibModel.resliceDataset: unsupported orientation %d', orientation), 'Error');
        notify(obj, 'StopProtocol');
        return;
end
BatchOpt.Dimension{2} = {'height', 'width', 'depth'};

if isempty(sliceNumbers)
    BatchOpt.SliceNumbers = '1:2:end';
else
    BatchOpt.SliceNumbers = num2str(sliceNumbers);
end
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
BatchOpt.mibBatchActionName  = 'Slice -> Stride reslicing';
BatchOpt.mibBatchTooltip.Dimension    = 'Dimension to reslice';
BatchOpt.mibBatchTooltip.SliceNumbers = 'Indices of slices to keep, for example: "1, 10:10:end"';
BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress bar during execution';

if nargin == 4  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        else
            ErrorDlgOpt.Title = 'Error';
            ErrorDlgOpt.String = 'A structure as the 4th parameter is required!';
            ErrorDlgOpt.Icon = 'puffin_error';
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
end
maxSlice = obj.I{BatchOpt.id}.dim_yxzct(orientation);

%% interactive dialog
if nargin < 4
    dlgOpt.WindowHeight = 180;
    answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, ...
        sprintf('Slice range: 1:%d  (all others will be deleted)', maxSlice), ...
        {'Dimension:', 'Slice index(es) to keep (e.g. 1, 5, 10, 20:30, 50:5:end):'}, ...
        {[BatchOpt.Dimension{2}, find(ismember(BatchOpt.Dimension{2}, BatchOpt.Dimension{1}), 1)], ...
         BatchOpt.SliceNumbers}, ...
        'Reslice dataset', dlgOpt);
    if isempty(answer); return; end

    BatchOpt.Dimension(1) = answer(1);
    BatchOpt.SliceNumbers = answer{2};
end

%%
sliceStr = strrep(BatchOpt.SliceNumbers, 'end', num2str(maxSlice));
keepSlices = str2num(sliceStr); %#ok<ST2NM>

if isempty(keepSlices)
    utils.dlgs.showErrorDialog(obj.mibGUI, 'Wrong slice number format!', 'Error');
    return;
end

dsOpts.showWaitbar  = BatchOpt.showWaitbar;
dsOpts.ParentFigure = obj.mibGUI;
result = obj.I{BatchOpt.id}.resliceDataset(keepSlices, orientation, dsOpts);
if result == 0; notify(obj, 'StopProtocol'); return; end

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'NewDataset', core.ToggleEventData(struct('index', obj.getActiveId(), 'keepBackup', true)));
notify(obj, 'ShowImage');
end
