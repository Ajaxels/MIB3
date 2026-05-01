function exploreActivations(obj)
% EXPLOREACTIVATIONS - explore activations within the trained network.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.exploreActivations()
%
utils.startController(obj, 'controllers.MibDeepActivations', obj);
end

