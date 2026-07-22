function tempDirEdit_Callback(obj)
% TEMPDIR_EDIT_CALLBACK - Validate and store the temporary directory path.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.tempDirEdit_Callback: triggered\n');
end

dirPath = obj.view.handles.TempDir.Value;
if ~isfolder(dirPath)
    mkdir(dirPath);
end
obj.dirOut = dirPath;
obj.BatchOpt.TempDir = dirPath;

end
