function addGuiControllers(obj)
% function addGuiControllers(obj)
% add GUI components (panels, ribbons) to the main view obj.view

arguments (Input)
    obj controllers.MibController
end

% Create the Quick access bar and controller
panelHandles = obj.view.addQuickAccessBar(); % add the addQuickAccessBar and return its handles (the handles are also in obj.view.handles.qab.handles)
obj.cQuickAccessBar = controllers.MibQuickAccessBar(obj, obj.view, panelHandles, obj.mibModel); % start Quick Access Bar Controller controller

% Create the Datasets panel UI and controller
panelHandles = obj.view.addDatasetsPanel(); % add the DirContents panel and return its handles (the handles are also in obj.view.handles.panels.datasets.handles)
obj.cDatasets = controllers.MibDatasets(obj, obj.view, panelHandles, obj.mibModel); % start Datasets controller

% Create the Directory contents panel UI and controller
panelHandles = obj.view.addDirContentsPanel(); % add the DirContents panel and return its handles (the handles are also in obj.view.handles.panels.dirContents.handles)
obj.cDirContents = controllers.MibDirContents(obj, obj.view, panelHandles, obj.mibModel); % start dirContents controller

% Create the Segmentation panel UI and controller
panelHandles = obj.view.addSegmentationPanel(); % add the Segmentation panel and return its handles (the handles are also in obj.view.handles.panels.segmentation.handles)
obj.cSegmentation = controllers.MibSegmentation(obj, obj.view, panelHandles, obj.mibModel); % start Segmentation controller

% Create the Selection and View settings panel UI and controller
panelHandles = obj.view.addSelectionViewSettingsPanel(); % add the Selection and View settings panel and return its handles (the handles are also in obj.view.handles.panels.selection.handles)
obj.cSelection = controllers.MibSelection(obj, obj.view, panelHandles, obj.mibModel); % start ROI controller

% Create the ROI panel UI and ROI controller
panelHandles = obj.view.addRoiPanel();  % add ROI panel and return its handles (the handles are also in obj.view.handles.panels.roi.handles)
obj.cRoi = controllers.MibRoi(obj, obj.view, panelHandles, obj.mibModel); % start ROI controller



end