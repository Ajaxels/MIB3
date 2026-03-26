function multiple_Callback(obj)
% function multiple_Callback(obj)
% Handle the Multiple properties checkbox toggle.
%
% When checked, enables the "Define properties" button (defineProperties) so the
% user can specify a list of properties for simultaneous calculation.
% When unchecked, disables defineProperties and syncs BatchOpt.Property from the
% single-property dropdown.
%
%|
% @b Examples:
% @code % wired in addCallbacks: @endcode
% @code h.Multiple.ValueChangedFcn = @(~,~) obj.multiple_Callback(); @endcode

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
