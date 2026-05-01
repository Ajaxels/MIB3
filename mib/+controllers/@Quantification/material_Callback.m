function material_Callback(obj)
% MATERIAL_CALLBACK - Handle selection change in the Material dropdown.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.material_Callback()
%
% Updates obj.BatchOpt.MaterialIndex and the dialog title bar to reflect
% the chosen material.  
%
% Index encoding:
%   - -1 = Mask
%   - 0 = Exterior
%   - 1, 2, … = individual model materials (modelType ≤ 255)
%   - string value = material name (modelType > 255, high-content models)
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.Material.ValueChangedFcn = @(~,~) obj.material_Callback();
%

% Updates
%

id = obj.mibModel.getActiveId();
val = obj.view.handles.Material.Value;
targetList = obj.view.handles.Material.Items;
valIdx = find(strcmp(targetList, val), 1);
if isempty(valIdx); valIdx = 1; end

obj.view.gui.Name = sprintf('"%s" stats...', val);

if obj.mibModel.I{id}.labels.maxMaterials <= 255
    obj.BatchOpt.MaterialIndex = num2str(valIdx - 2);
else
    if valIdx > 3
        obj.BatchOpt.MaterialIndex = val;
    else
        obj.BatchOpt.MaterialIndex = num2str(valIdx - 3);
    end
end
end
