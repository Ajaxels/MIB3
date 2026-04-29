function multipleBtn_Callback(obj)
% MULTIPLEBTN_CALLBACK - Open the property selection dialog for multi-property batch analysis.
%
% Syntax:
%   function multipleBtn_Callback(obj)
%
% Launches the QuantificationProperties child controller which displays
% checkboxes for all available shape and intensity properties.  When
% the user confirms, the child calls applySelectedProperties to update
% BatchOpt.MultipleProperty and the Property dropdown.
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.defineProperties.ButtonPushedFcn = @(~,~) obj.multipleBtn_Callback();
%

% Updates
%

obj3d = ~strcmp(obj.view.handles.ObjectShape.SelectedObject.Tag, 'Shape2D');    % 0 = 2D mode, 1 = 3D mode

if isempty(obj.BatchOpt.MultipleProperty)
    propertyList = obj.BatchOpt.Property(1);
else
    propertyList = cellstr(strtrim(split(obj.BatchOpt.MultipleProperty, ';')));
    allProps = [obj.availableProperties2D, obj.availableProperties3D, obj.availablePropertiesInt];
    propertyList(~ismember(propertyList, allProps)) = [];
end

utils.startController(obj, 'controllers.QuantificationProperties', obj, propertyList, obj3d);
end
