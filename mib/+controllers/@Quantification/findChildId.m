function id = findChildId(obj, childName)
% function id = findChildId(obj, childName)
% Find the index of an open child controller by its class name.
%
% Searches obj.childControllersIds for childName and returns the position.
% Returns empty [] when no matching child is open.
%
% Parameters:
% childName: string — full class name, e.g. 'controllers.CropObjects'
%
% Return values:
% id: numeric index into obj.childControllers, or [] if not open
%
%|
% @b Examples:
% @code id = obj.findChildId('controllers.CropObjects'); @endcode
% @code if ~isempty(obj.findChildId('controllers.CropObjects')); return; end  // guard @endcode

% Updates
%

if ~ismember(childName, obj.childControllersIds)
    id = [];
else
    id = find(ismember(obj.childControllersIds, childName), 1);
end
end
