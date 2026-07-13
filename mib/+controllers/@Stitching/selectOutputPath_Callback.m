function selectOutputPath_Callback(obj)
% SELECTOUTPUTPATH_CALLBACK - Open a file picker to choose the OME-Zarr output path.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectOutputPath_Callback()
%

startFolder = obj.BatchOpt.OutputPath;
if isempty(startFolder) || ~isfolder(fileparts(startFolder))
    startFolder = obj.mibModel.currentDirectory;
end

[selectedFile, selectedFolder] = uiputfile( ...
    {'*.zarr', 'OME-Zarr directory (*.zarr)'}, ...
    'Save OME-Zarr output as', fullfile(startFolder, 'stitched.zarr'));
if isequal(selectedFile, 0)
    return;
end

outputPath = fullfile(selectedFolder, selectedFile);
obj.BatchOpt.OutputPath = outputPath;
obj.view.handles.OutputPath.Value = outputPath;

end
