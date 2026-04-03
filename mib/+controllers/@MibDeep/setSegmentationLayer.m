function setSegmentationLayer(obj)
    % function setSegmentationLayer(obj)
    % callback for modification of the Segmentation Layer dropdown

    switch obj.view.handles.T_SegmentationLayer.Value
        case {'focalLossLayer', 'dicePixelCustomClassificationLayer'}
            obj.view.handles.T_SegmentationLayerSettings.Enable = 'on';
        otherwise   % classificationLayer, dicePixelClassificationLayer
            obj.view.handles.T_SegmentationLayerSettings.Enable = 'off';
    end
    obj.BatchOpt.T_SegmentationLayer{1} = obj.view.handles.T_SegmentationLayer.Value;
end

