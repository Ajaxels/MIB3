function moveLayers(obj, SourceLayer, DestinationLayer, DatasetType, ActionType, BatchOptIn)
% MOVELAYERS - Move datasets between the layers (selection, mask, labels).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.moveLayers(SourceLayer, DestinationLayer, DatasetType, ActionType)
%      obj.moveLayers(SourceLayer, Destinabuildtool testAlltionLayer, DatasetType, ActionType, BatchOptIn)
%
% Move data between the selection, mask, and labels layers. Supports operations like
% moving selection to mask, or selection to a specified material of the labels layer.
%
% Input Arguments:
%   - **SourceLayer** - [char] name of a layer to get data: ``'selection'``, ``'mask'``, or
%     ``'labels'``; can be empty ``[]``
%   - **DestinationLayer** - [char] name of a layer to set data: ``'selection'``, ``'mask'``, or
%     ``'labels'``; can be empty ``[]``
%   - **DatasetType** - [char] type of dataset to move:
%
%     - ``'2D, Slice'`` - 2D mode, move only the shown slice ``[y,x]``
%     - ``'3D, Stack'`` - 3D mode, move 3D dataset ``[y,x,z]``
%     - ``'4D, Dataset'`` - 4D mode, move 4D dataset ``[y,x,z,t]``
%   - **ActionType** - [char] type of the desired action:
%
%     - ``'add'`` - add source to destination
%     - ``'remove'`` - remove source from destination
%     - ``'replace'`` - replace destination with source
%   - **BatchOptIn** *(optional)* - [struct] structure for batch processing mode; when ``NaN``, returns
%     default options via ``SyncBatch`` event
%
%     - ``.id`` *(optional)* - [numeric] dataset index from 1 to 9 (default: currently shown dataset)
%     - ``.blockModeSwitch`` - [logical] use or not the block mode
%     - ``.roiId`` - [char] ROI mode control; ``-1`` to disable
%     - ``.fillBg`` - [numeric] when ``NaN`` crops as rectangle; when a number fills out-of-ROI areas
%     - ``.y`` *(optional)* - [numeric] ``[ymin, ymax]`` of the part of the dataset to take
%     - ``.x`` *(optional)* - [numeric] ``[xmin, xmax]`` of the part of the dataset to take
%     - ``.z`` *(optional)* - [numeric] ``[zmin, zmax]`` of the part of the dataset to take
%     - ``.t`` *(optional)* - [numeric] ``[tmin, tmax]`` of the part of the dataset to take
%     - ``.SelectedMaterial`` - [char] index of the selected material
%     - ``.selectedAddToMaterial`` - [char] index of the selected add-to material
%     - ``.restrictSelectionToMaterial`` - [logical] limit selection only to the selected material
%     - ``.restrictSelectionToMask`` - [logical] perform actions only in masked areas
%     - ``.showWaitbar`` - [logical] show or hide the progress bar
%
% Output Arguments:
%
% **Example 1** - add selection to mask:
%
%   .. code-block:: matlab
%
%      obj.mibModel.moveLayers('selection', 'mask', '3D, Stack', 'add');
%
% **Example 2** - replace selection with mask:
%
%   .. code-block:: matlab
%
%      obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'replace');
%

% Updates
%

if nargin < 5
    ErrorDlgOpt.winTitle = 'moveLayers Error';
    ErrorDlgOpt.optionalPrefix = 'Error in MibModel.moveLayers';
    ErrorDlgOpt.err = 'At least 4 parameters are required for this function';
    ErrorDlgOpt.WindowHeight = 150;
    eventdata = core.ToggleEventData(ErrorDlgOpt);
    notify(obj, 'ShowErrorDialog', eventdata);
    return;
end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(SourceLayer); BatchOpt.SourceLayer = {SourceLayer}; else; BatchOpt.SourceLayer = {'selection'}; end
BatchOpt.SourceLayer{2} = {'selection', 'mask', 'labels'};
if ~isempty(DestinationLayer); BatchOpt.DestinationLayer = {DestinationLayer}; else; BatchOpt.DestinationLayer = {'selection'}; end
BatchOpt.DestinationLayer{2} = {'selection', 'mask', 'labels'};
if ~isempty(DatasetType); BatchOpt.DatasetType = {DatasetType}; else; BatchOpt.DatasetType = {'2D, Slice'}; end
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
if ~isempty(ActionType); BatchOpt.ActionType = {ActionType}; else; BatchOpt.ActionType = {'add'}; end
BatchOpt.ActionType{2} = {'add', 'remove', 'replace'};
activeId = obj.getActiveId();
BatchOpt.SelectedMaterial = num2str(obj.I{activeId}.getSelectedMaterialIndex());
BatchOpt.SelectedAddToMaterial = num2str(obj.I{activeId}.getSelectedMaterialIndex('AddTo'));
BatchOpt.restrictSelectionToMaterial = logical(obj.I{activeId}.restrictSelectionToMaterial);
BatchOpt.restrictSelectionToMask = logical(obj.I{activeId}.restrictSelectionToMask);
BatchOpt.blockModeSwitch = logical(obj.I{activeId}.blockModeSwitch);
if obj.I{activeId}.roiShow
    BatchOpt.roiId = num2str(obj.I{activeId}.selectedROI);
