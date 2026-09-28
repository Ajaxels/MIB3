function exploreActivations(obj)
% EXPLOREACTIVATIONS - explore activations within the trained network.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.exploreActivations()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.exploreActivations: triggered\n');
end

utils.startController(obj, 'controllers.MibDeepActivations', obj);
end

