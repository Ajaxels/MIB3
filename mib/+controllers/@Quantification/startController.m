function startController(obj, controllerName, varargin)
% function startController(obj, controllerName, varargin)
% Launch a child controller by class name, guarding against duplicates.
%
% If a controller with the same class name is already open the call is
% silently ignored.  Otherwise the controller is instantiated, registered
% in obj.childControllers, and a 'CloseEvent' listener is added so the
% child is purged automatically when it closes.
%
% Parameters:
% controllerName: string — fully-qualified class name,
%   e.g. 'controllers.CropObjects'
% varargin: additional arguments forwarded to the child constructor after
%   mibModel; typically (parentController, batchModeSwitch, extraData)
%
%|
% @b Examples:
% @code obj.startController('controllers.CropObjects', obj, false, annotationLabels); @endcode

% Updates
%

id = obj.findChildId(controllerName);
if ~isempty(id); return; end    % already open

id = numel(obj.childControllersIds) + 1;
obj.childControllersIds{id} = controllerName;

fh = str2func(controllerName);
if nargin > 2
    obj.childControllers{id} = fh(obj.mibModel, varargin{1:numel(varargin)});
else
    obj.childControllers{id} = fh(obj.mibModel);
end

addlistener(obj.childControllers{id}, 'CloseEvent', ...
    @(src, evnt) controllers.Quantification.purgeControllers(obj, src, evnt));
end
