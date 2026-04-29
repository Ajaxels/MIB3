function multiple_Callback(obj)
% MULTIPLE_CALLBACK - Handle the Multiple properties checkbox toggle.
%
% Syntax:
%   function multiple_Callback(obj)
%
% When checked, enables the "Define properties" button (defineProperties) so the
% user can specify a list of properties for simultaneous calculation.
% When unchecked, disables defineProperties and syncs BatchOpt.Property from the
% single-property dropdown.
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.Multiple.ValueChangedFcn = @(~,~) obj.multiple_Callback();
%

% Updates
%

val = obj.view.handles.Multiple.Value;
if val
    obj.BatchOpt.Multiple = true;
    obj.view.handles.defineProperties.Enable = 'on';
else
    obj.BatchOpt.Multiple = false;
    obj.view.handles.defineProperties.Enable = 'off';
    obj.BatchOpt.Property(1) = {obj.view.handles.Property.Value};
end
end
