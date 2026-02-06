function mibGUI_WinMouseMotionFcn(obj)
% function mibGUI_WinMouseMotionFcn(obj)
% Returns coordinates and image intensities under the mouse cursor
%
% This function is called on every mouse movement over the figure window.
% It updates the cursor position display, tracks mouse movement distance,
% and manages the brush cursor visibility based on axes boundaries.
%
% Parameters:
% obj: handle to the MibView class instance
%
% Return values:
% none

% Prevent re-entrance to improve performance
% When mouse moves rapidly, this ensures previous callback completes before starting new one
persistent inCallback lastCallTime wasInside
currentTime = tic;

% Auto-reset if stuck for more than 100ms (handles debugging breakpoints and crashes)
if ~isempty(lastCallTime) && toc(lastCallTime) > 0.1
    inCallback = false;
end

% Exit immediately if already processing a mouse move
if ~isempty(inCallback) && inCallback; return; end
inCallback = true;
lastCallTime = currentTime;

try
    % get aliases
    selectedSet = obj.mibModel.Sets.selectedSet;
    imView = obj.handles.imView{selectedSet};
    imViewAxes = imView.handles.imViewAxes;

    % get mouse coordinates
    position = imViewAxes.CurrentPoint;
    x = round(position(1, 1));
    y = round(position(1, 2));

    % get axes limits
    axXLim = imViewAxes.XLim;
    axYLim = imViewAxes.YLim;

    % Check if mouse pointer is within the current axes boundaries
    isInside = x > axXLim(1) && x < axXLim(2) && y > axYLim(1) && y < axYLim(2);

    if isInside  % mouse pointer within the current axes
        % alias to the parent figure
        % the figure parent identified inside ImageView.mlapp as
        % parentFigure = ancestor(obj.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes, 'figure');
        imView.imViewFigure.Pointer = 'crosshair';

        sessionSettings = obj.mibModel.sessionSettings;
        % calculate mouse travel distance
        if sessionSettings.prevCursorCoordinate(1) > 0
            mouseDist = sqrt((sessionSettings.prevCursorCoordinate(1)-x)^2 + (sessionSettings.prevCursorCoordinate(2)-y)^2) * sessionSettings.metersPerPixel;
            obj.mibModel.preferences.Users.Tiers.mouseTravelDistance = obj.mibModel.preferences.Users.Tiers.mouseTravelDistance + mouseDist;
            obj.mibModel.preferences.Users.Tiers.collectedPoints = obj.mibModel.preferences.Users.Tiers.collectedPoints + mouseDist;
        end
        obj.mibModel.sessionSettings.prevCursorCoordinate = [x, y];     % store the previous coordinate of the cursor
        
       
        colorValues = 0;
        modelValues = 0;

        if numel(colorValues) == 0
            obj.controller.cStatus.handles.pixelLabel.Text = sprintf('%d:%d', x, y);
        else
            % Pad colorValues with NaN to always have 4 values
            colorPadded = [colorValues, NaN(1, max(0, 4-numel(colorValues)))];

            obj.controller.cStatus.handles.pixelLabel.Text = sprintf('%d:%d (%d:%d:%d:%d) / %d', x, y, ...
                colorPadded(1), colorPadded(2), colorPadded(3), colorPadded(4), modelValues);
        end
        % recalculate brush cursor positions
        % possible code to show brush cursor, requires obj.handles.cursor handle for the plot type object
        if obj.brushCursorShow; obj.updateBrushCursor([x, y], [], true); end

    else
        imView.imViewFigure.Pointer = 'arrow';
        obj.controller.cStatus.handles.pixelLabel.Text = 'Pixel: XXXXX:XXXXX (RRRRR:GGGGG:BBBBB)';
    end

    % Optimize: Only update cursor visibility when crossing axes boundary
    % This avoids unnecessary function calls when mouse stays outside axes
    if isempty(wasInside) || wasInside ~= isInside
        if ~isInside && obj.brushCursorShow
            % Hide brush cursor when leaving axes
            obj.updateBrushCursor([], [], false);
        end
        % Store current state for next comparison
        wasInside = isInside;
    end

catch err

end

inCallback = false;
end