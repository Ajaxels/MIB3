function status = doFileLoop(obj, startStep, finishStep, options)
% function status = doFileLoop(obj, startStep, finishStep, options)
% iterate over files matching a filter and execute a range of protocol steps for each file
%
% Lists all non-directory entries in options.DirectoryName that match
% options.FilenameFilter, then runs protocol steps startStep..finishStep
% once per file, passing the file path through stepOptions so that steps
% such as 'Load and combine images' can pick up the correct filename.
% Aborts immediately and returns false if any step fails or the stop
% flag is set.
%
% Parameters:
% startStep: index of the first protocol step to execute inside the loop body
% finishStep: index of the last protocol step to execute inside the loop body
% options: a struct controlling the loop behaviour:
%   @li .DirectoryName - directory to scan; use 'Current MIB path' to resolve at runtime
%   @li .FilenameFilter - wildcard filter passed to dir() (e.g. '*.tif')
%   @li .FileLoopWaitbar - [logical] when true show a per-file waitbar and
%       suppress waitbars inside individual steps
%
% Return values:
% status: [logical] true on success, false if any step returned an error
%
%|
% @b Examples:
% @code status = obj.doFileLoop(startStep, finishStep, FileloopSettings); @endcode
%
% Updates
%

status = false; %#ok<NASGU>

if strcmp(options.DirectoryName, 'Current MIB path'); options.DirectoryName = obj.mibModel.currentDirectory; end

filename = dir(fullfile(options.DirectoryName, options.FilenameFilter));   % get list of files
filename2 = arrayfun(@(filename) fullfile(options.DirectoryName, filename.name), filename, 'UniformOutput', false);  % generate full paths
notDirsIndices = arrayfun(@(filename2) ~isdir(cell2mat(filename2)), filename2);     % get indices of not directories %#ok<ISDIR>
filename = {filename(notDirsIndices).name}';

stepOptions.DirectoryName = options.DirectoryName;

if options.FileLoopWaitbar; wb = waitbar(0, '', 'Name', 'Processing files'); set(findall(wb, 'type', 'text'), 'Interpreter', 'none'); end

for fnId = 1:numel(filename)
    if options.FileLoopWaitbar
        waitbar(fnId/numel(filename), wb, sprintf('Processing: %s\nPlease wait...', filename{fnId}));
    end
    stepOptions.FilenameFilter = filename{fnId};
    stepOptions.Filenames = {{fullfile(stepOptions.DirectoryName, filename{fnId})}};
    stepOptions.FileLoopWaitbar = options.FileLoopWaitbar;
    for stepId = startStep:finishStep
        status = obj.doBatchStep(stepId, stepOptions);
        if status == 0; return; end
    end
end
if options.FileLoopWaitbar; delete(wb); end
status = true;
end
