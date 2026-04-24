function importDataset(obj, layerType, BatchOptIn)
% function importDataset(obj, layerType, BatchOptIn)
% Import the image, mask, or model layer from the MATLAB main workspace.
%
% Parameters:
% layerType: a string specifying which layer to import
% @li 'image' - replace the active dataset with an image variable from workspace
% @li 'mask'  - import a mask array from workspace into the active dataset
% @li 'model' - import a model array or struct from workspace into the active dataset
% BatchOptIn: [@em optional] a structure for batch processing mode; when NaN
%   returns a structure with default options via "SyncBatch" event
% @li .LayerType - cell string, {'image'|'mask'|'model'} layer to import
% @li .ImageVariable - string, [image only] workspace variable name for image data, default 'I'
% @li .MetaVariable  - string, [image only] workspace variable name for metadata (containers.Map or dictionary); empty = skip
% @li .MaskVariable  - string, [mask only] workspace variable name for mask data, default 'M'
% @li .ModelVariable - string, [model only] workspace variable name for model data or struct, default 'O'
% @li .showWaitbar - logical, show or not the waitbar
% @li .id - [@em optional] index of the dataset

%|
% @b Examples:
% @code obj.mibModel.importDataset('image');  // import image interactively @endcode
% @code obj.mibModel.importDataset('mask');   // import mask interactively @endcode
% @code
% BatchOpt.MaskVariable = 'myMask';
% BatchOpt.showWaitbar = false;
% obj.mibModel.importDataset('mask', BatchOpt);  // batch import of mask
% @endcode

% Updates
%

if nargin < 3; BatchOptIn = struct(); end
if nargin < 2; layerType = 'image'; end

activeId = obj.getActiveId();

%% Pre-flight checks (before building BatchOpt — fail fast)
if ismember(layerType, {'mask', 'model'})
    if strcmp(obj.I{activeId}.datasetType, 'Virtual')
        toolname = sprintf('Import of %s is', layerType);
        warningBody = sprintf('%s not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again', toolname);
        dlgOpt = struct();
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        dlgOpt.HeaderLines = 1;
        dlgOpt.WindowHeight = 190;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, 'Not implemented!', {''}, {warningBody}, ...
            'MibModel.importDataset: Ops!!!', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
end

if ismember(layerType, {'mask', 'model'})
    if obj.I{activeId}.enableSelection == 0
        dlgOpt = struct();
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        dlgOpt.WindowHeight = 180;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The selection layers are switched off!', {''}, ...
            {sprintf('Make sure that the "Enable selection" option in the Preferences dialog:\nRibbon -> Home -> Preferences\nis set to "yes" and try again...')}, ...
            'Selection layers disabled', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.LayerType    = {layerType};
BatchOpt.LayerType{2} = {'image', 'mask', 'model'};
BatchOpt.id           = activeId;
BatchOpt.showWaitbar  = true;

switch layerType
    case 'image'
        BatchOpt.ImageVariable = 'I';
        BatchOpt.MetaVariable  = '';
        BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
        BatchOpt.mibBatchActionName  = 'Import image from MATLAB';
        BatchOpt.mibBatchTooltip.LayerType     = 'Layer to import from MATLAB workspace';
        BatchOpt.mibBatchTooltip.ImageVariable = 'Name of the numeric variable in the MATLAB workspace';
        BatchOpt.mibBatchTooltip.MetaVariable  = 'Optional: name of a containers.Map or dictionary variable with metadata; leave empty to skip';
        BatchOpt.mibBatchTooltip.showWaitbar   = 'Show or not the progress bar during execution';
    case 'mask'
        BatchOpt.MaskVariable = 'M';
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Import mask from MATLAB';
        BatchOpt.mibBatchTooltip.LayerType    = 'Layer to import from MATLAB workspace';
        BatchOpt.mibBatchTooltip.MaskVariable = 'Name of the numeric variable in the MATLAB workspace';
        BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress bar during execution';
    case 'model'
        BatchOpt.ModelVariable = 'O';
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        BatchOpt.mibBatchActionName  = 'Import model from MATLAB';
        BatchOpt.mibBatchTooltip.LayerType     = 'Layer to import from MATLAB workspace';
        BatchOpt.mibBatchTooltip.ModelVariable = 'Name of the variable in the MATLAB workspace (numeric array or struct with .model, .modelMaterialNames, .modelMaterialColors, .modelType, .labelText fields)';
        BatchOpt.mibBatchTooltip.showWaitbar   = 'Show or not the progress bar during execution';
