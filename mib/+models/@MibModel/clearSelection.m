function clearSelection(obj, sel_switch, BatchOptIn)
% CLEARSELECTION - Clear the Selection layer for the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.clearSelection(sel_switch, BatchOptIn)
%
% Clears all pixels in the Selection layer for the current slice,
% the whole z-stack, or the entire 4D dataset, depending on the
% requested scope.  Supports batch-processing mode via BatchOptIn.
%
% Input Arguments:
%   - **sel_switch** - *(optional)* string defining the clear scope
%   - '2D, Slice'   - clear the currently shown slice only (default)
%   - '3D, Stack'   - clear the full z-stack at the current time point(s)
%   - '4D, Dataset' - clear the entire dataset (all z and t)
%   - **BatchOptIn** - *(optional)* structure for batch processing mode; when
%     NaN, returns default options via the "SyncBatch" event
%   - .DatasetType  - cell {value, {choices}} selecting the clear scope
%   - .showWaitbar  - logical, show or not the progress bar
%   - .id           - dataset index 1-9; default = obj.id
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** - clear current slice
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearSelection('2D, Slice');
%
%   **Example 2** - clear current z-stack
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearSelection('3D, Stack');
%
%   **Example 3** - clear full dataset
%
%   .. code-block:: matlab
%
%      obj.mibModel.clearSelection('4D, Dataset');
%

% Updates
%

% do nothing if selection is disabled
if obj.I{obj.id}.enableSelection == 0; return; end

interactive = nargin < 3;   % a batch run passes BatchOptIn and gets no dialogs
if nargin < 3; BatchOptIn = struct(); end
if nargin < 2; sel_switch = []; end

%% Build default BatchOpt
BatchOpt = struct();
if ~isempty(sel_switch)
    BatchOpt.DatasetType = {sel_switch};
else
    BatchOpt.DatasetType = {'2D, Slice'};
end
BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();
BatchOpt.mibBatchTooltip.DatasetType = 'Select to remove selection from the current slice, stack, or dataset';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
BatchOpt.mibBatchActionName  = 'Clear selection';

%% Batch mode check
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isscalar(BatchOptIn) && isnan(BatchOptIn)    % return default options for batch editor
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle       = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.clearSelection';
            ErrorDlgOpt.err            = 'A structure as the 3rd parameter is required!';
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

% render waitbar; a BigData clear shows its own (clearSelectionBigData)
wb = [];
if BatchOpt.showWaitbar && ~strcmp(BatchOpt.DatasetType{1}, '2D, Slice') && ...
        ~isa(obj.I{BatchOpt.id}.labels, 'core.MibBigDataLabels')
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Title', 'Clearing selection', ...
        'Message', 'Clearing Selection layer...', ...
        'Indeterminate', 'on');
end

id = BatchOpt.id;
%% Perform the clear
switch BatchOpt.DatasetType{1}
    case '2D, Slice'
        backupOptions.id = id;
        if isa(obj.I{id}.labels, 'core.MibBigDataLabels')
            orient   = obj.I{id}.orientation;
            curSlice = obj.I{id}.slices{orient}(1);
            if orient == 3
                % XY view: clear the tiles that may hold selection on this slice
                % (MibBigDataLabels.clearSelectionTiles), backed up at the level
                % the selection lives at
                if ~clearSelectionBigData(obj, id, [curSlice, curSlice], 0, interactive, false)
                    notify(obj, 'StopProtocol');
                    return;
                end
            else
                % Non-XY view or unknown footprint: scope to visible window only.
                backupOptions.blockModeSwitch = true;
                obj.backup('selection', 0, backupOptions);
                obj.I{id}.clearLayer('selection', '2D', [], [], [], true);
            end
        else
            obj.backup('selection', 0, backupOptions);
            obj.I{id}.clearLayer('selection', '2D');
        end

    case '3D, Stack'
        backupOptions.id = id;
        timePoint = obj.I{id}.slices{5}(1);
        box = [];
        boxFraction = 1;
        if strcmp(obj.I{id}.datasetType, 'Standard')
            [box, boxFraction] = obj.I{id}.getSelectionBoundingBox([timePoint, timePoint]);
        end
        if isa(obj.I{id}.labels, 'core.MibBigDataLabels')
            % the tiles that may hold selection, through the stack
            if ~clearSelectionBigData(obj, id, [1, obj.I{id}.image.depth], 1, interactive, BatchOpt.showWaitbar)
                notify(obj, 'StopProtocol');
                return;
            end
        elseif boxFraction == 0
            % nothing is selected, nothing to clear
        elseif boxFraction <= 0.25
            % back up and clear only the box that holds the selection; a larger
            % box is slower than the whole stack, as a ranged backup copies where a
            % whole one shares memory with the layer
            backupOptions.y = box(1:2);
            backupOptions.x = box(3:4);
            backupOptions.z = box(5:6);
            obj.backup('selection', 1, backupOptions);
            obj.I{id}.clearLayer('selection', box(1:2), box(3:4), box(5:6), [timePoint, timePoint], false);
        else
            % backup the full z-stack
            obj.backup('selection', 1, backupOptions);
            obj.I{id}.clearLayer('selection', '3D');
        end
        if ~isempty(wb); delete(wb); end

    case '4D, Dataset'
        backupOptions.id = id;
        if isa(obj.I{id}.labels, 'core.MibBigDataLabels')
            % a BigData dataset has one time point: as for the stack
            if ~clearSelectionBigData(obj, id, [1, obj.I{id}.image.depth], 1, interactive, BatchOpt.showWaitbar)
                notify(obj, 'StopProtocol');
                return;
            end
        else
            % backup the full dataset
            obj.backup('selection', 1, backupOptions);
            obj.I{id}.clearLayer('selection', '4D');
            if BatchOpt.showWaitbar; delete(wb); end
        end