else
    BatchOpt.roiId = '-1';
end
BatchOpt.fillBg = num2str(NaN);
BatchOpt.id = activeId;
BatchOpt.showWaitbar = true;

switch BatchOpt.SourceLayer{1}
    case 'labels'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        switch BatchOpt.DestinationLayer{1}
            case 'mask';        BatchOpt.mibBatchActionName = 'Model to Mask';
            case 'selection';   BatchOpt.mibBatchActionName = 'Model to Selection';
        end
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        switch BatchOpt.DestinationLayer{1}
            case 'labels';      BatchOpt.mibBatchActionName = 'Mask to Model';
            case 'selection';   BatchOpt.mibBatchActionName = 'Mask to Selection';
        end
    case 'selection'
        BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
        switch BatchOpt.DestinationLayer{1}
            case 'mask';        BatchOpt.mibBatchActionName = 'Selection to Mask';
            case 'labels';      BatchOpt.mibBatchActionName = 'Selection to Model';
        end
end

% tooltips for BatchOpt
BatchOpt.mibBatchTooltip.SourceLayer = sprintf('specify the source layer that will be moved');
BatchOpt.mibBatchTooltip.DestinationLayer = sprintf('specify the destination layer to where the source layer will be moved');
BatchOpt.mibBatchTooltip.DatasetType = sprintf('Type of the dataset to process, could be overridden with x,y,z,t fields');
BatchOpt.mibBatchTooltip.ActionType = sprintf('type of the layer movement');
BatchOpt.mibBatchTooltip.SelectedMaterial = sprintf('index of the selected material; -1 for mask, 0-for exterior, 1,2,3 materials of the model, NaN-for the selected');
BatchOpt.mibBatchTooltip.SelectedAddToMaterial = sprintf('index of the material to be added to; -1 for mask, 0-for exterior, 1,2,3 materials of the model, NaN-for the selected');
BatchOpt.mibBatchTooltip.restrictSelectionToMaterial = sprintf('when checked, limit selection only for the selected material');
BatchOpt.mibBatchTooltip.restrictSelectionToMask = sprintf('when checked, will do add, replace, remove actions only in the masked areas');
BatchOpt.mibBatchTooltip.blockModeSwitch = sprintf('force to use or not the block mode');
BatchOpt.mibBatchTooltip.roiId = sprintf('ROI mode: when less than 0, ROIs are not used; when 0 - move all ROIs; any number - move ROI with the index, [] - currently selected');
BatchOpt.mibBatchTooltip.fillBg = sprintf('ROI mode: when NaN - crop the dataset as a rectangle; when a number fills the areas out of the ROI area with this intensity');
BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not the progress bar during execution; always off for 2D datasets');

%% Batch mode check actions
if nargin == 6  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when varargin{3} == NaN return possible settings
            % trigger SyncBatch event to send BatchOptInOut to mibBatchController
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.moveLayers';
            ErrorDlgOpt.err = 'A structure as the 6th parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        % add/update BatchOpt with the provided fields in BatchOptIn
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% start function
% check for the virtual stacking mode and return
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.WindowHeight = 120;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', {''}, ...
        {'This action is not yet available in the virtual stacking mode. Please switch to the memory-resident mode and try again'}, ...
        'Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% BigData: moves of the selection to the labels or the mask go to
% MibBigDataLabels.moveSelection below. The other stack and dataset moves would go
% to the fast path, which edits the in-memory labels array - empty for a
% disk-backed model - so they would silently do nothing
if strcmp(obj.I{BatchOpt.id}.datasetType, 'BigData') && ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice') && ...
        ~(strcmp(BatchOpt.SourceLayer{1}, 'selection') && ismember(BatchOpt.DestinationLayer{1}, {'labels', 'mask'}))
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.WindowHeight = 120;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', {''}, ...
        {sprintf('For BigData datasets, only the selection can be moved for the whole stack.\nPlease use the 2D, Slice mode (shortcut without Shift)')}, ...
        'Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% when the Selection layer is disabled -> return
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 140;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'The models are disabled', {''}, ...
        {'The models, selection and mask layers are switched off! Please make sure that the "Enable selection" option in the Preferences dialog is set to "yes" and try again...'}, ...
        'The models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if BatchOpt.blockModeSwitch == 0
    if ~isfield(BatchOpt, 'roiId')
        BatchOpt.roiId = num2str(obj.I{BatchOpt.id}.selectedROI);
    end
else
    BatchOpt.roiId = '-1';
end

BatchOptLocal = BatchOpt;   % make a copy of the BatchOpt
BatchOpt = rmfield(BatchOpt, 'id');

