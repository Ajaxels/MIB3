function invertMask(obj, type, sel_switch, BatchOptIn)
% INVERTMASK - Invert the Mask or Selection layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.invertMask(type)
%       obj.invertMask(type, sel_switch)
%       obj.invertMask(type, sel_switch, BatchOptIn)
%
% Inverts the binary content of the mask or selection layer for the chosen
% scope (single slice, current z-stack, or full 4D dataset).  For standard
% (non-packed) datasets the inversion is ``1 - data``; for MibLabels63
% packed datasets the relevant bit (bit 7 for mask, bit 8 for selection) is
% flipped with ``bitxor``.
%
% Input Arguments:
%   - **type** - char, layer to invert: ``'mask'`` or ``'selection'``;
%     pass ``''`` to default to ``'mask'``
%   - **sel_switch** - *(optional)* char, scope of the inversion; initialises
%     ``BatchOpt.DatasetType``
%
%     - ``'2D, Slice'``   - current slice only *(default)*
%     - ``'3D, Stack'``   - full z-stack at the current time point
%     - ``'4D, Dataset'`` - entire dataset (all z and t)
%
%   - **BatchOptIn** - *(optional)* structure for batch processing mode; when NaN,
%     returns default options via the ``SyncBatch`` event
%
%     - ``.Target`` - cell string, ``{'mask','selection'}``
%     - ``.DatasetType`` - cell string, scope of inversion
%     - ``.showWaitbar`` - logical, show or not the progress dialog
%     - ``.id`` - *(optional)* dataset index 1-9, default = ``obj.getActiveId()``
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** - invert mask on the current slice
%
%   .. code-block:: matlab
%
%      obj.mibModel.invertMask('mask');
%
%   **Example 2** - invert selection across the full z-stack
%
%   .. code-block:: matlab
%
%      obj.mibModel.invertMask('selection', '3D, Stack');
%
%   **Example 3** - invert mask across the full 4D dataset (batch)
%
%   .. code-block:: matlab
%
%      BatchOpt.Target      = {'mask'};
%      BatchOpt.DatasetType = {'4D, Dataset'};
%      BatchOpt.showWaitbar = false;
%      obj.mibModel.invertMask('mask', '4D, Dataset', BatchOpt);
%
%   **Example 4** - return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.invertMask('', [], NaN);
%

% Updates
% 02.06.2026 - ported from MIB2 mibController.menuMaskInvert_Callback to
%              MibModel; replaced waitbar with uiprogressdlg; obj.Id ->
%              obj.getActiveId(); Virtual.virtual -> datasetType check;
%              mibDoBackup -> backup; getData/setData MIB3 arg order;
%              modelType ~= 63 -> isa(labels,'core.MibLabels63');
%              mibBatchSectionName 'Menu ->' -> 'Ribbon ->'
% 02.06.2026 - added sel_switch / DatasetType parameter for scoped inversion

if nargin < 4; BatchOptIn = struct(); end
if nargin < 3; sel_switch = []; end
if nargin < 2; type = []; end

%% Default BatchOpt
BatchOpt = struct();
if ~isempty(type)
    BatchOpt.Target = {type};
else
    BatchOpt.Target = {'mask'};
end
BatchOpt.Target{2} = {'mask', 'selection'};

if ~isempty(sel_switch)
    BatchOpt.DatasetType = {sel_switch};
else
    BatchOpt.DatasetType = {'2D, Slice'};
end
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};

BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

switch BatchOpt.Target{1}
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Invert mask';
    case 'selection'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Selection';
        BatchOpt.mibBatchActionName  = 'Invert selection';
end

BatchOpt.mibBatchTooltip.Target      = 'Layer to be inverted';
BatchOpt.mibBatchTooltip.DatasetType = 'Specify whether to invert the current slice (2D, Slice), the stack (3D, Stack), or complete dataset (4D, Dataset)';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress dialog during execution';

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isscalar(BatchOptIn) && isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    else
        ErrorDlgOpt.winTitle       = 'BatchOpt Error';
        ErrorDlgOpt.optionalPrefix = 'Error in MibModel.invertMask';
        ErrorDlgOpt.err            = 'A structure as the 3rd parameter is required!';
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