end

%% Notify batch system and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);
notify(obj, 'ShowImage');
end

% ------------------------------------------------------------------------
function cleared = clearSelectionBigData(obj, id, fullZ, switch3d, interactive, showWaitbar)
% Clear the selection of a disk-backed model over slices fullZ, touching only the
% tiles that may hold it (MibBigDataLabels.clearSelectionTiles). The undo copy is
% the selection at the finest level it lives at in those tiles, over their box:
% the clear itself writes the coarsest level, and an undo at that level would
% bring back only a coarse version. Above 2 GB the user is asked whether to keep
% it (batch runs skip it). Reading the copy is the slow step, so with showWaitbar
% a cancelable dialog opens after the question and before the copy; a cancel
% once the copy is read drops it from the undo history and clears nothing.
% Returns false when the user cancelled.
cleared = false;
keepUndo = false;
labels = obj.I{id}.labels;
[box, selectionLevel] = labels.selectionFootprint(fullZ, 3);
if isempty(box); cleared = true; return; end
if obj.Backup.enableSwitch
    levelScale = labels.modelScaleFactors(selectionLevel, :);
    copyBytes = prod(ceil((box(2:2:end) - box(1:2:end) + 1) ./ levelScale));   % uint8 per voxel
    keepUndo = true;
    if copyBytes > 2 * 2^30
        if interactive
            dlgOpt = struct('Icon', 'puffin_warning', 'WindowWidth', 480, 'WindowHeight', 180);
            answer = utils.dlgs.inputQuestDlg(obj.getProgressBarParent(), ...
                sprintf('The undo copy of this clear needs %.1f GB of memory.', copyBytes / 2^30), ...
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

wb = [];
if showWaitbar
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Title', 'Clearing selection', ...
        'Message', 'Clearing Selection layer...', 'Indeterminate', 'on', 'Cancelable', 'on');
end
if keepUndo
    if ~isempty(wb)
        wb.Message = sprintf('Making the undo copy (%.0f MB)...', copyBytes / 2^20);
        drawnow;
    end
    historyBefore = struct('undoList', obj.Backup.undoList, 'undoIndex', obj.Backup.undoIndex, ...
        'prevUndoIndex', obj.Backup.prevUndoIndex, 'index3d', obj.Backup.index3d);
    backupOptions = struct('id', id, 'magFactor', levelScale(1), 'y', box(1:2), 'x', box(3:4), 'z', box(5:6));
    obj.backup('selection', switch3d, backupOptions);
    if ~isempty(wb) && wb.CancelRequested
        % nothing is cleared yet: drop the copy just taken
        obj.Backup.undoList = historyBefore.undoList;
        obj.Backup.undoIndex = historyBefore.undoIndex;
        obj.Backup.prevUndoIndex = historyBefore.prevUndoIndex;
        obj.Backup.index3d = historyBefore.index3d;
        delete(wb);
        return;
    end
end
if ~isempty(wb)
    wb.Message = 'Clearing Selection layer...';
    drawnow;
end
labels.clearSelectionTiles(fullZ);
if ~isempty(wb); delete(wb); end
cleared = true;
end