% convert to numbers to use in MoveXXXtoXXXDataset functions
BatchOptLocal.SelectedMaterial = str2double(BatchOptLocal.SelectedMaterial);
if isnan(BatchOptLocal.SelectedMaterial)
    BatchOptLocal.SelectedMaterial = obj.I{BatchOptLocal.id}.getSelectedMaterialIndex();
end

BatchOptLocal.SelectedAddToMaterial = str2double(BatchOptLocal.SelectedAddToMaterial);
if isnan(BatchOptLocal.SelectedAddToMaterial)
    BatchOptLocal.SelectedAddToMaterial = obj.I{BatchOptLocal.id}.getSelectedMaterialIndex('AddTo');
end

BatchOptLocal.roiId = str2double(BatchOptLocal.roiId);
BatchOptLocal.fillBg = str2double(BatchOptLocal.fillBg);
BatchOptLocal.selected_sw = BatchOptLocal.restrictSelectionToMaterial;
BatchOptLocal.maskedAreaSw = BatchOptLocal.restrictSelectionToMask;

t1 = tic;

contSelIndex = BatchOptLocal.SelectedMaterial;
contAddIndex = BatchOptLocal.SelectedAddToMaterial;
if strcmp(BatchOptLocal.SourceLayer{1}, 'labels') && contSelIndex < 0; BatchOptLocal.SourceLayer{1} = 'mask'; end
if strcmp(BatchOptLocal.SourceLayer{1}, 'labels') && contAddIndex < 0; BatchOptLocal.DestinationLayer{1} = 'mask'; end

if strcmp(BatchOptLocal.SourceLayer{1}, 'mask') && ...
        strcmp(BatchOptLocal.DestinationLayer{1}, 'labels') && contAddIndex < 0; return; end

% fix situation when using Alt+A shortcut over the Mask entry when Fix
% selection to material is enabled
if BatchOptLocal.restrictSelectionToMaterial == 1 && strcmp(BatchOptLocal.SourceLayer{1}, 'mask') && contAddIndex == -1
    BatchOptLocal.restrictSelectionToMaterial = false;
end

% check for existence of the model layer
if obj.I{BatchOptLocal.id}.modelExist == 0 && strcmp(BatchOptLocal.DestinationLayer{1}, 'labels')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 140;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', {''}, ...
        {sprintf('Please Create the Model first!\nPress the Create button in the Segmentation panel')}, ...
        'The model is missing!', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

% tweak, when there is only a single time point in the dataset
if strcmp(BatchOptLocal.DatasetType{1}, '4D, Dataset') && obj.I{BatchOptLocal.id}.image.time == 1
    BatchOptLocal.DatasetType{1} = '3D, Stack';
end
% tweak, when there is only a single slice in the dataset
if strcmp(BatchOptLocal.DatasetType{1}, '3D, Stack') && obj.I{BatchOptLocal.id}.image.depth == 1
    BatchOptLocal.DatasetType{1} = '2D, Slice';
end

% BigData: selection -> labels/mask touches only the tiles holding selection, at
% the level their data lives at (see MibBigDataLabels.moveSelection). Its own
% progress dialog is cancelable, so this branch returns before the one below.
if isa(obj.I{BatchOptLocal.id}.labels, 'core.MibBigDataLabels') && ...
        strcmp(BatchOptLocal.SourceLayer{1}, 'selection') && ...
        ismember(BatchOptLocal.DestinationLayer{1}, {'labels', 'mask'}) && ...
        BatchOptLocal.roiId(1) < 0 && BatchOptLocal.blockModeSwitch == 0 && ...
        (~strcmp(BatchOptLocal.DatasetType{1}, '2D, Slice') || obj.I{BatchOptLocal.id}.orientation == 3)
    completed = moveSelectionBigData(obj, BatchOptLocal, contAddIndex, nargin < 6);
    if completed
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    else
        notify(obj, 'StopProtocol');
    end
    notify(obj, 'ShowImage');
    return;
end

if strcmp(BatchOptLocal.DatasetType{1}, '2D, Slice')
    switch3d = 0;
    showWaitbar = 0;
else
    switch3d = 1;
    showWaitbar = BatchOptLocal.showWaitbar;
end
if showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', sprintf('%s: %s to/with %s layer(s) for %s\nPlease wait...', ...
        BatchOptLocal.ActionType{1}, BatchOptLocal.SourceLayer{1}, BatchOptLocal.DestinationLayer{1}, BatchOptLocal.DatasetType{1}), ...
        'Title', 'Moving layers...', 'Indeterminate', 'on');
end

if strcmp(BatchOptLocal.DatasetType{1}, '4D, Dataset')
    BatchOptLocal.t = [1 obj.I{BatchOptLocal.id}.image.time];
else
    BatchOptLocal.t = [obj.I{BatchOptLocal.id}.slices{5}(1) obj.I{BatchOptLocal.id}.slices{5}(1)];
end

