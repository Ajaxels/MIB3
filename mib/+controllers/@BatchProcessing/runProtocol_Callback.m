function runProtocol_Callback(obj, parameter)
% RUNPROTOCOL_CALLBACK - start or stop protocol execution in response to a toolbar button press.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.runProtocol_Callback(parameter)
%
% Orchestrates the top-level execution loop: walks obj.Protocol from the
% requested start step, dispatches Directory loop blocks to doDirectoryLoop
% logic inline, File loop blocks to doFileLoop, Bio-Formats series loops to
% doSeriesLoop, and all other steps to doBatchStep.  Handles nested
% Directory-then-File loops and updates the Run button appearance (green /
% red) to reflect running state.
%
% Pressing the Run button a second time while a protocol is executing sets
% obj.stopProtocolSwitch which causes doBatchStep to abort on the next step.
%
% Input Arguments:
%   - **parameter** - [char] execution scope specifier:
%
%     - ``'complete'`` - run all steps from the first to the last
%     - ``'from'`` - run from the currently selected step to the end
%     - ``'step'`` - execute only the currently selected step
%     - ``'stepadvance'`` - execute the currently selected step then advance the selection to the next step
%
% **Example 1** - run entire protocol:
%
%   .. code-block:: matlab
%
%      obj.runProtocol_Callback('complete');
%
% **Example 2** - resume from selected step:
%
%   .. code-block:: matlab
%
%      obj.runProtocol_Callback('from');
%
% **Example 3** - execute single step:
%
%   .. code-block:: matlab
%
%      obj.runProtocol_Callback('step');
%
% **Example 4** - step with auto-advance:
%
%   .. code-block:: matlab
%
%      obj.runProtocol_Callback('stepadvance');

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.runProtocol_Callback(%s): triggered\n', parameter);
end
obj.stopProtocolSwitch = false;

if isempty(obj.Protocol); return; end
autoAddSwitch = obj.view.handles.autoAddToProtocol.Value;
obj.view.handles.autoAddToProtocol.Value = false;
switch parameter
    case 'complete'
        if strcmp(obj.view.handles.runProtocol.Text, 'Stop protocol')
            obj.stopProtocolSwitch = true;
        end
        startStep = 1;
        finishStep = numel(obj.Protocol);
        obj.view.handles.runProtocol.Text = 'Stop protocol';
        obj.view.handles.runProtocol.BackgroundColor = utils.themeColors(obj.view.gui).dialogStop;

        % count user's points
        obj.mibModel.preferences.Users.Tiers.numberOfBatchProcessings = obj.mibModel.preferences.Users.Tiers.numberOfBatchProcessings+1;
        eventdata = core.ToggleEventData(3);    % scale scoring by factor 3
        notify(obj.mibModel, 'UpdateUserScore', eventdata);
        timerProtocolStart = tic;
    case 'from'
        startStep = obj.protocolListIndex;
        if strcmp(obj.Protocol(startStep).mibBatchActionName, 'STOP EXECUTION')
            startStep = startStep + 1;
        end
        finishStep = numel(obj.Protocol);
        obj.view.handles.runProtocol.Text = 'Stop protocol';
        obj.view.handles.runProtocol.BackgroundColor = utils.themeColors(obj.view.gui).dialogStop;
    case {'step', 'stepadvance'}
        startStep = obj.protocolListIndex;
        finishStep = obj.protocolListIndex;
        if strcmp(parameter, 'stepadvance') && ...
                strcmp(obj.Protocol(startStep).mibBatchSectionName, 'Service steps') && ...
                strcmp(obj.Protocol(startStep).mibBatchActionName, 'STOP EXECUTION')
            obj.protocolListIndex = min([obj.protocolListIndex + 1, numel(obj.Protocol)]);
            obj.updateProtocolList();
            obj.protocolList_SelectionCallback();
            obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;
            return;
        end
end

