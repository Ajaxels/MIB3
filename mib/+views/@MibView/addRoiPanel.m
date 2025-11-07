function addRoiPanel(obj)
% function addRoiPanel(obj)
% add the ROI panel, add context menus and callbacks for widgets

arguments (Input)
    obj views.MibView
end

%% ---------------------- SEGMENTATION PANEL ----------------------
panelOptions.Title = "ROI";
panelOptions.Region = "bottom";
obj.handles.panels.roiPanel = matlab.ui.internal.FigurePanel(panelOptions);
obj.handles.panels.roiPanel.PreferredHeight = 400;
obj.handles.panels.roiPanel.Figure.AutoResizeChildren = 'off';
obj.handles.panels.roi = views.components.Roi('Parent', obj.handles.panels.roiPanel.Figure, ...
    'Units', 'normalized', 'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels

% add handle tags to tooltips
if obj.mibModel.preferences.System.DeveloperMode; utils.overrideDescriptions(obj.handles.panels.roi.handles, true, 'obj.handles.panels.roi.handles'); end


% ---------------------- Add CALLBACKS to widgets ----------------------
obj.handles.panels.roi.handles.roiOptions.ButtonPushedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiList.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiLoad.ButtonPushedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiSave.ButtonPushedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiAdd.ButtonPushedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiRemove.ButtonPushedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiType.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiFixAspect.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiShowLabel.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiShowROI.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiManually.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiX1.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiY1.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiWidth.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiHeight.ValueChangedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.roiToSelection.ButtonPushedFcn = @(src, event)obj.controller.roiPanel_Callbacks(src, event);
obj.handles.panels.roi.handles.help.ButtonPushedFcn = @(src, event)obj.controller.helpButtons_Callback(src, event);

% add the panel to the gui
obj.gui.add(obj.handles.panels.roiPanel);

end

