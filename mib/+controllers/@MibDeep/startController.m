function startController(obj, controllerName, varargin)
% STARTCONTROLLER - Launch a child controller by class name.
%
% Syntax:
%   function startController(obj, controllerName, varargin)
%
% Delegates to utils.startController — see that function for full
% documentation of interactive, batch, and lifecycle behaviour.
%
% Input Arguments:
%   - **controllerName** — char — fully-qualified controller class name
%   - **varargin** — additional arguments forwarded to the child constructor
%
% Usage:
%   Example 1::
%
%     obj.startController('controllers.MibDeepController');
%
%   Example 2::
%
%     BatchOpt.Mode = '3D, Stack';
%     obj.startController('controllers.HistThres', [], BatchOpt);
%

utils.startController(obj, controllerName, varargin{:});
end
