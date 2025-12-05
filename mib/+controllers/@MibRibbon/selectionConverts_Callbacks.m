function selectionConverts_Callbacks(obj, hWidget, hData)
% function selectionToMask_Callback(obj, hWidget, hData)
% callback on press of buttons in the Selection to Mask section of the Selection ribbon
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
    fprintf('controllers.MibRibbon.selectionToMask_Callback: Selection ribbon-> Selection to Mask section pressed -> %s\n', mode);
end

switch mode
    case 'Add, 2D'        % obj.handles.ribbonSelection.selectionToMask2DAdd 
    case 'Remove, 2D'     % obj.handles.ribbonSelection.selectionToMask2DRemove
    case 'Replace, 2D'    % obj.handles.ribbonSelection.selectionToMask2DReplace
    case 'Add, 3D'        % obj.handles.ribbonSelection.selectionToMask3DAdd 
    case 'Remove, 3D'     % obj.handles.ribbonSelection.selectionToMask3DRemove
    case 'Replace, 3D'    % obj.handles.ribbonSelection.selectionToMask3DReplace
    case 'Add, 4D'        % obj.handles.ribbonSelection.selectionToMask4DAdd 
    case 'Remove, 4D'     % obj.handles.ribbonSelection.selectionToMask4DRemove
    case 'Replace, 4D'    % obj.handles.ribbonSelection.selectionToMask4DReplace

    case 'Copy (Ctrl+C)'    % obj.handles.ribbonSelection.copy
    case 'Paste (Ctrl+V)'    % obj.handles.ribbonSelection.paste
    case 'Paste to all slices (Ctrl+Shift+V)'    % obj.handles.ribbonSelection.pasteAll
    case 'Clear'    % obj.handles.ribbonSelection.clear


end

end