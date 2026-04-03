function customTrainingProgressWindow_Callback(obj, event)
    % function customTrainingProgressWindow_Callback(obj, event)
    % callback for click on
    % obj.view.handles.O_CustomTrainingProgressWindow checkbox

    if obj.view.handles.O_CustomTrainingProgressWindow.Value
        obj.view.handles.O_RefreshRateIter.Enable = 'on';
        obj.view.handles.O_NumberOfPoints.Enable = 'on';
        obj.view.handles.O_PreviewImagePatches.Enable = 'on';
        obj.view.handles.O_FractionOfPreviewPatches.Enable = 'on';
    else
        obj.view.handles.O_RefreshRateIter.Enable = 'off';
        obj.view.handles.O_NumberOfPoints.Enable = 'off';
        obj.view.handles.O_PreviewImagePatches.Enable = 'off';
        obj.view.handles.O_FractionOfPreviewPatches.Enable = 'off';
    end
    obj.updateBatchOptFromGUI(event);
    event2.Source = obj.view.handles.O_PreviewImagePatches;
    obj.previewImagePatches_Callback(event2);
end

