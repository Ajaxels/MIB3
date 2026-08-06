function id = findChildId(obj, childName)
% FINDCHILDID - find id of a child controller.
%
% Syntax:
%   .. code-block:: matlab
%
%      id = obj.findChildId(childName)
%
% the child controllers of MIB are stored in obj.childControllersIds cell
% array. This function look for index that matches with childName string.
% If it is in the list the function returns its index, otherwise it adds it
% to the list as a new element
%
% Input Arguments:
%   - **childName** - name of a child controller
%
% Output Arguments:
%   - **id** - index of the requested child controller or empty if it is not open
%
% **Example 1** - find the index of an open child controller:
%
%   .. code-block:: matlab
%
%      id = obj.findChildId('mibImageAdjController');
%
 
% Updates
%

if ismember(childName, obj.childControllersIds) == 0    % not in the list of controllers
    %id = numel(obj.childControllersIds) + 1;
    %obj.childControllersIds{id} = childName;
    id = [];
else                % already in the list
    id = find(ismember(obj.childControllersIds, childName)==1);
end
end
