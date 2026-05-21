function status = changeImageMode(obj, BatchOptIn)
% CHANGEIMAGEMODE - Convert the active dataset to a different image mode or bit depth.
%
% Syntax:
%   .. code-block:: matlab
%
%       status = obj.changeImageMode(BatchOptIn)
%
% Orchestrates image format conversion for the active MibDataset.  Validates
% preconditions (virtual mode, selection enabled), takes an undo backup, handles
% the multi-channel LUT blending confirmation dialog, then delegates to
% ``core.MibImage.convertImage``.  Fully batch-compatible.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when ``NaN``,
%     returns default options via the ``SyncBatch`` event
%
%     - ``.Target`` — cell string, ``{'Grayscale'}`` with allowed values
%       ``{'Grayscale','Multi-channel','HSV color','Indexed','8 bit','16 bit','32 bit'}``
%     - ``.showWaitbar`` — logical, show or not the progress dialog
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%
% Output Arguments:
%   - **status** — ``1`` on success, ``0`` on failure or user cancel
%
% **Example 1** — convert current dataset to grayscale
%
%   .. code-block:: matlab
%
%      obj.mibModel.changeImageMode();
%
% **Example 2** — cast to 8-bit via batch call
%
%   .. code-block:: matlab
%
%      BatchOpt.Target = {'8 bit'};
%      BatchOpt.showWaitbar = false;
%      obj.mibModel.changeImageMode(BatchOpt);
%
% **Example 3** — return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.changeImageMode(NaN);
%

% Updates
% 

status = 0;
if nargin < 2; BatchOptIn = struct(); end

%% Default BatchOpt
BatchOpt = struct();
BatchOpt.Target = {'Grayscale'};
BatchOpt.Target{2} = {'Grayscale', 'Multi-channel', 'HSV color', 'Indexed', '8 bit', '16 bit', '32 bit'};
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
BatchOpt.mibBatchActionName  = 'Mode';
BatchOpt.mibBatchTooltip.Target       = 'Target image format or bit depth';
BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress dialog';

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    else
        ErrorDlgOpt.Title  = 'BatchOpt Error';
        ErrorDlgOpt.String = 'A structure as the 1st parameter is required!';
        ErrorDlgOpt.Icon   = 'puffin_error';
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

%% Guard: virtual stacking mode
if strcmp(obj.I{BatchOpt.id}.image.type, 'virtual')
    if ~batchModeSwitch
        warnOpt.MsgBoxOnly = true;
        warnOpt.Icon = 'puffin_warning';
        warnOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, ...
            sprintf('!!! Warning !!!\n\nThe image conversion tools are not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again'), ...
            {}, {}, 'Not implemented', warnOpt);
    end
    notify(obj, 'StopProtocol');
    return;
end

%% Backup (single time point only, non-batch to avoid redundant undo entries)
if obj.I{BatchOpt.id}.image.time < 2 && ~batchModeSwitch
    backupOpt.id = BatchOpt.id;
    obj.backup('image', 1, backupOpt);
end

%% LUT check for multichannel (>3 ch) → Grayscale or Indexed
lutChanged = false;
if strcmp(obj.I{BatchOpt.id}.image.colorType, 'multichannel') && obj.I{BatchOpt.id}.image.colors > 3
    if ismember(BatchOpt.Target{1}, {'Grayscale', 'Indexed'})
        if ~batchModeSwitch
            button = utils.dlgs.inputQuestDlg(obj.mibGUI, ...
                sprintf('!!! Attention !!!\n\nDirect conversion of the multichannel image to greyscale is not possible\nHowever it is possible to perform conversion using the LUT colors'), ...
                'Multiple color channels', 'Convert', 'Cancel', 'Cancel');
            if strcmp(button, 'Cancel'); notify(obj, 'StopProtocol'); return; end
            if obj.I{BatchOpt.id}.useLUT == 0
                utils.dlgs.showErrorDialog(obj.mibGUI, ...
                    'Please make sure that the LUT checkbox in the View settings panel is checked!', ...
                    'LUT is not selected');
                return;
            end
        end
        obj.I{BatchOpt.id}.useLUT = 0;
        lutChanged = true;
    end
end

%% Map Target string to convertImage format string
formatMap = dictionary( ...
    {'Grayscale', 'Multi-channel', 'HSV color', 'Indexed', '8 bit', '16 bit', '32 bit'}, ...
    {'grayscale', 'multichannel',  'hsvcolor',  'indexed', 'uint8', 'uint16', 'uint32'});
formatString = formatMap(BatchOpt.Target{1});

%% Call core converter
convertOpt.showWaitbar            = BatchOpt.showWaitbar;
convertOpt.parentFigure           = obj.mibGUI;
convertOpt.selectedColorChannels  = obj.I{BatchOpt.id}.slices{4};
status = obj.I{BatchOpt.id}.image.convertImage(formatString, convertOpt);

if status == 0
    notify(obj, 'StopProtocol');
    return;
end

%% Sync MibDataset state: reset displayed color channels to all
obj.I{BatchOpt.id}.slices{4} = 1:obj.I{BatchOpt.id}.image.colors;

%% Notify batch system and refresh display
BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));

updatePanels = {'ribbonImage'};
if lutChanged; updatePanels{end+1} = 'selectionPanel'; end
notify(obj, 'UpdateGuiWidgets', core.ToggleEventData(updatePanels));
notify(obj, 'ShowImage');
end
