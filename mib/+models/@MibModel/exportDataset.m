function exportDataset(obj, layerType, BatchOptIn)
% function exportDataset(obj, layerType, BatchOptIn)
% Export image, mask, or labels layer to the MATLAB main workspace.
%
% Parameters:
% layerType: a string specifying which layer to export
% @li 'image' - export image data with metadata (and colormap if indexed)
% @li 'mask' - export mask layer as a uint8 array
% @li 'model' - export model (labels) as a struct with material info
% BatchOptIn: [@em optional] a structure for batch processing mode; when NaN
%   returns a structure with default options via "SyncBatch" event
% @li .LayerType - cell string, {'image'|'mask'|'model'} layer to export
% @li .ImageVariable - string, [image only] workspace variable name for image data, default 'I'
% @li .ColormapVariable - string, [image only, indexed color] variable name for colormap, default 'cmap'
% @li .MaskVariable - string, [mask only] workspace variable name for mask, default 'M'
% @li .LabelsVariable - string, [model only] workspace variable name for labels struct, default 'O'
% @li .MaterialIndex - string, [model only] index of material to export; empty = whole model
% @li .MaterialOutputIndex - string, [model only] value assigned to single material export, default '1'
% @li .showWaitbar - logical, show or not the waitbar
% @li .id - [@em optional] index of the dataset

%|
% @b Examples:
% @code obj.mibModel.exportDataset('image'); // export image interactively @endcode
% @code obj.mibModel.exportDataset('mask');  // export mask interactively @endcode
% @code
% BatchOpt.MaskVariable = 'myMask';
% BatchOpt.showWaitbar = false;
% obj.mibModel.exportDataset('mask', BatchOpt); // export mask in batch mode
% @endcode

% Updates
%

if nargin < 3; BatchOptIn = struct(); end
if nargin < 2; layerType = 'image'; end

activeId = obj.getActiveId();

%% Pre-flight checks (before building BatchOpt — fail fast)
if ismember(layerType, {'mask', 'model'})
    if strcmp(obj.I{activeId}.datasetType, 'Virtual') == 1
        toolname = sprintf('Export of %s is', layerType);
        warningBody = sprintf('%s not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again', toolname);
        dlgOpt = struct();
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        dlgOpt.HeaderLines = 1;
        dlgOpt.WindowHeight = 190;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, 'Not implemented!', {''}, {warningBody}, 'MibModel.exportDataset: Ops!!!', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
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
        BatchOpt.ImageVariable = 'I';
        BatchOpt.ColormapVariable = 'cmap';
        BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
        BatchOpt.mibBatchActionName  = 'Export image to MATLAB';
        BatchOpt.mibBatchTooltip.LayerType = 'Layer to export to MATLAB workspace';
        BatchOpt.mibBatchTooltip.ImageVariable = 'Name of the variable to be created in the MATLAB workspace for the image';
        BatchOpt.mibBatchTooltip.ColormapVariable = '[Indexed color images only] Name of the variable for the colormap';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
    case 'mask'
        BatchOpt.MaskVariable = 'M';
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Export mask to MATLAB';
        BatchOpt.mibBatchTooltip.LayerType = 'Layer to export to MATLAB workspace';
        BatchOpt.mibBatchTooltip.MaskVariable = 'Name of the variable to be created in the MATLAB workspace';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
    case 'model'
        if obj.I{activeId}.selectedMaterial > 2
            materialIndex = obj.I{activeId}.selectedMaterial - 2;
            if materialIndex <= numel(obj.I{activeId}.labels.materialNames)
                defaultVariable = ['Export_' obj.I{activeId}.labels.materialNames{materialIndex}];
            else
                defaultVariable = 'O';
            end
        else
            defaultVariable = 'O';
        end
        BatchOpt.LabelsVariable      = defaultVariable;
        BatchOpt.MaterialIndex       = '';
        BatchOpt.MaterialOutputIndex = '1';
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        BatchOpt.mibBatchActionName  = 'Export model to MATLAB';
        BatchOpt.mibBatchTooltip.LayerType = 'Layer to export to MATLAB workspace';
        BatchOpt.mibBatchTooltip.LabelsVariable = 'Name of the output structure to be created in the MATLAB workspace';
        BatchOpt.mibBatchTooltip.MaterialIndex = 'Index of material to export; keep empty to export the whole model';
        BatchOpt.mibBatchTooltip.MaterialOutputIndex = 'When a single material is exported, this value is assigned to it [typical values: 1 or 255]';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
end
BatchOpt.showWaitbar = true;

