function createModel(obj, ModelType, ModelMaterialNames, BatchOptIn)
% function createModel(obj, ModelType, ModelMaterialNames, BatchOptIn)
% Create a new model — wrapper around core.MibDataset.createModel
%
% Parameters:
% ModelType: [@em optional], can be empty: []; a number with the model type:
% @li 63 - 63 material model
% @li 255 - 255 material model
% @li 65535 - 65535 material model
% @li 4294967295 - 4294967295 material model
% ModelMaterialNames: [@em optional] can be empty: []; a cell array with
%   names of materials; not used for ModelType > 255
% BatchOptIn: a structure for batch processing mode; when NaN, returns a
%   structure with default options via "SyncBatch" event
% @li .ModelType - cell string, {'63', '255', '65535', '4294967295'}
% @li .ModelMaterialNames - string with semicolon-separated material names
% @li .showWaitbar - logical, show or not the waitbar
% @li .id -> [@em optional], dataset index from 1 to 9, default = obj.id
%
% Return values:
%

%|
% @b Examples:
% @code obj.mibModel.createModel();     // create a new model @endcode

% Updates
% Ported from MIB2 mibModel.createModel

if nargin < 3; ModelMaterialNames = []; end
if nargin < 2; ModelType = []; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(ModelType)
    BatchOpt.ModelType = {num2str(ModelType)};
else
    BatchOpt.ModelType = {'63'};
end
BatchOpt.ModelType{2} = {'63', '255', '65535', '4294967295'};
if ~isempty(ModelMaterialNames)
    BatchOpt.ModelMaterialNames = sprintf('%s;', ModelMaterialNames{:});
    BatchOpt.ModelMaterialNames(end) = [];
else
    BatchOpt.ModelMaterialNames = '';
end
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName = 'New model';
BatchOpt.mibBatchTooltip.ModelType = ...
    'Specify type of the new model; the model type indicates the maximum number of materials. More materials require more memory and are slower to work with';
BatchOpt.mibBatchTooltip.ModelMaterialNames = sprintf( ...
    '[For 63 and 255 only]\nOptionally, specify names for materials as a semicolon-separated list: "mat1; mat2; mat3"');
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 4  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.createModel';
            ErrorDlgOpt.err = 'A structure as the 4th parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% Initial checks
% Check for virtual stacking mode
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    header = sprintf('Models are not yet available in the virtual stacking mode!\nPlease switch to the memory-resident mode and try again');
    dlgOpt.WindowHeight = 170;
    dlgOpt.HeaderLines = 3;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {}, {}, 'Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% Check that selection/segmentation layers are enabled
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    header = 'The models are switched off!';
    dlgOpt.HeaderLines = 1;
    text = sprintf(['Please make sure that the "Enable selection" option in the Preferences dialog ' ...
        '(Ribbon->Home->Preferences) is set to "yes" and try again...']);
    dlgOpt.WindowHeight = 190;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {text}, {text}, 'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% Warn if an existing model will be overwritten
if obj.I{BatchOpt.id}.modelExist && nargin < 4
    button = utils.dlgs.inputQuestDlg(obj.mibGUI, ...
        sprintf('!!! Warning !!!\nYou are about to start a new model,\nthe existing model will be deleted!'), ...
        'Start new model', 'Continue', 'Cancel', 'Cancel');
    if strcmp(button, 'Cancel'); return; end
end

% Show model-type selection dialog when the type was not provided
if isempty(ModelType) && nargin < 4
    dlg = utils.dlgs.selectModelTypeDlg(obj.mibGUI, obj.mibPath);
    drawnow;
    selectedType = dlg.run();
    if isempty(selectedType); return; end
    BatchOpt.ModelType{1} = num2str(selectedType);
end

%%
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', 'Creating model, please wait...', ...
        'Title', 'Create model', 'Indeterminate', 'on');
end

switch BatchOpt.ModelType{1}
    case {'63', '255'}
        ModelMaterialNames = BatchOpt.ModelMaterialNames;
        if ~isempty(ModelMaterialNames)
            splitCells = regexp(ModelMaterialNames, '([^ ;,]*)', 'tokens');
            ModelMaterialNames = cat(2, splitCells{:});
        end
        obj.I{BatchOpt.id}.createModel(str2double(BatchOpt.ModelType{1}), ModelMaterialNames);
        % Update material colors from preferences
        obj.I{BatchOpt.id}.labels.materialColors = obj.preferences.Colors.ModelMaterialColors;
    case '65535'
        obj.I{BatchOpt.id}.createModel(65535);
    case '4294967295'
        obj.I{BatchOpt.id}.createModel(4294967295);
end

% Make the model layer visible
obj.showModel = true;

% update checkboxes
eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
notify(obj, 'UpdateGuiWidgets', eventdata);
% show image
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar; delete(wb); end
end
