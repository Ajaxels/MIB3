function status = materialsActions(obj, action, BatchOptIn)
% MATERIALSACTIONS - Collection of actions related to materials of the model.
%
% Syntax:
%   function status = materialsActions(obj, action, BatchOptIn)
%
% Dispatches to the appropriate low-level method on MibDataset or MibLabels
% depending on the requested action: rename, add, insert, swap, reorder,
% or remove.  Each action supports both interactive mode (with dialogs) and
% batch mode (via BatchOptIn).
%
% Input Arguments:
%   - **action** — char, desired action.  Provide only this parameter for
%     interactive behaviour.  One of:
%
%     - ``'Rename material'`` — rename a single material (index 0 renames all
%       from a comma-separated list)
%     - ``'Add material'`` — append a new material at the end of the list;
%       delegates to obj.addMaterial
%     - ``'Insert material'`` — insert a new material at an arbitrary position,
%       shifting existing materials downward
%     - ``'Swap materials'`` — exchange two materials (pixel data + metadata)
%     - ``'Reorder materials'`` — rearrange all materials according to a
%       permutation vector (small models only, maxMaterials < 256)
%     - ``'Export material'`` — [not yet ported] export a material to the
%       MATLAB workspace
%     - ``'Save material to file'`` — [not yet ported] save a material to a
%       file on disk
%     - ``'Remove material'`` — delete one or more materials; delegates to
%       obj.removeMaterial
%
%   - **BatchOptIn** — *(optional)* a structure for batch processing mode; when
%     NaN, returns a structure with default options via "SyncBatch" event
%
%     - ``.Action`` — cell string with these options:
%       ``'Rename material'``, ``'Add material'``, ``'Insert material'``,
%       ``'Swap materials'``, ``'Reorder materials'``, ``'Export material'``,
%       ``'Save material to file'``, ``'Remove material'``
%     - ``.MaterialIndex1`` — char, primary index(indices) of materials to
%       perform required action; [*default]* index of the currently selected
%       material in the segmentation table
%     - ``.MaterialIndex2`` — char, secondary index of materials for swapping
%       of materials; [*default]* index of the selected AddTo material
%     - ``.MaterialName`` — char, new name for the material; [*default* ``''``]
%     - ``.showWaitbar`` — logical, show or not the waitbar; [*default* true]
%     - ``.id`` — *(optional)*, dataset index 1-9, default = obj.id
%
%
% Output Arguments:
%   - **status** — logical, true when the action completed successfully
%
% Usage:
%   **Example 1** — rename material 3
%
%   .. code-block:: matlab
%
%      BatchOptIn.Action = {'Rename material'};
%      BatchOptIn.MaterialIndex1 = '3';
%      BatchOptIn.MaterialName = 'material3';
%      obj.mibModel.materialsActions([], BatchOptIn);
%
%   **Example 2** — remove materials 2,3,4,10
%
%   .. code-block:: matlab
%
%      BatchOptIn.Action = {'Remove material'};
%      BatchOptIn.MaterialIndex1 = '2:4 10';
%      obj.mibModel.materialsActions([], BatchOptIn);
%

% Updates
% Ported from MIB2 mibModel.materialsActions

status = false;

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(action)
    BatchOpt.Action = {action};
else
    BatchOpt.Action = {'Rename material'};
end
BatchOpt.Action{2} = {'Rename material', 'Add material', 'Insert material', ...
    'Swap materials', 'Reorder materials', 'Export material', ...
    'Save material to file', 'Remove material'};
BatchOpt.MaterialName = '';

if obj.I{obj.id}.selectedMaterial > 2
    if obj.I{obj.id}.labels.maxMaterials > 256
        BatchOpt.MaterialIndex1 = obj.I{obj.id}.labels.materialNames{obj.I{obj.id}.selectedMaterial - 2};
    else
        BatchOpt.MaterialIndex1 = num2str(obj.I{obj.id}.selectedMaterial - 2);
    end
else
    BatchOpt.MaterialIndex1 = '1';
end

if obj.I{obj.id}.selectedAddToMaterial > 2
    BatchOpt.MaterialIndex2 = num2str(obj.I{obj.id}.selectedAddToMaterial - 2);
else
    BatchOpt.MaterialIndex2 = '2';
end

BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Material actions';
BatchOpt.batchModeFlag       = false;

BatchOpt.mibBatchTooltip.Action = 'Specify action for materials';
BatchOpt.mibBatchTooltip.MaterialName = sprintf('New name for the material\nUse empty for automatic naming\nWhen renaming all materials provide the comma-separated list. Do not use spaces!');
BatchOpt.mibBatchTooltip.MaterialIndex1 = sprintf('[all actions] Index(indices) of materials or new order of materials\nWhen "NaN" use the currently selected material; use 0 to rename all materials');
BatchOpt.mibBatchTooltip.MaterialIndex2 = sprintf('[swap only] Secondary index(indices) of materials to perform required action');
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.materialsActions';
            ErrorDlgOpt.err = 'A structure as the 2nd parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
        if strcmp(BatchOpt.Action{1}, 'Add material')
            BatchOpt.MaterialIndex1 = [];
        end
    end
else
    BatchOptIn = struct();
end

dlgOpt.mibPath  = obj.mibPath;

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
    return;
end

id = BatchOpt.id;
modelType = obj.I{id}.labels.maxMaterials;
nMats = numel(obj.I{id}.labels.materialNames);