%% Interactive dialog (nargin < 3)
if nargin < 3
    switch BatchOpt.LayerType{1}
        case 'image'
            colorType = obj.I{BatchOpt.id}.image.colorType;
            dlgOpt.WindowHeight = 160;
            if strcmp(colorType, 'indexed')
                prompts = {'Variable for the image:'; 'Variable for the colormap:'};
                defaultAnswers = {BatchOpt.ImageVariable; BatchOpt.ColormapVariable};
            else
                prompts = {'Variable for the image:'};
                defaultAnswers = {BatchOpt.ImageVariable};
            end
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defaultAnswers, 'Export image to MATLAB', dlgOpt);
            if isempty(answer); return; end
            BatchOpt.ImageVariable = answer{1};
            if numel(answer) == 2
                BatchOpt.ColormapVariable = answer{2};
            end

        case 'mask'
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', {'Variable for the mask image:'}, {BatchOpt.MaskVariable}, 'Export mask to MATLAB', struct());
            if isempty(answer); return; end
            BatchOpt.MaskVariable = answer{1};

        case 'model'
            prompts = {'Output variable:'; 'Material index [empty = export whole model]:'; 'Output material index [when single material exported]:'};
            defaultAnswers = {BatchOpt.LabelsVariable; BatchOpt.MaterialIndex; BatchOpt.MaterialOutputIndex};
            dlgOpt.WindowHeight = 190;
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defaultAnswers, 'Export model to MATLAB', dlgOpt);
            if isempty(answer); return; end
            BatchOpt.LabelsVariable      = answer{1};
            BatchOpt.MaterialIndex       = answer{2};
            BatchOpt.MaterialOutputIndex = answer{3};
    end
end

%% Batch mode check actions
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt = struct();
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.exportDataset';
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

%% Export
getDataOptions.blockModeSwitch = 0;
getDataOptions.id = BatchOpt.id;

switch BatchOpt.LayerType{1}
    case 'image'
        colorType = obj.I{BatchOpt.id}.image.colorType;
        if ~strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
            imageData = obj.I{BatchOpt.id}.image.data{1};
        else
            imageData = cell2mat(obj.getData4D('image', 3, NaN, getDataOptions));
        end
        assignin('base', BatchOpt.ImageVariable, imageData);
        imageMeta = obj.I{BatchOpt.id}.image.getMeta();
        assignin('base', [BatchOpt.ImageVariable '_meta'], imageMeta);
        disp(['Image export: created [' BatchOpt.ImageVariable '] and [' BatchOpt.ImageVariable '_meta] variables in the MATLAB workspace']);
        if strcmp(colorType, 'indexed')
            assignin('base', BatchOpt.ColormapVariable, obj.I{BatchOpt.id}.image.colormap);
            disp(['Image export: created variable [' BatchOpt.ColormapVariable '] in the MATLAB workspace']);
        end

    case 'mask'
        if BatchOpt.showWaitbar
            waitbar = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
                'Message', 'Exporting the mask...', ...
                'Title', 'Export mask');
        end
        if BatchOpt.showWaitbar; waitbar.Value = 0.05; end
        maskData = cell2mat(obj.getData4D('mask', 3, NaN, getDataOptions));
        assignin('base', BatchOpt.MaskVariable, maskData);
        if BatchOpt.showWaitbar; waitbar.Value = 1; delete(waitbar); end
        disp(['Mask export: created variable [' BatchOpt.MaskVariable '] in the MATLAB workspace']);

    case 'model'
        materialIndex = str2double(BatchOpt.MaterialIndex);   % NaN when MaterialIndex is ''
        if BatchOpt.showWaitbar
            waitbar = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
                'Message', 'Exporting the model...', ...
                'Title', 'Export model');
        end
        rawLabels = obj.getData4D('labels', 3, materialIndex, getDataOptions);
        if BatchOpt.showWaitbar; waitbar.Value = 0.4; end

        outputStruct.model = cell2mat(rawLabels);
        outputStruct.modelMaterialNames  = obj.I{BatchOpt.id}.labels.materialNames;
        outputStruct.modelMaterialColors = obj.I{BatchOpt.id}.labels.materialColors;
        outputStruct.modelType           = obj.I{BatchOpt.id}.labels.maxMaterials;

        if ~isnan(materialIndex)
            materialOutputIndex = str2double(BatchOpt.MaterialOutputIndex);
            if materialOutputIndex ~= 1
                outputStruct.model = outputStruct.model * materialOutputIndex;
            end
            if materialIndex <= numel(outputStruct.modelMaterialNames)
                outputStruct.modelMaterialNames  = outputStruct.modelMaterialNames(materialIndex);
                outputStruct.modelMaterialColors = outputStruct.modelMaterialColors(materialIndex, :);
            end
        end

        % include annotations if present
        if ~isempty(obj.I{BatchOpt.id}.annotations.labelText)
            outputStruct.labelText     = obj.I{BatchOpt.id}.annotations.labelText;
            outputStruct.labelValue    = obj.I{BatchOpt.id}.annotations.labelValue;
            outputStruct.labelPosition = obj.I{BatchOpt.id}.annotations.labelPosition;
        end

        if BatchOpt.showWaitbar; waitbar.Value = 0.9; end
        assignin('base', BatchOpt.LabelsVariable, outputStruct);
        if BatchOpt.showWaitbar; waitbar.Value = 1; delete(waitbar); end
        disp(['Model export: created structure [' BatchOpt.LabelsVariable '] in the MATLAB workspace']);
end

%% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
