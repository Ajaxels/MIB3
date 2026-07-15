function saveProjectBtn_Callback(obj)
% SAVEPROJECTBTN_CALLBACK - Save the current stitching project to a JSON file.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.saveProjectBtn_Callback()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.saveProjectBtn_Callback: triggered\n');
end
if isempty(obj.layout)
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No layout loaded. Nothing to save.', {}, {}, 'No layout', warnOptions);
    return;
end

% Choose save path
startFolder = fileparts(obj.BatchOpt.InputPath);
if isempty(startFolder) || ~isfolder(startFolder)
    startFolder = obj.mibModel.currentDirectory;
end
[selectedFile, selectedFolder] = uiputfile( ...
    {'*.mibstitch.json', 'MIB Stitch project (*.mibstitch.json)'}, ...
    'Save project as', fullfile(startFolder, 'stitch_project.mibstitch.json'));
if isequal(selectedFile, 0)
    return;
end
projectPath = fullfile(selectedFolder, selectedFile);

outputInfo = struct();
if ~isempty(obj.canvas)
    outputInfo.canvasSize = obj.canvas.size;
end
outputInfo.outputMode = obj.BatchOpt.OutputMode{1};
outputInfo.blendMode  = obj.BatchOpt.BlendMode{1};

try
    utils.stitch.saveProject(projectPath, obj.layout, obj.edges, ...
        obj.positions, struct(), outputInfo);
catch saveError
    utils.dlgs.showErrorDialog(obj.view.gui, saveError.message, 'Save failed');
end

end
