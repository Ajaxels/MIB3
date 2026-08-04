function renameMaterial(obj, BatchOptIn)
% RENAMEMATERIAL - Rename one or all materials of the current model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.renameMaterial(BatchOptIn)
%
% For small models (63 or 255 materials): prompts the user for a new
% name for the selected material.  Use MaterialIndex '0' with a
% comma-separated MaterialName to rename all materials at once.
%
% For large models (65535 or 4294967295 materials): the table holds only two
% material slots whose displayed names store the actual material index, so
% MaterialIndex addresses the slot (1 or 2) and MaterialName must be a number
% between 1 and the model capacity.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* a structure for batch processing mode; when
%     NaN, returns a structure with default options via "SyncBatch" event
%
%     - ``.MaterialIndex`` — char, 1-based row index of the material to rename in
%       the segmentation table (for 65535+ models: the material slot, 1 or 2 — not
%       the material index shown in the slot); use ``'0'`` to rename all materials
%       at once (MaterialName must then be a comma-separated list);
%       [*default]* row of the currently selected material in the segmentation table
%     - ``.MaterialName`` — char, new name for the material, or
%       comma-separated list when MaterialIndex is ``'0'``; [*default* ``''``]
%     - ``.showWaitbar`` — logical, show or not the waitbar; [*default* true]
%     - ``.id`` — *(optional)*, dataset index 1-9, default = obj.id
%
%
% Output Arguments:
%
% Usage:
%   **Example 1** — interactive rename with dialog
%
%   .. code-block:: matlab
%
%      obj.mibModel.renameMaterial();
%
%   **Example 2** — scripted / batch call
%
%   .. code-block:: matlab
%
%      BatchOpt.MaterialIndex = '3';
%      BatchOpt.MaterialName = 'Nucleus';
%      obj.mibModel.renameMaterial(BatchOpt);
%
%   **Example 3** — rename all three materials
%
%   .. code-block:: matlab
%
%      BatchOpt.MaterialIndex = '0';
%      BatchOpt.MaterialName = 'A,B,C';
%      obj.mibModel.renameMaterial(BatchOpt);
%

% Updates
% Ported from MIB2 mibModel.materialsActions 'Rename material' case

if nargin < 2; BatchOptIn = struct(); end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.MaterialName  = '';
BatchOpt.showWaitbar   = true;
BatchOpt.id            = obj.getActiveId();

% Pre-populate MaterialIndex from the currently selected material.
% MaterialIndex is always a row (slot) index of labels.materialNames. For large
% models (65535+) the table holds only two material slots whose displayed names
% store the actual material index, so the displayed name must never be used here
% as the row index — see controllers.MibController.findMaterialUnderCursor for
% the same slot convention.
if obj.I{BatchOpt.id}.selectedMaterial > 2
    BatchOpt.MaterialIndex = num2str(obj.I{BatchOpt.id}.selectedMaterial - 2);
elseif obj.I{BatchOpt.id}.labels.maxMaterials > 255 && obj.I{BatchOpt.id}.restrictSelectionToMaterial
    % Mask/Exterior highlighted while the selection is restricted to a material:
    % target the Add-To slot, the one that is actually being painted into
    BatchOpt.MaterialIndex = num2str(max(obj.I{BatchOpt.id}.selectedAddToMaterial - 2, 1));
else
    BatchOpt.MaterialIndex = '1';
end

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName  = 'Rename material';
BatchOpt.mibBatchTooltip.MaterialIndex = ...
    'Index of the material to rename (1-based). Use 0 to rename all materials at once (MaterialName must then be a comma-separated list).';
BatchOpt.mibBatchTooltip.MaterialName = ...
    sprintf('New name for the material (no spaces / no letters as the 1st character).\nWhen MaterialIndex is 0, provide a comma-separated list matching the number of materials.');
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check
if nargin == 2
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.renameMaterial';
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
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 160;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'The models are switched off!', {''}, ...
        {'Please make sure that the "Enable selection" option in the Preferences dialog (Ribbon->Home->Preferences) is set to "yes" and try again...'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if ~obj.I{BatchOpt.id}.modelExist
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'No model exists!', {''}, ...
        {'Please create a model first (Ribbon -> Models -> New Model).'}, ...
        'No model', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

id = BatchOpt.id;
modelType = obj.I{id}.labels.maxMaterials;
materialIndex = str2double(BatchOpt.MaterialIndex);
materialSlots = numel(obj.I{id}.labels.materialNames);

% NaN means "use the currently selected material" (MIB2 compatibility)
if isnan(materialIndex)
    materialIndex = max(obj.I{id}.selectedMaterial - 2, 1);
end

% Clamp the slot index to the existing rows of the table; for large models only
% two slots exist and renaming outside of them would silently grow materialNames
if materialIndex > materialSlots
    materialIndex = max(materialSlots, 1);
end
if materialIndex < 0; materialIndex = 1; end
BatchOpt.MaterialIndex = num2str(materialIndex);

%% Interactive prompt for new name
if nargin < 2
    if modelType > 255
        prompts = {sprintf('New material index for slot %d\n(only numbers, 1-%d):', materialIndex, modelType)};
        defAns = {obj.I{id}.labels.materialNames{materialIndex}};
    else
        prompts = {sprintf('New material name\n(no spaces / no letters as the 1st character)\nCurrent index: %d, name: %s', ...
            materialIndex, obj.I{id}.labels.materialNames{materialIndex})};
        defAns = {obj.I{id}.labels.materialNames{materialIndex}};
    end
    answer = utils.dlgs.inputSingleDlg(obj.getProgressBarParent(), prompts, defAns, 'Rename material');
    if isempty(answer); return; end
    BatchOpt.MaterialName = answer;
end

%% Validate the new name
% Large models store the material index as the displayed name; only numbers
% within the model capacity are acceptable
if modelType > 255 && materialIndex ~= 0
    newMaterialIndex = round(str2double(BatchOpt.MaterialName));
    if isnan(newMaterialIndex) || newMaterialIndex < 1 || newMaterialIndex > modelType
        ErrorDlgOpt.winTitle = 'Wrong material index';
        ErrorDlgOpt.optionalPrefix = 'Error in MibModel.renameMaterial';
        ErrorDlgOpt.err = sprintf('Materials of %d-type models are named after their index!\nPlease enter a number between 1 and %d', modelType, modelType);
        ErrorDlgOpt.WindowHeight = 170;
        eventdata = core.ToggleEventData(ErrorDlgOpt);
        notify(obj, 'ShowErrorDialog', eventdata);
        notify(obj, 'StopProtocol');
        return;
    end
    BatchOpt.MaterialName = num2str(newMaterialIndex);
end

%% Delegate to MibLabels
obj.I{id}.labels.renameMaterial(materialIndex, BatchOpt.MaterialName);

% BigData: persist the updated material names into the disk-backed store
if isa(obj.I{id}.labels, 'core.MibBigDataLabels')
    obj.I{id}.labels.writeMaterialMetadata();
end

notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
