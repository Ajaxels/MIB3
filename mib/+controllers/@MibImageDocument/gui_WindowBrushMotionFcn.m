function gui_WindowBrushMotionFcn(obj, structElement)
% function gui_WindowBrushMotionFcn(obj, structElement)
% Draw the brush trace during use of the brush tool
%
% This function is called on every mouse movement while the brush tool
% is active. It rasterizes the line from the previous cursor position to
% the current one, dilates it with the structural element, and updates
% the selection overlay on the displayed image. Supports both normal
% brush and superpixel-assisted (SLIC/Watershed) modes.
%
% Parameters:
% structElement: double matrix, circular structural element for brush
%   dilation, generated in segmentationBrush.m
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code % typically called as a callback, not directly:
% hFig.WindowButtonMotionFcn = @(~,~)obj.gui_WindowBrushMotionFcn(structElement); @endcode

% Updates
%

pos = obj.handles.imViewAxes.CurrentPoint;
XLim = size(obj.mibModel.Ishown, 2);
YLim = size(obj.mibModel.Ishown, 1);

if isempty(obj.brushPrevXY) || (isscalar(obj.brushPrevXY) && isnan(obj.brushPrevXY))
    obj.brushPrevXY = [pos(1,1) pos(1,2)];
    return;
end

% ---- recalculate brush cursor positions (data-space delta) ----
% brushPrevXY and pos are both in axes/data coords, so diffX/Y correctly
% drives the cursor even when coef_z != 1 (anisotropic ZX/ZY orientations).
diffX = pos(1,1) - obj.brushPrevXY(1);
diffY = pos(1,2) - obj.brushPrevXY(2);
if ~isempty(obj.brushCursor) && isvalid(obj.brushCursor)
    obj.brushCursor.XData = obj.brushCursor.XData + diffX;
    obj.brushCursor.YData = obj.brushCursor.YData + diffY;
end

% ---- calculate brush mouse distance ----
obj.brushSelection{1}.travelPathInPixels = ...
    obj.brushSelection{1}.travelPathInPixels + sqrt(diffX^2 + diffY^2);

% ---- convert data coords to CData pixel indices ----
% imageHandle.XData = [1, shownW * coef_z]; for ZX/ZY orientations coef_z
% can be >> 1, so axes data coords are a stretched version of CData indices.
XData = obj.imageHandle.XData;
YData = obj.imageHandle.YData;
if XData(end) > XData(1) && XLim > 1
    toCDataX = @(v) max(1, min(XLim, round((v - XData(1)) / (XData(end) - XData(1)) * (XLim - 1)) + 1));
else
    toCDataX = @(v) max(1, min(XLim, round(v)));
end
if YData(end) > YData(1) && YLim > 1
    toCDataY = @(v) max(1, min(YLim, round((v - YData(1)) / (YData(end) - YData(1)) * (YLim - 1)) + 1));
else
    toCDataY = @(v) max(1, min(YLim, round(v)));
end

curX  = toCDataX(pos(1,1));
curY  = toCDataY(pos(1,2));
prevX = toCDataX(obj.brushPrevXY(1));
prevY = toCDataY(obj.brushPrevXY(2));

% ---- rasterize line between previous and current point ----
selarea = false([YLim, XLim]);

if abs(curX - prevX) > abs(curY - prevY)
    % horizontal-dominant movement
    if curX <= prevX
        X = [curX prevX];
        Y = [curY prevY];
    else
        X = [prevX curX];
        Y = [prevY curY];
    end
    dY = (Y(2) - Y(1)) / (X(2) - X(1) + 1);
    for xp = X(1):X(2)
        yp = round(Y(1) + (xp - X(1)) * dY);
        selarea(yp, xp) = true;
    end
else
    % vertical-dominant movement
    if curY < prevY
        X = [curX prevX];
        Y = [curY prevY];
    else
        X = [prevX curX];
        Y = [prevY curY];
    end
    dX = (X(2) - X(1)) / (Y(2) - Y(1) + 1);
    for yp = Y(1):Y(2)
        xp = round(X(1) + (yp - Y(1)) * dX);
        selarea(yp, xp) = true;
    end
end

% ---- dilate with structural element ----
if size(structElement, 2) < 10
    selarea1 = imdilate(selarea, structElement);
else
    selarea1 = bwdist(selarea) <= size(structElement, 1)/2;
end

% ---- update selection and CData overlay ----
CData = obj.imageHandle.CData;

if numel(obj.brushSelection) > 1
    % ---- superpixel mode ----
    % NOTE: adaptive dilate mode is not yet ported (no UI widget in MIB3)
    % standard superpixel selection
    slicIndices = unique(obj.brushSelection{2}.slic(selarea1));
    if min(ismember(slicIndices, obj.brushSelection{2}.selectedSlicIndices)) == 0
        % new superpixel detected -> update history
        slicIndices(ismember(slicIndices, obj.brushSelection{2}.selectedSlicIndices)) = [];
        selectedSlicIndices = [obj.brushSelection{2}.selectedSlicIndices; slicIndices];
        obj.brushSelection{2}.selectedSlicIndices = selectedSlicIndices;
    end
    selarea2 = ismember(obj.brushSelection{2}.slic, slicIndices);

    obj.brushSelection{2}.selectedSlic(selarea2 == 1) = 1;
    CData(obj.brushSelection{2}.selectedSlic == 1) = intmax(class(obj.imageHandle.CData)) * .4;
    obj.brushSelection{1}.selection(selarea1 == 1) = true;
else
    % ---- normal brush mode ----
    obj.brushSelection{1}.selection = obj.brushSelection{1}.selection | selarea1;
    CData(obj.brushSelection{1}.selection) = intmax(class(obj.imageHandle.CData)) * .4;
end

obj.imageHandle.CData = CData;
obj.brushPrevXY = [pos(1,1) pos(1,2)];  % keep in data/axes coords

end
