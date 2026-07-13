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

startFolder = obj.mibModel.currentDirectory;
if ~isempty(obj.BatchOpt.InputPath) && isfolder(fileparts(obj.BatchOpt.InputPath))
    startFolder = fileparts(obj.BatchOpt.InputPath);
end

[selectedFile, selectedFolder] = uigetfile( ...
    {'*.mibstitch.json', 'MIB Stitch project (*.mibstitch.json)'; '*.*', 'All files'}, ...
    'Open project file', startFolder);
if isequal(selectedFile, 0)
    return;
end
projectPath = fullfile(selectedFolder, selectedFile);

try
    [obj.layout, obj.edges, obj.positions, solverInfo, outputInfo] = ...
        utils.stitch.loadProject(projectPath);
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
