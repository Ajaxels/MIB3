function exportResults(obj)
% EXPORTRESULTS - Save the results in several formats at once, export them to MATLAB, or write a report.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.exportResults()
%
% A dialog with one checkbox per output; any combination can be chosen.
% The file outputs share one base name, asked once with ``uiputfile``; each
% adds its own extension, and existing files of those names are replaced
% after one confirmation. The ticked boxes are remembered for the session
% (``obj.exportChoices``, stored with storeSession). One cancelable progress
% dialog covers all steps; its title names the step in progress (``Export:
% Excel table``, ``Export: Word and PDF report``, ...). Cancel stops before
% the next step; files already written stay and are listed.
%
% Outputs:
%
%   - Excel (``*.xlsx``) and/or comma-separated values (``*.csv``): the
%     content of the results table as shown, with a header row, written with
%     ``writecell``
%   - MATLAB (``*.mat``): variable ``ImageSharpness`` with the fields
%     ``.table`` (the table content), ``.columnNames`` and ``.details``
%     (``obj.results`` with all curves and spectra; the SNR there is the
%     power ratio, ``.analysis.fft.signalToNoise``)
%   - Word (``*.docx``) and/or PDF (``*.pdf``) report, see
%     :func:`controllers.ImageSharpness.writeReport`
%   - MATLAB workspace (not in the compiled version): the same structure as
%     the MAT file, under the variable name entered in the dialog
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageSharpness.exportResults: triggered\n');
end
if isempty(obj.results)
    uialert(obj.view.gui, 'The results table is empty.', 'Export', 'Icon', 'info');
    return;
end

% ---- choose the outputs
outputs = struct('key', {'xlsx', 'csv', 'mat', 'docx', 'pdf', 'workspace'}, ...
    'label', {'Excel table (.xlsx)', 'CSV table (.csv)', 'MATLAB file with all curves (.mat)', ...
    'Report, Word (.docx)', 'Report, PDF (.pdf)', 'Export to MATLAB workspace'});
if isdeployed; outputs(end) = []; end
if isempty(obj.exportChoices) || numel(obj.exportChoices) ~= numel(outputs)
    obj.exportChoices = [true, false(1, numel(outputs) - 1)];
end
prompts = {outputs.label}';
defaultAnswers = num2cell(obj.exportChoices(:));
if ~isdeployed
    prompts{end+1} = 'Variable name:';
    defaultAnswers{end+1} = 'ImageSharpness';
end
dialogOptions = struct('WindowWidth', 480, 'WindowHeight', 300, 'Icon', 'puffin_question', 'OkBtnText', 'Export', 'LabelPosition', 'left');
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, 'Select one or more outputs', prompts, defaultAnswers, ...
    'Export results', dialogOptions);
if isempty(answer); return; end
choices = logical([answer{1:numel(outputs)}]);
obj.exportChoices = choices;
obj.storeSession();
if ~any(choices); return; end
selectedKeys = {outputs(choices).key};
fileKeys = setdiff(selectedKeys, {'workspace'}, 'stable');

columnNames = obj.view.handles.resultsTable.ColumnName(:)';
tableData = obj.view.handles.resultsTable.Data;
exportStruct = struct('table', {tableData}, 'columnNames', {columnNames}, 'details', {obj.results});
written = {};

% ---- files, one base name for all
if ~isempty(fileKeys)
    defaultName = fullfile(obj.mibModel.currentDirectory, 'image_sharpness');
    [fileName, pathName] = uiputfile({'*.*', 'Base name for the selected files'}, 'Export results', defaultName);
    if isequal(fileName, 0); return; end
    [~, baseName] = fileparts(fileName);
    baseFileName = fullfile(pathName, baseName);
    targetFiles = strcat(baseFileName, '.', fileKeys);
    existing = targetFiles(isfile(targetFiles));
    if ~isempty(existing)
        reply = utils.dlgs.inputQuestDlg(obj.view.gui, ...
            sprintf('These files exist and will be replaced:\n%s', strjoin(existing, newline)), ...
            'Export results', 'Replace', 'Cancel', 'Cancel');
        if ~strcmp(reply, 'Replace'); return; end
    end
end

% one progress dialog for all steps; its title names the step in progress
progressDialog = uiprogressdlg(obj.view.gui, 'Title', 'Export results', 'Cancelable', 'on');
cleanupProgress = onCleanup(@() delete(progressDialog));
tableNames = struct('xlsx', 'Excel table', 'csv', 'CSV table');
try
    for key = intersect({'xlsx', 'csv'}, fileKeys, 'stable')
        if progressDialog.CancelRequested; break; end
        progressDialog.Title = ['Export: ' tableNames.(key{1})];
        progressDialog.Message = sprintf('Writing %s', [baseFileName '.' key{1}]);
        writecell([columnNames; tableData], [baseFileName '.' key{1}]);
        written{end+1} = [baseFileName '.' key{1}]; %#ok<AGROW>
    end
    if ismember('mat', fileKeys) && ~progressDialog.CancelRequested
        progressDialog.Title = 'Export: MATLAB file';
        progressDialog.Message = sprintf('Writing %s', [baseFileName '.mat']);
        ImageSharpness = exportStruct;
        save([baseFileName '.mat'], 'ImageSharpness', '-v7.3');
        written{end+1} = [baseFileName '.mat'];
    end
    reportFormats = intersect({'docx', 'pdf'}, fileKeys, 'stable');
    if ~isempty(reportFormats) && ~progressDialog.CancelRequested
        if obj.writeReport(baseFileName, reportFormats, progressDialog)
            written = [written, strcat(baseFileName, '.', reportFormats)];
        end
    end
    if ismember('workspace', selectedKeys) && ~progressDialog.CancelRequested
        progressDialog.Title = 'Export: MATLAB workspace';
        progressDialog.Message = 'Creating the variable...';
        variableName = matlab.lang.makeValidName(strtrim(answer{end}));
        assignin('base', variableName, exportStruct);
        written{end+1} = sprintf('variable "%s" in the MATLAB workspace', variableName);
    end
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Export results');
    return;
end
cancelled = progressDialog.CancelRequested;
delete(progressDialog);

if isempty(written); written = {'nothing'}; end
if cancelled
    uialert(obj.view.gui, sprintf('The export was cancelled. Written before that:\n%s', strjoin(written, newline)), ...
        'Export results', 'Icon', 'warning');
    return;
end

fprintf('Sharpness and noise results exported:\n%s\n', strjoin(written, newline));
uialert(obj.view.gui, sprintf('Exported:\n%s', strjoin(written, newline)), 'Export results', 'Icon', 'success');
end
