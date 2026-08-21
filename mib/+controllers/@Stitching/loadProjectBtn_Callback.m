function loadProjectBtn_Callback(obj)
% LOADPROJECTBTN_CALLBACK - Load a stitching project from a JSON sidecar file.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.loadProjectBtn_Callback()
%
% A project file carries two independent things: the STATE of one particular
% stitch (tiles, seam measurements, solved positions) and the SETTINGS it was
% produced with (layout source, grid, overlap, registration, output - schema v3
% and newer). Both are useful on their own, so the user is asked which to take:
%
%   - **Restore everything** - ``obj.layout`` / ``obj.edges`` / ``obj.positions``
%     / ``obj.tforms`` / ``obj.zSliceFixes`` come back from the file and every
%     widget is reset to the saved settings, reproducing the dialog as it was.
%   - **Settings only** - the saved parameters are applied to the tiles selected
%     HERE (``InputPath`` / ``OutputPatih`` are kept), the layout is rebuilt from
%     them, and the file's tiles/measurements/positions are ignored. This is the
%     "stitch a new acquisition exactly like the previous one" case.
%
% Files written before the settings block existed have nothing to choose from,
% so they load their state directly without a dialog.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.loadProjectBtn_Callback: triggered\n');
end
% InputPath may be a newline-joined multi-select list - derive the start folder
% from the first entry (file → its folder; folder → itself).
startFolder = obj.mibModel.currentDirectory;
if ~isempty(obj.BatchOpt.InputPath)
    entries = strtrim(strsplit(obj.BatchOpt.InputPath, newline));
    entries = entries(~cellfun(@isempty, entries));
    if ~isempty(entries)
        if isfolder(entries{1})
            startFolder = entries{1};
        elseif isfile(entries{1})
            startFolder = fileparts(entries{1});
        end
    end
end

[selectedFile, selectedFolder] = uigetfile( ...
    {'*.mibstitch.json', 'MIB Stitch project (*.mibstitch.json)'; '*.*', 'All files'}, ...
    'Open project file', startFolder);
if isequal(selectedFile, 0)
    return;
end
projectPath = fullfile(selectedFolder, selectedFile);

% Decode into locals first - the "settings only" branch discards the state.
try
    [loadedLayout, loadedEdges, loadedPositions, solverInfo, outputInfo, ...
        loadedTforms, loadedZFixes, settings] = utils.stitch.loadProject(projectPath);
catch loadError
    utils.dlgs.showErrorDialog(obj.view.gui, loadError.message, 'Load failed');
    return;
end

% ---- What should this load bring in? ----
hasSettings = ~isempty(fieldnames(settings));
if hasSettings
    loadMode = askLoadMode(obj, selectedFile, loadedLayout, loadedEdges, loadedPositions);
    if isempty(loadMode); return; end        % cancelled / dialog closed
else
    loadMode = 'Restore everything';         % pre-v3 file: no settings to reuse
end
settingsOnly = strcmp(loadMode, 'Settings only');

% ---- State (tiles / measurements / positions) ----
if ~settingsOnly
    obj.layout      = loadedLayout;
    obj.edges       = loadedEdges;
    obj.positions   = loadedPositions;
    obj.tforms      = loadedTforms;
    obj.zSliceFixes = loadedZFixes;
    % These are DIFFERENT tiles, so any cached intensity correction describes the
    % previous job. It is re-estimated on first use rather than being saved: the
    % estimate is a deterministic function of the tiles, and an [H W] float field
    % has no business in the sidecar JSON.
    obj.intensityCorrection = [];
    % The saved RMSE / prune counts belong to these positions - restoring them
    % lets the alignment chip report the loaded stitch instead of sitting blank
    % until the user re-solves.
    obj.solverInfo  = emptyToStruct(solverInfo);
    % The layout now comes from the file, not from the widgets - nothing may
    % silently re-derive it from BatchOpt until the user rebuilds deliberately.
    obj.layoutFromProject = true;
    obj.seamScoresStamp = [];   % stamped below, once the settings are in force
    % Point InputPath at the restored tiles. Without this it still names the
    % PREVIOUS job's input, which sends the project auto-save and the Browse
    % start folder to the wrong dataset (and a pre-v3 file carries no settings
    % block to correct it).
    obj.BatchOpt.InputPath = inputPathFromLayout(loadedLayout);
end

% ---- Settings ----
% Legacy output settings first (pre-v3 files carry only these two); the v3
% settings block then wins wherever both are present.
if ~isempty(outputInfo)
    if isfield(outputInfo, 'outputMode') && ismember(outputInfo.outputMode, obj.BatchOpt.OutputMode{2})
        obj.BatchOpt.OutputMode{1} = outputInfo.outputMode;
    end
    if isfield(outputInfo, 'blendMode') && ismember(outputInfo.blendMode, obj.BatchOpt.BlendMode{2})
        obj.BatchOpt.BlendMode{1} = outputInfo.blendMode;
    end
end
if hasSettings
    % Settings-only reuse keeps the paths of the CURRENT job - that is the whole
    % point of applying the parameters to a different set of files.
    if settingsOnly
        obj.applyProjectSettings(settings, {'InputPath', 'OutputPath'});
    else
        obj.applyProjectSettings(settings);
    end
end

% The canvas must be re-planned in both cases, and any cached OME-Zarr3 pyramid
% settings belong to the previous output configuration.
obj.canvas = [];
obj.zarrExportOptions = [];

