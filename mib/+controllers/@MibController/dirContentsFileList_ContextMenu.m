function dirContentsFileList_ContextMenu(obj, menuEntry, selectedData)
% function dirContentsFileList_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the file list widget 
% (obj.handles.panels.datasets.handles.fileList)
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
    obj controllers.MibController
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('Pressed: controllers.MibController.dirContentsFileList_ContextMenu -> %s\n', menuEntry.Tag);
end

switch menuEntry.Tag
    case 'fileListContextCombine'
        
    case 'fileListContextLoadPart'
        
    case 'fileListContextLoadNth'
       
    case 'fileListContextInsert'
        
    case 'fileListContextColorCombine'
        
    case 'fileListContextColorAdd'
        
    case 'fileListContextColorAddNth'
        
    case 'fileListContextRename'
        
    case 'fileListContextDelete'
        
    case 'fileListContextProps'
        
end

end