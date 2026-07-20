function selectOutputPath_Callback(obj)
% SELECTOUTPUTPATH_CALLBACK - Open a file picker to choose the OME-Zarr output path.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectOutputPath_Callback()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.selectOutputPath_Callback: triggered\n');
end
startFolder = obj.BatchOpt.OutputPath;
if isempty(startFolder) || ~isfolder(fileparts(startFolder))
    startFolder = obj.mibModel.currentDirectory;
end

[selectedFile, selectedFolder] = uiputfile( ...
    {'*.zarr3', 'OME-Zarr directory (*.zarr3)'}, ...
    'Save OME-Zarr output as', fullfile(startFolder, 'stitched.zarr3'));
if isequal(selectedFile, 0)
    return;
end

outputPath = fullfile(selectedFolder, selectedFile);
obj.BatchOpt.OutputPath = outputPath;
obj.view.handles.OutputPath.Value = outputPath;

% A fresh output path means the pyramid settings are re-asked on the next
% Stitch (they described the previous destination).
obj.zarrExportOptions = [];

end
