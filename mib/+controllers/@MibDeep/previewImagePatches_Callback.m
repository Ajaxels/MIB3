function previewImagePatches_Callback(obj, event)
    % function previewImagePatches_Callback(obj, event)
    % callback for value change of obj.view.handles.O_PreviewImagePatches

    if obj.view.handles.O_PreviewImagePatches.Value && strcmp(obj.view.handles.O_PreviewImagePatches.Enable, 'on')
        obj.view.handles.O_FractionOfPreviewPatches.Enable = 'on';
    else
        obj.view.handles.O_FractionOfPreviewPatches.Enable = 'off';
    end
    obj.updateBatchOptFromGUI(event);
end

