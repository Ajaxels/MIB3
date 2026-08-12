function addMaterial(obj, BatchOptIn)
% ADDMATERIAL - Add a material to the current model - wrapper around core.MibDataset.addMaterial.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.addMaterial(BatchOptIn)
%
% For models with 63 or 255 materials: prompts the user for a material
% name, verifies that the model type can accommodate one more material, then
% appends the new entry to the list.
%
% For models with 65535 or 4294967295 materials: rescans the model data for
% the highest label in use to determine the next available index, checks
% that the model is not full, then asks MibDataset to register the new
% index. Pressing the button repeatedly therefore keeps offering the same
% free index until it is actually painted.
%
% In all cases the model is created automatically when it does not yet
% exist.  After a successful addition, UpdateGuiWidgets and ShowImage
% events are fired so the segmentation table and image view refresh.
%
% Input Arguments:
%   - **BatchOptIn** - a structure for batch processing mode; when NaN, returns a
%     structure with default options via "SyncBatch" event
%
%     - ``.MaterialName`` - char, name of the new material (used for types 63
%       and 255; for larger types the value is overridden with the next unused
%       index string) [*default* 'NewMaterial']
%     - ``.showWaitbar`` - logical, show or not the waitbar [*default* false]
%     - ``.id`` - *(optional)*, dataset index from 1 to 9, default = obj.id
%
%
% Output Arguments:
%
% Usage:
%   **Example 1** - interactive add with name dialog
%
%   .. code-block:: matlab
%
%      obj.mibModel.addMaterial();
%
%   **Example 2** - scripted / batch call
%
%   .. code-block:: matlab
%
%      BatchOpt.MaterialName = 'Nucleus';
%      BatchOpt.showWaitbar  = false;
%      obj.mibModel.addMaterial(BatchOpt);
%

% Updates
% Ported from MIB2 mibController.mibAddMaterialBtn_Callback

if nargin < 2; BatchOptIn = struct(); end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.MaterialName  = 'NewMaterial';
BatchOpt.showWaitbar   = false;
BatchOpt.id            = obj.getActiveId();

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
    header      = 'The models are switched off!';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 160;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), header, {''}, ...
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

        answer = utils.dlgs.inputSingleDlg(obj.getProgressBarParent(), ...
            'Please enter a name for the new material:', ...
            sprintf('m%.3d', number + 1), 'Add material');
        if isempty(answer); return; end

        BatchOpt.MaterialName = answer;
    end
end

%% Waitbar
% The large-model path scans the whole volume for the highest label in use
% (see core.MibDataset.addMaterial), which is not instant on a big dataset, so
% an interactive press gets a bar even though showWaitbar defaults to false.
% Batch calls keep exactly the bar they asked for, and the small-model path
% stays instant and silent.
wb = [];
if BatchOpt.showWaitbar || (nargin < 2 && modelType >= 256)
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', 'Adding material, please wait...', ...
        'Title', 'Add material', 'Indeterminate', 'on');
end

%% Delegate to MibDataset (scanning, capacity check, metadata update)
[result, newMaterialIndex] = obj.I{BatchOpt.id}.addMaterial(BatchOpt.MaterialName, [], wb);

if ~result
    if ~isempty(wb); delete(wb); end
    if modelType < 256
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        header      = sprintf('The current model type supports only %d materials!', modelType);
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), header, {''}, ...
            {'Please convert the model to a larger type and try again (Ribbon -> Models -> Type).'}, ...
            'Wrong model type', dlgOpt);
    else
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        header      = 'The model is full!';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), header, {''}, ...
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

% MibDataset.addMaterial already set selectedMaterial/selectedAddToMaterial
% correctly for all model types (table rows 3-4 for large models, nMats+2
% for small models). Do NOT override here - for large models newMaterialIndex
% is the raw pixel value (1, 2, 3 …) and adding 2 produces out-of-range row
% indices that crash the 4-row materialsTable.

if ~isempty(wb); wb.Value = 1; end

% BigData: persist the updated material list into the disk-backed store
if isa(obj.I{BatchOpt.id}.labels, 'core.MibBigDataLabels')
    obj.I{BatchOpt.id}.labels.writeMaterialMetadata();
end

notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if ~isempty(wb); delete(wb); end
end
