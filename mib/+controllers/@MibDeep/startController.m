function startController(obj, controllerName, varargin)
% function startController(obj, controllerName, varargin)
% Launch a child controller by class name.
%
% Delegates to utils.startController — see that function for full
% documentation of interactive, batch, and lifecycle behaviour.
%
% Parameters:
% controllerName: char — fully-qualified controller class name
% varargin: additional arguments forwarded to the child constructor
%
%|
% @b Examples:
% @code obj.startController('controllers.MibDeepController'); @endcode
% @code
% BatchOpt.Mode = '3D, Stack';
% obj.startController('controllers.HistThres', [], BatchOpt);
% @endcode

utils.startController(obj, controllerName, varargin{:});
end
