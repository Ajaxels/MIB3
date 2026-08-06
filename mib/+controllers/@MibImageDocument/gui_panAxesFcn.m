function gui_panAxesFcn(obj, xy, imgXLim, imgYLim)
% GUI_PANAXESFCN - Move the image in obj.handles.imViewAxes during a pan gesture.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_panAxesFcn(xy, imgXLim, imgYLim)
%
% This is the ``WindowButtonMotionFcn`` callback active while the mouse button
% is held during panning. Installed by ``gui_WindowButtonDownFcn``:
%
%   .. code-block:: matlab
%
%      hFig.WindowButtonMotionFcn = @(~,~)obj.gui_panAxesFcn(xy2, imgXLim, imgYLim);
%
% Input Arguments:
%   - **xy** - [1×2 double] axes data-unit coordinates of mouse at moment button was first pressed (from ``gui_WindowButtonDownFcn``)
%   - **imgXLim** - [1×2 double] ``[xMin, xMax]`` data-coord boundaries of displayed image (left and right edges);
%     ``[1, imgWidth]`` for full image, ``[paddedX(1), paddedX(2)]`` for padded region
%   - **imgYLim** - [1×2 double] ``[yMin, yMax]`` data-coord boundaries of displayed image (top and bottom edges)
%
% Output Arguments:
%   (none)
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
    % In slow pan (full-image) mode, clamp to 1 when zoomed in (magFactor < 1)
    % because the padded image is displayed at 1:1 data pixels (no downscale).
    % When magFactor >= 1, both padded+downscaled and full-image paths use
    % the same display coordinate system (data * coef_z / magFactor).
    if obj.mibController.fastPanningMode
        magFactorFixed = magFactor;
    else
        if magFactor < 1 % padded 1:1 path: image is not rescaled
            magFactorFixed = 1;
        else
            magFactorFixed = magFactor;
        end
    end

    % Aspect ratio correction for X axis: XData is in physical space where
    % 1 data pixel = coef_z XData units. Divide the XData-space delta by
    % coef_z to convert it to data-pixel coordinates before updating axesX.
    dataset = obj.mibModel.I{obj.mibModel.id};
    switch dataset.orientation
        case 3;  coef_z = dataset.image.pixSize.x / dataset.image.pixSize.y;
        case 1;  coef_z = dataset.image.pixSize.z / dataset.image.pixSize.x;
        otherwise; coef_z = dataset.image.pixSize.z / dataset.image.pixSize.y;
    end

    % Move the axes display limits immediately for smooth visual feedback
    obj.handles.imViewAxes.XLim = newXLim;
    obj.handles.imViewAxes.YLim = newYLim;

    % Sync the model's stored axes limits so that showImage() renders at the
    % correct position after the pan is released (gui_WindowButtonUpFcn).
    % delta is in physical (XData) space: divide by coef_z to get data pixels.
    % Y axis has coef_z == 1 so no correction needed there.
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    axesX = axesX + (xy(1) - (pt(1,1)+pt(2,1))/2) * magFactorFixed / coef_z;
    axesY = axesY + (xy(2) - (pt(1,2)+pt(2,2))/2) * magFactorFixed;
    obj.mibModel.setAxesLimits(axesX, axesY);
end
end