%% Dispatch actions
switch BatchOpt.Action{1}
    case 'Rename material'
        % Delegate to the dedicated renameMaterial wrapper
        if nargin < 3
            obj.renameMaterial();
        else
            obj.renameMaterial(BatchOptIn);
        end
        status = true;
        return;  % renameMaterial handles its own events and SyncBatch

    case 'Add material'
        % Delegate to the dedicated addMaterial wrapper
        if nargin < 3
            obj.addMaterial();
        else
            obj.addMaterial(BatchOptIn);
        end
        status = true;
        return;  % addMaterial handles its own events and SyncBatch

    case 'Insert material'
        if ~isfield(BatchOptIn, 'MaterialName') || ~isfield(BatchOptIn, 'MaterialIndex1')
            dlgOpt.WindowHeight = 180;
            prompts = {sprintf('Material name\n(no spaces / no letters as the 1st character):'); ...
                       sprintf('Index where material needs to be inserted\n[number between 1-%d]:', nMats + 1)};
            defAns = {sprintf('mat%.3d', nMats + 1); BatchOpt.MaterialIndex1};
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defAns, 'Insert material', dlgOpt);
            if isempty(answer); return; end
            BatchOpt.MaterialName = answer{1};
            BatchOpt.MaterialIndex1 = answer{2};
        end

        wb = [];
        if BatchOpt.showWaitbar
            wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
                'Message', 'Inserting material, please wait...', ...
                'Title', 'Insert material');
        end
        obj.I{id}.insertMaterial(str2double(BatchOpt.MaterialIndex1), BatchOpt.MaterialName, wb);
        if BatchOpt.showWaitbar; wb.Value = 1; delete(wb); end
        status = true;

    case 'Swap materials'
        if ~isfield(BatchOptIn, 'MaterialIndex1') || ~isfield(BatchOptIn, 'MaterialIndex2')
            dlgOpt.WindowHeight = 180;
            prompts = {sprintf('Index of the first material to swap\n[number between 1-%d]:', nMats); ...
                       sprintf('Index of the second material to swap\n[number between 1-%d]:', nMats)};
            defAns = {BatchOpt.MaterialIndex1; BatchOpt.MaterialIndex2};
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', prompts, defAns, 'Swap materials', dlgOpt);
            if isempty(answer); return; end
            BatchOpt.MaterialIndex1 = answer{1};
            BatchOpt.MaterialIndex2 = answer{2};
        end

        wb = [];
        if BatchOpt.showWaitbar
            wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
                'Message', 'Swapping materials, please wait...', ...
                'Title', 'Swap materials');
        end
        obj.I{id}.swapMaterials(str2double(BatchOpt.MaterialIndex1), str2double(BatchOpt.MaterialIndex2), wb);
        if BatchOpt.showWaitbar; wb.Value = 1; delete(wb); end
        status = true;

    case 'Reorder materials'
        if modelType > 256
            dlgOpt.MsgBoxOnly  = true;
            header      = 'Not implemented';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {''}, ...
                {'Reordering of materials is only supported for models with up to 256 materials!'}, ...
                'Not implemented', dlgOpt);
            return;
        end

        if ~isfield(BatchOptIn, 'MaterialIndex1')
            prompts = {sprintf('Provide a new order for materials\nyou can use MATLAB notation: "1:5 9:-1:6 12 11 10"\n          => "1,2,3,4,5,9,8,7,6,12,11,10"\n[numbers between 1-%d]:', nMats)};
            defAns = {num2str(1:nMats)};
            dlgOpt.WindowWidth = 600;
            answer = utils.dlgs.inputSingleDlg(obj.mibGUI, prompts, defAns, 'Reorder materials', dlgOpt);
            if isempty(answer); return; end
            BatchOpt.MaterialIndex1 = answer;
        end

        newOrder = str2num(BatchOpt.MaterialIndex1); %#ok<ST2NM>
        if numel(newOrder) ~= nMats
            dlgOpt.MsgBoxOnly  = true;
            header      = 'Wrong number of materials';
            dlgOpt.HeaderLines = 1;
            dlgOpt.WindowWidth = 450;
            dlgOpt.WindowHeight = 150;
            utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {''}, ...
                {sprintf('The current model has %d materials, but %d indices were specified.', nMats, numel(newOrder))}, ...
                'Wrong number', dlgOpt);
            return;
        end

        wb = [];
        if BatchOpt.showWaitbar
            wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
                'Message', sprintf('%s\nPlease wait...', BatchOpt.MaterialIndex1), ...
                'Title', 'Reordering materials');
        end
        obj.I{id}.reorderMaterials(newOrder, wb);
        if BatchOpt.showWaitbar; wb.Value = 1; delete(wb); end
        status = true;

    case 'Export material'
        % TODO: port from MIB2 — calls obj.modelExport with MaterialIndex
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        header      = 'Not yet implemented';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {''}, ...
            {'Export material is not yet ported to MIB3.'}, ...
            'Export material', dlgOpt);
        return;

    case 'Save material to file'
        % TODO: port from MIB2 — calls obj.saveModel with MaterialIndex
        dlgOpt.MsgBoxOnly  = true;
        dlgOpt.Icon        = 'puffin_warning';
        header      = 'Not yet implemented';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {''}, ...
            {'Save material to file is not yet ported to MIB3.'}, ...
            'Save material to file', dlgOpt);
        return;

    case 'Remove material'
        % Delegate to the dedicated removeMaterial wrapper
        if nargin < 3
            obj.removeMaterial();
        else
            obj.removeMaterial(BatchOptIn);
        end
        status = true;
        return;  % removeMaterial handles its own events and SyncBatch
end

if ~status
    notify(obj, 'StopProtocol');
    return;
end

%% Post-action updates
eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
notify(obj, 'UpdateGuiWidgets', eventdata);

notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
end
