function classifierFilenameBtn_Callback(obj)
% CLASSIFIERFILENAMEBTN_CALLBACK - Open file browser to select a .forest classifier file.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.classifierFilenameBtn_Callback: triggered\n');
end

[fileName, pathName] = uigetfile('*.forest', 'Select filename for classifier', obj.classFilename);
if isequal(fileName, 0); return; end
obj.view.handles.ClassifierFilename.Value = fullfile(pathName, fileName);
obj.classifierFilenameEdit_Callback();

end
