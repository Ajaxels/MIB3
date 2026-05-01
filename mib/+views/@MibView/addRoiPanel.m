function panelHandles = addRoiPanel(obj)
% ADDROIPANEL - add the ROI panel with context menus and callbacks.
%
% Syntax:
%   .. code-block:: matlab
%
%      panelHandles = obj.addRoiPanel()
%
% Output Arguments:
%   - **panelHandles** — [struct] handles to the ROI panel widgets
%
% Notes:
%   The callbacks are added in the controller of the panel: ``controllers.MibRoi``
%   during its creation in ``MibController.initialize()`` and ``MibController.addGuiControllers()``

arguments (Input)
    obj views.MibView
end

%% ---------------------- ROI PANEL ----------------------
panelOptions.Title = "ROI";
panelOptions.Region = "bottom";

obj.handles.panels.roiPanel = matlab.ui.internal.FigurePanel(panelOptions);
%obj.handles.panels.roiPanel.PreferredHeight = 400;
obj.handles.panels.roiPanel.Figure.AutoResizeChildren = 'off';

panelHandles = views.components.Roi( ...
    'Parent', obj.handles.panels.roiPanel.Figure, ...
    'Units', 'normalized', ...
    'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels

% add handle tags to tooltips
if obj.mibModel.preferences.System.DeveloperMode
    utils.overrideDescriptions(panelHandles.handles, true, 'obj.cRoi.view.handles'); 
end

obj.handles.panels.roi = panelHandles;

% add the panel to the gui
obj.gui.add(obj.handles.panels.roiPanel);

end

