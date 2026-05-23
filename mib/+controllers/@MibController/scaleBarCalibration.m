% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 23.05.2025

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
% The ruler line is temporarily stored in :class:`core.Measurements` so it
% appears as a measurement overlay while the user adjusts its endpoints.
% It is removed immediately after the calibration is applied.
%
% Replaces MIB2: ``@mibController/menuDatasetScalebar_Callback.m``
%

% Step 1 — explain the procedure
choice = utils.dlgs.inputQuestDlg(obj.view.gui, ...
    sprintf(['The following procedure allows to define the pixel size\n' ...
             'for the dataset using a scale bar displayed on the image.\n\n' ...
             'How to use:\n' ...
             '1. Specify the length of the scale bar\n' ...
             '2. With the left mouse button mark the end points of the scale bar\n' ...
             '3. Modify the scale bar by moving the end points\n' ...
             '4. Double click on the line to confirm the selection']), ...
    'Scale bar calibration', 'Continue', 'Cancel', 'Cancel');
if strcmp(choice, 'Cancel'); return; end

% Step 2 — ask for scale bar length and units
prompts = {'Length of the scale bar'; 'Units'};
defAns  = { struct('Spinner', true, 'Value', 2, 'Limits', [0 1e9], 'Step', 0.1, 'Round', false); ...
            {'m', 'cm', 'mm', 'um', 'nm', 4} };
dlgOptions.WindowHeight = 200;
dlgOptions.Columns      = 2;
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
    'Please enter the length of the scale bar as shown on the image.', ...
    prompts, defAns, 'Scale bar length', dlgOptions);
if isempty(answer)
    obj.showImage();
    return;
end
scaleBarLength = answer{1};   % numeric from spinner
scaleBarUnits  = answer{2};   % string from dropdown

% Step 3 — interactively draw a line over the scale bar (blocking)
datasetId = obj.getActiveId();
obj.mibModel.disableSegmentation = true;
cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
cImageDoc.UIFigure.Pointer = 'cross';

roiLine = drawline(cImageDoc.handles.imViewAxes);

if ~isvalid(roiLine)
    % user pressed Escape before placing any points
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    obj.mibModel.disableSegmentation = false;
    obj.showImage();
    return;
end

% Register in cRoi.drawingROI so pan/zoom repositions the line during wait
obj.cRoi.drawingROI.roi           = roiLine;
obj.cRoi.drawingROI.type          = 'Polyline';
obj.cRoi.drawingROI.dataPos       = [];
obj.cRoi.drawingROI.repositioning = false;
obj.cRoi.drawingROI.active        = true;

try
    wait(roiLine);   % blocks until the user double-clicks or Escape
catch
    obj.cRoi.drawingROI.active = false;
    if isvalid(roiLine); delete(roiLine); end
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    obj.mibModel.disableSegmentation = false;
    obj.showImage();
    return;
end

obj.cRoi.drawingROI.active = false;
obj.mibModel.disableSegmentation = false;
cImageDoc.UIFigure.Pointer = 'cross';
cImageDoc.updateBrushCursor();

if ~isvalid(roiLine)
    obj.showImage();
    return;
end
linePosition = roiLine.Position;   % [2×2] axes-space [x y] per endpoint
delete(roiLine);

if isempty(linePosition) || size(linePosition, 1) < 2
    obj.showImage();
    return;
end

% Step 4 — convert axes-space coordinates to data pixel coordinates
[pixelX, pixelY] = obj.mibModel.convertMouseToDataCoordinates( ...
    linePosition(:, 1), linePosition(:, 2), 'shown');

% Step 5 — store ruler temporarily in core.Measurements for visual overlay
hMeasure    = obj.mibModel.I{datasetId}.measure;
orientation = obj.mibModel.I{datasetId}.orientation;
pixSize     = obj.mibModel.I{datasetId}.image.pixSize;

newData.n              = NaN;
newData.type           = 'Distance (linear)';
newData.value          = core.Measurements.computeDistance(pixelX, pixelY, pixSize, orientation);
newData.X              = pixelX(:)';
newData.Y              = pixelY(:)';
newData.Z              = obj.mibModel.I{datasetId}.slices{3}(1);
newData.T              = obj.mibModel.I{datasetId}.slices{5}(1);
newData.orientation    = orientation;
newData.spline         = [];
newData.circ           = [];
newData.intensity      = NaN;
newData.profile        = NaN;
newData.integrateWidth = [];
newData.info           = 'scale bar';
newData.colCh          = 0;

measurementIndex = hMeasure.getNumberOfMeasurements() + 1;
hMeasure.storeMeasurement(newData);

% Step 6 — compute raw pixel distance (independent of current pixSize)
distancePix = sqrt((pixelX(1) - pixelX(2))^2 + (pixelY(1) - pixelY(2))^2);

if distancePix < 1
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'The drawn line is too short to use for calibration. Please try again.', ...
        'Scale bar error');
    hMeasure.removeMeasurement(measurementIndex);
    obj.showImage();
    return;
end

% Step 7 — build new pixSize from the known physical length / pixel distance
newPixSize       = obj.mibModel.I{datasetId}.image.pixSize;
newPixSize.x     = scaleBarLength / distancePix;
newPixSize.y     = scaleBarLength / distancePix;
newPixSize.z     = scaleBarLength / distancePix;
newPixSize.units = scaleBarUnits;

% Step 8 — remove the transient ruler measurement
hMeasure.removeMeasurement(measurementIndex);

% Step 9 — apply the new pixel size and update bounding box
dataset = obj.mibModel.I{datasetId};
dataset.setPixSize(newPixSize);
dataset.image.boundingBox(2) = dataset.image.boundingBox(1) + (dataset.image.width  - 1) * dataset.image.pixSize.x;
dataset.image.boundingBox(4) = dataset.image.boundingBox(3) + (dataset.image.height - 1) * dataset.image.pixSize.y;
dataset.image.boundingBox(6) = dataset.image.boundingBox(5) + (dataset.image.depth  - 1) * dataset.image.pixSize.z;

axesOptions.mode  = 'resize';
axesOptions.index = datasetId;
notify(obj.mibModel, 'UpdateDatasetAxes', core.ToggleEventData(axesOptions));
notify(obj.mibModel, 'ShowImage');
end
