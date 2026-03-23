function updateBrushCursorOffset(obj)
% function updateBrushCursorOffset(obj)
% Update brush cursor offset based on current brush radius and magnification
%
% Calculates the circle points for the brush cursor based on
% the current brush radius setting and image magnification factor.
% The offset is stored as a 2×N array with X and Y offsets.
%
% Parameters:
%   none
%
% Return values:
%   none
%
% Example:
%   % Called automatically when brush size changes
%   obj.updateBrushCursorOffset();

% Get brush radius from segmentation panel
radius = obj.view.handles.panels.segmentation.handles.brushRadius.Value - 1;

% Get current magnification factor for cursor scaling
magFactor = obj.mibModel.getMagFactor();

% Calculate scaled size (in CData pixels)
if radius == 0
    se_size = round(1/magFactor/2);
else
    se_size = round(radius/magFactor);
end

% Derive coef_z from imageHandle XData so the cursor is stretched to match
% the displayed image for anisotropic orientations (ZX/ZY).
% XData = [1, shownW * coef_z]; YData = [1, shownH] (no Y stretch).
coef_z = 1;
if ~isempty(obj.imageHandle) && isvalid(obj.imageHandle)
    XData = obj.imageHandle.XData;
    shownW = size(obj.mibModel.Ishown, 2);
    if numel(XData) >= 2 && shownW > 1
        coef_z = (XData(end) - XData(1)) / (shownW - 1);
    end
end

% Generate ellipse points (17 points for smooth appearance):
%   X radius scaled by coef_z, Y radius unscaled.
theta = linspace(0, 2*pi, 17);
obj.brushCursorOffset(1, :) = cos(theta) * se_size * coef_z;  % X offsets
obj.brushCursorOffset(2, :) = sin(theta) * se_size;           % Y offsets

end