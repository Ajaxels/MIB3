function renameMaterial(obj, BatchOptIn)
% RENAMEMATERIAL - Rename one or all materials of the current model.
%
% Syntax:
%   function renameMaterial(obj, BatchOptIn)
%
% For small models (63 or 255 materials): prompts the user for a new
% name for the selected material.  Use MaterialIndex '0' with a
% comma-separated MaterialName to rename all materials at once.
%
% For large models (65535 or 4294967295 materials): only numeric names
% are accepted.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* a structure for batch processing mode; when
%     NaN, returns a structure with default options via "SyncBatch" event
%
%     - ``.MaterialIndex`` — char, 1-based index of the material to rename;
%       use ``'0'`` to rename all materials at once (MaterialName must then be a
%       comma-separated list); [*default]* index of the currently selected
%       material in the segmentation table
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

% Pre-populate MaterialIndex from the currently selected material
if obj.I{obj.id}.selectedMaterial > 2
    if obj.I{obj.id}.labels.maxMaterials > 256
        BatchOpt.MaterialIndex = obj.I{obj.id}.labels.materialNames{obj.I{obj.id}.selectedMaterial - 2};
    else
        BatchOpt.MaterialIndex = num2str(obj.I{obj.id}.selectedMaterial - 2);
    end
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
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The models are switched off!', {''}, ...
        {'Please make sure that the "Enable selection" option in the Preferences dialog (Ribbon->Home->Preferences) is set to "yes" and try again...'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if ~obj.I{BatchOpt.id}.modelExist
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'No model exists!', {''}, ...
        {'Please create a model first (Ribbon -> Models -> New Model).'}, ...
        'No model', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

id = BatchOpt.id;
modelType = obj.I{id}.labels.maxMaterials;
materialIndex = str2double(BatchOpt.MaterialIndex);

%% Interactive prompt for new name
if nargin < 2
    if modelType > 255
        prompts = {sprintf('New material name\n(only numbers!):')};
        defAns = {BatchOpt.MaterialIndex};
        dlgOpt.PromptLines = 2;
    else
        prompts = {sprintf('New material name\n(no spaces / no letters as the 1st character)\nCurrent index: %d, name: %s', ...
            materialIndex, obj.I{id}.labels.materialNames{materialIndex})};
        defAns = {obj.I{id}.labels.materialNames{materialIndex}};
        dlgOpt.PromptLines = 3;
    end
    answer = utils.dlgs.inputSingleDlg(obj.mibGUI, prompts, defAns, 'Rename material', dlgOpt);
    if isempty(answer); return; end
    BatchOpt.MaterialName = answer;
end

%% Delegate to MibLabels
obj.I{id}.labels.renameMaterial(materialIndex, BatchOpt.MaterialName);

notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