stepId = startStep;
while stepId <= finishStep
    if strcmp(obj.Protocol(stepId).mibBatchActionName, 'DIRECTORY LOOP START')    % make directory loop
        startStep2 = stepId + 1;
        finishStep2 = find(ismember({obj.Protocol(:).mibBatchActionName}, 'DIRECTORY LOOP STOP'));
        if isempty(finishStep2); finishStep2 = finishStep; end

        % for compatibility add check for DirLoopWaitbar
        if ~isfield(obj.Protocol(stepId).Batch, 'DirLoopWaitbar')
            obj.Protocol(stepId).Batch.DirLoopWaitbar = false;
            obj.Protocol(stepId).Batch.mibBatchTooltip.DirLoopWaitbar = 'when checked the waitbar for the dirloop is displayed';
        end

        % show dirloop waitbar
        showDirLoopWaitbar = false;     % do not show the dir-loop waitbar
        if obj.Protocol(stepId).Batch.DirLoopWaitbar
            dirLoopWaitbar = uiprogressdlg(obj.view.gui, 'Title', 'Processing directories', ...
                'Message', 'Please wait...', 'Value', 0, 'Cancelable', 'on', 'CancelText', 'Stop');
            showDirLoopWaitbar = true;  % show dir-loop waitbar, disable other waitbars
        end

        for dirId = 1:numel(obj.Protocol(stepId).Batch.DirectoriesList{2})
            if obj.Protocol(stepId).Batch.DirLoopWaitbar
                [~, currDirWaitbarText] = fileparts(obj.Protocol(stepId).Batch.DirectoriesList{2}{dirId});
                dirLoopWaitbar.Value   = dirId / numel(obj.Protocol(stepId).Batch.DirectoriesList{2});
                dirLoopWaitbar.Message = sprintf('Processing: %s', currDirWaitbarText);
                if dirLoopWaitbar.CancelRequested
                    close(dirLoopWaitbar);
                    notify(obj.mibModel, 'StopProtocol');
                    obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;
                    return;
                end
            end

            stepId2 = startStep2;
            while stepId2 <= finishStep2
                switch obj.Protocol(stepId2).mibBatchActionName
                    case 'FILE LOOP START'
                        if strcmp(obj.Protocol(stepId2).Batch.DirectoryName{1}, 'Inherit from Directory loop')  % check whether the dir name provided from Dir-loop
                            DirectoryName = obj.Protocol(stepId).Batch.DirectoriesList{2}{dirId};   % take directory name from dir-loop
                        elseif strcmp(obj.Protocol(stepId2).Batch.DirectoryName{1}, 'Current MIB path')
                            DirectoryName = obj.mibModel.currentDirectory;
                        else
                            DirectoryName = obj.Protocol(stepId2).Batch.DirectoryName{1};           % take directory name from File loop
                        end

                        fileLoopStart = stepId2 + 1;
                        fileLoopFinish = find(ismember({obj.Protocol(startStep2:finishStep2).mibBatchActionName}, 'FILE LOOP STOP')) + startStep2 - 1;
                        if isempty(fileLoopFinish); fileLoopFinish = finishStep2; end

                        FileloopSettings.DirectoryName = DirectoryName;
                        FileloopSettings.FilenameFilter = obj.Protocol(stepId2).Batch.FilenameFilter;
                        FileloopSettings.FileLoopWaitbar = obj.Protocol(stepId2).Batch.FileLoopWaitbar;
                        status = obj.doFileLoop(fileLoopStart, fileLoopFinish, FileloopSettings);
                        if status == 0
                            notify(obj.mibModel, 'StopProtocol');
                            obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;
                            if obj.Protocol(stepId).Batch.DirLoopWaitbar; close(dirLoopWaitbar); end
                            return;
                        end
                        stepId2 = fileLoopFinish + 1;
                    otherwise
                        SteploopSettings.DirectoryName = obj.Protocol(stepId).Batch.DirectoriesList{2}{dirId};
                        SteploopSettings.FileLoopWaitbar = showDirLoopWaitbar;
                        status = obj.doBatchStep(stepId2, SteploopSettings);    % make a single step
                        if status == 0
                            notify(obj.mibModel, 'StopProtocol');
                            obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;
                            if obj.Protocol(stepId).Batch.DirLoopWaitbar; close(dirLoopWaitbar); end
                            return;
                        end
                        stepId2 = stepId2 + 1;
                end
            end
        end
        if obj.Protocol(stepId).Batch.DirLoopWaitbar; close(dirLoopWaitbar); end
        stepId = finishStep2 + 1;
    elseif strcmp(obj.Protocol(stepId).mibBatchActionName, 'FILE LOOP START')
        if strcmp(obj.Protocol(stepId).Batch.DirectoryName{1}, 'Inherit from Directory loop')
            errOpts.MsgBoxOnly = true; 
            header = 'Inherit from Directory loop works only when the File loop is placed after the Directory loop!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong sequence of actions', errOpts);
            obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;
            return;
        end
        FileloopSettings.DirectoryName = obj.Protocol(stepId).Batch.DirectoryName{1};
        FileloopSettings.FilenameFilter = obj.Protocol(stepId).Batch.FilenameFilter;
        FileloopSettings.FileLoopWaitbar = obj.Protocol(stepId).Batch.FileLoopWaitbar;

        fileLoopStart = stepId+1;
        fileLoopFinish = find(ismember({obj.Protocol(:).mibBatchActionName}, 'FILE LOOP STOP'));
        if isempty(fileLoopFinish); fileLoopFinish = finishStep; end

        status = obj.doFileLoop(fileLoopStart, fileLoopFinish, FileloopSettings);
        if status == 0
            notify(obj.mibModel, 'StopProtocol');
            obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;
            return;
        end
        stepId = fileLoopFinish + 1;
    else
        if strcmp(obj.Protocol(stepId).mibBatchActionName, 'Load and combine images') && ...
                strcmp(obj.Protocol(stepId).Batch.Mode{1}, 'Series-by-series')
            % processing of bio-formats dataset series by series
            startStep = stepId;
            status = obj.doSeriesLoop(startStep, finishStep);
        else
            status = obj.doBatchStep(stepId);    % make a single step
        end

        if status == 0
            notify(obj.mibModel, 'StopProtocol');
            obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;
            return;
        end
        stepId = stepId + 1;
    end
end

if strcmp(parameter, 'stepadvance')
    obj.protocolListIndex = min([obj.protocolListIndex + 1, numel(obj.Protocol)]);
    obj.updateProtocolList();
    obj.protocolList_SelectionCallback();
end
obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;

obj.view.handles.runProtocol.Text = 'Run protocol';
obj.view.handles.runProtocol.BackgroundColor = utils.themeColors(obj.view.gui).dialogAction;
if strcmp(parameter, 'complete')
    fprintf('Protocol finished; elapsed time: %f seconds\n', toc(timerProtocolStart));
end
end
