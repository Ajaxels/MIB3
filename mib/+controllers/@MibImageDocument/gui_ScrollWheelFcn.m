function gui_ScrollWheelFcn(obj, eventdata)
% function gui_ScrollWheelFcn(obj, eventdata)
% Callback for mouse scroll wheel
%
% Handles different scroll wheel operations:
% - Ctrl+Scroll: Change brush/tool size, display size on cursor
% - Ctrl+Shift+Scroll: Change size in larger steps (5 units)
% - Regular scroll: Zoom in/out or slice navigation (handled elsewhere)
%
% Parameters:
%   eventdata: event data structure with VerticalScrollCount/Amount
%
% Return values:
%   none
%
% Example usage:
%   % This callback is automatically triggered by scroll events
%   % User actions:
%   % - Ctrl+Scroll Up: Increase brush size by 1
%   % - Ctrl+Shift+Scroll Down: Decrease brush size by 5

imViewFigure = obj.gui.imViewFigure;
modifier = imViewFigure.CurrentModifier;

% Get scroll parameters
if isprop(eventdata, 'Parameter')
    % Call from key shortcuts using ToggleEventData
    verticalScrollCount = eventdata.Parameter.VerticalScrollCount;
    verticalScrollAmount = eventdata.Parameter.VerticalScrollAmount;
    if strcmp(modifier, 'shift')
        modifier = {'shiftcontrol'};
    else
        modifier = {'control'};
    end
else
    % Standard mouse scroll wheel call
    verticalScrollCount = eventdata.VerticalScrollCount;
    verticalScrollAmount = eventdata.VerticalScrollAmount;
end

% Ctrl+Scroll: change brush/tool size
if ismember('control', modifier)
    step = 1;
    if ismember('shift', modifier)
        step = 5;
    end

    % Get appropriate widget based on current segmentation tool
    switch obj.view.handles.panels.segmentation.handles.segmTool.Value
        case '3D ball'
            h1 = obj.view.handles.panels.segmentation.handles.brushRadius;
        case {'Brush'}
            if strcmp(cell2mat(modifier), 'controlalt') || strcmp(cell2mat(modifier), 'shiftcontrolalt')
                h1 = obj.view.handles.panels.segmentation.handles.clustersPar1;
            else
                h1 = obj.view.handles.panels.segmentation.handles.brushRadius;
            end
        case 'Membrane ClickTracker'
            h1 = obj.view.handles.panels.segmentation.handles.membraneWidth;
        case 'Spot'
            h1 = obj.view.handles.panels.segmentation.handles.brushRadius;
        case 'MagicWand/RegionGrowing'
            h1 = obj.view.handles.panels.segmentation.handles.magicRange1;
        otherwise
            return;
    end

    % Get current value
    val = h1.Value;

    % Handle eraser modification
    if obj.view.ctrlPressed > 0 && h1 == obj.view.handles.panels.segmentation.handles.brushRadius
        val = val - obj.view.ctrlPressed;
        obj.view.ctrlPressed = -1;
        h1.Value = val;
        obj.updateBrushCursor();
    end

    % Update value based on scroll direction
    if verticalScrollCount < 0
        val = val + step;
    else
        val = val - step;
        if val < 1; val = 1; end
    end

    % Prepare text for custom cursor (max 99)
    if val < 100
        text_str = num2str(val);
    else
        text_str = '99';
    end

    % Create custom cursor showing the size value
    colorText = 1;
    valuePointer = zeros([16 16]);
    for i = 1:numel(text_str)
        col_start = i*8 - 7;
        col_end = i*8;
        valuePointer(:, col_start:col_end) = obj.view.brushSizeNumbers{text_str(i)} * colorText;
    end
    valuePointer(valuePointer==0) = NaN;
    valuePointer(1:5,3) = colorText;
    valuePointer(3,1:5) = colorText;

    obj.gui.imViewFigure.Pointer = 'custom';
    obj.gui.imViewFigure.PointerShapeCData = valuePointer;

    % Update widget value
    h1.Value = val;

    % Update brush cursor for new size
    obj.updateBrushCursorOffset();
    obj.updateBrushCursor();
    return;
end

% Note: Other scroll wheel functionality (zoom, slice navigation)
% is still handled by MibView/MibController methods
% This can be migrated here later if needed
end
