function updateBrushCursorOffset(obj)
% function updateBrushCursorOffset(obj)
% update offset for showing the brush cursor, depends on the brush radius
% in the segmentation panel
% (obj.handles.panels.segmentation.handles.brushRadius.Value).
%
% Used in obj.updateBrushCursor()

% get required brush radius
radius = obj.handles.panels.segmentation.handles.brushRadius.Value-1;
% get magnification value for cursor scaling
magFactor = obj.mibModel.getMagFactor();

% adjust size
if radius == 0
    se_size = round(1/magFactor/2);
else
    se_size = round(radius/magFactor);
end
se_size(2) = se_size(1);

% set brush cursor offset
theta = linspace(0, 2*pi, 17); % 17 points for smoothness
obj.brushCursorOffset(1, :) = cos(theta)*se_size(1); % X offset of the brush cursor
obj.brushCursorOffset(2, :) = sin(theta)*se_size(2); % Y offset of the brush cursor
end