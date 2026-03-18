function status = doBatchStep(obj, stepId, stepOptions)
% function status = doBatchStep(obj, stepId, stepOptions)
% execute a single step of the batch protocol
%
% Handles all built-in service steps (STOP EXECUTION, loop markers, Directory
% operations, File operations) directly, then delegates every other action to
% the MIB controller by calling eval() on the pre-built command string stored
% in obj.Protocol(stepId).Command.  The current step is highlighted in the
% protocol listbox while it executes.
%
% Returns false immediately if obj.stopProtocolSwitch is set to true (the
% user pressed the Stop button while the protocol was running).
%
% Parameters:
% stepId: 1-based index into obj.Protocol of the step to execute
% stepOptions: optional struct carrying loop context; may include:
%   @li .DirectoryName    - directory from an enclosing Directory or File loop
%   @li .FilenameFilter   - bare filename (without path) supplied by a File loop
%   @li .Filenames        - full path(s) to the file supplied by a File loop
%   @li .FileLoopWaitbar  - [logical] when true suppress per-step waitbars
%   @li .seriesId         - integer BioFormats series index (from doSeriesLoop)
%
% Return values:
% status: [logical] true on success, false if the step failed or was aborted
%
%|
% @b Examples:
% @code status = obj.doBatchStep(stepId); @endcode
% @code status = obj.doBatchStep(stepId, stepOptions);  // with loop context @endcode
%
% Updates
%

status = false;
if nargin < 3; stepOptions = struct; end

if obj.stopProtocolSwitch == true
    obj.view.handles.runProtocol.Text = 'Run protocol';
    obj.view.handles.runProtocol.BackgroundColor = [0.149 0.902 0.1804];
    return;
end    % stop protocol

% highlight current step in protocol list
items = obj.view.handles.protocolList.Items;
if stepId <= numel(items)
    obj.view.handles.protocolList.Value = items{stepId};
end
obj.protocolListIndex = stepId;

