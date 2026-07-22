function classifierFilenameEdit_Callback(obj)
% CLASSIFIERFILENAMEEDIT_CALLBACK - Store the classifier filename from the edit field.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.classifierFilenameEdit_Callback: triggered\n');
end

obj.classFilename = obj.view.handles.ClassifierFilename.Value;
obj.BatchOpt.ClassifierFilename = obj.classFilename;

end
