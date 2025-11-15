function datasetsBuffers_ContextMenu(obj, menuEntry, selectedData)
% function datasetsBuffers_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the buffers 
% (obj.handles.panels.datasets.handles.buffer1) buttons

% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% buffersContextDuplicate - duplicate the dataset to another MIB container (buffer)
% buffersContextSyncXY - sync the view with another dataset using only XY axes
% buffersContextSyncXYZ - sync the view with another dataset using only XYZ axes
% buffersContextSyncXYZT - sync the view with another dataset using only XYZT axes
% buffersContextLink - link the view with another dataset
% buffersContextClose - close the current dataset
% buffersContextCloseSet - close all datasets from the current set


arguments (Input)
    obj controllers.MibController
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

% get id of the button with the menu
buttonId = str2double(selectedData.ContextObject.Text);
% get global id of the dataset
globalDatasetIndex = buttonId + (obj.mibModel.Sets.selectedSet-1)*obj.mibModel.Sets.datasetsInSet; % NOT obj.mibModel.id as the context menu may be attached to not selected buffer

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.datasetsBuffers_ContextMenu: selected button (obj.view.handles.panels.datasets.handles.%s), dataset: %d -> %s\n', selectedData.ContextObject.Tag, globalDatasetIndex, menuEntry.Tag);
end

switch menuEntry.Tag
    case 'buffersContextDuplicate' % duplicate the dataset to another MIB container (buffer)
        
    case 'buffersContextSyncXY' % sync the view with another dataset using only XY axes
        
    case 'buffersContextSyncXYZ' % sync the view with another dataset using only XYZ axes
        
    case 'buffersContextSyncXYZT' % sync the view with another dataset using only XYZT axes
        
    case 'buffersContextLink' % link the view with another dataset
        
    case 'buffersContextClose' % close the current dataset
        
    case 'buffersContextCloseSet' % close all datasets from the current set
        
end


end