switch obj.Protocol(stepId).mibBatchActionName
    case 'STOP EXECUTION'
        % stop the protocol
        msgbox(sprintf('Protocol: stop execution event!\n\n%s', obj.Protocol(stepId).Batch.Description), 'STOP EXECUTION', 'help');
        status = false;
        return;
    case {'DIRECTORY LOOP STOP', 'FILE LOOP STOP'}
        status = true;
        return;
    case 'Directory operations'
        % get directory
        dirOut = obj.obtainDirectoryForAction('Mode', 'DirectoryName', stepId, stepOptions);
        if isempty(dirOut); return; end
        switch obj.Protocol(stepId).Batch.Operation{1}
            case 'Change current MIB directory'
                obj.mibModel.currentDirectory = dirOut;
            case 'Create new'
                % already created in obtainDirectoryForAction function, except for Dir loop mode
                if ~isfolder(dirOut)
                    try
                        mkdir(dirOut);
                    catch err
                        errordlg(sprintf('!!! Error !!!\n\n%s\n\n%s\n\n%s', err.identifier, err.message, dirOut), 'Problem with directory');
                        return;
                    end
                end
            case 'Delete directory'
                try
                    rmdir(dirOut, 's');
                catch err
                    errordlg(sprintf('!!! Error !!!\n\n%s\n\n%s\n\nMost likely the following directory is not empty!\n%s', err.identifier, err.message, dirOut), 'Problem with directory');
                    return;
                end
        end
        % force to refresh main window
        notify(obj.mibModel, 'updateId');
        status = true;
        return;
    case 'File operations'
        % obtain directories
        sourceDir = obj.obtainDirectoryForAction('CurrentDirectoryMode', 'CurrentDirectory', stepId, stepOptions);
        if isempty(sourceDir); return; end

        switch obj.Protocol(stepId).Batch.Operation{1}
            case 'Delete'   % delete files
                delete(fullfile(sourceDir, obj.Protocol(stepId).Batch.FilenameMask))
            case 'Copy'     % copy files
                targetDir = obj.obtainDirectoryForAction('TargetDirectoryMode', 'TargetDirectory', stepId, stepOptions);
                if isempty(targetDir); return; end
                try
                    copyfile(fullfile(sourceDir, obj.Protocol(stepId).Batch.FilenameMask), targetDir);
                catch err
                    errordlg(sprintf('!!! Error !!!\n\n%s\n\n%s\n\nSource directory:\n%s', err.identifier, err.message, fullfile(sourceDir, obj.Protocol(stepId).Batch.FilenameMask)), 'Problem with directory');
                    return;
                end
            case 'Move'     % move files
                targetDir = obj.obtainDirectoryForAction('TargetDirectoryMode', 'TargetDirectory', stepId, stepOptions);
                if isempty(targetDir); return; end
                try
                    movefile(fullfile(sourceDir, obj.Protocol(stepId).Batch.FilenameMask), targetDir);
                catch err
                    errordlg(sprintf('!!! Error !!!\n\n%s\n\n%s\n\nSource directory:\n%s', err.identifier, err.message, fullfile(sourceDir, obj.Protocol(stepId).Batch.FilenameMask)), 'Problem with directory');
                    return;
                end
        end
        status = true;
        return;
    case 'Load and combine images'
        Batch = obj.Protocol(stepId).Batch; %#ok<NASGU>
        if strcmp(Batch.DirectoryName{1}, 'Inherit from Directory/File loop')
            if ~isfield(stepOptions, 'DirectoryName')
                errordlg(sprintf('!!! Error !!!\n\nWrong settings: Inherit from Directory/File loop parameter requires Directory or File loop before this action!'));
                return;
            end
            Batch.DirectoryName{1} = stepOptions.DirectoryName;
            if isfield(stepOptions, 'FilenameFilter'); Batch.FilenameFilter = stepOptions.FilenameFilter; end
            if isfield(stepOptions, 'Filenames'); Batch.Filenames = stepOptions.Filenames; end
        end
        if Batch.UseBioFormats && strcmp(Batch.Mode{1}, 'Series-by-series')
            Batch.Mode{1} = 'Combine datasets';     % replace mode to load the datasets
            Batch.BioFormatsIndices = num2str(stepOptions.seriesId);
        end
    case 'Save dataset'
        Batch = obj.Protocol(stepId).Batch;
        if ~isempty(strfind(Batch.DestinationDirectory, '[InheritLastDIR]')) %#ok<STREMP>
            if ~isfield(stepOptions, 'DirectoryName')
                errordlg(sprintf('!!! Error !!!\n\n[InheritLastDIR] requires DIRECTORY LOOP START action above this step!'), 'Problem with [InheritLastDIR]');
                return;
            end
            % get inherited path
            [~, InheritLastDIR] = fileparts(stepOptions.DirectoryName);
            Batch.DestinationDirectory = strrep(Batch.DestinationDirectory, '[InheritLastDIR]', InheritLastDIR);
        end
    case 'Example datasets'
        Batch = obj.Protocol(stepId).Batch;
        if strcmp(Batch.DirectoryName{1}, 'Inherit from Directory/File loop')
            if ~isfield(stepOptions, 'DirectoryName')
                errordlg(sprintf('!!! Error !!!\n\nWrong settings: Inherit from Directory/File loop parameter requires Directory or File loop before this action!'));
                return;
            end
            Batch.DirectoryName{1} = stepOptions.DirectoryName;
        end
    otherwise
        Batch = obj.Protocol(stepId).Batch; %#ok<NASGU>
        Batch.batchModeFlag = true;
        % The general logic of a function: (implemented in mibModel.materialsActions)
        % - when function called without parameters it is interactive, i.e. question dialog will appear for settings
        % - when parameters provided as BatchIn structure, the function still interactive, but it is using the provided parameters as default values
        % - when BatchIn.batchModeFlag == true, complete automatic mode without any question asked
end

% update waitbar for file loops
if isfield(stepOptions, 'FileLoopWaitbar') && isfield(Batch, 'showWaitbar')
    if stepOptions.FileLoopWaitbar == 1
        Batch.showWaitbar = false;
    end
end

eval(obj.Protocol(stepId).Command);

status = true;
end
