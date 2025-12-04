function imageInvert_Callbacks(obj, hWidget, hData)
% function imageInvert_Callbacks(obj, hWidget, hData)
% callback on press of the Invert buttons in the Image ribbon
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
    fprintf('controllers.MibRibbon.imageInvert_Callbacks: Image ribbon-> %s\n', mode);
end

switch mode
    case 'Shown slice (2D)'         % obj.handles.ribbonImage.invert2D
    case 'Current stack (3D)'       % obj.handles.ribbonImage.invert3D
    case 'Complete volume (4D)'     % obj.handles.ribbonImage.invert4D

end


end