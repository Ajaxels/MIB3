function favTool_Callback(obj, hWidget, hData)
% FAVTOOL_CALLBACK - callbacks for press of obj.handles.panels.segmentation.handles.favoriteTool in.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.favTool_Callback(hWidget, hData)
%
% obj.handles.panels.segmentation panel.
% Select the current tool as favorite, the favorite tools available upon
% press of the 'D' keyboard shortcut key
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting data class
%

arguments (Input)
    obj controllers.MibSegmentation
    hWidget matlab.ui.control.CheckBox
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.favTool_Callback: change state of "obj.view.handles.panels.segmentation.handles.favoriteTool" -> %d\n', hWidget.Value);
end

% get index of the segmentation tool
toolIndex = obj.handles.segmTool.ValueIndex;

switch hWidget.Value
    case true
        obj.mibModel.preferences.SegmTools.FavoriteTools(end+1) = toolIndex;
        obj.mibModel.preferences.SegmTools.FavoriteTools = sort(unique(obj.mibModel.preferences.SegmTools.FavoriteTools));
    case false
        obj.mibModel.preferences.SegmTools.FavoriteTools(obj.mibModel.preferences.SegmTools.FavoriteTools==toolIndex) = [];
end

end
