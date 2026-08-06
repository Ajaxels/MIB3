function panelHandles = addFijiConnectPanel(obj)
% ADDROIPANEL - add the Fiji Connect panel with context menus and callbacks.
%
% Syntax:
%   .. code-block:: matlab
%
%      panelHandles = obj.addFijiConnectPanel()
%
% Output Arguments:
%   - **panelHandles** - [struct] handles to the ROI panel widgets
%
% Notes:
%   The callbacks are added in the controller of the panel: ``controllers.MibFijiConnect``
%   during its creation in ``MibController.initialize()`` and ``MibController.addGuiControllers()``

arguments (Input)
    obj views.MibView
end

%% ---------------------- ROI PANEL ----------------------
panelOptions.Title = "Fiji Connect";
panelOptions.Region = "bottom";

obj.handles.panels.fijiPanel = matlab.ui.internal.FigurePanel(panelOptions);
%obj.handles.panels.fijiPanel.PreferredHeight = 400;
obj.handles.panels.fijiPanel.Figure.AutoResizeChildren = 'off';

panelHandles = views.components.FijiConnect( ...
    'Parent', obj.handles.panels.fijiPanel.Figure, ...
    'Units', 'normalized', ...
    'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels

% add handle tags to tooltips
if obj.mibModel.preferences.System.DeveloperMode
    utils.overrideDescriptions(panelHandles.handles, true, 'obj.cFiji.view.handles'); 
end

obj.handles.panels.fiji = panelHandles;

% add the panel to the gui
obj.gui.add(obj.handles.panels.fijiPanel);

end