% Standard fast-scope: 'add' and 'remove' of the selection change nothing outside the
% selected voxels, so measure the selection's bounding box once (a few max-reductions,
% see MibDataset.getSelectionBoundingBox) and back up and process only that box.
% A box over a quarter of the volume is slower than the whole-volume pass (copy out,
% write back, and a ranged backup copies where a whole one shares memory), so it
% falls back to that pass. 'replace' also clears the destination outside the
% selection and keeps the whole-volume pass. Limited to the stack/dataset moves of
% the fast path below.
selectionBox = [];
if strcmp(BatchOptLocal.SourceLayer{1}, 'selection') && ...
        ismember(BatchOptLocal.DestinationLayer{1}, {'labels', 'mask'}) && ...
        ismember(BatchOptLocal.ActionType{1}, {'add', 'remove'}) && ...
        strcmp(obj.I{BatchOptLocal.id}.datasetType, 'Standard') && ...
        (strcmp(BatchOptLocal.DatasetType{1}, '4D, Dataset') || ...
        (strcmp(BatchOptLocal.DatasetType{1}, '3D, Stack') && obj.I{BatchOptLocal.id}.image.time == 1)) && ...
        BatchOptLocal.roiId(1) < 0 && BatchOptLocal.blockModeSwitch == 0 && ...
        ~any(isfield(BatchOptLocal, {'x', 'y', 'z'}))
    [selectionBox, boxFraction] = obj.I{BatchOptLocal.id}.getSelectionBoundingBox(BatchOptLocal.t);
    if isempty(selectionBox)    % nothing is selected, nothing to move
        if showWaitbar; delete(wb); end
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        return;
    end
    if boxFraction > 0.25
        selectionBox = [];
    else
        BatchOptLocal.y = selectionBox(1:2);
        BatchOptLocal.x = selectionBox(3:4);
        BatchOptLocal.z = selectionBox(5:6);
        BatchOptLocal.t = selectionBox(7:8);
    end
end

% do backup, not for 4D data
if ~strcmp(BatchOptLocal.DatasetType{1},'4D, Dataset')
    if isa(obj.I{BatchOptLocal.id}.labels, 'core.MibLabels63')
        obj.backup('everything', switch3d, BatchOptLocal);
    else
        obj.backup(BatchOptLocal.DestinationLayer{1}, switch3d, BatchOptLocal);
    end
end

% strip x/y/z/t from options before passing to fast-path helpers (P3 optimization)
fieldsToRemove = intersect(fieldnames(BatchOptLocal), {'x','y','z','t'});

% The fast path: full dataset without ROI/block mode
% Use direct array manipulation for maximum performance
if strcmp(BatchOptLocal.DatasetType{1},'4D, Dataset') || ...
        (strcmp(BatchOptLocal.DatasetType{1},'3D, Stack') && obj.I{BatchOptLocal.id}.image.time == 1) && ...
        BatchOptLocal.roiId(1) < 0 && BatchOptLocal.blockModeSwitch == 0

    BatchOptLocal.contSelIndex = contSelIndex;
    BatchOptLocal.contAddIndex = contAddIndex;

    % strip coordinate fields before passing to helpers
    helperOpt = BatchOptLocal;
    if ~isempty(fieldsToRemove)
        helperOpt = rmfield(helperOpt, fieldsToRemove);
    end
    helperOpt.box = selectionBox;

    switch BatchOptLocal.SourceLayer{1}
        case 'mask'
            switch BatchOptLocal.DestinationLayer{1}
                case 'selection'
                    obj.I{BatchOptLocal.id}.moveMaskToSelectionDataset(BatchOptLocal.ActionType{1}, helperOpt);
                case 'labels'
                    obj.I{BatchOptLocal.id}.moveMaskToModelDataset(BatchOptLocal.ActionType{1}, helperOpt);
                case 'mask'
                    return;
            end
        case 'labels'
            switch BatchOptLocal.DestinationLayer{1}
                case 'selection'
                    obj.I{BatchOptLocal.id}.moveModelToSelectionDataset(BatchOptLocal.ActionType{1}, helperOpt);
                case 'mask'
                    obj.I{BatchOptLocal.id}.moveModelToMaskDataset(BatchOptLocal.ActionType{1}, helperOpt);

                case 'labels'
                    return;
            end
        case 'selection'
            switch BatchOptLocal.DestinationLayer{1}
                case 'mask'
                    obj.I{BatchOptLocal.id}.moveSelectionToMaskDataset(BatchOptLocal.ActionType{1}, helperOpt);
                case 'labels'
                    obj.I{BatchOptLocal.id}.moveSelectionToModelDataset(BatchOptLocal.ActionType{1}, helperOpt);
                case 'selection'
                    return;
            end
    end
