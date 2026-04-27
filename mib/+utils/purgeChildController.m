function purgeChildController(parentObj, src)
% utils.purgeChildController — remove a child controller from its parent
%
% Called as the CloseEvent listener callback wired by utils.startController.
% Finds the child by class name, deletes it if still valid, and removes it
% from the parent's tracking arrays.
%
% Parameters:
% parentObj:  handle — parent controller (must have childControllers / childControllersIds)
% src:        handle — the child controller that fired CloseEvent
%
%| 
% @b Examples:
% @code
% % Wired internally by utils.startController — not called directly by user code.
% addlistener(child, 'CloseEvent', @(src,~) utils.purgeChildController(parentObj, src));
% @endcode

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
