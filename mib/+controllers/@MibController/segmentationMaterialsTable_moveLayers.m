function segmentationMaterialsTable_moveLayers(obj, menuEntry, selectedData)
% function segmentationMaterialsTable_moveLayers(obj, menuEntry, selectedData)
% callbacks for the context menu of the segmentation table widget (obj.handles.panels.segmentation.handles.materialsTableContextM2S):
% -> Material to Selection
% -> Material to Mask
% -> Mask to Material 
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% 

fprintf('segmentationMaterialsTable_moveLayers pressed\n');

end