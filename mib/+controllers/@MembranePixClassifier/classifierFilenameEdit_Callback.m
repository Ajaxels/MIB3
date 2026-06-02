function classifierFilenameEdit_Callback(obj)
% CLASSIFIERFILENAMEEDIT_CALLBACK - Store the classifier filename from the edit field.

arguments (Input)
    obj controllers.MembranePixClassifier
end

obj.classFilename = obj.view.handles.ClassifierFilename.Value;
obj.BatchOpt.ClassifierFilename = obj.classFilename;

end
