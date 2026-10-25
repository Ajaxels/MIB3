function loadResults(obj)
% LOADRESULTS - Open a .mibSharp file and add its measurements to the results table, or replace them.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.loadResults()
%
% Reads a file written by :func:`controllers.ImageSharpness.saveResults`.
% When the table already holds rows the user chooses to add the loaded rows
% after them or to replace them. Rows of different versions are combined
% with :func:`controllers.ImageSharpness.mergeResults`. A file that is not
% a MAT file or has no ``mibSharpness`` variable of the expected
% ``fileFormat`` is refused with a message.
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageSharpness.loadResults: triggered\n');
end

[fileName, pathName] = uigetfile({'*.mibSharp', 'Sharpness and noise results (*.mibSharp)'}, ...
    'Load results', obj.mibModel.currentDirectory);
if isequal(fileName, 0); return; end
fullFileName = fullfile(pathName, fileName);

try
    fileContent = load(fullFileName, '-mat', 'mibSharpness');
catch
    fileContent = struct();
end
if ~isfield(fileContent, 'mibSharpness') || ~isfield(fileContent.mibSharpness, 'fileFormat') || ...
        ~strcmp(fileContent.mibSharpness.fileFormat, 'MIB image sharpness and noise results')
    uialert(obj.view.gui, sprintf('%s\nis not a sharpness and noise results file.', fileName), ...
        'Load results', 'Icon', 'warning');
    return;
end
loadedResults = fileContent.mibSharpness.results;
if isempty(loadedResults)
    uialert(obj.view.gui, 'The file holds no measurements.', 'Load results', 'Icon', 'info');
    return;
end

if ~isempty(obj.results)
    reply = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf('The table holds %d measurements. Add the %d measurements of the file, or replace the table?', ...
        numel(obj.results), numel(loadedResults)), 'Load results', 'Add', 'Replace', 'Cancel', 'Add');
    switch reply
        case 'Add'
            obj.results = controllers.ImageSharpness.mergeResults(obj.results, loadedResults);
        case 'Replace'
            obj.results = loadedResults(:);
        otherwise
            return;
    end
else
    obj.results = loadedResults(:);
end
obj.selectedRows = [];
obj.storeSession();
obj.updateResultsTable();
obj.updatePlots(numel(obj.results));
fprintf('Sharpness and noise results were loaded from %s\n', fullFileName);
end
