function restrictMaterial_Callback(obj)
% function restrictMaterial_Callback(obj)
% callbacks for press of obj.handles.panels.segmentation.handles.restrictMaterial in
% obj.handles.panels.segmentation panel.
% Restrict selection to the selected material in obj.handles.panels.segmentation.handles.materialsTable
%
% Parameters:
% 

arguments (Input)
    obj controllers.MibSegmentation
end

% create alias
hWidget = obj.handles.restrictMaterial;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.restrictMaterial_Callback: change state of "obj.view.handles.panels.segmentation.handles.restrictMaterial" -> %d\n', hWidget.Value);
end

% create a alias for the dataset
dataset = obj.mibModel.I{obj.mibModel.id};

dataset.restrictSelectionToMaterial = hWidget.Value;

switch hWidget.Value
    case true % restrict selection to material
        hWidget.FontColor = 'r';
    case false % do not restrict selection to material
        hWidget.FontColor = obj.handles.favoriteTool.FontColor;
        
        userData = obj.handles.materialsTable.UserData;
        if isfield(userData, 'unlink') && ~userData.unlink
            dataset.selectedAddToMaterial = dataset.selectedMaterial;
        end
end

% update segmentation table
obj.updateMaterialsTable();

focus(ancestor(hWidget, 'figure')); % remove focus from hObject
end