else
    % Slow path: move layers for 2D/3D with ROI and block modes
    % Uses getData/setData which handle transposition, ROI cropping, etc.
    if BatchOptLocal.blockModeSwitch
        orient = [];        % current orientation (block mode crops to visible area)
    else
        orient = 3;         % YX orientation, full dataset
    end

    switch BatchOptLocal.SourceLayer{1}
        case 'mask'
            if switch3d
                img = obj.I{BatchOptLocal.id}.getData4D('mask', orient, NaN, BatchOptLocal);
            else
                img = obj.I{BatchOptLocal.id}.getData2D('mask', [], [], NaN, BatchOptLocal);
            end
        case 'labels'
            if obj.I{BatchOptLocal.id}.modelExist == 0; if showWaitbar; delete(wb); end; notify(obj, 'StopProtocol'); return; end
            if switch3d
                img = obj.I{BatchOptLocal.id}.getData4D('labels', orient, contSelIndex, BatchOptLocal);
            else
                img = obj.I{BatchOptLocal.id}.getData2D('labels', [], [], contSelIndex, BatchOptLocal);
            end
        case 'selection'
            if switch3d
                img = obj.I{BatchOptLocal.id}.getData4D('selection', orient, NaN, BatchOptLocal);
                obj.I{BatchOptLocal.id}.clearLayer('selection', '3D');
            else
                img = obj.I{BatchOptLocal.id}.getData2D('selection', [], [], NaN, BatchOptLocal);
                obj.I{BatchOptLocal.id}.clearLayer('selection', '2D');
            end
    end

    % filter results by selected material
    if BatchOptLocal.restrictSelectionToMaterial && ~strcmp(BatchOptLocal.SourceLayer{1}, 'labels') && ...
            obj.I{BatchOptLocal.id}.modelExist && ~strcmp(BatchOptLocal.DestinationLayer{1}, 'labels')
        if switch3d
            sel_img = obj.I{BatchOptLocal.id}.getData4D('labels', orient, contSelIndex, BatchOptLocal);
        else
            sel_img = obj.I{BatchOptLocal.id}.getData2D('labels', [], [], contSelIndex, BatchOptLocal);
        end
        for i = 1:numel(img)
            img{i} = bitand(img{i}, sel_img{i});
        end
    end

    % filter results by mask
    if BatchOptLocal.restrictSelectionToMask
        if ~strcmp(BatchOptLocal.SourceLayer{1}, 'mask') && ~strcmp(BatchOptLocal.DestinationLayer{1}, 'mask')
            if switch3d
                mask = obj.I{BatchOptLocal.id}.getData4D('mask', orient, NaN, BatchOptLocal);
            else
                mask = obj.I{BatchOptLocal.id}.getData2D('mask', [], [], NaN, BatchOptLocal);
            end
            for i = 1:numel(mask)
                img{i} = bitand(img{i}, mask{i});
            end
        end
    end

    if switch3d     % 3D mode full dataset
        switch BatchOptLocal.DestinationLayer{1}
            case 'selection'
                switch BatchOptLocal.ActionType{1}
                    case 'add'
                        selection = obj.I{BatchOptLocal.id}.getData4D('selection', orient, NaN, BatchOptLocal);
                        for i = 1:numel(img)
                            selection{i} = bitor(selection{i}, img{i});
                        end
                    case 'replace'
                        selection = img;
                    case 'remove'
                        selection = obj.I{BatchOptLocal.id}.getData4D('selection', orient, NaN, BatchOptLocal);
                        for i = 1:numel(img)
                            selection{i} = selection{i} - img{i};
                        end
                end
                obj.I{BatchOptLocal.id}.setData4D(selection, 'selection', orient, NaN, BatchOptLocal);
            case 'mask'
                % allocate the mask container when it is missing (no-op for MibLabels63)
                obj.I{BatchOptLocal.id}.allocateMask();
                obj.I{BatchOptLocal.id}.maskExist = 1;
                switch BatchOptLocal.ActionType{1}
                    case 'add'
                        mask = obj.I{BatchOptLocal.id}.getData4D('mask', orient, NaN, BatchOptLocal);
                        for i = 1:numel(mask)
                            mask{i} = bitor(mask{i}, img{i});
                        end
                    case 'replace'
                        mask = img;
                    case 'remove'
                        mask = obj.I{BatchOptLocal.id}.getData4D('mask', orient, NaN, BatchOptLocal);
                        for i = 1:numel(img)
                            mask{i} = mask{i} - img{i};
                        end
                end
                obj.I{BatchOptLocal.id}.setData4D(mask, 'mask', orient, NaN, BatchOptLocal);
            case 'labels'
                if obj.I{BatchOptLocal.id}.modelExist == 0; if showWaitbar; delete(wb); end; notify(obj, 'StopProtocol'); return; end
                model = obj.I{BatchOptLocal.id}.getData4D('labels', orient, NaN, BatchOptLocal);
                obj.I{BatchOptLocal.id}.modelExist = 1;
                switch BatchOptLocal.ActionType{1}
                    case 'add'
                        for i = 1:numel(img)
                            model{i}(img{i} == 1) = contAddIndex;
                        end
                    case 'replace'
                        for i = 1:numel(img)
                            model{i}(model{i} == contAddIndex) = 0;
                            model{i}(img{i} == 1) = contAddIndex;
                        end
                    case 'remove'
                        if BatchOptLocal.restrictSelectionToMaterial
                            for i = 1:numel(img)
                                model{i}(img{i} == 1 & model{i} == contSelIndex) = 0;
                            end
                        else
                            for i = 1:numel(img)
                                model{i}(img{i} == 1) = 0;
                            end
                        end
                end
                obj.I{BatchOptLocal.id}.setData4D(model, 'labels', orient, NaN, BatchOptLocal);
        end
    else    % 2D mode, the current slice only
        switch BatchOptLocal.DestinationLayer{1}
            case 'selection'
                switch BatchOptLocal.ActionType{1}
                    case 'add'
                        selection = obj.I{BatchOptLocal.id}.getData2D('selection', [], [], NaN, BatchOptLocal);
                        for i = 1:numel(img)
                            selection{i}(img{i} == 1) = 1;
                        end
                    case 'replace'
                        selection = img;
                    case 'remove'
                        selection = obj.I{BatchOptLocal.id}.getData2D('selection', [], [], NaN, BatchOptLocal);
                        for i = 1:numel(img)
                            selection{i}(img{i} == 1) = 0;
                        end
                end
                obj.I{BatchOptLocal.id}.setData2D(selection, 'selection', [], [], [], BatchOptLocal);
            case 'mask'
                % allocate the mask container when it is missing (no-op for MibLabels63)
                obj.I{BatchOptLocal.id}.allocateMask();
                obj.I{BatchOptLocal.id}.maskExist = 1;
                switch BatchOptLocal.ActionType{1}
                    case 'add'
                        mask = obj.I{BatchOptLocal.id}.getData2D('mask', [], [], NaN, BatchOptLocal);
                        for i = 1:numel(mask)
                            mask{i} = bitor(mask{i}, img{i});
                        end
                    case 'replace'
                        mask = img;
                    case 'remove'
                        mask = obj.I{BatchOptLocal.id}.getData2D('mask', [], [], NaN, BatchOptLocal);
                        for i = 1:numel(img)
                            mask{i} = mask{i} - img{i};
                        end
                end
                obj.I{BatchOptLocal.id}.setData2D(mask, 'mask', [], [], [], BatchOptLocal);
            case 'labels'
                if obj.I{BatchOptLocal.id}.modelExist == 0
                    dlgOpt.MsgBoxOnly = true;
                    dlgOpt.HeaderLines = 1;
                    dlgOpt.WindowHeight = 120;
                    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'Problem with model', {''}, ...
                        {'No model, or the model of the wrong type. Press the Create button in the Segmentation panel to start a new model.'}, ...
                        'Problem with model', dlgOpt);
                    notify(obj, 'StopProtocol');
                    return;
                end
                obj.I{BatchOptLocal.id}.modelExist = 1;
                model = obj.I{BatchOptLocal.id}.getData2D('labels', [], [], NaN, BatchOptLocal);
                switch BatchOptLocal.ActionType{1}
                    case 'add'
                        for i = 1:numel(img)
                            model{i}(img{i} == 1) = contAddIndex;
                        end
                    case 'replace'
                        for i = 1:numel(img)
                            model{i}(model{i} == contAddIndex) = 0;
                            model{i}(img{i} == 1) = contAddIndex;
                        end
                    case 'remove'
                        if BatchOptLocal.restrictSelectionToMaterial
                            for i = 1:numel(img)
                                model{i}(img{i} == 1 & model{i} == contSelIndex) = 0;
                            end
                        else
                            for i = 1:numel(img)
                                model{i}(img{i} == 1) = 0;
                            end
                        end
                end
                obj.I{BatchOptLocal.id}.setData2D(model, 'labels', [], [], [], BatchOptLocal);
        end
        % notify MibModel that slice was added, used in Graphcut
        setDataOpt.type = BatchOptLocal.DestinationLayer{1};
        setDataOpt.mode = '2D';
        eventdata = core.ToggleEventData(setDataOpt);
        notify(obj, 'SetData', eventdata);
    end
