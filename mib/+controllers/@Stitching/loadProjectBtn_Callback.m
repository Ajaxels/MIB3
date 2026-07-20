function loadProjectBtn_Callback(obj)
% LOADPROJECTBTN_CALLBACK - Load a stitching project from a JSON sidecar file.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.loadProjectBtn_Callback()
%
% Restores ``obj.layout``, ``obj.edges``, and ``obj.positions`` from the
% selected ``*.mibstitch.json`` file.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.loadProjectBtn_Callback: triggered\n');
end
% InputPath may be a newline-joined multi-select list — derive the start folder
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

try
    [obj.layout, obj.edges, obj.positions, solverInfo, outputInfo, obj.tforms, ...
        obj.zSliceFixes] = utils.stitch.loadProject(projectPath);
catch loadError
    utils.dlgs.showErrorDialog(obj.view.gui, loadError.message, 'Load failed');
    return;
end

% Restore output settings if available
if ~isempty(outputInfo)
    if isfield(outputInfo, 'outputMode')
        obj.BatchOpt.OutputMode{1} = outputInfo.outputMode;
    end
    if isfield(outputInfo, 'blendMode')
        obj.BatchOpt.BlendMode{1} = outputInfo.blendMode;
    end
end

% Clear canvas (must be re-planned after loading)
obj.canvas = [];

obj.updateWidgets();

% Suppress unused variable warning
solverInfo; %#ok<VUNUS>

end
