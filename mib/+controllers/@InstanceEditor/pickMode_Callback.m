function pickMode_Callback(obj)
% PICKMODE_CALLBACK - Toggle "pick objects by clicking" from the checkbox.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.pickMode_Callback()

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.pickMode_Callback: triggered\n');
end

obj.setPickMode(obj.view.handles.pickByClick.Value);
end