% The sidecar stores each edge's seamScore alongside the positions it was
% measured at, so a COMPLETE set is already current: adopt it instead of letting
% the seam inspector re-read every overlap on the way in. Stamped here rather
% than with the rest of the restored state because the stamp records the
% intensity-correction method, which applyProjectSettings has only just put in
% force. Skipped for a settings-only load - buildLayoutFromBatchOpt clears the
% stamp there anyway, since those are different tiles.
if ~settingsOnly && ~isempty(obj.edges) && ~isempty(obj.positions) && ...
        isfield(obj.edges, 'seamScore') && ~any(cellfun(@isempty, {obj.edges.seamScore}))
    obj.seamScoresStamp = obj.currentSeamScoreStamp();
end

% ---- Settings-only: re-derive the layout for the tiles selected here ----
statusText = '';
if settingsOnly
    if isempty(obj.BatchOpt.InputPath)
        clearLayoutAndPreview(obj);
        statusText = sprintf('Settings loaded from %s - now select the input tiles', selectedFile);
    else
        try
            obj.buildLayoutFromBatchOpt();   % also resets edges/positions/tforms/canvas
            statusText = sprintf('Settings loaded from %s - layout rebuilt: %d tiles, re-measure to continue', ...
                selectedFile, numel(obj.layout));
        catch buildError
            % The saved layout source may not fit the current input (e.g. a tile
            % file list under a Position-file source). Not a failure of the load -
            % ask for a re-select through the status line, as the layout-source
            % switch does, instead of a modal error.
            clearLayoutAndPreview(obj);
            statusText = sprintf('Settings loaded from %s - re-select the input (%s)', ...
                selectedFile, buildError.message);
        end
    end
end

obj.updateWidgets();

% Refresh an on-screen preview so it shows the layout that was just loaded/rebuilt.
if ~isempty(obj.layout) && ~isempty(obj.view.handles.previewAxes.Children)
    obj.previewLayoutBtn_Callback();
end

if ~isempty(statusText)
    obj.view.handles.statusLabel.Text = statusText;   % after updateWidgets, which rewrites it
end

end

% =========================================================================
function loadMode = askLoadMode(obj, projectName, layout, edges, positions)
% ASKLOADMODE - Ask whether to restore the saved stitch or only its parameters.
% Returns '' when the user cancels.

summaryParts = {sprintf('%d tiles', numel(layout))};
if ~isempty(edges)
    summaryParts{end+1} = sprintf('%d measured seams', numel(edges));
end
if ~isempty(positions)
    summaryParts{end+1} = 'solved positions';
end

question = sprintf([ ...
    '%s\n(%s)\n\n' ...
    'Restore everything - bring back the tiles, seam measurements and solved\n' ...
    'positions from the file and reset every setting to the saved values.\n\n' ...
    'Settings only - apply the saved parameters (layout source, grid, overlap,\n' ...
    'registration, output) to the tiles selected here, keeping the current input\n' ...
    'path. Use this to stitch other files exactly the same way.'], ...
    projectName, strjoin(summaryParts, ', '));

dlgOptions.WindowWidth  = 600;
dlgOptions.WindowHeight = 340;
dlgOptions.Icon         = 'puffin_question';
loadMode = utils.dlgs.inputQuestDlg(obj.view.gui, question, 'Load stitching project', ...
    'Restore everything', 'Settings only', 'Cancel', 'Restore everything', dlgOptions);
if strcmp(loadMode, 'Cancel'); loadMode = ''; end

end

% =========================================================================
function solverInfo = emptyToStruct(solverInfo)
% EMPTYTOSTRUCT - loadProject returns [] when a file carries no solver block;
% obj.solverInfo is always a struct so every consumer can read it with isfield.
if isempty(solverInfo); solverInfo = struct(); end
end

% =========================================================================
function inputPath = inputPathFromLayout(layout)
% INPUTPATHFROMLAYOUT - Newline-joined tile source list from a restored layout.
% Each tile's `filename` is its source ENTRY (an image file, or the folder for a
% Z-stack tile), which is exactly the shape BatchOpt.InputPath expects. Unique
% because a multi-series Bio-Formats file appears once per series.

if isempty(layout)
    inputPath = '';
    return;
end
entries = unique({layout.filename}, 'stable');
entries = entries(~cellfun(@isempty, entries));
inputPath = strjoin(entries, newline);

end

% =========================================================================
function clearLayoutAndPreview(obj)
% CLEARLAYOUTANDPREVIEW - Drop the stitch state and wipe the preview axes,
% including any interactive edit-mode ROIs (same cleanup as a layout-source
% switch that leaves the current input unusable).

obj.layout      = [];
obj.edges       = [];
obj.positions   = [];
obj.tforms      = {};
obj.canvas      = [];
obj.zSliceFixes = [];
obj.solverInfo  = struct();
obj.layoutFromProject = false;

for listenerIdx = 1:numel(obj.roiListeners)
    if isvalid(obj.roiListeners{listenerIdx}); delete(obj.roiListeners{listenerIdx}); end
end
obj.roiListeners = {};
if ~isempty(obj.tileROIs)
    delete(obj.tileROIs(isvalid(obj.tileROIs)));
    obj.tileROIs = images.roi.Rectangle.empty;
end
cla(obj.view.handles.previewAxes);

end
