function fileList_ContextMenu(obj, menuEntry, selectedData)
% function fileList_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the file list widget 
% (obj.handles.panels.activeDataset.handles.fileList)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% fileListContextCombine - combine selected files and open them all as a dataset in MIB
% fileListContextLoadPart - load part of the dataset from the selected file
% fileListContextLoadNth - load each N-th file and combine in a MIB dataset
% fileListContextInsert - insert selected files into the current dataset
% fileListContextColorCombine - combine selected files as color channels and open as a new MIB dataset
% fileListContextColorAdd - add selected file(s) as a new color channel to the current MIB dataset
% fileListContextColorAddNth - add each N-th selected file as a new color channel to the current MIB dataset
% fileListContextRename - rename the selected file
% fileListContextDelete - delete the selected file
% fileListContextProps - get file properties

arguments (Input)
    obj controllers.MibDirContents
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('Pressed: controllers.MibDirContents.fileList_ContextMenu -> %s\n', menuEntry.Tag);
end

% override selected files since Ctrl+A is not detected
obj.mibModel.selectedFiles = obj.mibController.cDirContents.handles.fileList.Value;
obj.mibModel.selectedFiles(ismember(obj.mibModel.selectedFiles, {'[.]','[..]'})) = []; % remove [.] and [..]

switch menuEntry.Tag
    case 'fileListContextCombine'
        obj.mibModel.loadImages('Combine datasets');
    case 'fileListContextLoadPart'
        obj.mibModel.loadImages('Load part of dataset');
    case 'fileListContextLoadNth'
        obj.mibModel.loadImages('Load each N-th dataset');
    case 'fileListContextInsert'
        obj.mibModel.loadImages('Insert into open dataset');
    case 'fileListContextColorCombine'
        obj.mibModel.loadImages('Combine files as color channels');
    case 'fileListContextColorAdd'
        obj.mibModel.loadImages('Add as new color channel');
    case 'fileListContextColorAddNth'
        obj.mibModel.loadImages('Add each N-th dataset as new color channel');
    case 'fileListContextRename'

    case 'fileListContextDelete'

    case 'fileListContextProps'

end

end