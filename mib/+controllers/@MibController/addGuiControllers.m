function addGuiControllers(obj)
% function addGuiControllers(obj)
% add GUI components (panels, ribbons) to the main view obj.view

arguments (Input)
    obj controllers.MibController
end

% Create ROI panel UI and ROI controller
roiHandles = obj.view.addRoiPanel();  % add ROI panel and return its handles (the handles are also in obj.view.handles.panels.roi.handles)
obj.cRoi = controllers.MibRoiController(obj, obj.view, roiHandles, obj.mibModel); % start ROI controller

end