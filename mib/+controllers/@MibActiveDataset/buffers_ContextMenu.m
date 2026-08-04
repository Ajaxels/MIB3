function buffers_ContextMenu(obj, parameter, buttonID, BatchOptIn)
% BUFFERS_CONTEXTMENU - Callback for context menu operations on dataset buffers.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.buffers_ContextMenu(parameter, buttonID, BatchOptIn)
%
% Handles context menu operations for the buffer buttons (``buffer1`` through ``buffer10``)
% in the Datasets panel. Supports both interactive mode (via right-click menu) and batch
% processing mode. Batch-compatible.
%
% Input Arguments:
%   - **parameter** — [char] action to perform:
%
%     - ``'duplicate'`` — duplicate selected buffer to another buffer
%     - ``'sync_xy'`` — synchronize XY view parameters across buffers
%     - ``'sync_xyz'`` — synchronize XYZ view parameters across buffers
%     - ``'sync_xyzt'`` — synchronize all dimensions and time across buffers
%     - ``'link_views'`` — link or unlink views between two buffers
%     - ``'close'`` — close the current dataset in the buffer
%     - ``'closeSet'`` — close all datasets in the current set
%
%   - **buttonID** — [numeric] local buffer index (1–10), or ``NaN`` when called from batch mode without a physical button press
%   - **BatchOptIn** — *(optional)* [struct] batch processing mode options; when ``NaN``, returns default structure via ``'SyncBatch'`` event
%
% Output Arguments:
%   None
%
% **Example 1** — duplicate buffer interactively:
%
%   .. code-block:: matlab
%
%      obj.buffers_ContextMenu('duplicate', 2)
%
% **Example 2** — duplicate dataset in batch mode:
%
%   .. code-block:: matlab
%
%      BatchOpt.Source = {'Container 1'};
%      BatchOpt.Destination = {'Container 3'};
%      BatchOpt.showWaitbar = false;
%      obj.buffers_ContextMenu('duplicate', NaN, BatchOpt)
%

% Updates
% Based on mibBufferToggleContext_Callback (MIB2), ported to MIB3

if nargin < 4; BatchOptIn = struct(); end
if nargin < 3; buttonID = NaN; end
if isempty(buttonID); buttonID = NaN; end

maxId = obj.mibModel.Sets.datasetsInSet * numel(obj.mibModel.Sets.names);  % total containers across all sets
selectedSet = obj.mibModel.Sets.selectedSet;
interactiveMode = isstruct(BatchOptIn) && isempty(fieldnames(BatchOptIn));  % true when called via UI (not batch)

% compute global dataset index and normalise local button ID
if isnan(buttonID)
    globalDatasetIndex = obj.mibModel.id;
    buttonID = mod(obj.mibModel.id-1, obj.mibModel.Sets.datasetsInSet) + 1;
else
    globalDatasetIndex = buttonID + (selectedSet-1)*obj.mibModel.Sets.datasetsInSet;
end
bufferStringId = sprintf('buffer%d', buttonID);

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibActiveDataset.buffers_ContextMenu: button %d (global %d), action: %s\n', ...
        buttonID, globalDatasetIndex, parameter);
