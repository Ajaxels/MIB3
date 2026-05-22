function copySwapSlice(obj, sourceSlice, targetSlice, mode, BatchOptIn)
% COPYSWAPSLICE - Copy, insert, or swap slice(s) within the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.copySwapSlice(sourceSlice, targetSlice, mode)
%       obj.copySwapSlice(sourceSlice, targetSlice, mode, BatchOptIn)
%
% Batch-compatible dispatcher.  Shows an interactive dialog when called
% without ``BatchOptIn``.  Delegates to ``MibDataset.copySlice``,
% ``MibDataset.insertSlice``, or ``MibDataset.swapSlices``.
% In insert mode the image, labels, mask, and selection layers of the
% source slice are all copied into the newly inserted position.
%
% Input Arguments:
%   - **sourceSlice** — *(optional)* index of the source slice; ``[]`` uses
%     the current slice
%   - **targetSlice** — *(optional)* index of the destination slice; ``[]``
%     uses the current slice
%   - **mode** — *(optional)* one of ``'replace'`` (default), ``'insert'``,
%     or ``'swap'``
%   - **BatchOptIn** — *(optional)* struct for batch processing mode; when
%     ``NaN``, returns default options via the ``SyncBatch`` event.
%
%     - ``.Mode`` — [cell] operation mode (default: ``{'replace'}``).
%       Allowed values: ``{'replace', 'insert', 'swap'}``
%     - ``.SourceSlice`` — [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       index of the source slice
%     - ``.TargetSlice`` — [numeric cell] ``{value, [minLim maxLim], 'on'}``
%       index of the destination slice; for insert mode ``1`` = insert as
%       first slice, ``0`` = append to the end
%     - ``.showWaitbar`` — [logical] show the progress dialog (default: ``true``)
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%
% Usage:
%   **Example 1** — copy slice 4 to slice 10
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.copySwapSlice(4, 10, 'replace');
%
%   **Example 2** — swap slices 4 and 10
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.copySwapSlice(4, 10, 'swap');
%
%   **Example 3** — batch mode
%
%   .. code-block:: matlab
%
%
%     BatchOpt.Mode        = {'replace'};
%     BatchOpt.SourceSlice = {4, [1, 100], 'on'};
%     BatchOpt.TargetSlice = {10, [1, 100], 'on'};
%     obj.mibModel.copySwapSlice([], [], [], BatchOpt);
%

% Updates
%

if nargin < 4; mode = []; end
if nargin < 3; targetSlice = []; end
if nargin < 2; sourceSlice = []; end

activeId = obj.getActiveId();
maxSlice = obj.I{activeId}.dim_yxzct(obj.I{activeId}.orientation);
currentSlice = obj.I{activeId}.getCurrentSliceNumber();

%% populate BatchOpt with default values
BatchOpt = struct();
if ~isempty(mode)
    BatchOpt.Mode = {mode};
else
    BatchOpt.Mode = {'replace'};
end
BatchOpt.Mode{2} = {'replace', 'insert', 'swap'};

sourceVal = currentSlice;
targetVal = currentSlice;
if ~isempty(sourceSlice); sourceVal = sourceSlice; end
if ~isempty(targetSlice); targetVal = targetSlice; end

BatchOpt.SourceSlice = {sourceVal, [1, maxSlice], 'on'};
BatchOpt.TargetSlice = {targetVal, [0, maxSlice], 'on'};
BatchOpt.showWaitbar = true;
BatchOpt.id = activeId;

BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
if strcmp(BatchOpt.Mode{1}, 'swap')
    BatchOpt.mibBatchActionName = 'Slice -> Swap slices';
else
    BatchOpt.mibBatchActionName = 'Slice -> Copy slice';
end
BatchOpt.mibBatchTooltip.Mode        = '"swap": swap two slices; "replace": replace target slice with source slice; "insert": insert source slice before target slice';
BatchOpt.mibBatchTooltip.SourceSlice = 'Index of the source slice';
BatchOpt.mibBatchTooltip.TargetSlice = 'Index of the destination slice; for insert mode 1 = insert as first slice, 0 = append to the end';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

if nargin == 5  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        else
            ErrorDlgOpt.Title = 'Error';
            ErrorDlgOpt.String = 'A structure as the 5th parameter is required!';
            ErrorDlgOpt.Icon = 'puffin_error';
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
        if isfield(BatchOptIn, 'mibBatchTooltip'); end  % batch mode detected implicitly
    end
end

%% define parameters
maxSlice = obj.I{BatchOpt.id}.dim_yxzct(obj.I{BatchOpt.id}.orientation);

% update spinner limits to reflect the actual dataset
BatchOpt.SourceSlice{2} = [1, maxSlice];
BatchOpt.TargetSlice{2} = [0, maxSlice];

if nargin < 5
    if strcmp(BatchOpt.Mode{1}, 'swap')
        textString1 = 'Index of the source slice:';
        textString2 = 'Index of the destination slice:';
    else
        textString1 = 'Index of the source slice:';
        textString2 = sprintf('Index of the destination slice\n(1 = first slice, 0 = append to end):', maxSlice);
    end

    dlgOpt.WindowHeight = 230;
    answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, ...
        sprintf('Slice range: 1 to %d', maxSlice), ...
        {'Replace or insert slice at the destination:', textString1, textString2}, ...
        {[BatchOpt.Mode{2}, find(ismember(BatchOpt.Mode{2}, BatchOpt.Mode{1}), 1)], ...
         struct('Spinner', true, 'Value', BatchOpt.SourceSlice{1}, 'Limits', BatchOpt.SourceSlice{2}, 'Step', 1, 'Round', true), ...
         struct('Spinner', true, 'Value', BatchOpt.TargetSlice{1}, 'Limits', BatchOpt.TargetSlice{2}, 'Step', 1, 'Round', true)}, ...
        'Copy slice', dlgOpt);
    if isempty(answer); return; end

    BatchOpt.Mode(1)        = answer(1);
    BatchOpt.SourceSlice{1} = answer{2};
    BatchOpt.TargetSlice{1} = answer{3};
