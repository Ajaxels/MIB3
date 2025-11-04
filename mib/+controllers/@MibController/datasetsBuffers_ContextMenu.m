function datasetsBuffers_ContextMenu(obj, menuEntry, selectedData)
% function datasetsBuffers_ButtonPushedFcn(obj, menuEntry, selectedData)
% callbacks for the context menu of the buffers 
% (obj.handels.panels.datasets.handles.buffer1) buttons

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

switch menuEntry.Tag
    case 'buffersContextDuplicate' % duplicate the dataset to another MIB container (buffer)
        fprintf('Pressed: obj.controller.datasetsBuffer_ContextMenu -> buffersContextDuplicate\n');
    case 'buffersContextSyncXY' % sync the view with another dataset using only XY axes
        fprintf('Pressed: obj.controller.datasetsBuffer_ContextMenu -> buffersContextSyncXY\n');
    case 'buffersContextSyncXYZ' % sync the view with another dataset using only XYZ axes
        fprintf('Pressed: obj.controller.datasetsBuffer_ContextMenu -> buffersContextSyncXYZ\n');
    case 'buffersContextSyncXYZT' % sync the view with another dataset using only XYZT axes
        fprintf('Pressed: obj.controller.datasetsBuffer_ContextMenu -> buffersContextSyncXYZT\n');
    case 'buffersContextLink' % link the view with another dataset
        fprintf('Pressed: obj.controller.datasetsBuffer_ContextMenu -> buffersContextLink\n');
    case 'buffersContextClose' % close the current dataset
        fprintf('Pressed: obj.controller.datasetsBuffer_ContextMenu -> buffersContextClose\n');
    case 'buffersContextCloseSet' % close all datasets from the current set
        fprintf('Pressed: obj.controller.datasetsBuffer_ContextMenu -> buffersContextCloseSet\n');
end


end