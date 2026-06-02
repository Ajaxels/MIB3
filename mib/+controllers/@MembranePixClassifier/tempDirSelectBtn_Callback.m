function tempDirSelectBtn_Callback(obj)
% TEMPDIRSELECT_BTN_CALLBACK - Open directory browser to choose the temp directory.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if isfolder(obj.dirOut)
    pathIn = obj.dirOut;
else
    pathIn = fileparts(obj.dirOut);
end
selectedPath = uigetdir(pathIn, 'Select temp directory');
if isequal(selectedPath, 0); return; end
obj.view.handles.TempDir.Value = selectedPath;
obj.tempDirEdit_Callback();

end
