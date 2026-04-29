function update_fromModel(obj)
% UPDATE_FROMMODEL - update widgets of the Segmentation panel from obj.mibModel.
%
% Syntax:
%   function update_fromModel(obj)
%

% update widgets of the segmentation panel from preferences

% ---------- Annotations ----------
% update precision value for the annotations
obj.handles.annPrecision.Value = obj.mibModel.preferences.SegmTools.Annotations.Precision;
obj.handles.annFocusOnValue.Value = obj.mibModel.preferences.SegmTools.Annotations.FocusOnValue;
obj.handles.annDisplayAs.Value = obj.mibModel.preferences.SegmTools.Annotations.DisplayAs;

% ----------  Brush tool   ----------
% Brush eraser factor
obj.handles.eraserFactor.Value = obj.mibModel.preferences.SegmTools.Brush.EraserRadiusFactor;
% update cluster sizes
obj.brushPanel_Callback([], [], 'brushUseClustering');

% % ---------- Segment-anything preferences ----------
obj.handles.samVersion.Value = obj.mibModel.preferences.SegmTools.SAM.samVersion;

end
