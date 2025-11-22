function addGuiControllers(obj)
% function addGuiControllers(obj)
% add GUI components (panels, ribbons) to the main view obj.view

arguments (Input)
    obj controllers.MibController
end

% Create the Selection and View settings panel UI and ROI controller
panelHandles = obj.view.addSelectionViewSettingsPanel(); % add the Segmentation panel
obj.cSelection = controllers.MibSelectionController(obj, obj.view, panelHandles, obj.mibModel); % start ROI controller

% Create the ROI panel UI and ROI controller
panelHandles = obj.view.addRoiPanel();  % add ROI panel and return its handles (the handles are also in obj.view.handles.panels.roi.handles)
obj.cRoi = controllers.MibRoiController(obj, obj.view, panelHandles, obj.mibModel); % start ROI controller



end