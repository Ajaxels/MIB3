function activationLayerChangeCallback(obj)
    % function activationLayerChangeCallback(obj)
    % callback for modification of the Activation Layer dropdown

    switch obj.view.handles.T_ActivationLayer.Value
        case {'leakyReluLayer', 'clippedReluLayer', 'eluLayer'}
            obj.view.handles.T_ActivationLayerSettings.Enable = 'on';
        otherwise
            obj.view.handles.T_ActivationLayerSettings.Enable = 'off';
    end
    obj.BatchOpt.T_ActivationLayer{1} = obj.view.handles.T_ActivationLayer.Value;
end

