function objects3D_Callback(obj)
% OBJECTS3D_CALLBACK - Set whether the objects of an instance model are 2D or 3D.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.objects3D_Callback()
%
% Callback of ``obj.handles.objects3D``, the "3D objects" checkbox of the
% Segmentation panel. Writes the checkbox state to ``labels.objects3D`` of the
% active dataset (see ``core.MibLabels.objects3D``):
%
% - checked - each index names one object through the whole volume, as in a
%   stitched model. Next empty index (the addMaterial button of these models)
%   takes the index above the highest in the model; Squeeze (the
%   removeMaterial button) renumbers the whole model
% - unchecked - the numbering restarts on every slice. Next empty index takes
%   the index above the highest on the shown slice and reads only that slice;
%   Squeeze renumbers only the shown slice
%
% The checkbox is enabled only for 65535 and 4294967295 models
% (``updateMaterialsTable`` keeps it in step with the dataset). The setting is
% saved with the model in the ``.model`` format.

% Updates
%

hWidget = obj.handles.objects3D;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.objects3D_Callback: change state of "obj.view.handles.panels.segmentation.handles.objects3D" -> %d\n', hWidget.Value);
end

dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
if ~dataset.modelExist || dataset.labels.maxMaterials < 256 || ~isprop(dataset.labels, 'objects3D')
    hWidget.Value = false;
    hWidget.Enable = false;
    return;
end
dataset.labels.objects3D = hWidget.Value;

focus(obj.view.handles.panels.segmentationPanel.Figure); % remove focus from hObject
end
