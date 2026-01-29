function addGuiControllers(obj)
% function addGuiControllers(obj)
% add GUI components (panels, ribbons) to the main view obj.view

arguments (Input)
    obj controllers.MibController
end

% Create the Quick access bar and controller
panelHandles = obj.view.addQuickAccessBar(); % add the addQuickAccessBar and return its handles (the handles are also in obj.view.handles.qab.handles)
obj.cQuickAccessBar = controllers.MibQuickAccessBar(obj, obj.view, panelHandles, obj.mibModel); % start Quick Access Bar controller

% Create the Datasets panel UI and controller
panelHandles = obj.view.addActiveDatasetPanel(); % add the Active Dataset panel and return its handles (the handles are also in obj.view.handles.panels.activeDataset.handles)
obj.cActiveDataset = controllers.MibActiveDataset(obj, obj.view, panelHandles, obj.mibModel); % start Datasets controller

% Create the Directory contents panel UI and controller
panelHandles = obj.view.addDirContentsPanel(); % add the DirContents panel and return its handles (the handles are also in obj.view.handles.panels.dirContents.handles)
obj.cDirContents = controllers.MibDirContents(obj, obj.view, panelHandles, obj.mibModel); % start dirContents controller

% Create the Segmentation panel UI and controller
panelHandles = obj.view.addSegmentationPanel(); % add the Segmentation panel and return its handles (the handles are also in obj.view.handles.panels.segmentation.handles)
obj.cSegmentation = controllers.MibSegmentation(obj, obj.view, panelHandles, obj.mibModel); % start Segmentation controller

% Create the Selection and View settings panel UI and controller
panelHandles = obj.view.addSelectionViewSettingsPanel(); % add the Selection and View settings panel and return its handles (the handles are also in obj.view.handles.panels.selection.handles)
obj.cSelection = controllers.MibSelection(obj, obj.view, panelHandles, obj.mibModel); % start Selection controller

% Create the ROI panel UI and controller
panelHandles = obj.view.addRoiPanel();  % add ROI panel and return its handles (the handles are also in obj.view.handles.panels.roi.handles)
obj.cRoi = controllers.MibRoi(obj, obj.view, panelHandles, obj.mibModel); % start ROI controller

% Create the Status bar UI and controller
panelHandles = obj.view.addStatusBar();  % add ROI panel and return its handles (the handles are also in obj.view.handles.status)
obj.cStatus = controllers.MibStatusBar(obj, obj.view, panelHandles, obj.mibModel); % start Status bar controller

% add ribbon last so that it knows about other widgets
[ribbonHandles, ribbonWidgets] = obj.view.addRibbonTabs();
obj.cRibbon = controllers.MibRibbon(obj, obj.view, ribbonHandles, ribbonWidgets, obj.mibModel); % start Ribbon controller

end