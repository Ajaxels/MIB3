function addSelectionViewSettingsPanel(obj)
% function addSelectionViewSettingsPanel(obj)
% add the Selection and View Setttings panel, add context menus and callbacks for widgets

arguments (Input)
    obj views.MibView
end

%% ---------------------- SELECTION AND VIEW SETTINGS PANEL ----------------------
panelOptions.Title = "Selection and View settings";
panelOptions.Region = "bottom";
obj.handles.panels.selectionPanel = matlab.ui.internal.FigurePanel(panelOptions);
%obj.handles.panels.datasetsPanel.PreferredHeight = 100;
%obj.handles.panels.datasetsPanel.PreferredWidth = 120;
obj.handles.panels.selectionPanel.WindowBounds(3) = 100;
obj.handles.panels.selectionPanel.Resizable = false;
%obj.handles.panels.selectionPanel.Maximizable = false;
obj.handles.panels.selectionPanel.Figure.AutoResizeChildren = 'off';
obj.handles.panels.selection = views.components.SelectionViewSettings('Parent', obj.handles.panels.selectionPanel.Figure, ...
    'Units', 'normalized', 'Position', [0 0 1 1]); % needs to have normalized units, by default those are pixels
% add handle tags to tooltips
if obj.mibModel.developerMode; utils.overrideDescriptions(obj.handles.panels.selection.handles, true, 'obj.handles.panels.selection.handles'); end


% ---------------------- Add CONTEXT Menus ----------------------
% ---------------------- Add context menu for lutTable ----------------------
obj.handles.panels.selection.handles.lutTableContext = uicontextmenu(obj.handles.panels.selectionPanel.Figure);

obj.handles.panels.selection.handles.lutTableContextInsert = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Insert empty channel', 'Tag', 'lutTableContextInsert', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));
obj.handles.panels.selection.handles.lutTableContextCopy = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Copy channel', 'Tag', 'lutTableContextCopy', 'Separator', 'on', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));
obj.handles.panels.selection.handles.lutTableContextInvert = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Invert channel', 'Tag', 'lutTableContextInvert', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));
obj.handles.panels.selection.handles.lutTableContextRotate = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Rotate channel', 'Tag', 'lutTableContextRotate', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));
obj.handles.panels.selection.handles.lutTableContextShift = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Shift channel', 'Tag', 'lutTableContextShift', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));
obj.handles.panels.selection.handles.lutTableContextSwap = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Swap channels', 'Tag', 'lutTableContextSwap', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));
obj.handles.panels.selection.handles.lutTableContextDelete = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Delete channel', 'Tag', 'lutTableContextDelete', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));
obj.handles.panels.selection.handles.lutTableContextSetLUT = uimenu(obj.handles.panels.selection.handles.lutTableContext, ...
    'Text', 'Set LUT color', 'Tag', 'lutTableContextSetLUT', 'Separator', 'on', ...
    'MenuSelectedFcn', @(src, event)obj.controller.selectionLutTable_ContextMenu(src, event));

% Add the context menu to lutTable
obj.handles.panels.selection.handles.lutTable.ContextMenu = obj.handles.panels.selection.handles.lutTableContext;


% ---------------------- Add CALLBACKS to widgets ----------------------
obj.handles.panels.selection.handles.add.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.subtract.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.replace.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.clear.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.fill.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);

obj.handles.panels.selection.handles.colChannel.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.apply3D.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.autoFill.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.preset1.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.preset2.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.preset3.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.erode.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.dilate.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.strel.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.difference.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);

obj.handles.panels.selection.handles.lutColors.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.showModel.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.showMask.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.showAnnotations.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.hideImage.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.display.ButtonPushedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.onFly.ValueChangedFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);

obj.handles.panels.selection.handles.modelTransparency.ValueChangingFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.maskTransparency.ValueChangingFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);
obj.handles.panels.selection.handles.selectionTransparency.ValueChangingFcn = @(src, event)obj.controller.selectionPanel_Callbacks(src, event);



% add the panel to GUI
obj.gui.add(obj.handles.panels.selectionPanel);

end