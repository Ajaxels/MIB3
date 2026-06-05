function invertImage(obj, datasetType, BatchOptIn)
% INVERTIMAGE - Invert pixel intensities in the image dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.invertImage()
%       obj.invertImage(datasetType)
%       obj.invertImage(datasetType, BatchOptIn)
%
% Inverts all or selected color channels of the current dataset across
% the chosen scope (single slice, current z-stack, or complete 4D volume).
%
% For 3D and 4D scopes, inversion is performed by a vectorised call to
% ``MibImage.invertColorChannel``.  For the 2D (single-slice) scope,
% ``getData2D`` / ``setData2D`` are used so that ROI masking and arbitrary
% viewing orientation are handled correctly.
%
% Input Arguments:
%   - **datasetType** — *(optional)* char, pre-sets ``BatchOpt.DatasetType{1}``;
%     pass ``[]`` or omit to use the BatchOptIn value or the default ``'2D, Slice'``.
%     One of: ``'2D, Slice'``, ``'3D, Stack'``, ``'4D, Dataset'``.
%     Pass ``NaN`` to return default options via the ``SyncBatch`` event.
%   - **BatchOptIn** — *(optional)* structure for batch processing mode
%
%     - ``.DatasetType`` — cell string, scope of inversion
%       (default ``{'2D, Slice'}``); values:
%       ``{'2D, Slice', '3D, Stack', '4D, Dataset'}``
%     - ``.ColorChannels`` — cell string, channels to invert
%       (default ``{'Shown channels'}``); values:
%       ``{'Shown channels', 'All channels'}``
%     - ``.showWaitbar`` — logical, show the progress dialog (default ``true``)
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** — invert shown channels on the current slice
%
%   .. code-block:: matlab
%
%      obj.mibModel.invertImage();
%
%   **Example 2** — pre-select 3D mode (controller calls this from the menu)
%
%   .. code-block:: matlab
%
%      obj.mibModel.invertImage('3D, Stack');
%
%   **Example 3** — invert all channels across the full dataset (batch)
%
%   .. code-block:: matlab
%
%      BatchOpt.ColorChannels = {'All channels'};
%      BatchOpt.showWaitbar   = true;
%      obj.mibModel.invertImage('4D, Dataset', BatchOpt);
%
%   **Example 4** — return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.invertImage(NaN);

% Updates
% 2026-05-24 — ported from MIB2 mibModel.invertImage / menuImageInvert_Callback;
%              replaced waitbar with uiprogressdlg; orientation 4->3;
%              3D/4D inversion delegates to MibImage.invertColorChannel

if nargin < 2; datasetType = []; end
if nargin < 3; BatchOptIn = struct(); end

% Handle invertImage(NaN) — NaN passed positionally as datasetType means SyncBatch
if ~ischar(datasetType) && ~isempty(datasetType) && isscalar(datasetType) && isnan(datasetType)
    BatchOptIn  = NaN;
    datasetType = [];
end

%% Default BatchOpt
BatchOpt = struct();
BatchOpt.DatasetType = {'2D, Slice'};
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.ColorChannels = {'Shown channels'};
BatchOpt.ColorChannels{2} = {'Shown channels', 'All channels'};
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
BatchOpt.mibBatchActionName  = 'Invert image';

BatchOpt.mibBatchTooltip.DatasetType   = 'Scope: shown slice (2D), current z-stack (3D), or whole dataset (4D)';
BatchOpt.mibBatchTooltip.ColorChannels = 'Channels to invert: currently shown channels or all channels';
BatchOpt.mibBatchTooltip.showWaitbar   = 'Show or not the progress dialog during execution';

%% Apply datasetType shortcut
if ~isempty(datasetType) && ischar(datasetType)
    BatchOpt.DatasetType{1} = datasetType;
end

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    else
        ErrorDlgOpt.winTitle        = 'Error in MibModel.invertImage';
        ErrorDlgOpt.optionalPrefix  = 'Wrong input parameter!';
        ErrorDlgOpt.err             = 'A structure as the 2nd parameter is required!';
        ErrorDlgOpt.WindowHeight    = 150;
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

%% Guard: virtual dataset
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_error';
    dlgOpt.WindowHeight = 160;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', {''}, ...
        {'Image invert is not yet available in the virtual stacking mode. Please switch to the memory-resident mode and try again.'}, ...
        'invertImage: Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

tic;

%% Demote 4D → 3D when only one time point
if strcmp(BatchOpt.DatasetType{1}, '4D, Dataset') && obj.I{BatchOpt.id}.image.time == 1
    BatchOpt.DatasetType{1} = '3D, Stack';
end

%% Resolve color channels
% colChannels      — for invertColorChannel: 0 = all channels, vector = specific
% colChannelsGetSet — for getData2D/setData2D: NaN = all, [] = shown
if strcmp(BatchOpt.ColorChannels{1}, 'All channels')
    colChannels       = 0;
    colChannelsGetSet = NaN;
else
    colChannels       = obj.I{BatchOpt.id}.slices{4};
    colChannelsGetSet = [];
end

%% Backup (skipped for 4D and in batch mode)
getDataOptions.id = BatchOpt.id;
if ~batchModeSwitch
    switch BatchOpt.DatasetType{1}
        case '2D, Slice'
            obj.backup('image', 0, getDataOptions);
        case '3D, Stack'
            obj.backup('image', 1, getDataOptions);
        % 4D: no backup — too expensive for large datasets
    end
end

%% Perform inversion
imOptions.showWaitbar  = BatchOpt.showWaitbar;
imOptions.ParentFigure = obj.mibGUI;

switch BatchOpt.DatasetType{1}
    case '2D, Slice'
        imageData = obj.getData2D('image', [], [], colChannelsGetSet, getDataOptions);
        maxIntValue = obj.I{BatchOpt.id}.image.maxInt;
        for roiIndex = 1:numel(imageData)
            imageData{roiIndex} = maxIntValue - imageData{roiIndex};
        end
        obj.I{BatchOpt.id}.setData2D(imageData, 'image', [], [], colChannelsGetSet, getDataOptions);

    case '3D, Stack'
        t1 = obj.I{BatchOpt.id}.slices{5}(1);
        t2 = obj.I{BatchOpt.id}.slices{5}(2);
        imOptions.tRange = [t1, t2];
        obj.I{BatchOpt.id}.image.invertColorChannel(colChannels, imOptions);

    case '4D, Dataset'
        imOptions.tRange = [1, obj.I{BatchOpt.id}.image.time];
        obj.I{BatchOpt.id}.image.invertColorChannel(colChannels, imOptions);
end

if ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice'); toc; end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end
