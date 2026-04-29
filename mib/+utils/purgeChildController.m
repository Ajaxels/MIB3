function purgeChildController(parentObj, src)
% PURGECHILDCONTROLLER - remove a child controller from its parent.
%
% Syntax:
%   function purgeChildController(parentObj, src)
%
% Called as the CloseEvent listener callback wired by utils.startController.
% Finds the child by class name, deletes it if still valid, and removes it
% from the parent's tracking arrays.
%
% Input Arguments:
%   - **parentObj** — handle — parent controller (must have childControllers / childControllersIds)
%   - **src** — handle — the child controller that fired CloseEvent
%
% Usage:
%
%   **Example 1** — wired internally by ``utils.startController`` (not called directly)
%
%   .. code-block:: matlab
%
%      addlistener(child, 'CloseEvent', @(src,~) utils.purgeChildController(parentObj, src));
%

% Updates
%

if ~isvalid(parentObj);                     return; end
if isempty(parentObj.childControllersIds);  return; end

controllerName = class(src);
id = find(strcmp(parentObj.childControllersIds, controllerName), 1);
if isempty(id); return; end

if isvalid(parentObj.childControllers{id})
    delete(parentObj.childControllers{id});
end
parentObj.childControllers(id)    = [];
parentObj.childControllersIds(id) = [];

end
