function addGuiControllers(obj)
% function addGuiControllers(obj)
% add GUI components (panels, ribbons) to the main view obj.view

arguments (Input)
    obj controllers.MibController
end

% Create the Segmentation panel UI and controller
panelHandles = obj.view.addDirContentsPanel(); % add the DirContents panel and return its handles (the handles are also in obj.view.handles.panels.dirContents.handles)
obj.cDirContents = controllers.MibDirContentsController(obj, obj.view, panelHandles, obj.mibModel); % start dirContents controller

% Create the Segmentation panel UI and controller
panelHandles = obj.view.addSegmentationPanel(); % add the Segmentation panel and return its handles (the handles are also in obj.view.handles.panels.segmentation.handles)
obj.cSegmentation = controllers.MibSegmentationController(obj, obj.view, panelHandles, obj.mibModel); % start Segmentation controller

% Create the Selection and View settings panel UI and controller
panelHandles = obj.view.addSelectionViewSettingsPanel(); % add the Selection and View settings panel and return its handles (the handles are also in obj.view.handles.panels.selection.handles)
obj.cSelection = controllers.MibSelectionController(obj, obj.view, panelHandles, obj.mibModel); % start ROI controller

% Create the ROI panel UI and ROI controller
panelHandles = obj.view.addRoiPanel();  % add ROI panel and return its handles (the handles are also in obj.view.handles.panels.roi.handles)
obj.cRoi = controllers.MibRoiController(obj, obj.view, panelHandles, obj.mibModel); % start ROI controller



end