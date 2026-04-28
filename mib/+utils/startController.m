function startController(parentObj, controllerName, varargin)
% utils.startController — launch a child controller from any MIB controller
%
% Works identically to controllers.MibController.startController but can
% be called from any controller that exposes the following properties:
%   childControllers      — cell array of open child controller handles
%   childControllersIds   — cell array of open child controller class names
%   mibModel              — handle to MibModel
%
% The child controller must follow the MIB controller contract:
%   Constructor  MyController(mibModel) or MyController(mibModel, [], BatchOpt)
%   Event        CloseEvent — fired when the controller closes
%   Property     view       — empty when running in batch mode (no GUI)
%
% Parameters:
% parentObj:       handle — parent controller that owns the child
% controllerName:  char   — fully-qualified class name, e.g. 'controllers.ResampleDataset'
% varargin{1}:     [@em optional] extra arg passed to the child constructor (usually [])
% varargin{2}:     [@em optional] BatchOpt struct to run in batch mode, or NaN for returnBatchOpt
%
%| 
% @b Examples:
% @code
% % Open ResampleDataset GUI (interactive mode):
% utils.startController(obj, 'controllers.ResampleDataset');
% @endcode
% @code
% % Run ResampleDataset in batch mode (no GUI):
% BatchOpt.ResamplingMode = {'Dimensions'};
% BatchOpt.DimensionX = '256';
% BatchOpt.DimensionY = '256';
% utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
% @endcode

% Updates
%

% Check whether the controller is already open
if ~isempty(parentObj.childControllersIds)
    existingId = find(strcmp(parentObj.childControllersIds, controllerName), 1);
else
    existingId = [];
end

if ~isempty(existingId)
    if numel(varargin) == 2   % batch mode — run even if already open
        fh = str2func(controllerName);
        fh(parentObj.mibModel, varargin{1:numel(varargin)});
        return;
    else
        try
            figure(parentObj.childControllers{existingId}.view.gui);
            parentObj.childControllers{existingId}.updateWidgets();
            return;
        catch
            % Stale entry (e.g. closed via debugger without firing CloseEvent,
            % or arrays de-synced by a previous failed constructor).
            % Guard against childControllers being shorter than childControllersIds.
            if existingId <= numel(parentObj.childControllers)
                parentObj.childControllers(existingId) = [];
            end
            parentObj.childControllersIds(existingId) = [];
        end
    end
end

% Allocate a new slot and instantiate the controller.
% Write the name first so the slot is reserved, then roll it back if the
% constructor throws (keeps both tracking arrays in sync).
id = numel(parentObj.childControllersIds) + 1;
parentObj.childControllersIds{id} = controllerName;

fh = str2func(controllerName);
try
    if nargin > 2
        parentObj.childControllers{id} = fh(parentObj.mibModel, varargin{1:numel(varargin)});
    else
        parentObj.childControllers{id} = fh(parentObj.mibModel);
    end
catch constructorErr
    parentObj.childControllersIds(id) = [];   % roll back the pre-written slot
    rethrow(constructorErr);
end

% Wire CloseEvent for lifecycle management
addlistener(parentObj.childControllers{id}, 'CloseEvent', ...
    @(src, ~) utils.purgeChildController(parentObj, src));

% In batch mode the child fires CloseEvent during its constructor, before
% the listener above is wired.  The view property stays empty in that case,
% so re-fire CloseEvent here so the listener can perform cleanup.
childProperties = fieldnames(parentObj.childControllers{id});
if ismember('noGui', childProperties)
    notify(parentObj.childControllers{id}, 'CloseEvent');
elseif isempty(parentObj.childControllers{id}.view)
    notify(parentObj.childControllers{id}, 'CloseEvent');
end

end