%% Guard: selection disabled
if obj.I{BatchOpt.id}.enableSelection == 0
    notify(obj, 'StopProtocol');
    return;
end

%% Guard: virtual stacking mode not supported
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), ...
        '!!! Warning !!!', ...
        {''}, {'Invert action is not yet available in the virtual stacking mode. Please switch to the memory-resident mode and try again.'}, ...
        'Not Implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Guard: no mask to invert
if strcmp(BatchOpt.Target{1}, 'mask')
    if obj.I{BatchOpt.id}.maskExist == 0; return; end
end

%% Demote 4D to 3D when dataset has only one time point
if strcmp(BatchOpt.DatasetType{1}, '4D, Dataset') && obj.I{BatchOpt.id}.image.time == 1
    BatchOpt.DatasetType{1} = '3D, Stack';
end

%% Backup
getDataOptions.id = BatchOpt.id;

if ~batchModeSwitch
    switch3d = ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice');
    obj.backup(BatchOpt.Target{1}, switch3d, getDataOptions);
end

%% Waitbar
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', 'Please wait...', ...
        'Title', sprintf('Inverting the %s', BatchOpt.Target{1}));
end

%% Invert
isPacked = isa(obj.I{BatchOpt.id}.labels, 'core.MibLabels63');
if isPacked
    if strcmp(BatchOpt.Target{1}, 'mask')
        bitxorValue = uint8(64);    % bit 7: mask
    else
        bitxorValue = uint8(128);   % bit 8: selection
    end
end

switch BatchOpt.DatasetType{1}
    case '2D, Slice'
        if ~isPacked
            sliceData = cell2mat(obj.getData2D(BatchOpt.Target{1}, [], [], [], getDataOptions));
            sliceData = 1 - sliceData;
            obj.I{BatchOpt.id}.setData2D(sliceData, BatchOpt.Target{1}, [], [], [], getDataOptions);
        else
            sliceData = cell2mat(obj.getData2D('everything', [], [], [], getDataOptions));
            sliceData = bitxor(sliceData, bitxorValue);
            obj.I{BatchOpt.id}.setData2D(sliceData, 'everything', [], [], [], getDataOptions);
        end

    case '3D, Stack'
        if BatchOpt.showWaitbar; wb.Value = 0.1; end
        if ~isPacked
            stackData = cell2mat(obj.getData3D(BatchOpt.Target{1}, [], [], [], getDataOptions));
            if BatchOpt.showWaitbar; wb.Value = 0.5; end
            stackData = 1 - stackData;
            obj.setData3D(stackData, BatchOpt.Target{1}, [], [], [], getDataOptions);
        else
            stackData = cell2mat(obj.getData3D('everything', [], [], [], getDataOptions));
            if BatchOpt.showWaitbar; wb.Value = 0.5; end
            stackData = bitxor(stackData, bitxorValue);
            obj.setData3D(stackData, 'everything', [], [], [], getDataOptions);
        end

    case '4D, Dataset'
        if BatchOpt.showWaitbar; wb.Value = 0.1; end
        if ~isPacked
            layerData = obj.getData4D(BatchOpt.Target{1}, [], [], getDataOptions);
            if BatchOpt.showWaitbar; wb.Value = 0.5; end
            for roiIndex = 1:numel(layerData)
                layerData{roiIndex} = 1 - layerData{roiIndex};
            end
            obj.setData4D(layerData, BatchOpt.Target{1}, [], [], getDataOptions);
        else
            layerData = obj.getData4D('everything', [], [], getDataOptions);
            if BatchOpt.showWaitbar; wb.Value = 0.5; end
            for roiIndex = 1:numel(layerData)
                layerData{roiIndex} = bitxor(layerData{roiIndex}, bitxorValue);
            end
            obj.setData4D(layerData, 'everything', [], [], getDataOptions);
        end
end

if BatchOpt.showWaitbar; delete(wb); end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
