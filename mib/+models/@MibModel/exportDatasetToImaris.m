function exportDatasetToImaris(obj, layerType, BatchOptIn)
% EXPORTDATASETTOIMARIS - Export the image, mask, or model layer to Imaris via IceImarisConnector.
%
% Syntax:
%   function exportDatasetToImaris(obj, layerType, BatchOptIn)
%
% Input Arguments:
%   - **layerType** — a string specifying which layer to export:
%
%     - ``'image'`` — export image data
%     - ``'mask'`` — export mask layer as a single binary channel
%     - ``'model'`` — export model (labels layer); prompts for material index
%
%   - **BatchOptIn** — *(optional)* a structure for batch processing mode; when ``NaN``
%     returns a structure with default options via "SyncBatch" event:
%
%     - ``.LayerType`` — cell string, ``{'image'|'mask'|'model'}`` layer to export
%     - ``.MaterialIndex`` — string, [model only] material index to export; empty = all materials
%     - ``.showWaitbar`` — logical, show or not the waitbar
%     - ``.id`` — *(optional)* index of the dataset
%
% Usage:
%   **Example 1** — export image interactively
%
%   .. code-block:: matlab
%
%      obj.mibModel.exportDatasetToImaris('image');
%
%   **Example 2** — export mask interactively
%
%   .. code-block:: matlab
%
%      obj.mibModel.exportDatasetToImaris('mask');
%
%   **Example 3** — export first material in batch mode
%
%   .. code-block:: matlab
%
%      BatchOpt.MaterialIndex = '1';
%      obj.mibModel.exportDatasetToImaris('model', BatchOpt);
%

% Updates
%

if nargin < 3; BatchOptIn = struct(); end
if nargin < 2; layerType = 'image'; end

activeId = obj.getActiveId();

%% Pre-flight checks (before building BatchOpt — fail fast)
if strcmp(obj.I{activeId}.datasetType, 'Virtual')
    dlgOpt = struct();
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 190;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'Not implemented!', {''}, ...
        {sprintf('This mode is not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again')}, ...
        'MibModel.exportDatasetToImaris: Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if strcmp(layerType, 'model')
    if obj.I{activeId}.enableSelection == 0
        dlgOpt = struct();
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        dlgOpt.WindowHeight = 180;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The models are switched off!', {''}, ...
            {sprintf('Make sure that the "Enable selection" option in the Preferences dialog:\nRibbon -> Home -> Preferences\nis set to "yes" and try again...')}, ...
            'Models are disabled', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
    if ~obj.I{activeId}.modelExist
        dlgOpt = struct();
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The model is not yet created!', {''}, ...
            {sprintf('Create or load a model first!')}, ...
            'The model is missing!', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.LayerType = {layerType};
BatchOpt.LayerType{2} = {'image', 'mask', 'model'};
BatchOpt.id = activeId;

switch layerType
    case 'image'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
        BatchOpt.mibBatchActionName  = 'Export image to Imaris';
        BatchOpt.mibBatchTooltip.LayerType = 'Layer to export to Imaris';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Export mask to Imaris';
        BatchOpt.mibBatchTooltip.LayerType = 'Layer to export to Imaris';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
    case 'model'
        if obj.I{activeId}.selectedMaterial > 2
            materialIndex = obj.I{activeId}.selectedMaterial - 2;
            if materialIndex <= numel(obj.I{activeId}.labels.materialNames)
                defaultMaterialIndex = num2str(materialIndex);
            else
                defaultMaterialIndex = '';
            end
        else
            defaultMaterialIndex = '';
        end
        BatchOpt.MaterialIndex = defaultMaterialIndex;
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        BatchOpt.mibBatchActionName  = 'Export model to Imaris';
        BatchOpt.mibBatchTooltip.LayerType = 'Layer to export to Imaris';
        BatchOpt.mibBatchTooltip.MaterialIndex = 'Index of material to export; keep empty to export all materials';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
end
BatchOpt.showWaitbar = true;

%% Interactive dialog (nargin < 3)
if nargin < 3
    switch BatchOpt.LayerType{1}
        case 'image'
            % no extra parameters needed — lutColors picked from dataset automatically

        case 'mask'
            % no extra parameters — mask is always a single binary channel

        case 'model'
            dlgOpt = struct();
            dlgOpt.WindowHeight = 155;
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', ...
                {'Material index [empty = export all materials]:'}, ...
                {BatchOpt.MaterialIndex}, ...
                'Export model to Imaris', dlgOpt);
            if isempty(answer); return; end
            BatchOpt.MaterialIndex = answer{1};
    end
end

%% Batch mode check (nargin == 3)
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt = struct();
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.exportDatasetToImaris';
            ErrorDlgOpt.err = 'A structure as the 3rd parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% Build options for setImarisDataset
imarisOptions = struct();
imarisOptions.mibGUI = obj.mibGUI;
imarisOptions.showWaitbar = BatchOpt.showWaitbar;

switch BatchOpt.LayerType{1}
    case 'image'
        imarisOptions.type = 'image';
        imarisOptions.lutColors = obj.I{BatchOpt.id}.image.lutColors;
    case 'mask'
        imarisOptions.type = 'mask';
    case 'model'
        imarisOptions.type = 'labels';
        materialIndex = str2double(BatchOpt.MaterialIndex);  % NaN when empty
        if ~isnan(materialIndex)
            imarisOptions.modelIndex = materialIndex;
        else
            imarisOptions.modelIndex = NaN;  % export all materials
        end
end

%% Export
obj.connImaris = io.imaris.setImarisDataset(obj.I{BatchOpt.id}, obj.connImaris, imarisOptions);

%% Notify batch
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
