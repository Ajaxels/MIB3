function insertEmptySlice(obj, BatchOptIn)
% INSERTEMPTYSLICE - Insert one or more empty (background-filled) slices into the volume.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertEmptySlice()
%       obj.insertEmptySlice(BatchOptIn)
%
% Batch-compatible dispatcher.  Shows an interactive dialog when called
% without ``BatchOptIn``.  Creates a zero-filled (or background-filled) image
% block of the required size and delegates to ``MibDataset.insertSlice``.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* struct for batch processing mode; when
%     ``NaN``, returns default options via the ``SyncBatch`` event.
%
%     - ``.Dimension`` — [cell] insertion dimension (default: ``{'depth'}``).
%       Allowed values: ``{'depth', 'time'}``
%     - ``.InsertPosition`` — [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       insert before this 1-based slice index; ``1`` = insert as first slice;
%       ``0`` = append to the end (default: current slice)
%     - ``.NumberOfSlices`` — [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       number of slices to insert (default: ``{1, [1, maxSlice], 'on'}``)
%     - ``.BackgroundColor`` — [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       fill intensity, 0 = black (default: ``{maxInt, [0, maxInt], 'on'}``)
%     - ``.showWaitbar`` — [logical] show the progress dialog (default: ``true``)
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%
% Usage:
%   **Example 1** — interactive
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.insertEmptySlice();
%
%   **Example 2** — batch: insert 10 blank time-frames before frame 2
%
%   .. code-block:: matlab
%
%
%     BatchOpt.Dimension       = {'time'};
%     BatchOpt.InsertPosition  = {2, [0, 100], 'on'};
%     BatchOpt.NumberOfSlices  = {10, [1, 100], 'on'};
%     BatchOpt.BackgroundColor = {0, [0, 255], 'on'};
%     obj.mibModel.insertEmptySlice(BatchOpt);
%

% Updates
%

activeId = obj.getActiveId();
maxIntValue = double(obj.I{activeId}.image.maxInt);

%% populate BatchOpt with default values
BatchOpt = struct();
BatchOpt.Dimension    = {'depth'};
BatchOpt.Dimension{2} = {'depth', 'time'};
BatchOpt.InsertPosition  = {obj.I{activeId}.getCurrentSliceNumber(), [0, obj.I{activeId}.dim_yxzct(3)], 'on'};
BatchOpt.NumberOfSlices  = {1, [1, 1000], 'on'};
BatchOpt.BackgroundColor = {maxIntValue, [0, maxIntValue], 'on'};
BatchOpt.showWaitbar     = true;
BatchOpt.id              = activeId;

BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
BatchOpt.mibBatchActionName  = 'Slice -> Insert an empty slice';
BatchOpt.mibBatchTooltip.Dimension       = 'Dimension to which insert an empty slice';
BatchOpt.mibBatchTooltip.InsertPosition  = 'Insert before this 1-based slice index; 1 = insert as first slice; 0 = append to the end';
BatchOpt.mibBatchTooltip.NumberOfSlices  = 'Number of empty slices to insert';
BatchOpt.mibBatchTooltip.BackgroundColor = 'Intensity of the background fill value';
BatchOpt.mibBatchTooltip.showWaitbar     = 'Show or not the progress bar during execution';

if nargin == 2  % batch mode
    if isstruct(BatchOptIn) == 0
        if isscalar(BatchOptIn) && isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        else
            ErrorDlgOpt.winTitle       = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.insertEmptySlice';
            ErrorDlgOpt.err            = 'A structure as the 1st parameter is required!';
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%%
switch BatchOpt.Dimension{1}
    case 'depth'; dimOrient = 3;
    case 'time';  dimOrient = 5;
end
maxIntValue = double(obj.I{BatchOpt.id}.image.maxInt);
maxSlice    = obj.I{BatchOpt.id}.dim_yxzct(dimOrient);

% update spinner limits to reflect the actual dimension and dataset
BatchOpt.InsertPosition{2} = [0, maxSlice];
BatchOpt.NumberOfSlices{2} = [1, maxSlice];
BatchOpt.BackgroundColor{2} = [0, maxIntValue];

%% interactive dialog
if nargin < 2
    dlgOpt.WindowHeight = 300;
    dlgOpt.HeaderLines = 2;
    answer = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
        sprintf('Slice position range: 1 (first) to %d; 0 = append to end', maxSlice), ...
        {'Dimension:', ...
         sprintf('Destination slice index\n(1 = first, %d = last, 0 = append to end):', maxSlice), ...
         'Number of slices to insert:', ...
         sprintf('Background intensity (0 – %d):', maxIntValue)}, ...
        {[BatchOpt.Dimension{2}, find(ismember(BatchOpt.Dimension{2}, BatchOpt.Dimension{1}), 1)], ...
         struct('Spinner', true, 'Value', BatchOpt.InsertPosition{1}, 'Limits', BatchOpt.InsertPosition{2}, 'Step', 1, 'Round', true), ...
         struct('Spinner', true, 'Value', BatchOpt.NumberOfSlices{1}, 'Limits', BatchOpt.NumberOfSlices{2}, 'Step', 1, 'Round', true), ...
         struct('Spinner', true, 'Value', BatchOpt.BackgroundColor{1}, 'Limits', BatchOpt.BackgroundColor{2}, 'Step', 1, 'Round', true)}, ...
        'Insert empty slice(s)', dlgOpt);
    if isempty(answer); return; end

    BatchOpt.Dimension(1)       = answer(1);
    BatchOpt.InsertPosition{1}  = answer{2};
    BatchOpt.NumberOfSlices{1}  = answer{3};
    BatchOpt.BackgroundColor{1} = answer{4};
end

%%
imageHeight = obj.I{BatchOpt.id}.image.height;
imageWidth  = obj.I{BatchOpt.id}.image.width;
imageColors = obj.I{BatchOpt.id}.image.colors;
numSlices   = BatchOpt.NumberOfSlices{1};
bgColor     = BatchOpt.BackgroundColor{1};
dataClass   = obj.I{BatchOpt.id}.image.dataClass;

% shape: [y, x, numSlices, colors] — insertSlice treats 4D as [y,x,z,c,1]
img = zeros([imageHeight, imageWidth, numSlices, imageColors], dataClass) + bgColor;

insertOpts.dim          = BatchOpt.Dimension{1};
insertOpts.BackgroundColorIntensity = bgColor;
insertOpts.showWaitbar  = BatchOpt.showWaitbar;
insertOpts.ParentFigure = obj.mibGUI;
obj.I{BatchOpt.id}.insertSlice(img, BatchOpt.InsertPosition{1}, [], insertOpts);

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'NewDataset', core.ToggleEventData(struct('index', obj.getActiveId(), 'keepBackup', true)));
notify(obj, 'ShowImage');
end
