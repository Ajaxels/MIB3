function fileList_Callback(obj, hWidget, hData)
% function fileList_Callback(obj, hWidget, hData)
% callback for double click on a filename in obj.handles.panels.dirContents.handles.fileList
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibDirContents
    hWidget matlab.ui.control.ListBox
    hData matlab.ui.eventdata.DoubleClickedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContents.fileList_Callback: Double clicked on: obj.handles.panels.dirContents.handles.fileList\n');
end

% require the double click to proceed further
if ~strcmp(hData.EventName, 'DoubleClicked'); return; end

% get the entry upon the double clicked
filename = hWidget.Value{1};

if strcmp(filename, '[.]')
    if ispc()
        dirname = fileparts(obj.mibModel.currentDirectory);
        obj.mibModel.currentDirectory = dirname(1:3);
    else
        obj.mibModel.currentDirectory = '/';
    end
    obj.mibController.cDirContents.updateFileList_Callback();
    obj.mibController.cStatus.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
elseif strcmp(filename, '[..]')
    [dirname, oldDir] = fileparts(obj.mibModel.currentDirectory);
    if ~isequal(dirname, obj.mibModel.currentDirectory)
        obj.mibModel.currentDirectory = dirname;
        obj.mibController.cDirContents.updateFileList_Callback(['[', oldDir, ']']);  % the squares are required because the directory is reported as [dirname] in obj.updateFilelist function
    end
    obj.mibController.cStatus.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
elseif filename(1) == '['
    dirname = fullfile(obj.mibModel.currentDirectory, filename(2:end-1));
    obj.mibModel.currentDirectory = dirname;
    obj.mibController.cDirContents.updateFileList_Callback();
    obj.mibController.cStatus.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
else
    filename
end


end
