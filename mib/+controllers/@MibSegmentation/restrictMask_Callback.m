function restrictMask_Callback(obj)
% RESTRICTMASK_CALLBACK - callbacks for press of obj.handles.restrictMask in.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.restrictMask_Callback()
%
% obj.handles.panels.segmentation panel. Restrict selection to the mask layer

arguments (Input)
    obj controllers.MibSegmentation
end

% create alias
hWidget = obj.handles.restrictMask;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.restrictMask_Callback: change state of "obj.view.handles.panels.segmentation.handles.restrictMask" -> %d\n', hWidget.Value);
end

% create a alias for the dataset
dataset = obj.mibModel.I{obj.mibModel.id};

if ~dataset.maskExist
    hWidget.Value = false;
    hWidget.FontColor = obj.handles.favoriteTool.FontColor;
    return;
end

% update dataset restrictSelectionToMask property
dataset.restrictSelectionToMask = hWidget.Value;

switch hWidget.Value
    case true       % restrict selection to mask
        hWidget.FontColor = [0.784 0 1];
    case false      % do not restrict selection to mask
        hWidget.FontColor = obj.handles.favoriteTool.FontColor;
end

% set focus to the widget's figure parent
focus(obj.view.handles.panels.segmentationPanel.Figure); % remove focus from hObject
end
