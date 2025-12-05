function maskToSelection_Callback(obj, hWidget, hData)
% function maskToSelection_Callback(obj, hWidget, hData)
% callback on press of buttons in the Mask to Selection section of the Mask ribbon
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
    fprintf('controllers.MibRibbon.maskToSelection_Callback: Mask ribbon-> Mask to Section pressed -> %s\n', mode);
end

switch mode
    case 'Add, 2D'      % obj.handles.ribbonMask.maskToSelection2DAdd
    case 'Remove, 2D'   % obj.handles.ribbonMask.maskToSelection2DRemove
    case 'Replace, 2D'  % obj.handles.ribbonMask.maskToSelection2DReplace
    case 'Add, 3D'      % obj.handles.ribbonMask.maskToSelection3DAdd
    case 'Remove, 3D'   % obj.handles.ribbonMask.maskToSelection3DRemove
    case 'Replace, 3D'  % obj.handles.ribbonMask.maskToSelection3DReplace
    case 'Add, 4D'      % obj.handles.ribbonMask.maskToSelection4DAdd
    case 'Remove, 4D'   % obj.handles.ribbonMask.maskToSelection4DRemove
    case 'Replace, 4D'  % obj.handles.ribbonMask.maskToSelection4DReplace
end


end