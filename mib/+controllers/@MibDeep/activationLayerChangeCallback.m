function activationLayerChangeCallback(obj)
% ACTIVATIONLAYERCHANGECALLBACK - callback for modification of the Activation Layer dropdown.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.activationLayerChangeCallback()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.activationLayerChangeCallback: triggered\n');
end
    switch obj.view.handles.T_ActivationLayer.Value
        case {'leakyReluLayer', 'clippedReluLayer', 'eluLayer'}
            obj.view.handles.T_ActivationLayerSettings.Enable = 'on';
        otherwise
            obj.view.handles.T_ActivationLayerSettings.Enable = 'off';
    end
    obj.BatchOpt.T_ActivationLayer{1} = obj.view.handles.T_ActivationLayer.Value;
end

