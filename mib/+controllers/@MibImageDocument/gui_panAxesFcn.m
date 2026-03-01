function gui_panAxesFcn(obj, xy, imgXLim, imgYLim)
% function gui_panAxesFcn(obj, xy, imgXLim, imgYLim)
% Moves the image in obj.handles.imViewAxes during a pan gesture.
%
% This is the WindowButtonMotionFcn callback active while the mouse button
% is held during panning. It is installed by obj.gui_WindowButtonDownFcn:
%   hFig.WindowButtonMotionFcn = @(~,~)obj.gui_panAxesFcn(xy2, imgXLim, imgYLim);
%
% Parameters:
% xy:       [1×2] double - axes data-unit coordinates of the mouse at the
%           moment the button was first pressed (captured in gui_WindowButtonDownFcn)
% imgXLim:  [1×2] double - [xMin, xMax] data-coord boundaries of the
%           displayed image (left and right edges). For the full image this
%           is [1, imgWidth]; for a padded region it is [paddedX(1), paddedX(2)].
% imgYLim:  [1×2] double - [yMin, yMax] data-coord boundaries of the
%           displayed image (top and bottom edges).
%
% Return values:
%   (none)
%
% Updates
%

% Get the current mouse position in axes data units.
pt = obj.handles.imViewAxes.CurrentPoint;   % 2x3, use row(1,1:2)

% Current axes display limits
Xlim = obj.handles.imViewAxes.XLim;
Ylim = obj.handles.imViewAxes.YLim;

% Compute proposed new limits.
% Logic: shift the window by (original click position) - (current mouse midpoint).
% This keeps the image pixel that was under the cursor fixed under the cursor.
newXLim = Xlim + (xy(1) - (pt(1,1)+pt(2,1))/2);
newYLim = Ylim + (xy(2) - (pt(1,2)+pt(2,2))/2);

% check for out of image shifts: skip update when view would leave the image entirely
outSwitch = false;
if newXLim(2) < imgXLim(1) || newXLim(1) > imgXLim(2); outSwitch = true; end
if newYLim(2) < imgYLim(1) || newYLim(1) > imgYLim(2); outSwitch = true; end

if ~outSwitch
    magFactor = obj.mibModel.getMagFactor();

    % Determine the effective magnification factor for data-coordinate adjustment.
    % In fast pan mode, always use the actual magFactor.
    % In slow pan (full-image) mode, clamp to 1 when zoomed out (magFactor < 1)
    % because the image is not rescaled in that regime.
    if obj.mibController.fastPanningMode
        magFactorFixed = magFactor;
    else
        if magFactor < 1 % the image is not rescaled if magFactor less than 1
            magFactorFixed = 1;
        else
            magFactorFixed = magFactor;
        end
    end

    % Move the axes display limits immediately for smooth visual feedback
    obj.handles.imViewAxes.XLim = newXLim;
    obj.handles.imViewAxes.YLim = newYLim;

    % Sync the model's stored axes limits so that showImage() renders at the
    % correct position after the pan is released (gui_WindowButtonUpFcn).
    % The shift is scaled by magFactorFixed to convert from screen/axes pixels
    % to image data coordinates.
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    axesX = axesX + (xy(1) - (pt(1,1)+pt(2,1))/2) * magFactorFixed;
    axesY = axesY + (xy(2) - (pt(1,2)+pt(2,2))/2) * magFactorFixed;
    obj.mibModel.setAxesLimits(axesX, axesY);
end
end
