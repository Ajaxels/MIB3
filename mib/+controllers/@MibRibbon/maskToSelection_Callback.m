function maskToSelection_Callback(obj, hWidget, hData)
% MASKTOSELECTION_CALLBACK - callback on press of buttons in the Mask to Selection section of the Mask ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.maskToSelection_Callback(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

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
        obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'add');    
    case 'Remove, 2D'   % obj.handles.ribbonMask.maskToSelection2DRemove
        obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'remove');    
    case 'Replace, 2D'  % obj.handles.ribbonMask.maskToSelection2DReplace
        obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'replace');    
    case 'Add, 3D'      % obj.handles.ribbonMask.maskToSelection3DAdd
        obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'add');    
    case 'Remove, 3D'   % obj.handles.ribbonMask.maskToSelection3DRemove
        obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'remove');    
    case 'Replace, 3D'  % obj.handles.ribbonMask.maskToSelection3DReplace
        obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'replace');    
    case 'Add, 4D'      % obj.handles.ribbonMask.maskToSelection4DAdd
        obj.mibModel.moveLayers('mask', 'selection', '4D, Dataset', 'add');    
    case 'Remove, 4D'   % obj.handles.ribbonMask.maskToSelection4DRemove
        obj.mibModel.moveLayers('mask', 'selection', '4D, Dataset', 'remove');    
    case 'Replace, 4D'  % obj.handles.ribbonMask.maskToSelection4DReplace
        obj.mibModel.moveLayers('mask', 'selection', '4D, Dataset', 'replace');    
end
notify(obj.mibModel, 'ShowImage');

end