end

%% Interactive dialog (nargin < 3)
if nargin < 3
    availableVars = evalin('base', 'whos');

    switch BatchOpt.LayerType{1}
        case 'image'
            numericClasses = {'uint8','uint16','uint32','uint64','int8','int16','int32','int64','double','single'};
            idxNum = ismember({availableVars.class}, numericClasses);
            if sum(idxNum) == 0
                utils.dlgs.showErrorDialog(obj.mibGUI, 'No numeric variables found in the MATLAB workspace!', 'Nothing to import');
                return;
            end
            filteredVars = availableVars(idxNum);
            imageVars = {filteredVars.name}';
            imageVarsDetails = imageVars;
            for i = 1:numel(imageVarsDetails)
                imageVarsDetails{i} = sprintf('%s: %s [%s]', filteredVars(i).name, filteredVars(i).class, num2str(filteredVars(i).size));
            end
            % set default to 'I' if present
            defaultImgIdx = find(ismember(imageVars, 'I'), 1);
            if isempty(defaultImgIdx); defaultImgIdx = 1; end

            % meta variables: containers.Map and dictionary
            idxMeta = ismember({availableVars.class}, {'containers.Map', 'dictionary'});
            metaVars = [{'Do not import'}; {availableVars(idxMeta).name}'];
            defaultMetaIdx = find(ismember(metaVars, 'I_meta'), 1);
            if isempty(defaultMetaIdx); defaultMetaIdx = 1; end

            prompts  = {'Image variable (H x W x color x Z x T):', 'Metadata variable (optional):'};
            defAns   = {[imageVarsDetails(:)', {defaultImgIdx}], [metaVars(:)', {defaultMetaIdx}]};
            dlgOpt.WindowHeight = 175;
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defAns, ...
                'Import image from MATLAB', dlgOpt);
            if isempty(answer); return; end

            BatchOpt.ImageVariable = imageVars{selIndex(1)};
            if strcmp(answer{2}, 'Do not import')
                BatchOpt.MetaVariable = '';
            else
                metaVarsNoPrefix = metaVars(2:end);   % strip 'Do not import'
                BatchOpt.MetaVariable = metaVarsNoPrefix{selIndex(2) - 1};
            end

        case 'mask'
            numericClasses = {'uint8','uint16','uint32','uint64','int8','int16','int32','int64','double','single','logical'};
            idxNum = ismember({availableVars.class}, numericClasses);
            if sum(idxNum) == 0
                utils.dlgs.showErrorDialog(obj.mibGUI, 'No numeric variables found in the MATLAB workspace!', 'Nothing to import');
                return;
            end
            filteredVars = availableVars(idxNum);
            maskVars = {filteredVars.name}';
            maskVarsDetails = maskVars;
            for i = 1:numel(maskVarsDetails)
                maskVarsDetails{i} = sprintf('%s: %s [%s]', filteredVars(i).name, filteredVars(i).class, num2str(filteredVars(i).size));
            end
            defaultIdx = find(ismember(maskVars, 'M'), 1);
            if isempty(defaultIdx); defaultIdx = 1; end

            prompts  = {'Mask variable (H x W x Z x T):'};
            defAns   = {[maskVarsDetails(:)', {defaultIdx}]};
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defAns, ...
                'Import mask from MATLAB', struct());
            if isempty(answer); return; end
            BatchOpt.MaskVariable = maskVars{selIndex(1)};

        case 'model'
            modelClasses = {'uint8','uint16','uint32','struct'};
            idxModel = ismember({availableVars.class}, modelClasses);
            if sum(idxModel) == 0
                utils.dlgs.showErrorDialog(obj.mibGUI, 'No suitable variables (uint8/uint16/uint32/struct) found in the MATLAB workspace!', 'Nothing to import');
                return;
            end
            filteredVars = availableVars(idxModel);
            modelVars = {filteredVars.name}';
            modelVarsDetails = modelVars;
            for i = 1:numel(modelVarsDetails)
                modelVarsDetails{i} = sprintf('%s: %s', filteredVars(i).name, filteredVars(i).class);
            end
            defaultIdx = find(ismember(modelVars, 'O'), 1);
            if isempty(defaultIdx); defaultIdx = 1; end

            dlgOpt.PromptLines = 3;
            prompts  = {sprintf('Model variable\n(numeric array or struct with .model,\n.modelMaterialNames, .modelMaterialColors, .modelType):')};
            defAns   = {[modelVarsDetails(:)', {defaultIdx}]};
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defAns, ...
                'Import model from MATLAB', dlgOpt);
            if isempty(answer); return; end
            BatchOpt.ModelVariable = modelVars{selIndex(1)};
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
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.importDataset';
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

%% Import execution
switch BatchOpt.LayerType{1}

    case 'image'
        %% --- load image ---
        try
            img = evalin('base', BatchOpt.ImageVariable);
        catch exception
            utils.dlgs.showErrorDialog(obj.mibGUI, ...
                sprintf('Variable not found in the MATLAB workspace:\n%s', exception.message), 'Missing variable');
            notify(obj, 'StopProtocol'); return;
        end
        if isstruct(img); img = img.data; end   % Amira-style struct

        %% --- convert double or logical to integer ---
        if isa(img, 'double')
            maxVal = max(img(:));
            if     maxVal <= double(intmax('uint8'))
                convertClass = 'uint8';
            elseif maxVal <= double(intmax('uint16'))
                convertClass = 'uint16';
            elseif maxVal <= double(intmax('uint32'))
                convertClass = 'uint32';
            else
                utils.dlgs.showErrorDialog(obj.mibGUI, ...
                    'Cannot convert: double values exceed uint32 range.', 'Conversion error');
                notify(obj, 'StopProtocol'); return;
            end
            convertBtn = utils.dlgs.inputQuestDlg(obj.mibGUI, ...
                sprintf('The variable is in double format.\nConvert to %s and continue?', convertClass), ...
                'Convert', 'Proceed', 'Cancel', 'Proceed');
            if strcmp(convertBtn, 'Cancel'); return; end
            img = cast(img, convertClass);
        elseif islogical(img)
            img = uint8(img);
        end

        %% --- reshape if color channel is missing (3D with dim3 > 3) ---
        if ndims(img) == 3 && size(img, 3) > 3
            reshapeBtn = utils.dlgs.inputQuestDlg(obj.mibGUI, ...
                sprintf('The color-channel dimension appears to be missing.\nMove the 3rd dimension to depth (Z)?'), ...
                'Reshape image', 'Yes', 'No', 'Yes');
            if strcmp(reshapeBtn, 'Yes')
                img = reshape(img, size(img,1), size(img,2), 1, size(img,3));
            end
        end

        %% --- load metadata ---
        if ~isempty(BatchOpt.MetaVariable)
            try
                metaIn = evalin('base', BatchOpt.MetaVariable);
                if isa(metaIn, 'containers.Map')
                    metaIn = dictionary(keys(metaIn), values(metaIn));
                end
            catch
                metaIn = dictionary('Filename', fullfile(obj.currentDirectory, 'import.tif'));
            end
        else
            metaIn = dictionary('Filename', fullfile(obj.currentDirectory, 'import.tif'));
        end

        %% --- initialize dataset with new image ---
        obj.I{BatchOpt.id}.initialize(img, metaIn, 'Standard', 'imageOnly', obj.preferences.System.EnableSelection);

        %% --- notify controllers ---
        eventdata = core.ToggleEventData(BatchOpt.id);
        notify(obj, 'NewDataset', eventdata);
        notify(obj, 'ShowImage');

    case 'mask'
        %% --- load mask ---
        try
            maskData = evalin('base', BatchOpt.MaskVariable);
        catch exception
            utils.dlgs.showErrorDialog(obj.mibGUI, ...
                sprintf('Variable not found in the MATLAB workspace:\n%s', exception.message), 'Missing variable');
            notify(obj, 'StopProtocol'); return;
        end
        if islogical(maskData); maskData = uint8(maskData); end

        %% --- dimension check (H × W must match) ---
        if size(maskData,1) ~= obj.I{BatchOpt.id}.image.height || ...
           size(maskData,2) ~= obj.I{BatchOpt.id}.image.width
            errorMsg = sprintf(['Mask and image dimensions mismatch!\n' ...
                'Image: %d x %d\nMask:  %d x %d'], ...
                obj.I{BatchOpt.id}.image.height, obj.I{BatchOpt.id}.image.width, ...
                size(maskData,1), size(maskData,2));
            utils.dlgs.showErrorDialog(obj.mibGUI, errorMsg, 'Dimensions mismatch');
            notify(obj, 'StopProtocol'); return;
        end

        %% --- backup ---
        backupOptions.blockModeSwitch = 0;
        backupOptions.id = BatchOpt.id;
        obj.backup('mask', 1, backupOptions);

        if BatchOpt.showWaitbar
            progressBar = uiprogressdlg(obj.mibGUI, 'Value', 0.1, ...
                'Message', 'Importing mask...', 'Title', 'Import mask');
        end

        %% --- smart import: 2D / 3D / 4D ---
        setDataOptions.blockModeSwitch = 0;
        setDataOptions.id = BatchOpt.id;
        if size(maskData,3) == 1
            obj.setData2D(maskData, 'mask', [], 3, NaN, setDataOptions);
        elseif size(maskData,3) == obj.I{BatchOpt.id}.image.depth && size(maskData,4) == 1
            obj.setData3D(maskData, 'mask', NaN, 3, NaN, setDataOptions);
        else
            obj.setData4D(maskData, 'mask', 3, NaN, setDataOptions);
        end

        if BatchOpt.showWaitbar; progressBar.Value = 1; delete(progressBar); end

        %% --- show mask ---
        obj.showMask = true;
        notify(obj, 'ShowImage');

    case 'model'
        %% --- load variable ---
        try
            varIn = evalin('base', BatchOpt.ModelVariable);
        catch exception
            utils.dlgs.showErrorDialog(obj.mibGUI, ...
                sprintf('Variable not found in the MATLAB workspace:\n%s', exception.message), 'Missing variable');
            notify(obj, 'StopProtocol'); return;
        end

        %% --- parse struct or numeric ---
        loadOpts = struct();
        loadOpts.showWaitbar = BatchOpt.showWaitbar;
        loadOpts.id = BatchOpt.id;

        if isstruct(varIn)
            modelFieldName = 'model';
            if isfield(varIn, 'modelVariable'); modelFieldName = varIn.modelVariable; end
            modelArray = varIn.(modelFieldName);

            if isfield(varIn, 'modelMaterialNames');  loadOpts.modelMaterialNames  = varIn.modelMaterialNames;  end
            if isfield(varIn, 'modelMaterialColors'); loadOpts.modelMaterialColors = varIn.modelMaterialColors; end
            if isfield(varIn, 'labelText')
                loadOpts.labelText     = varIn.labelText;
                loadOpts.labelPosition = varIn.labelPosition;
                loadOpts.labelValue    = varIn.labelValue;
            end
            if isfield(varIn, 'modelType')
                loadOpts.modelType = varIn.modelType;
            else
                maxVal = double(max(modelArray(:)));
                loadOpts.modelType = 63;
                if maxVal >= 64; loadOpts.modelType = 255; end
            end
        else
            modelArray = varIn;
            maxVal = double(max(modelArray(:)));
            loadOpts.modelType = 63;
            if maxVal >= 64; loadOpts.modelType = 255; end
        end

        %% --- delegate to loadModel ---
        obj.loadModel(modelArray, loadOpts);

        %% --- show model ---
        obj.showModel = true;
        notify(obj, 'ShowImage');
end

%% Notify batch
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
