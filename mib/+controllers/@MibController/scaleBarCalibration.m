function scaleBarCalibration(obj)
% SCALEBARCALIBRATION - Calibrate pixel size using a scale bar drawn on the image.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.scaleBarCalibration()
%
% Guides the user to draw a line over a known-length scale bar visible in
% the image, then sets ``pixSize.x/y/z`` and ``pixSize.units`` of the active
% dataset so that one pixel corresponds to the measured physical length.
%
% Interactive drawing replicates the :meth:`controllers.MeasureTool.drawROI`
% line-draw flow - blocking ``wait()``, ``cRoi.drawingROI`` registration, and
% ``MovingROI``/``ROIMoved`` listeners - so the ruler line stays anchored to
% the image during pan and zoom.  No MeasureTool window is opened and
% nothing is written to :class:`core.Measurements`.
%

% Step 1 - explain the procedure
choiceOpt.WindowHeight = 220;
choiceOpt.WindowWidth  = 540;
choiceOpt.Icon         = 'puffin_info';
choice = utils.dlgs.inputQuestDlg(obj.view.gui, ...
    sprintf(['The following procedure allows to define the pixel size\n' ...
             'for the dataset using a scale bar displayed on the image.\n\n' ...
             'How to use:\n' ...
             '1. Specify the length of the scale bar\n' ...
             '2. With the left mouse button mark the end points of the scale bar\n' ...
             '3. Modify the scale bar by moving the end points\n' ...
             '4. Double click on the line to confirm the selection']), ...
    'Scale bar calibration', 'Continue', 'Cancel', 'Continue', choiceOpt);
if strcmp(choice, 'Cancel'); return; end

% Step 2 - ask for scale bar length and units
prompts = {'Length of the scale bar'; 'Units'};
defAns  = { struct('Spinner', true, 'Value', 2, 'Limits', [0 1e9], 'Step', 0.1, 'Round', false); ...
            {'m', 'cm', 'mm', 'um', 'nm', 4} };
dlgOptions.WindowHeight  = 200;
dlgOptions.HeaderLines   = 2;
dlgOptions.LabelPosition = 'left';
dlgOptions.Focus         = 1;
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
    'Please enter the length of the scale bar as shown on the image.', ...
    prompts, defAns, 'Scale bar length', dlgOptions);
if isempty(answer)
    obj.showImage();
    return;
end
scaleBarLength = answer{1};   % numeric from spinner
scaleBarUnits  = answer{2};   % string from dropdown

% Step 3 - blocking interactive line draw (mirrors MeasureTool.drawROI 'line' path)
% Running inline keeps MeasureTool's window closed; obj (MibController) already
% owns cImageDoc and cRoi, which are all that drawROI uses from its parent.
cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
axesHandle = cImageDoc.handles.imViewAxes;

if ~isempty(cImageDoc.brushCursor) && isvalid(cImageDoc.brushCursor)
    cImageDoc.brushCursor.Visible = false;
end
cImageDoc.UIFigure.Pointer = 'cross';

prevDisableState = obj.mibModel.disableSegmentation;
obj.mibModel.disableSegmentation = true;

try
    roiObject = drawline(axesHandle);
catch
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    obj.mibModel.disableSegmentation = prevDisableState;
    return;
end

if ~isvalid(roiObject)
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    obj.mibModel.disableSegmentation = prevDisableState;
    return;
end

% Register the active ROI so repositionDrawingROI() can reanchor it on
% every showImage call that occurs while the user pans or zooms.
cRoi = obj.cRoi;
cRoi.drawingROI.roi           = roiObject;
cRoi.drawingROI.type          = 'Polyline';
cRoi.drawingROI.dataPos       = [];
cRoi.drawingROI.repositioning = false;
cRoi.drawingROI.active        = true;

% Keep drawingROI.dataPos current on every vertex move so
% repositionDrawingROI() can convert back to screen coordinates correctly.
movingLsn = addlistener(roiObject, 'MovingROI', @(~,~) captureDataPos());
movedLsn  = addlistener(roiObject, 'ROIMoved',  @(~,~) captureDataPos());
captureDataPos();

try
    wait(roiObject);   % blocks until the user double-clicks or presses Escape
catch
    cleanupDraw();
    obj.showImage();
    return;
end

if ~isvalid(roiObject)
    cleanupDraw();
    obj.showImage();
    return;
end

screenPos = roiObject.Position;   % [2×2] axes-space [x y] per endpoint
cleanupDraw();
delete(roiObject);

if isempty(screenPos) || size(screenPos, 1) < 2
    obj.showImage();
    return;
end

% Step 4 - convert axes-space to data pixel coordinates
[pixelX, pixelY] = obj.mibModel.convertMouseToDataCoordinates( ...
    screenPos(:, 1), screenPos(:, 2), 'shown');

% Step 5 - compute raw pixel distance (independent of current pixSize)
distancePix = sqrt((pixelX(1) - pixelX(2))^2 + (pixelY(1) - pixelY(2))^2);

if distancePix < 1
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'The drawn line is too short to use for calibration. Please try again.', ...
        'Scale bar error');
    obj.showImage();
    return;
end

% Step 6 - build new pixSize: physical length / pixel distance
datasetId        = obj.mibModel.getActiveId();
newPixSize       = obj.mibModel.I{datasetId}.image.pixSize;
newPixSize.x     = scaleBarLength / distancePix;
newPixSize.y     = scaleBarLength / distancePix;
newPixSize.z     = scaleBarLength / distancePix;
newPixSize.units = scaleBarUnits;

% Step 7 - apply the new pixel size and update bounding box
dataset = obj.mibModel.I{datasetId};
dataset.setPixSize(newPixSize);
dataset.image.boundingBox(2) = dataset.image.boundingBox(1) + (dataset.image.width  - 1) * dataset.image.pixSize.x;
dataset.image.boundingBox(4) = dataset.image.boundingBox(3) + (dataset.image.height - 1) * dataset.image.pixSize.y;
dataset.image.boundingBox(6) = dataset.image.boundingBox(5) + (dataset.image.depth  - 1) * dataset.image.pixSize.z;

axesOptions.mode  = 'resize';
axesOptions.index = datasetId;
notify(obj.mibModel, 'UpdateDatasetAxes', core.ToggleEventData(axesOptions));
notify(obj.mibModel, 'ShowImage');

% -------------------------------------------------------------------------
    function captureDataPos()
        if ~isvalid(roiObject) || cRoi.drawingROI.repositioning; return; end
        try
            verts = roiObject.Position;
            [X, Y] = obj.mibModel.convertMouseToDataCoordinates( ...
                verts(:, 1), verts(:, 2), 'shown');
            cRoi.drawingROI.dataPos = [X(:), Y(:)];
        catch
        end
    end

    function cleanupDraw()
        delete(movingLsn);
        delete(movedLsn);
        cRoi.drawingROI.active = false;
        cRoi.drawingROI.roi    = [];
        cImageDoc.UIFigure.Pointer = 'cross';
        cImageDoc.updateBrushCursor();
        obj.mibModel.disableSegmentation = prevDisableState;
    end

end
