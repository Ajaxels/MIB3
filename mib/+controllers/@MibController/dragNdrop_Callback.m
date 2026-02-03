function status = dragNdrop_Callback(obj, parameterIn)
% status = dragNdrop_Callback(obj, parameterIn)
% callback for filename drag-and-drop operation in MIB
%
% Parameters:
% parameterIn: a cell array, where 
% - the first element is a handle to the webWindow that was a target for the drag-and-drop operation
% - the second element is a filename that was dragged into MIB

% arguments (Input)
%     obj controllers.MibController
%     parameterIn cell    
% end

arguments (Output)
    status logical
end

status = false;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('MibController.dragNdrop_Callback: drag-and-drop file into MIB:\n%s\n', parameterIn{2});
end

filenameList = cell(size(parameterIn{2},1), 1);
for i=1:size(parameterIn{2},1)
    filenameList(i) = cellstr(parameterIn{2}(i,:));
end

[path, fn, ext] = fileparts(filenameList{1});
switch ext
    case '.model'   % drag and drop model files to load
    case '.mask'
    case '.ann'
    otherwise % drag and drop image files to open
        % BatchOpt.Mode = {'Combine datasets'};
        % % sort filenames, otherwise the first file may be the one that was under the focus when drag-n-drop started
        % BatchOpt.Filenames = sort(filenameList);
        % BatchOpt.DirectoryName = {path};
        % obj.mibModel.loadImages([], BatchOpt);
        % 
        % obj.mibModel.currentDirectory = path;
        % obj.cDirContents.updateFileList_Callback([fn ext]);
end

% update the current directory in MIB GUI
obj.view.handles.status.currentDirectory.Value = path;

status = true;
end