end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
switch parameter
    case 'link_views'
        % find a default destination (first loaded dataset different from current)
        destinationGlobalId = maxId;
        for iDs = 1:maxId
            if isLoadedContainer(obj.mibModel, iDs) && iDs ~= globalDatasetIndex
                destinationGlobalId = iDs;
                break;
            end
        end

        BatchOpt.ContainerA = {sprintf('Container %d', globalDatasetIndex)};
        BatchOpt.ContainerA{2} = [{'Current'}, arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false)];
        BatchOpt.ContainerB = {sprintf('Container %d', destinationGlobalId)};
        BatchOpt.ContainerB{2} = arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false);
        % default: toggle current link state (linked → unlink, unlinked → link)
        linked = obj.handles.(bufferStringId).UIContextMenu.Children(3).Text(1) == '['; % check for "[Linked..."
        BatchOpt.Linked = ~linked;
        BatchOpt.mibBatchTooltip.ContainerA = 'Index of the first container to link the views';
        BatchOpt.mibBatchTooltip.ContainerB = 'Index of the second container to link the views';
        BatchOpt.mibBatchTooltip.Linked = 'Check to link the views between ContainerA and ContainerB';
        BatchOpt.mibBatchActionName = 'Link views';

    case 'duplicate'
        % find first empty buffer in the current set as default destination
        destinationLocalId = obj.mibModel.Sets.datasetsInSet;
        for iDs = 1:obj.mibModel.Sets.datasetsInSet
            globalI = iDs + (selectedSet-1)*obj.mibModel.Sets.datasetsInSet;
            if ~isLoadedContainer(obj.mibModel, globalI)
                destinationLocalId = iDs;
                break;
            end
        end
        destinationGlobalId = destinationLocalId + (selectedSet-1)*obj.mibModel.Sets.datasetsInSet;

        BatchOpt.Source = {sprintf('Container %d', globalDatasetIndex)};
        BatchOpt.Source{2} = [{'Current'}, arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false)];
        BatchOpt.Destination = {sprintf('Container %d', destinationGlobalId)};
        BatchOpt.Destination{2} = arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false);
        BatchOpt.showWaitbar = true;
        BatchOpt.mibBatchTooltip.Source = 'Index of the source container with a dataset to copy';
        BatchOpt.mibBatchTooltip.Destination = 'Index of the destination container to copy the current dataset';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
        BatchOpt.mibBatchActionName = 'Duplicate dataset';

    case 'close'
        BatchOpt.Target = {sprintf('Container %d', globalDatasetIndex)};
        BatchOpt.Target{2} = [{'Current'}, arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false)];
        BatchOpt.mibBatchTooltip.Target = 'Index of the target container with a dataset to close';
        BatchOpt.mibBatchActionName = 'Close dataset';

    case 'closeSet'
        %BatchOpt.SetName = [{'Current'}; obj.mibModel.Sets.names];
        BatchOpt.SetName = obj.mibModel.Sets.names(obj.mibModel.Sets.selectedSet);
        BatchOpt.SetName{2} = [{'Current'}; obj.mibModel.Sets.names];   % dropdown: items + default index 1
        BatchOpt.showWaitbar = true;
        BatchOpt.mibBatchTooltip.SetName = 'Name of the set to close; use "Current" for the currently active set';
        BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';
        BatchOpt.mibBatchActionName = 'Close all datasets in set';

    case {'sync_xy', 'sync_xyz', 'sync_xyzt'}
        % find first loaded dataset different from current
        destinationGlobalId = maxId;
        for iDs = 1:maxId
            if isLoadedContainer(obj.mibModel, iDs) && iDs ~= globalDatasetIndex
                destinationGlobalId = iDs;
                break;
            end
        end

        BatchOpt.ApplyTo = {sprintf('Container %d', globalDatasetIndex)};
        BatchOpt.ApplyTo{2} = [{'Current'}, arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false)];
        BatchOpt.GetFrom = {sprintf('Container %d', destinationGlobalId)};
        BatchOpt.GetFrom{2} = arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false);
        BatchOpt.Mode = {parameter};
        BatchOpt.Mode{2} = {'sync_xy', 'sync_xyz', 'sync_xyzt'};
        BatchOpt.mibBatchTooltip.ApplyTo = 'Index of a container to be synchronized with another one';
        BatchOpt.mibBatchTooltip.GetFrom = 'Index of a container with desired viewing parameters';
        BatchOpt.mibBatchTooltip.Mode = 'Specify dimensions that should be synchronized';
        BatchOpt.mibBatchActionName = 'Sync views';
end
BatchOpt.mibBatchSectionName = 'Panel -> Datasets';

%% Batch mode check actions
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)     % when BatchOptIn == NaN return possible settings
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);
    else
        utils.dlgs.showErrorDialog(obj.view.gui, 'A structure as the 4th parameter is required!', ...
            'Error in buffers_ContextMenu');
    end
    return;
elseif ~interactiveMode
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

