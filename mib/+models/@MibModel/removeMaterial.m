function removeMaterial(obj, BatchOptIn)
% REMOVEMATERIAL - Remove one or more materials from the current model — wrapper around core.MibDataset.removeMaterial.
%
% Syntax:
%   function removeMaterial(obj, BatchOptIn)
%
% For models with 63 or 255 materials: prompts the user for material
% indices to remove, remaps the remaining materials to contiguous indices
% (1..N), and updates the materialNames/materialColors lists.
%
% For models with 65535 or 4294967295 materials in interactive (non-batch)
% mode: squeezes all label indices to a contiguous range starting at 1 by
% renumbering every unique value, then calls addMaterial to re-register the
% next available index.  In batch mode, the specified material pixel values
% are zeroed out without renumbering.
%
% In all cases the operation aborts when no model exists.  After a
% successful removal, UpdateGuiWidgets and ShowImage events are fired so
% the segmentation table and image view refresh.
%
% Input Arguments:
%   - **BatchOptIn** — a structure for batch processing mode; when NaN, returns a
%     structure with default options via "SyncBatch" event
%
%     - ``.MaterialIndices`` — char, space- or comma-separated list of material
%       indices to remove, e.g. ``'2'`` or ``'1 3'`` or ``'2,4,6:8'``; [*default* ``''``],
%       pre-populated with the currently selected material index when one is
%       selected in the segmentation table.  For large model types
%       (65535/4294967295) in batch mode the corresponding pixel values are
%       zeroed; the squeeze-and-renumber operation is available in interactive
%       mode only.
%     - ``.showWaitbar`` — logical, show or not the waitbar [*default* true]
%     - ``.id`` — *(optional)*, dataset index from 1 to 9, default = obj.id
%
%
% Output Arguments:
%
% Usage:
%   **Example 1** — interactive remove with index dialog
%
%   .. code-block:: matlab
%
%      obj.mibModel.removeMaterial();
%
%   **Example 2** — scripted / batch call
%
%   .. code-block:: matlab
%
%      BatchOpt.MaterialIndices = '2 4';
%      BatchOpt.showWaitbar = false;
%      obj.mibModel.removeMaterial(BatchOpt);
%

% Updates
% Ported from MIB2 mibController.mibRemoveMaterialBtn_Callback

if nargin < 2; BatchOptIn = struct(); end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.MaterialIndices  = '';
BatchOpt.showWaitbar      = true;
BatchOpt.id               = obj.getActiveId();

% Pre-populate with the currently selected material index when available
if obj.I{BatchOpt.id}.selectedMaterial >= 3
    BatchOpt.MaterialIndices = num2str(obj.I{BatchOpt.id}.selectedMaterial - 2);
end

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName  = 'Remove material';
BatchOpt.mibBatchTooltip.MaterialIndices = ...
    'Indices of materials to be removed from the model (e.g. ''2'' or ''1 3'' or ''2:5'').';
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
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.removeMaterial';
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

% define mibPath for input dialogs
dlgOpt.mibPath = obj.mibPath;

%% Initial checks
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    dlgOpt.WindowHeight = 160;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The models are switched off!', {''}, ...
        {'Please make sure that the "Enable selection" option in the Preferences dialog (Ribbon->Home->Preferences) is set to "yes" and try again...'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if ~obj.I{BatchOpt.id}.modelExist
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'No model exists!', {''}, ...
        {'Please create a model first (Ribbon -> Models -> New Model).'}, ...
        'No model', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

modelType = obj.I{BatchOpt.id}.labels.maxMaterials;

%% Large models in interactive mode: squeeze labels to contiguous range
if nargin < 2 && modelType >= 256
    wb = [];
    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
            'Message', 'Squeezing labels, please wait...', ...
            'Title', 'Squeeze labels');
    end

    obj.I{BatchOpt.id}.labels.squeezeMaterialLabels(wb);

    if BatchOpt.showWaitbar; delete(wb); end

    % Re-register the next available material index
    obj.addMaterial();
    return;
end

%% Interactive prompt for material indices (small models or batch for large)
if nargin < 2
    answer = utils.dlgs.inputSingleDlg(obj.mibGUI, ...
        {sprintf('Specify indices of materials to be removed\n(for example, 2  or  1 3  or  2,4,6:8)')}, ...
        {BatchOpt.MaterialIndices}, ...
        'Remove material', dlgOpt);
    if isempty(answer); return; end
    BatchOpt.MaterialIndices = answer;
end

%% Parse material indices
MaterialIndices = str2num(BatchOpt.MaterialIndices); %#ok<ST2NM>
if isempty(MaterialIndices)
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    header       = sprintf('Wrong material indices: "%s"', BatchOpt.MaterialIndices);
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {''}, ...
        {'The function requires a list of numbers, for example "1", "2 4", or "3:5".'}, ...
        'Remove material', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Bounds check
maxValid = numel(obj.I{BatchOpt.id}.labels.materialNames);
MaterialIndices = MaterialIndices(MaterialIndices >= 1 & MaterialIndices <= maxValid);
if isempty(MaterialIndices)
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'No valid material indices!', {''}, ...
        {sprintf('All specified indices are out of range. The model has only %d material(s).', maxValid)}, ...
        'Remove material', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Confirmation (interactive only)
if nargin < 2
    modelMaterialNames = obj.I{BatchOpt.id}.labels.materialNames;
    matListStr  = sprintf('"%s", ', modelMaterialNames{MaterialIndices});
    matIndexStr = sprintf('%d, ', MaterialIndices);
    msg = sprintf('You are about to delete material(s):\n%s\nwith indices: %s\n\nAre you sure?', ...
        matListStr(1:end-2), matIndexStr(1:end-2));
    answer = utils.dlgs.inputQuestDlg(obj.mibGUI, msg, 'Delete materials?', 'Yes', 'Cancel', 'Cancel');
    if strcmp(answer, 'Cancel'); return; end
end

%% Delegate pixel-data manipulation + metadata cleanup to MibDataset
wb = [];
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', 'Deleting materials, please wait...', ...
        'Title', 'Remove material');
end

obj.I{BatchOpt.id}.removeMaterial(MaterialIndices, wb);

if BatchOpt.showWaitbar; wb.Value = 1; end

notify(obj, 'UpdateGuiWidgets');
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar; delete(wb); end
end
