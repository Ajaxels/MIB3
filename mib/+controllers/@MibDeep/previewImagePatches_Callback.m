function previewImagePatches_Callback(obj, event)
% PREVIEWIMAGEPATCHES_CALLBACK - callback for value change of obj.view.handles.O_PreviewImagePatches.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.previewImagePatches_Callback(event)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.previewImagePatches_Callback: triggered\n');
end
    if obj.view.handles.O_PreviewImagePatches.Value && strcmp(obj.view.handles.O_PreviewImagePatches.Enable, 'on')
        obj.view.handles.O_FractionOfPreviewPatches.Enable = 'on';
    else
        obj.view.handles.O_FractionOfPreviewPatches.Enable = 'off';
    end
    obj.updateBatchOptFromGUI(event);
end