end

% switch on Model layer
if strcmp(BatchOptLocal.DestinationLayer{1}, 'labels')
    obj.I{BatchOptLocal.id}.modelExist = 1;
    if ~obj.showModel
        obj.showModel = true;
        eventdata = core.ToggleEventData({'checkboxes'});
        notify(obj, 'UpdateGuiWidgets', eventdata);
    end
end

% switch on Mask layer
if strcmp(BatchOptLocal.DestinationLayer{1}, 'mask')
    obj.I{BatchOptLocal.id}.maskExist = 1;
    if ~obj.showMask
        obj.showMask = true;
        eventdata = core.ToggleEventData({'checkboxes'});
        notify(obj, 'UpdateGuiWidgets', eventdata);
    end
end

if switch3d; if showWaitbar; delete(wb); end; toc(t1); end

% notify the batch mode
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

notify(obj, 'ShowImage');   % render image

end

% ------------------------------------------------------------------------
function completed = moveSelectionBigData(obj, BatchOptLocal, contAddIndex, interactive)
% Move the selection to the labels or the mask of a disk-backed model, for the
% current slice (2D) or the whole stack (3D), through MibBigDataLabels.moveSelection.
%
% Shift+R (3D replace) asks first whether to replace only around the selection
% (the tiles holding it; fast, with undo) or in the whole volume (eraseEverywhere
% visits every written tile; slow, no undo). Batch runs take the whole volume,
% which is what replace means for a Standard dataset. 2D replace is local.
%
% The undo copy is taken at the level the move works at, over the box of the
% selection tiles. Above 2 GB the user is asked whether to keep it (batch runs
% skip it). On cancel the copy is written back, so nothing is left half-moved;
% without a copy the dialog says which slices were moved.
%
% Returns false when the move did not run to the end (the user cancelled).
completed = false;
id = BatchOptLocal.id;
labels = obj.I{id}.labels;
destination = BatchOptLocal.DestinationLayer{1};
action = BatchOptLocal.ActionType{1};
switch3d = ~strcmp(BatchOptLocal.DatasetType{1}, '2D, Slice');
if switch3d
    zRange = [1, obj.I{id}.image.depth];