%% Execute the selected action
switch parameter
    case 'link_views'
        if strcmp(BatchOpt.ContainerA{1}, 'Current')
            buttonGlobalA = obj.mibModel.id;
        else
            buttonGlobalA = str2double(BatchOpt.ContainerA{1}(10:end));
        end
        buttonLocalA = mod(buttonGlobalA-1, obj.mibModel.Sets.datasetsInSet) + 1;
        bufferStrA = sprintf('buffer%d', buttonLocalA);

        if BatchOpt.Linked == false  % unlink the two containers
            linkText = obj.handles.(bufferStrA).UIContextMenu.Children(3).Text;
            ids = sscanf(linkText, '[Linked: %d <-> %d]');
            if numel(ids) >= 2
                bufferStrB = sprintf('buffer%d', ids(2));
                obj.handles.(bufferStrA).UIContextMenu.Children(3).Text = 'Link view with... [Unlinked]';
                obj.handles.(bufferStrB).UIContextMenu.Children(3).Text = 'Link view with... [Unlinked]';
            end
            % remove from linkedPairs
            obj.mibModel.linkedPairs = obj.mibModel.linkedPairs( ...
                ~any(obj.mibModel.linkedPairs == buttonGlobalA, 2), :);
        else  % link two containers
            if interactiveMode
                destGlobalId = str2double(BatchOpt.ContainerB{1}(10:end));
                destSetIdx   = ceil(destGlobalId / obj.mibModel.Sets.datasetsInSet);
                destLocalId  = mod(destGlobalId-1, obj.mibModel.Sets.datasetsInSet) + 1;

                prompts = {'Destination set:', sprintf('Destination buffer (1-%d):', obj.mibModel.Sets.datasetsInSet)};
                setItems = obj.mibModel.Sets.names(:)';
                defAns = {[setItems, {destSetIdx}], ...
                           struct('Spinner', true, 'Value', destLocalId, 'Limits', [1 obj.mibModel.Sets.datasetsInSet], 'Step', 1, 'Round', true)};
                dlgOptions.mibPath = obj.mibModel.mibPath;
                dlgOptions.LabelPosition = 'left';
                dlgOptions.Focus = 2;
                [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, 'Link views', dlgOptions);
                if isempty(answer); return; end

                destSetIdx   = selIndex(1);
                destLocalId  = answer{2};
                destGlobalId = destLocalId + (destSetIdx-1)*obj.mibModel.Sets.datasetsInSet;
                BatchOpt.ContainerB(1) = {sprintf('Container %d', destGlobalId)};
            end
            buttonGlobalB = str2double(BatchOpt.ContainerB{1}(10:end));

            if buttonGlobalB == buttonGlobalA
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                dlgOpt.WindowHeight = 180;
                utils.dlgs.inputUniversalDlg(obj.view.gui, '', {''}, ...
                    {sprintf('Please select 2 different datasets!\n\nSelected datasets:\n   %s\n   %s', ...
                    BatchOpt.ContainerA{1}, BatchOpt.ContainerB{1})}, ...
                    'Wrong selection!', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            if obj.mibModel.I{buttonGlobalA}.orientation ~= obj.mibModel.I{buttonGlobalB}.orientation
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('The datasets should be in the same orientation!\n\nFor example, switch orientation of both datasets to XY (the XY button in the toolbar) and try again'), ...
                    'Wrong buffer');
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            buttonLocalB = mod(buttonGlobalB-1, obj.mibModel.Sets.datasetsInSet) + 1;
            bufferStrB = sprintf('buffer%d', buttonLocalB);

            % check that the destination is not already linked
            if obj.handles.(bufferStrB).UIContextMenu.Children(3).Text(1) == '['
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, '', {''}, ...
                    {sprintf('The second dataset in %s is already linked!\nUnlink it first and repeat the operation', ...
                    BatchOpt.ContainerB{1})}, ...
                    'Already linked!', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            % store link state as context menu text (per-button, local IDs)
            obj.handles.(bufferStrA).UIContextMenu.Children(3).Text = ...
                sprintf('[Linked: %d <-> %d] press to unlink', buttonLocalA, buttonLocalB);
            obj.handles.(bufferStrB).UIContextMenu.Children(3).Text = ...
                sprintf('[Linked: %d <-> %d] press to unlink', buttonLocalB, buttonLocalA);

            % register in model's linkedPairs (global IDs, order: smaller first)
            obj.mibModel.linkedPairs(end+1, :) = sort([buttonGlobalA, buttonGlobalB]);
        end

        % notify batch
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);

    case 'duplicate'
        if interactiveMode
            destGlobalId = str2double(BatchOpt.Destination{1}(10:end));
            destSetIdx   = ceil(destGlobalId / obj.mibModel.Sets.datasetsInSet);
            destLocalId  = min([mod(destGlobalId-1, obj.mibModel.Sets.datasetsInSet) + 1 obj.mibModel.Sets.datasetsInSet]);

            prompts = {'Destination set:', ...
                       sprintf('Destination buffer (1-%d):', obj.mibModel.Sets.datasetsInSet)};
            setItems = obj.mibModel.Sets.names(:)';   % row cell of set name strings
            defAns = {[setItems, {destSetIdx}], ...
                       struct('Spinner', true, 'Value', destLocalId, 'Limits', [1 obj.mibModel.Sets.datasetsInSet], 'Step', 1, 'Round', true)};
            dlgOptions.mibPath = obj.mibModel.mibPath;
            dlgOptions.LabelPosition = 'left';
            dlgOptions.Focus = 2;
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, 'Duplicate dataset', dlgOptions);
            if isempty(answer); return; end

            destSetIdx  = selIndex(1);
            destLocalId = answer{2};
            destGlobalId = destLocalId + (destSetIdx-1)*obj.mibModel.Sets.datasetsInSet;
            BatchOpt.Destination(1) = {sprintf('Container %d', destGlobalId)};
        end

        if strcmp(BatchOpt.Source{1}, 'Current')
            srcGlobalId = obj.mibModel.getActiveId;
        else
            srcGlobalId = str2double(BatchOpt.Source{1}(10:end));
        end
        destGlobalId = str2double(BatchOpt.Destination{1}(10:end));

        % warn if overwriting a non-empty buffer (interactive mode only)
        if interactiveMode && isLoadedContainer(obj.mibModel, destGlobalId)
            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                sprintf('You are going to overwrite dataset in buffer %d\n\nAre you sure?', destGlobalId), ...
                '!! Warning !!', 'Overwrite', 'Cancel', 'Cancel');
            if strcmp(button, 'Cancel'); return; end
        end

        deepCopyOpt.showWaitbar = BatchOpt.showWaitbar;
        deepCopyOpt.UIFigure    = obj.view.gui;
        obj.mibModel.deepCopyDataset(srcGlobalId, destGlobalId, deepCopyOpt);

        % update destination button appearance
        destLocalId = mod(destGlobalId-1, obj.mibModel.Sets.datasetsInSet) + 1;
        dstBufferStr = sprintf('buffer%d', destLocalId);
        obj.handles.(dstBufferStr).BackgroundColor = [0.7 1 0.7];
        obj.handles.(dstBufferStr).Tooltip = obj.mibModel.I{destGlobalId}.image.filename;

        % notify: triggers axes initialisation, GUI update, and image redraw
        EventDataOpt.mode = 'resize';
        EventDataOpt.index = destGlobalId;
        notify(obj.mibModel, 'NewDataset', core.ToggleEventData(EventDataOpt));

        % notify batch
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);

    case {'sync_xy', 'sync_xyz', 'sync_xyzt'}
        if interactiveMode
            srcGlobalId = str2double(BatchOpt.GetFrom{1}(10:end));
            srcSetIdx   = ceil(srcGlobalId / obj.mibModel.Sets.datasetsInSet);
            srcLocalId  = mod(srcGlobalId-1, obj.mibModel.Sets.datasetsInSet) + 1;

            prompts = {'Source set:', sprintf('Source buffer (1-%d):', obj.mibModel.Sets.datasetsInSet)};
            setItems = obj.mibModel.Sets.names(:)';
            defAns = {[setItems, {srcSetIdx}], ...
                       struct('Spinner', true, 'Value', srcLocalId, 'Limits', [1 obj.mibModel.Sets.datasetsInSet], 'Step', 1, 'Round', true)};
            dlgOptions.mibPath = obj.mibModel.mibPath;
            dlgOptions.LabelPosition = 'left';
            dlgOptions.Focus = 2;
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, 'Synchronize dataset', dlgOptions);
            if isempty(answer); return; end

            srcSetIdx  = selIndex(1);
            srcLocalId = answer{2};
            srcGlobalId = srcLocalId + (srcSetIdx-1)*obj.mibModel.Sets.datasetsInSet;
            BatchOpt.GetFrom(1) = {sprintf('Container %d', srcGlobalId)};
        end

        srcGlobalId = str2double(BatchOpt.GetFrom{1}(10:end));
        if strcmp(BatchOpt.ApplyTo{1}, 'Current')
            dstGlobalId = obj.mibModel.id;
        else
            dstGlobalId = str2double(BatchOpt.ApplyTo{1}(10:end));
        end

        if obj.mibModel.I{dstGlobalId}.orientation ~= obj.mibModel.I{srcGlobalId}.orientation
            utils.dlgs.showErrorDialog(obj.view.gui, ...
                sprintf('The datasets should be in the same orientation!\n\nFor example, switch orientation of both datasets to XY (the XY button in the toolbar) and try again'), ...
                'Wrong buffer');
            notify(obj.mibModel, 'StopProtocol');
            return;
        end

        % sync XY axes and magnification
        [axesX, axesY] = obj.mibModel.getAxesLimits(srcGlobalId);
        obj.mibModel.setAxesLimits(axesX, axesY, dstGlobalId);
        obj.mibModel.setMagFactor(obj.mibModel.getMagFactor(srcGlobalId), dstGlobalId);

        if strcmp(BatchOpt.Mode{1}, 'sync_xyz') || strcmp(BatchOpt.Mode{1}, 'sync_xyzt')
            orient = obj.mibModel.I{srcGlobalId}.orientation;
            destZ = obj.mibModel.I{srcGlobalId}.slices{orient}(1);
            if destZ > obj.mibModel.I{dstGlobalId}.dim_yxzct(obj.mibModel.I{dstGlobalId}.orientation)
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                dlgOpt.WindowHeight = 180;
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'Dimensions mismatch!', {''}, ...
                    {sprintf('The second dataset has the Z value higher than the Z-dimension of the first dataset!\n\nThe synchronization was done in the XY mode.')}, ...
                    'Dimensions mismatch!', dlgOpt);
                notify(obj.mibModel, 'ShowImage');
                notify(obj.mibModel, 'StopProtocol');
                return;
            end
            if obj.mibModel.I{dstGlobalId}.image.depth > 1
                obj.mibController.cImageDoc{selectedSet}.sliceNumber_Callback(destZ);
            end

            if strcmp(BatchOpt.Mode{1}, 'sync_xyzt') && obj.mibModel.I{dstGlobalId}.image.time > 1
                destT = obj.mibModel.I{srcGlobalId}.slices{5}(1);
                if destT > obj.mibModel.I{dstGlobalId}.image.time
                    dlgOpt.MsgBoxOnly = true;
                    dlgOpt.Icon = 'puffin_warning';
                    dlgOpt.HeaderLines = 1;
                    dlgOpt.WindowHeight = 180;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, 'Dimensions mismatch!', {''}, ...
                        {sprintf('The second dataset has the T value higher than the T-dimension of the first dataset!\n\nThe synchronization was done in the XYZ mode.')}, ...
                        'Dimensions mismatch!', dlgOpt);
                    notify(obj.mibModel, 'ShowImage');
                    notify(obj.mibModel, 'StopProtocol');
                    return;
                end
                obj.mibController.cImageDoc{selectedSet}.frameNumber_Callback(destT);
            end
        end

        notify(obj.mibModel, 'ShowImage');
        % note: sync does not notify SyncBatch — matches MIB2 behaviour

    case 'close'
        if strcmp(BatchOpt.Target{1}, 'Current')
            targetGlobalId = obj.mibModel.id;
        else
            targetGlobalId = str2double(BatchOpt.Target{1}(10:end));
        end
        targetLocalId = mod(targetGlobalId-1, obj.mibModel.Sets.datasetsInSet) + 1;
        targetBufferStr = sprintf('buffer%d', targetLocalId);

        % remember the currently selected dataset type so closing keeps the buffer
        % in that mode (Virtual / BigData) instead of always reverting to Standard
        prevDatasetType = obj.mibModel.I{targetGlobalId}.datasetType;

        obj.mibModel.I{targetGlobalId}.closeVirtualDataset();
        delete(obj.mibModel.I{targetGlobalId});

        % create a fresh empty dataset in place of the closed one
        fn = fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.png');
        imgData = imread(fn);
        meta = dictionary();
        if obj.mibModel.preferences.System.EnableSelection
            obj.mibModel.I{targetGlobalId} = core.MibDataset(imgData, meta, 'Standard', 'labels63');
        else
            obj.mibModel.I{targetGlobalId} = core.MibDataset(imgData, meta, 'Standard', 'imageOnly');
            obj.mibModel.I{targetGlobalId}.enableSelection = false;
        end
        obj.mibModel.I{targetGlobalId}.labels.materialColors = obj.mibModel.preferences.Colors.ModelMaterialColors;
        if obj.mibModel.I{targetGlobalId}.image.colors < size(obj.mibModel.preferences.Colors.LUTColors, 1)
            obj.mibModel.I{targetGlobalId}.image.lutColors = obj.mibModel.preferences.Colors.LUTColors;
        end

        % keep the buffer in the previously selected dataset type: if it was
        % Virtual / BigData, switch the fresh placeholder into that mode (empty,
        % browse-only) so the type dropdown and Sets.datasetTypes stay consistent
        % rather than reverting to Standard. Standard is left as created above.
        targetSet = floor((targetGlobalId - 1) / obj.mibModel.Sets.datasetsInSet) + 1;
        switch prevDatasetType
            case 'Virtual'
                defH5 = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
                obj.mibModel.I{targetGlobalId}.switchDatasetMode(2, ...
                    obj.mibModel.preferences.System.EnableSelection, defH5);
            case 'BigData'
                defH5 = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
                obj.mibModel.I{targetGlobalId}.switchDatasetMode(3, ...
                    obj.mibModel.preferences.System.EnableSelection, defH5);
        end
        obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = prevDatasetType;

        % unlink this dataset: reset partner's context menu text and remove from linkedPairs
        partnerOfTarget = obj.mibModel.getLinkedDataset(targetGlobalId);
        if ~isempty(partnerOfTarget)
            partnerLocalId = mod(partnerOfTarget-1, obj.mibModel.Sets.datasetsInSet) + 1;
            partnerBufStr  = sprintf('buffer%d', partnerLocalId);
            obj.handles.(partnerBufStr).UIContextMenu.Children(3).Text = 'Link view with... [Unlinked]';
            obj.mibModel.linkedPairs = obj.mibModel.linkedPairs( ...
                ~any(obj.mibModel.linkedPairs == targetGlobalId, 2), :);
        end

        % reset button appearance
        defaultColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;
        obj.handles.(targetBufferStr).BackgroundColor = defaultColor;
        obj.handles.(targetBufferStr).Tooltip = 'use RMB for a context menu with additional options';

        % notify: triggers axes initialisation, GUI update, and image redraw
        Options.mode = 'resize';
        Options.index = targetGlobalId;
        notify(obj.mibModel, 'NewDataset', core.ToggleEventData(Options));

        % notify batch
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);

    case 'closeSet'
        % resolve target set index
        if strcmp(BatchOpt.SetName{1}, 'Current')
            targetSet = selectedSet;
        else
            targetSet = find(strcmp(obj.mibModel.Sets.names, BatchOpt.SetName{1}), 1);
            if isempty(targetSet)
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Set "%s" not found.', BatchOpt.SetName{1}), 'Error');
                return;
            end
        end

        if interactiveMode
            selection = uiconfirm(obj.view.gui, ...
                sprintf('!!! Warning !!!\n\nYou are going to close all datasets in set "%s"!\nContinue?', ...
                    obj.mibModel.Sets.names{targetSet}), ...
                'Close all datasets', 'Icon', 'warning', 'DefaultOption', 2);
            if strcmp(selection, 'Cancel'); return; end
        end

        pwb = [];
        if BatchOpt.showWaitbar
            pwb = core.PoolWaitbar(obj.mibModel.Sets.datasetsInSet, 'Please wait...', obj.view.gui, 'Close all datasets', true);
        end

        fn = fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.png');
        imgData = imread(fn);
        firstGlobalId = (targetSet-1)*obj.mibModel.Sets.datasetsInSet + 1;
        defaultColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;

        for iButton = 1:obj.mibModel.Sets.datasetsInSet
            globalI = firstGlobalId + iButton - 1;

            % reset partner's context menu text before closing
            partnerI = obj.mibModel.getLinkedDataset(globalI);
            if ~isempty(partnerI)
                partnerLocalId = mod(partnerI-1, obj.mibModel.Sets.datasetsInSet) + 1;
                partnerBufStr  = sprintf('buffer%d', partnerLocalId);
                obj.handles.(partnerBufStr).UIContextMenu.Children(3).Text = 'Link view with... [Unlinked]';
            end

            obj.mibModel.I{globalI}.closeVirtualDataset();
            delete(obj.mibModel.I{globalI});

            meta = dictionary();
            if obj.mibModel.preferences.System.EnableSelection
                obj.mibModel.I{globalI} = core.MibDataset(imgData, meta, 'Standard', 'labels63');
            else
                obj.mibModel.I{globalI} = core.MibDataset(imgData, meta, 'Standard', 'imageOnly');
                obj.mibModel.I{globalI}.enableSelection = false;
            end
            obj.mibModel.I{globalI}.labels.materialColors = obj.mibModel.preferences.Colors.ModelMaterialColors;
            if obj.mibModel.I{globalI}.image.colors < size(obj.mibModel.preferences.Colors.LUTColors, 1)
                obj.mibModel.I{globalI}.image.lutColors = obj.mibModel.preferences.Colors.LUTColors;
            end

            % the replacement is a Standard dataset — reset the panel type label
            obj.mibModel.Sets.datasetTypes{targetSet, iButton} = 'Standard';

            % reset buffer buttons only when closing the currently visible set
            if targetSet == selectedSet
                bufBtn = sprintf('buffer%d', iButton);
                obj.handles.(bufBtn).BackgroundColor = defaultColor;
                obj.handles.(bufBtn).Tooltip = 'use RMB for a context menu with additional options';
            end

            if ~isempty(pwb)
                if ~isempty(pwb) && pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
                pwb.increment(); 
            end
        end

        % remove all linkedPairs involving any dataset in the closed set
        lastGlobalId = firstGlobalId + obj.mibModel.Sets.datasetsInSet - 1;
        closedIds = firstGlobalId:lastGlobalId;
        obj.mibModel.linkedPairs = obj.mibModel.linkedPairs( ...
            ~any(ismember(obj.mibModel.linkedPairs, closedIds), 2), :);

        % switch to buffer 1 of the target set; if target == current set,
        % also update obj.mibModel.id and mark buffer 1 as active
        obj.mibModel.Sets.selectedDataset(targetSet) = 1;
        if targetSet == selectedSet
            obj.mibModel.id = firstGlobalId;
            obj.handles.buffer1.BackgroundColor = [0 1 0];  % mark buffer 1 as active
        end

        if ~isempty(pwb); pwb.deletePoolWaitbar(); end

        % reinitialise axes for ALL datasets in the target set;
        % stale axesX/axesY from the old images cause showImage to fail when
        % the user switches to any non-active buffer after closeSet
        for iButton = 1:obj.mibModel.Sets.datasetsInSet
            AxesOpt.mode  = 'resize';
            AxesOpt.index = firstGlobalId + iButton - 1;
            notify(obj.mibModel, 'UpdateDatasetAxes', core.ToggleEventData(AxesOpt));
        end

        notify(obj.mibModel, 'NewDataset');

        % notify batch
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);
end

end

function loaded = isLoadedContainer(mibModel, containerId)
% ISLOADEDCONTAINER - check whether a container holds a dataset loaded from a file.
%
% Returns ``false`` for empty containers ('none.tif') and, importantly, also for
% containers left in a broken state by a failed load or dataset-mode switch,
% where the image layer is not a core.MibImage. Without this guard the scans
% above crash with "Dot indexing is not supported for variables of type double"
% and make the whole context menu unusable because of a single bad container.
%
% Input Arguments:
%   - **mibModel** — [models.MibModel] handle to the model
%   - **containerId** — [numeric] global container index
%
% Output Arguments:
%   - **loaded** — [logical] true when the container holds a loaded dataset
%

loaded = false;
if containerId < 1 || containerId > numel(mibModel.I); return; end
dataset = mibModel.I{containerId};
if ~isa(dataset, 'core.MibDataset') || ~isvalid(dataset); return; end
if ~isa(dataset.image, 'core.MibImage'); return; end
loaded = ~strcmp(dataset.image.filename, 'none.tif');
end
