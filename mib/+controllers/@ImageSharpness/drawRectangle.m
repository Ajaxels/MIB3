function drawRectangle(obj)
% DRAWRECTANGLE - Let the user draw the region to analyse as a rectangle on the image.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.drawRectangle()
%
% Hides the dialog, starts ``drawrectangle`` on the image axes of the active
% panel and waits until the user double-clicks inside the rectangle (Escape
% cancels). The position is stored in ``obj.drawnRectangle`` in data pixels
% of the shown orientation, clamped to the image, together with the dataset
% id and orientation so that a later calculation on another dataset or
% orientation is refused. Called by the action button
% (:func:`controllers.ImageSharpness.runButtonPushed`) for the ``Drawn
% rectangle`` region, and from ``calculate`` in that region when no
% rectangle exists yet. The rectangle is analysed at once with
% :func:`controllers.ImageSharpness.calculate`. Cancelling the drawing, or a
% rectangle below 64 x 64 pixels, keeps the previous rectangle and runs no
% calculation.
%
% When the previous rectangle belongs to the active dataset and orientation
% and lies fully inside the current view, it is placed again
% (``images.roi.Rectangle``) instead of starting a new drawing: the user can
% move or resize it, or double-click to analyse the same area again, for
% example on another slice; deleting it from its context menu cancels. If it
% is accepted without moving, the stored pixel position is reused exactly;
% converting it to screen coordinates and back could shift it by a pixel.
% A rectangle outside the view starts a new drawing.
%
% While drawing, the position is converted to data pixels on every move and
% the rectangle is registered in ``cRoi.drawingROI``, which keeps it in place
% when the view is zoomed or panned (same pattern as
% ``controllers.CropDataset``). Segmentation tools are disabled meanwhile.
%
% The rectangle is removed after drawing; the region is shown as text under
% the region list.
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageSharpness.drawRectangle: triggered\n');
end
if isempty(obj.mibController) || ~isvalid(obj.mibController); return; end

id = obj.mibModel.getActiveId();
cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
imViewAxes = cImageDoc.handles.imViewAxes;
cRoi = obj.mibController.cRoi;
if isempty(imViewAxes) || ~isgraphics(imViewAxes)
    utils.dlgs.showErrorDialog(obj.view.gui, 'Image axes are not available.', 'Sharpness and noise');
    return;
end

obj.view.gui.Visible = 'off';
obj.mibModel.disableSegmentation = true;
cImageDoc.UIFigure.Pointer = 'cross';
if ~isempty(cRoi)
    cRoi.drawingROI.type          = 'Rectangle';
    cRoi.drawingROI.dataPos       = [];
    cRoi.drawingROI.repositioning = false;
    cRoi.drawingROI.active        = false;
end

% start from the previous rectangle of this dataset and orientation when it is fully in view
previous = obj.drawnRectangle;
initialPosition = [];
if ~isempty(previous) && previous.id == id && previous.orientation == obj.mibModel.I{id}.orientation
    % stored values are the first and last pixel; their outer edges are at x1-1 and x2
    [edgeX, edgeY] = obj.mibModel.convertDataToMouseCoordinates( ...
        previous.position([1 3]) - [1 0], previous.position([2 4]) - [1 0], 'shown');
    axesX = imViewAxes.XLim;
    axesY = imViewAxes.YLim;
    if min(edgeX) >= axesX(1) && max(edgeX) <= axesX(2) && min(edgeY) >= axesY(1) && max(edgeY) <= axesY(2)
        initialPosition = [min(edgeX), min(edgeY), abs(diff(edgeX)), abs(diff(edgeY))];
    end
end

roi = [];
movingListener = [];
movedListener = [];
dataPosition = [];
moved = false;
drawOk = false;
try
    if isempty(initialPosition)
        roi = drawrectangle(imViewAxes);
    else
        roi = images.roi.Rectangle(imViewAxes, 'Position', initialPosition);
    end
    if isvalid(roi)
        movingListener = addlistener(roi, 'MovingROI', @(~,~) rectangleMoved());
        movedListener  = addlistener(roi, 'ROIMoved',  @(~,~) rectangleMoved());
        captureDataPosition();
        if ~isempty(cRoi)
            cRoi.drawingROI.roi    = roi;
            cRoi.drawingROI.active = true;
        end
        wait(roi);
        % Escape clears roi.Position without deleting the object
        drawOk = isvalid(roi) && ~isempty(roi.Position);
    end
catch
end

if ~isempty(movingListener); delete(movingListener); end
if ~isempty(movedListener);  delete(movedListener);  end
if ~isempty(cRoi); cRoi.drawingROI.active = false; end
obj.mibModel.disableSegmentation = false;
if ~isempty(roi) && isvalid(roi); delete(roi); end
obj.view.gui.Visible = 'on';
figure(obj.view.gui);
drawnow;

if ~drawOk || isempty(dataPosition); return; end

if ~isempty(initialPosition) && ~moved
    % accepted unchanged: keep the stored pixels instead of a round trip through screen coordinates
    position = previous.position;
else
    position = ceil([dataPosition(1,1), dataPosition(1,2), dataPosition(2,1), dataPosition(2,2)]);
end
[height, width] = obj.mibModel.I{id}.getDatasetDimensions('selection', [], struct('blockModeSwitch', 0));
position(1:2) = max(position(1:2), 1);
position(3) = min(position(3), width);
position(4) = min(position(4), height);
if position(3) - position(1) + 1 < 64 || position(4) - position(2) + 1 < 64
    uialert(obj.view.gui, sprintf('The rectangle is %d x %d pixels; draw at least 64 x 64 pixels.', ...
        position(3)-position(1)+1, position(4)-position(2)+1), 'Sharpness and noise', 'Icon', 'warning');
    return;
end

obj.drawnRectangle = struct('position', position, 'orientation', obj.mibModel.I{id}.orientation, 'id', id);
obj.updateRegionInfo();
obj.calculate();

    function rectangleMoved()
        moved = true;
        captureDataPosition();
    end

    function captureDataPosition()
        % keep the rectangle in data pixels; skipped while the view repositions it after zoom
        if isempty(roi) || ~isvalid(roi) || isempty(roi.Position); return; end
        if ~isempty(cRoi) && cRoi.drawingROI.repositioning; return; end
        roiPosition = roi.Position;   % [x y width height] in axes coordinates
        [pointX, pointY] = obj.mibModel.convertMouseToDataCoordinates( ...
            [roiPosition(1); roiPosition(1)+roiPosition(3)], [roiPosition(2); roiPosition(2)+roiPosition(4)], 'shown');
        dataPosition = [pointX(:), pointY(:)];
        if ~isempty(cRoi); cRoi.drawingROI.dataPos = dataPosition; end
    end
end