else
    currentSlice = obj.I{id}.slices{3}(1);
    zRange = [currentSlice, currentSlice];
end
dlgParent = obj.getProgressBarParent();
dlgOpt = struct('Icon', 'puffin_question', 'WindowWidth', 540, 'WindowHeight', 270);

moveOptions = struct('z', zRange, 'materialIndex', contAddIndex, 'restrictMaterial', [], ...
    'restrictMask', BatchOptLocal.restrictSelectionToMask && strcmp(destination, 'labels'));
if BatchOptLocal.restrictSelectionToMaterial && obj.I{id}.modelExist
    moveOptions.restrictMaterial = BatchOptLocal.SelectedMaterial;
end

% --- Shift+R: around the selection or the whole volume
moveAction = action;
wholeVolume = false;
if strcmp(action, 'replace') && switch3d
    if interactive
        if strcmp(destination, 'labels')
            target = sprintf('material %d', contAddIndex);
        else
            target = 'the mask';
        end
        blockSize = labels.modelScaleFactors(end, 1:2);
        answer = utils.dlgs.inputQuestDlg(dlgParent, sprintf(['Replace %s with the selection of every slice that has one:\n\n' ...
            'Around the selection - on each slice with a selection, remove %s only inside the %d x %d pixel blocks ' ...
            'that the selection touches, then add the selection. Other slices are not changed. Fast, can be undone.\n\n' ...
            'Whole volume - remove %s from all slices, then add the selection. Reads the whole model, ' ...
            'which may take long for a large dataset, and cannot be undone.'], target, target, blockSize(1), blockSize(2), target), ...
            'Replace', 'Around the selection', 'Whole volume', 'Cancel', 'Around the selection', dlgOpt);
        switch answer
            case 'Whole volume'
                wholeVolume = true;
            case 'Around the selection'
            otherwise
                return;
        end
    else
        wholeVolume = true;
    end
end
if wholeVolume; moveAction = 'add'; end

[box, levelIdx] = labels.selectionFootprint(zRange, 1:3);
if isempty(box) && ~wholeVolume; completed = true; return; end   % nothing selected

% --- undo copy, at the level the move works at: ask first, copy once the
% progress dialog is up (reading the copy is the first slow step)
keepUndo = ~wholeVolume && ~isempty(box) && obj.Backup.enableSwitch;
if keepUndo
    levelScale = labels.modelScaleFactors(levelIdx, :);
    copyBytes = prod(ceil((box(2:2:end) - box(1:2:end) + 1) ./ levelScale)) * ...
        numel(typecast(zeros(1, labels.containerClass), 'uint8'));
    if copyBytes > 2 * 2^30
        if interactive
            dlgOpt.Icon = 'puffin_warning';
            answer = utils.dlgs.inputQuestDlg(dlgParent, sprintf(['The undo copy of this move needs %.1f GB of memory.\n\n' ...
                'Without undo the move cannot be reverted, nor stopped without leaving part of it done.'], copyBytes / 2^30), ...
                'Undo copy', 'Keep undo', 'Without undo', 'Cancel', 'Keep undo', dlgOpt);
            if strcmp(answer, 'Without undo')
                keepUndo = false;
            elseif ~strcmp(answer, 'Keep undo')
                return;
            end
        else
            keepUndo = false;
        end
    end
end

% --- progress, cancelable
wb = [];
moveMessage = sprintf('%s: selection to/with %s layer for %s\nPlease wait...', action, destination, BatchOptLocal.DatasetType{1});
if switch3d && BatchOptLocal.showWaitbar
    wb = uiprogressdlg(dlgParent, 'Title', 'Moving layers...', 'Value', 0, 'Cancelable', 'on', 'Message', moveMessage);
end