end

sourceSlice = BatchOpt.SourceSlice{1};
targetSlice = BatchOpt.TargetSlice{1};

% Translate 0 to the logical "end" for each mode:
%   insert  → append after last slice (NaN triggers the clamp in insertSlice)
%   replace / swap → last existing slice
if targetSlice == 0
    if strcmp(BatchOpt.Mode{1}, 'insert')
        targetSlice = NaN;
    else
        targetSlice = maxSlice;
    end
end

%%
switch BatchOpt.Mode{1}
    case 'replace'
        result = obj.I{BatchOpt.id}.copySlice(sourceSlice, targetSlice);
        if result == 0; notify(obj, 'StopProtocol'); return; end

    case 'insert'
        getDataOpt.blockmodeSwitch = 0;
        getDataOpt.id = BatchOpt.id;
        imgSlice = cell2mat(obj.getData2D('image', sourceSlice(1), [], [], getDataOpt));
        % reshape [y, x, colors] → [y, x, 1, colors] so insertSlice
        % treats it as a single depth slice with correct colour count
        img = reshape(imgSlice, [size(imgSlice,1), size(imgSlice,2), 1, size(imgSlice,3)]);

        insertMeta = [];
        if ~isempty(obj.I{BatchOpt.id}.image.sliceName)
            sliceNames = obj.I{BatchOpt.id}.image.sliceName;
            if numel(sliceNames) > 1
                sliceName = sliceNames{sourceSlice(1)};
                [~, fn, ext] = fileparts(sliceName);
                sliceName = [fn '_copy' ext];
                insertMeta = dictionary('SliceName', {cellstr(sliceName)});
            end
        end
        insertOpts.dim          = 'depth';
        insertOpts.showWaitbar  = BatchOpt.showWaitbar;
        insertOpts.ParentFigure = obj.mibGUI;
        obj.I{BatchOpt.id}.insertSlice(img, targetSlice, insertMeta, insertOpts);

        % After insertion the dataset is one slice larger.  Compute:
        %   insertedIdx  — position of the newly inserted empty-label slice
        %   sourceNewIdx — position of the source slice (may have shifted +1)
        if isnan(targetSlice)
            insertedIdx  = maxSlice + 1;   % was appended to the end
            sourceNewIdx = sourceSlice;    % source position unchanged
        else
            insertedIdx  = targetSlice;
            if sourceSlice >= targetSlice
                sourceNewIdx = sourceSlice + 1;  % source shifted right
            else
                sourceNewIdx = sourceSlice;
            end
        end

        % Copy label layers from the (shifted) source into the new slice.
        if obj.I{BatchOpt.id}.modelExist
            labelData = cell2mat(obj.getData2D('labels', sourceNewIdx, [], [], getDataOpt));
            obj.setData2D(labelData, 'labels', insertedIdx, [], [], getDataOpt);
        end
        if obj.I{BatchOpt.id}.maskExist
            maskData = cell2mat(obj.getData2D('mask', sourceNewIdx, [], [], getDataOpt));
            obj.setData2D(maskData, 'mask', insertedIdx, [], [], getDataOpt);
        end
        if obj.I{BatchOpt.id}.selection.exists
            selData = cell2mat(obj.getData2D('selection', sourceNewIdx, [], [], getDataOpt));
            obj.setData2D(selData, 'selection', insertedIdx, [], [], getDataOpt);
        end

        datasetId = BatchOpt.id;
        BatchOpt = rmfield(BatchOpt, 'id');
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        notify(obj, 'NewDataset', core.ToggleEventData(struct('index', datasetId, 'keepBackup', true)));
        notify(obj, 'ShowImage');
        return;

    case 'swap'
        result = obj.I{BatchOpt.id}.swapSlices(sourceSlice, targetSlice);
        if result == 0; notify(obj, 'StopProtocol'); return; end
end

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'ShowImage');
end
