function exploreActivations(obj)
% EXPLOREACTIVATIONS - explore activations within the trained network.
%
% Syntax:
%   function exploreActivations(obj)
%
utils.startController(obj, 'controllers.MibDeepActivations', obj);
end

