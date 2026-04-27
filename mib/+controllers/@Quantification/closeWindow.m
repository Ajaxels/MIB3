function closeWindow(obj)
% function closeWindow(obj)
% Close the Quantification dialog and release all resources.
%
% Deletes the AppDesigner figure, removes all event listeners, and fires
% the 'CloseEvent' so the parent MibController can purge this child
% from its childControllers list.
%
%|
% @b Examples:
% @code obj.closeWindow();  // programmatic close @endcode

% Updates
%

for i = numel(obj.childControllers):-1:1
    child = obj.childControllers{i};
    if isa(child, 'handle') && isvalid(child)
        child.closeWindow();
    end
end
obj.childControllers    = {};
obj.childControllersIds = {};

if isvalid(obj.view.gui)
    delete(obj.view.gui);
end

for i = 1:numel(obj.listener)
    delete(obj.listener{i});
end

notify(obj, 'CloseEvent');
end
