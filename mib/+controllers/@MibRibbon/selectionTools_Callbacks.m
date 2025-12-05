function selectionTools_Callbacks(obj, hWidget, hData)
% function selectionTools_Callbacks(obj, hWidget, hData)
% callback on press of buttons in the Tools section of the Selection ribbon
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting EventData class

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.selectionTools_Callbacks: Selection ribbon-> Tools section pressed -> %s\n', mode);
end

switch mode
    case 'Branch points'        % obj.handles.ribbonSelection.branch
    case 'Diagonal fill'     % obj.handles.ribbonSelection.diag
    case 'Replace, 2D'    % obj.handles.ribbonSelection.selectionToMask2DReplace
    case 'Endpoints'        % obj.handles.ribbonSelection.endpoints
    case 'Skeleton'     % obj.handles.ribbonSelection.skeleton
    case 'Spur'    % obj.handles.ribbonSelection.spur
    case 'Thin'        % obj.handles.ribbonSelection.thin
    case 'Ultimate erosion'     % obj.handles.ribbonSelection.ultErosion

    case 'Shown slice (2D)'        % obj.handles.ribbonSelection.invert2D
    case 'Current stack (3D)'        % obj.handles.ribbonSelection.invert3D
    case {'Complete volume (4D)', 'Invert'}        % obj.handles.ribbonSelection.invert4D or obj.handles.ribbonSelection.invert

    case sprintf('Expand to\nmask border')        % obj.handles.ribbonSelection.expandToMask
    case {sprintf('Interpolate as\nshape'), sprintf('Interpolate as\nlines')}        % obj.handles.ribbonSelection.interpolate
    case sprintf('Replace\nselected areas')        % obj.handles.ribbonSelection.replaceImage
    case sprintf('Smooth\nselection')        % obj.handles.ribbonSelection.smooth

end

end