undoEntry = [];
if keepUndo
    if ~isempty(wb)
        wb.Message = sprintf('Making the undo copy (%.0f MB)...', copyBytes / 2^20);
        wb.Indeterminate = 'on';
        drawnow;
    end
    historyBefore = struct('undoList', obj.Backup.undoList, 'undoIndex', obj.Backup.undoIndex, ...
        'prevUndoIndex', obj.Backup.prevUndoIndex, 'index3d', obj.Backup.index3d);
    backupOptions = struct('id', id, 'magFactor', levelScale(1), 'y', box(1:2), 'x', box(3:4), 'z', box(5:6));
    obj.backup('everything', switch3d, backupOptions);
    if obj.Backup.undoIndex > 1
        % the entry just stored, to write back on cancel
        lastEntry = obj.Backup.undoList(obj.Backup.undoIndex - 1);
        if strcmp(lastEntry.type, 'everything') && isfield(lastEntry.options, 'z') && ...
                isequal(lastEntry.options.y, box(1:2)) && isequal(lastEntry.options.z, box(5:6))
            undoEntry = lastEntry;
        end
    end
    if ~isempty(wb)
        if wb.CancelRequested
            % nothing is changed yet: drop the copy just taken
            restoreHistory(obj, historyBefore);
            delete(wb);
            return;
        end
        wb.Indeterminate = 'off';
        wb.Message = moveMessage;
    end
end
progressStart = 0;
progressShare = 1;
if wholeVolume; progressShare = 0.5; end

% --- whole volume: remove the material or the mask everywhere first (no undo)
if wholeVolume
    if strcmp(destination, 'labels'); layerGroup = 1; else; layerGroup = 2; end
    eraseStatus = labels.eraseEverywhere(layerGroup, contAddIndex, makeProgressFcn(wb, 0, progressShare));
    if eraseStatus.cancelled
        if ~isempty(wb); delete(wb); end
        reportCancel(obj, interactive, sprintf(['Replace was stopped while removing the old values: they were removed from %d of %d tile planes, ' ...
            'and the selection was not added. This cannot be undone.'], eraseStatus.planesDone, size(labels.matLevel, 3)));
        return;
    end
    progressStart = 0.5;
end

% --- the move itself
moveOptions.progressFcn = makeProgressFcn(wb, progressStart, progressShare);
moveStatus = labels.moveSelection(destination, moveAction, moveOptions);
if moveStatus.cancelled
    if ~isempty(undoEntry)
        % write the copy back, then drop it: the move is as if never started
        if ~isempty(wb)
            wb.Message = 'Cancelling: restoring the model from the undo copy...';
            wb.Indeterminate = 'on';
            drawnow;
        end
        restoreHistory(obj, historyBefore);
        restoreOptions = rmfield(undoEntry.options, intersect(fieldnames(undoEntry.options), {'roiId'}));
        if undoEntry.options.switch3d
            obj.I{id}.setData3D(undoEntry.data{1}, 'everything', undoEntry.options.t(1), undoEntry.options.orient, NaN, restoreOptions);
        else
            obj.I{id}.setData2D(undoEntry.data{1}, 'everything', undoEntry.options.z(1), undoEntry.options.orient, NaN, restoreOptions);
        end
        if ~isempty(wb); delete(wb); end
        return;
    end
    if ~isempty(wb); delete(wb); end
    if isempty(moveStatus.zDone)
        doneText = 'No slices were changed.';
    else
        doneText = sprintf('Slices %d-%d were changed, the rest were not.', moveStatus.zDone(1), moveStatus.zDone(2));
    end
    reportCancel(obj, interactive, sprintf('The move was stopped without an undo copy. %s', doneText));
    return;
end
if ~isempty(wb); delete(wb); end

% --- switch the destination layer on, as for the other modes
if strcmp(destination, 'labels')
    obj.I{id}.modelExist = 1;
    if ~obj.showModel
        obj.showModel = true;
        notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
    end
else
    obj.I{id}.maskExist = 1;
    if ~obj.showMask
        obj.showMask = true;
        notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
    end
end
if ~switch3d
    % notify MibModel that slice was added, used in Graphcut
    notify(obj, 'SetData', core.ToggleEventData(struct('type', destination, 'mode', '2D')));
end
completed = true;
end

function restoreHistory(obj, historyBefore)
% put the undo history back as it was before a backup taken by this move
obj.Backup.undoList = historyBefore.undoList;
obj.Backup.undoIndex = historyBefore.undoIndex;
obj.Backup.prevUndoIndex = historyBefore.prevUndoIndex;
obj.Backup.index3d = historyBefore.index3d;
end

function progressFcn = makeProgressFcn(wb, progressStart, progressShare)
% cancel = progressFcn(fraction): show the progress of one stage, report a cancel
if isempty(wb); progressFcn = []; return; end
progressFcn = @(fraction) updateProgress(wb, progressStart + fraction * progressShare);
end

function cancelRequested = updateProgress(wb, value)
wb.Value = min(1, max(0, value));
cancelRequested = wb.CancelRequested;
end

function reportCancel(obj, interactive, message)
% say what the cancelled operation did and did not do
if interactive
    dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_warning', 'WindowHeight', 140);
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', {''}, {message}, 'Stopped', dlgOpt);
else
    warning('MibModel:moveLayers:cancelled', '%s', message);
end
end
