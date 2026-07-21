function updateWidgets(obj)
% UPDATEWIDGETS - Refresh all GUI widgets from the current model state and BatchOpt.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateWidgets()
%
% Called at startup (after the view is created) and whenever the active
% dataset changes.  
%
% Repopulates:
%   - Material dropdown — Mask, Exterior, and all model materials
%   - ColorChannel1/ColorChannel2 dropdowns
%   - DatasetType, ObjectShape, DetectionType, Property, Connectivity, Units dropdowns
%   - Multiple checkbox and MultipleProperty string
%   - Sorting popup
%   - Slice/time-point slider state
%   - statTable enable/disable state via enableStatTable
%
% Usage:
%   Example 1::
%
%     obj.updateWidgets();  // full refresh, e.g. on dataset change
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Quantification.updateWidgets: triggered\n');
end

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

% --- Material dropdown ---
% remember current selection string before repopulating
try prevMaterialValue = obj.view.handles.Material.Value; catch; prevMaterialValue = ''; end

targetList = {'Mask'; 'Exterior'};
if dataset.modelExist
    materials = dataset.labels.materialNames;
    if dataset.labels.maxMaterials <= 255
        targetList = [targetList; materials];
    else
        if size(materials, 1) < size(materials, 2)
            targetList = [{'Model'}; targetList; materials'];
        else
            targetList = [{'Model'}; targetList; materials];
        end
    end
end
obj.view.handles.Material.Items = targetList;

% restore selection or fall back to first item
if ismember(prevMaterialValue, targetList)
    obj.view.handles.Material.Value = prevMaterialValue;
else
    obj.view.handles.Material.Value = targetList{1};
end

% If results exist for this dataset, try to restore material selection from runId
if ~isempty(obj.runId) && obj.runId(1) == id
    if dataset.labels.maxMaterials <= 255
        targetIdx = max([1, obj.runId(2) + 2]);
    else
        if obj.runId(2) > 0
            found = find(ismember(targetList, num2str(obj.runId(2))), 1);
            if ~isempty(found); targetIdx = found; else; targetIdx = 1; end
        else
            targetIdx = obj.runId(2) + 3;
        end
    end
    if targetIdx >= 1 && targetIdx <= numel(targetList)
        obj.view.handles.Material.Value = targetList{targetIdx};
    end
end
obj.material_Callback();

% --- Color channels ---
colorChannels = dataset.image.colors;
colorChannelsList = arrayfun(@(x) sprintf('ColCh %d', x), 1:colorChannels, 'UniformOutput', false);
obj.view.handles.ColorChannel1.Items = colorChannelsList;
obj.view.handles.ColorChannel2.Items = colorChannelsList;

slices = dataset.slices;
if isscalar(slices{4})
    ch = slices{4};
    if ch >= 1 && ch <= colorChannels
        obj.view.handles.ColorChannel1.Value = colorChannelsList{ch};
        obj.BatchOpt.ColorChannel1(1) = colorChannelsList(ch);
    end
else
    obj.view.handles.ColorChannel1.Value = colorChannelsList{slices{4}(1)};
end

if colorChannels > 1
    obj.view.handles.ColorChannel2.Value = colorChannelsList{2};
else
    obj.view.handles.ColorChannel2.Value = colorChannelsList{1};
end

% --- Table enable state ---
obj.enableStatTable();

% --- DatasetType ---
obj.BatchOpt.DatasetType(1) = {obj.view.handles.DatasetType.Value};
end
