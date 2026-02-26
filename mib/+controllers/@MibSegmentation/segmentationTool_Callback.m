function segmentationTool_Callback(obj, segmToolIndex)
% function segmentationTool_Callback(obj, segmToolIndex)
% callbacks for press of obj.handles.panels.segmentation.handles.segmTool dropdown in
% obj.handles.panels.segmentation panel. 
% Select segmentation tool
%
% Parameters:
% segmToolIndex: [optional] index of the segmentation tool to select, when
% not provided, takes currently selected value in obj.view.handles.panels.segmentation.handles.segmTool.ValueIndex

% get alias
handles = obj.view.handles.panels.segmentation.handles;

if nargin < 4
    % get index of the segmentation tool
    segmToolIndex = handles.segmTool.ValueIndex;
end

% get name of the segmentation tool
segmToolName = handles.segmTool.Items{segmToolIndex};

if obj.mibModel.preferences.System.DeveloperMode
    % obj.mibController.cSegmentation.segmentationTool_Callback
    fprintf('controllers.MibSegmentation.segmentationTool_Callback: -> "%s"\n', segmToolName);
end


handles.panelLines3D.Visible = 'off';
handles.panelAnnotations.Visible = 'off';
handles.panelBrush.Visible = 'off';
handles.panelThresholding.Visible = 'off';
handles.panelDrag.Visible = 'off';
handles.panelLasso.Visible = 'off';
handles.panelMagicwand.Visible = 'off';
handles.panelMembrane.Visible = 'off';
handles.panelSAM.Visible = 'off';  

switch segmToolName
    case {'3D ball', 'Spot'}
        handles.brushUseClustering.Visible = 'off';
        handles.panelBrush.Visible = 'on';
    case '3D lines'
        handles.panelLines3D.Visible = 'on';
    case 'Annotations'
        handles.panelAnnotations.Visible = 'on';
    case 'Brush'
        handles.brushUseClustering.Visible = 'on';
        handles.panelBrush.Visible = 'on';
    case 'BW thresholding'
        handles.panelThresholding.Visible = 'on';
    case 'Drag&Drop materials'
        handles.panelDrag.Visible = 'on'; 
    case 'Lasso'
        handles.lassoObjectPicker.Visible = 'off';
        handles.lassoCustomParameters.Visible = 'on';
        handles.panelLasso.Visible = 'on'; 
    case 'MagicWand/RegionGrowing'
        handles.panelMagicwand.Visible = 'on'; 
    case 'Membrane ClickTracker'
        handles.panelMembrane.Visible = 'on'; 
    case 'Object picker'
        handles.lassoCustomParameters.Visible = 'off';
        handles.lassoObjectPicker.Visible = 'on';
        handles.panelLasso.Visible = 'on'; 
    case 'Segment-anything model'
        handles.panelSAM.Visible = 'on';  
end

% update the favorite tools checkbox
toolIndex = handles.segmTool.ValueIndex;
if ismember(toolIndex, obj.mibModel.preferences.SegmTools.FavoriteTools)
    handles.favoriteTool.Value = true;
else
    handles.favoriteTool.Value = false;
end

end
