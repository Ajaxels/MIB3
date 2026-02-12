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

% Calculate scaled size
if radius == 0
    se_size = round(1/magFactor/2);
else
    se_size = round(radius/magFactor);
end
se_size(2) = se_size(1);

% Generate circle points (17 points for smooth appearance)
theta = linspace(0, 2*pi, 17);
obj.brushCursorOffset(1, :) = cos(theta) * se_size(1);  % X offsets
obj.brushCursorOffset(2, :) = sin(theta) * se_size(2);  % Y offsets

end