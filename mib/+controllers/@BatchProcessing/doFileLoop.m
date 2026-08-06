function status = doFileLoop(obj, startStep, finishStep, options)
% DOFILELOOP - iterate over files matching a filter and execute a range of protocol steps for each file.
%
% Syntax:
%   .. code-block:: matlab
%
%       status = obj.doFileLoop(startStep, finishStep, options)
%
% Lists all non-directory entries in options.DirectoryName that match
% options.FilenameFilter, then runs protocol steps startStep..finishStep
% once per file, passing the file path through stepOptions so that steps
% such as 'Load and combine images' can pick up the correct filename.
% Aborts immediately and returns false if any step fails or the stop
% flag is set.
%
% Input Arguments:
%   - **startStep** - [numeric] index of the first protocol step to execute inside the loop body
%   - **finishStep** - [numeric] index of the last protocol step to execute inside the loop body
%   - **options** - [struct] loop control struct with fields:
%
%     - ``.DirectoryName`` - directory to scan; use ``'Current MIB path'`` to resolve at runtime
%     - ``.FilenameFilter`` - wildcard filter passed to dir() (e.g., ``'*.tif'``)
%     - ``.FileLoopWaitbar`` - [logical] when true show per-file waitbar and suppress per-step waitbars
%
% Output Arguments:
%   - **status** - [logical] true on success, false if any step returned an error
%
% **Example** - iterate over files matching a filter:
%
%   .. code-block:: matlab
%
%      status = obj.doFileLoop(startStep, finishStep, FileloopSettings);

status = false; %#ok<NASGU>

if strcmp(options.DirectoryName, 'Current MIB path'); options.DirectoryName = obj.mibModel.currentDirectory; end

filename = dir(fullfile(options.DirectoryName, options.FilenameFilter));   % get list of files
filename2 = arrayfun(@(filename) fullfile(options.DirectoryName, filename.name), filename, 'UniformOutput', false);  % generate full paths
notDirsIndices = arrayfun(@(filename2) ~isdir(cell2mat(filename2)), filename2);     % get indices of not directories %#ok<ISDIR>
filename = {filename(notDirsIndices).name}';

stepOptions.DirectoryName = options.DirectoryName;

if options.FileLoopWaitbar
    wb = uiprogressdlg(obj.view.gui, 'Title', 'Processing files', ...
        'Message', 'Please wait...', 'Value', 0, 'Cancelable', 'on', 'CancelText', 'Stop');
end

for fnId = 1:numel(filename)
    if options.FileLoopWaitbar
        wb.Value   = fnId / numel(filename);
        wb.Message = sprintf('Processing: %s', filename{fnId});
        if wb.CancelRequested; close(wb); return; end
    end
    stepOptions.FilenameFilter = filename{fnId};
    stepOptions.Filenames = {fullfile(stepOptions.DirectoryName, filename{fnId})};
    stepOptions.FileLoopWaitbar = options.FileLoopWaitbar;
    for stepId = startStep:finishStep
        status = obj.doBatchStep(stepId, stepOptions);
        if status == 0; return; end
    end
end
if options.FileLoopWaitbar; close(wb); end
status = true;
end
