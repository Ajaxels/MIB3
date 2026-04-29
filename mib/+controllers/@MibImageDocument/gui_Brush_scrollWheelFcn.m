function gui_Brush_scrollWheelFcn(obj, eventdata)
% GUI_BRUSH_SCROLLWHEELFCN - Handle mouse scroll wheel during adaptive superpixel brush mode.
%
% Syntax:
%   function gui_Brush_scrollWheelFcn(obj, eventdata)
%
% Adjusts the adaptive dilation factor (brushSelection{3}.factor) up or
% down when the scroll wheel is used during an active superpixel brush
% stroke with adaptive mode enabled.
%
% Input Arguments:
%   - **eventdata** — ScrollWheelData with field .VerticalScrollCount
%     negative = scroll up (increase factor), positive = scroll down (decrease)
%
% Output Arguments:
%   (none)
%
% Usage:
%   @code % typically set as a callback, not called directly:
%   hFig.WindowScrollWheelFcn = @(~, eventdata)obj.gui_Brush_scrollWheelFcn(eventdata); @endcode
%

% Updates
%

hFig = obj.UIFigure;
modifier = hFig.CurrentModifier;

step = 0.2;  % default step of the adaptive factor change
if ~isempty(modifier)
    modStr = strjoin(sort(modifier), '');
    if strcmp(modStr, 'shift')
        step = 1;
    elseif strcmp(modStr, 'controlshift') || strcmp(modStr, 'shiftcontrol')
        step = 5;
    end
end

if eventdata.VerticalScrollCount < 0
    obj.brushSelection{3}.factor = obj.brushSelection{3}.factor + step;
else
    obj.brushSelection{3}.factor = obj.brushSelection{3}.factor - step;
    if obj.brushSelection{3}.factor < 0
        obj.brushSelection{3}.factor = 0.1;
    end
end

end
