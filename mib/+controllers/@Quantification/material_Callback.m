function material_Callback(obj)
% function material_Callback(obj)
% Handle selection change in the Material dropdown.
%
% Updates obj.BatchOpt.MaterialIndex and the dialog title bar to reflect
% the chosen material.  Index encoding:
% @li -1 = Mask
% @li  0 = Exterior
% @li  1, 2, … = individual model materials (modelType ≤ 255)
% @li  string value = material name (modelType > 255, high-content models)
%
%|
% @b Examples:
% @code % wired in addCallbacks: @endcode
% @code h.Material.ValueChangedFcn = @(~,~) obj.material_Callback(); @endcode

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
