function addMaterial(obj, BatchOptIn)
% function addMaterial(obj, BatchOptIn)
% Add a material to the current model — wrapper around core.MibDataset.addMaterial
%
% For models with 63 or 255 materials: prompts the user for a material
% name, verifies that the model type can accommodate one more material, then
% appends the new entry to the list.
%
% For models with 65535 or 4294967295 materials: uses
% obj.labels.materialsCount to determine the next available index, checks
% that the model is not full, then asks MibDataset to register the new
% index.
%
% In all cases the model is created automatically when it does not yet
% exist.  After a successful addition, UpdateGuiWidgets and ShowImage
% events are fired so the segmentation table and image view refresh.
%
% Parameters:
% BatchOptIn: a structure for batch processing mode; when NaN, returns a
%   structure with default options via "SyncBatch" event
% @li .MaterialName - char, name of the new material (used for types 63
%   and 255; for larger types the value is overridden with the next unused
%   index string) [@em default 'NewMaterial']
% @li .showWaitbar - logical, show or not the waitbar [@em default false]
% @li .id -> [@em optional], dataset index from 1 to 9, default = obj.id
%
% Return values:
%

%|
% @b Examples:
% @code obj.mibModel.addMaterial();     // interactive add with name dialog @endcode
% @code
% BatchOpt.MaterialName = 'Nucleus';
% BatchOpt.showWaitbar  = false;
% obj.mibModel.addMaterial(BatchOpt);   // scripted / batch call
% @endcode

% Updates
% Ported from MIB2 mibController.mibAddMaterialBtn_Callback

if nargin < 2; BatchOptIn = struct(); end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.MaterialName  = 'NewMaterial';
BatchOpt.showWaitbar   = false;
BatchOpt.id            = obj.id;

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName  = 'Add material';
BatchOpt.mibBatchTooltip.MaterialName = ...
    '[Models with 63 or 255 materials] Name of a new material to add (no spaces). For larger model types the index is assigned automatically.';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 2
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.addMaterial';
            ErrorDlgOpt.err = 'A structure as the 2nd parameter is required!';
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
% Abort when selection / segmentation layers are disabled
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.Header      = 'The models are switched off!';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 160;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, {''}, ...
        {'Please make sure that the "Enable selection" option in the Preferences dialog (Ribbon->Home->Preferences) is set to "yes" and try again...'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

modelType = obj.I{BatchOpt.id}.labels.maxMaterials;

%% Interactive prompt for material name (small models, non-batch only)
if nargin < 2
    if modelType < 256
        list   = obj.I{BatchOpt.id}.labels.materialNames;
        if isempty(list); list = cell(0); end
        number = numel(list);

        answer = utils.dlgs.inputSingleDlg(obj.mibGUI, ...
            'Please enter a name for the new material:', ...
            sprintf('m%.3d', number + 1), 'Add material');
        if isempty(answer); return; end

        BatchOpt.MaterialName = answer;
    end
end

%% Waitbar
wb = [];
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', 'Adding material, please wait...', ...
        'Title', 'Add material', 'Indeterminate', 'on');
end

%% Delegate to MibDataset (scanning, capacity check, metadata update)
[result, newMaterialIndex] = obj.I{BatchOpt.id}.addMaterial(BatchOpt.MaterialName, [], wb);

if ~result
    if BatchOpt.showWaitbar; delete(wb); end
    if modelType < 256
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        dlgOpt.Header      = sprintf('The current model type supports only %d materials!', modelType);
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, {''}, ...
            {'Please convert the model to a larger type and try again (Ribbon -> Models -> Type).'}, ...
            'Wrong model type', dlgOpt);
    else
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        dlgOpt.Header      = 'The model is full!';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, {''}, ...
            {'The maximum material index equals the model capacity.'}, ...
            'Model is full', dlgOpt);
    end
    notify(obj, 'StopProtocol');
    return;
end

% Update BatchOpt.MaterialName for large models so SyncBatch records the
% actual assigned index
if modelType >= 256 && ~isempty(newMaterialIndex)
    BatchOpt.MaterialName = num2str(newMaterialIndex);
end

if BatchOpt.showWaitbar; wb.Value = 1; end

notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar; delete(wb); end
end
