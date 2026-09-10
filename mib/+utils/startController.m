function startController(parentObj, controllerName, varargin)
% STARTCONTROLLER - launch a child controller from any MIB controller.
%
% Syntax:
%   function startController(parentObj, controllerName, varargin)
%
% Works identically to controllers.MibController.startController but can
% be called from any controller that exposes the following properties:
% childControllers      - cell array of open child controller handles
% childControllersIds   - cell array of open child controller class names
% mibModel              - handle to MibModel
%
% The child controller must follow the MIB controller contract:
% Constructor  MyController(mibModel) or MyController(mibModel, [], BatchOpt)
% Event        CloseEvent - fired when the controller closes
% Property     view       - empty when running in batch mode (no GUI)
%
% Input Arguments:
%   - **parentObj** - handle - parent controller that owns the child
%   - **controllerName** - char   - fully-qualified class name, e.g. 'controllers.ResampleDataset'
%   - **varargin{1}** - *(optional)* extra arg passed to the child constructor (usually [])
%   - **varargin{2}** - *(optional)* BatchOpt struct to run in batch mode, or NaN for returnBatchOpt
%
% Usage:
%
%   **Example 1** - open ResampleDataset GUI (interactive mode)
%
%   .. code-block:: matlab
%
%      utils.startController(obj, 'controllers.ResampleDataset');
%
%   **Example 2** - run ResampleDataset in batch mode (no GUI)
%
%   .. code-block:: matlab
%
%      BatchOpt.ResamplingMode = {'Dimensions'};
%      BatchOpt.DimensionX = '256';
%      BatchOpt.DimensionY = '256';
%      utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
%

% Updates
%

% Check whether the controller is already open
if ~isempty(parentObj.childControllersIds)
    existingId = find(strcmp(parentObj.childControllersIds, controllerName), 1);
else
    existingId = [];
end

if ~isempty(existingId)
    if numel(varargin) == 2   % batch mode - run even if already open
        fh = str2func(controllerName);
        fh(parentObj.mibModel, varargin{1:numel(varargin)});
        return;
    elseif existingId > numel(parentObj.childControllers)
        % The entry is a reservation with no handle behind it yet: the
        % controller is still inside its constructor, which yielded to the
        % event queue (drawnow, progress dialog) - that is how this second
        % call got here, typically a double click on the ribbon button.  Its
        % window is on its way, so do nothing rather than start a duplicate.
        return;
    else
        try
            figure(parentObj.childControllers{existingId}.view.gui);
            parentObj.childControllers{existingId}.updateWidgets();
            return;
        catch
            % Stale entry (e.g. closed via debugger without firing CloseEvent).
            parentObj.childControllers(existingId)    = [];
            parentObj.childControllersIds(existingId) = [];
        end
    end
end

% Reserve the slot by name, so that a re-entrant call - a second click on the
% ribbon button, or a timer callback firing while the constructor below sits in
% a drawnow - sees the controller as already open.
parentObj.childControllersIds{end+1} = controllerName;

fh = str2func(controllerName);
try
    if nargin > 2
        childObj = fh(parentObj.mibModel, varargin{1:numel(varargin)});
    else
        childObj = fh(parentObj.mibModel);
    end
catch constructorErr
    id = find(strcmp(parentObj.childControllersIds, controllerName), 1);
    if ~isempty(id); parentObj.childControllersIds(id) = []; end   % roll back the reservation
    rethrow(constructorErr);
end

% The constructor yields to the event queue (drawnow, progress dialogs, timer
% callbacks) and utils.purgeChildController shifts both tracking arrays when
% another child window closes meanwhile.  An index taken before the constructor
% ran is therefore stale, and writing the handle to it pads childControllers
% with an empty double - locate the reservation again by name instead.  The
% early return above guarantees at most one entry per controllerName.
id = find(strcmp(parentObj.childControllersIds, controllerName), 1);
if isempty(id)      % the reservation itself was purged while the constructor ran
    parentObj.childControllersIds{end+1} = controllerName;
    id = numel(parentObj.childControllersIds);
end
id = min(id, numel(parentObj.childControllers) + 1);    % never write past the end
parentObj.childControllers = [parentObj.childControllers(1:id-1), {childObj}, ...
                              parentObj.childControllers(id:end)];

% Wire CloseEvent for lifecycle management
addlistener(childObj, 'CloseEvent', @(src, ~) utils.purgeChildController(parentObj, src));

% In batch mode the child fires CloseEvent during its constructor, before
% the listener above is wired.  The view property stays empty in that case,
% so re-fire CloseEvent here so the listener can perform cleanup.
childProperties = fieldnames(childObj);
if ismember('noGui', childProperties)
    notify(childObj, 'CloseEvent');
elseif isempty(childObj.view)
    notify(childObj, 'CloseEvent');
end

end
