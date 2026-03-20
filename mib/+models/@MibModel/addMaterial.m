function addMaterial(obj, BatchOptIn)
% function addMaterial(obj, BatchOptIn)
% Add a material to the current model — wrapper around core.MibDataset.addMaterial
%
% For models with 63 or 255 materials: prompts the user for a material
% name, verifies that the model type can accommodate one more material, then
% appends the new entry to the list.
%
% For models with 65535 or 4294967295 materials: scans all time-points to
% find the highest occupied material index, checks that the model is not
% full, then asks MibDataset to register the next unused index.
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
%   index string)
% @li .showWaitbar - logical, show or not the waitbar
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

BatchOpt.mibBatchSectionName = 'Ribbon -> Segmentation';
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

%% Capacity check for small models
if modelType < 256
    list   = obj.I{BatchOpt.id}.labels.materialNames;
    if isempty(list); list = cell(0); end
    number = numel(list);

    if modelType < number + 1
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        dlgOpt.Header      = sprintf('The current model type supports only %d materials!', modelType);
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, {''}, ...
            {'Please convert the model to a larger type and try again (Ribbon -> Models -> Type).'}, ...
            'Wrong model type', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end
end

%%
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', 'Adding material, please wait...', ...
        'Title', 'Add material', 'Indeterminate', 'on');
end

%% For large models: scan all time-points to find the next unused index
newMaterialIndex = [];
if modelType >= 256
    % Ensure a model exists before scanning
    if ~obj.I{BatchOpt.id}.modelExist
        obj.I{BatchOpt.id}.createModel(modelType);
    end

    maxVal    = 0;
    options.blockModeSwitch = false;
    numT      = obj.I{BatchOpt.id}.image.time;
    for t = 1:numT
        M = obj.I{BatchOpt.id}.getData3D('labels', t, 4, 0, options);
        if ~isempty(M) && ~isempty(M{1})
            maxVal = max(maxVal, double(max(M{1}(:))));
        end
        if BatchOpt.showWaitbar
            wb.Value = t / numT * 0.9;
        end
    end

    if maxVal >= modelType
        if BatchOpt.showWaitbar; delete(wb); end
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        dlgOpt.Header      = 'The model is full!';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, {''}, ...
            {sprintf('The maximum material index (%d) equals the model capacity.', maxVal)}, ...
            'Model is full', dlgOpt);
        notify(obj, 'StopProtocol');
        return;
    end

    newMaterialIndex      = maxVal + 1;
    BatchOpt.MaterialName = num2str(newMaterialIndex);
end

%% Delegate to MibDataset
obj.I{BatchOpt.id}.addMaterial(BatchOpt.MaterialName, newMaterialIndex);

if BatchOpt.showWaitbar; wb.Value = 1; end

notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar; delete(wb); end
end
