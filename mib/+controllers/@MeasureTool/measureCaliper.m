function annotationText = measureCaliper(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
% MEASURECALIPER - Interactive caliper (perpendicular-width) measurement.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureCaliper(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg)
%       obj.measureCaliper(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
%
% Draws a 2-point line (P1, P2) then a single point (P3) perpendicular to
% it.  Computes the shortest distance from P3 to the line P1–P2, scaled by
% pixel size.  P4 (foot of perpendicular) is stored for overlay rendering.
%
% Input Arguments:
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **colCh** — [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** — [logical] when ``false`` accept each ROI immediately after placement (no double-click required)
%   - **calcIntensity** — [logical] compute intensity profile along perpendicular
%   - **showInfoDlg** — [logical] show annotation text dialog
%   - **insertIndex** — *(optional)* [double] replace-at-position (0 = append)
%
% Output Arguments:
%   - **annotationText** — [char] annotation label entered by the user;
%     empty string ``''`` when the dialog was skipped or cancelled
%

if nargin < 7; insertIndex = 0; end
annotationText = '';

hMeasure    = obj.mibModel.I{datasetId}.measure;
orientation = obj.mibModel.I{datasetId}.orientation;
pixSize     = obj.mibModel.I{datasetId}.image.pixSize;

initialLinePos  = [];
initialPointPos = [];
if insertIndex > 0 && insertIndex <= hMeasure.getNumberOfMeasurements()
    oldData         = hMeasure.Data(insertIndex);
    initialLinePos  = [oldData.X(1:2)', oldData.Y(1:2)'];
    initialPointPos = [oldData.X(3), oldData.Y(3)];
end

% draw the baseline
[lineX, lineY, wasCancelled] = obj.drawROI('line', finetuneCheck, [], initialLinePos);
if wasCancelled || numel(lineX) < 2; return; end
p1x = lineX(1); p1y = lineY(1);
p2x = lineX(2); p2y = lineY(2);

% Keep the baseline visible while the user places the perpendicular point.
cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
axesHandle = cImageDoc.handles.imViewAxes;
baselineOverlay = [];
try
    [screenX12, screenY12] = obj.mibModel.convertDataToMouseCoordinates([p1x, p2x], [p1y, p2y], 'shown');
    baselineOverlay = line(axesHandle, screenX12, screenY12, ...
        'Color', [1 1 0], 'LineWidth', 1.5, ...
        'HitTest', 'off', 'PickableParts', 'none', 'Tag', 'caliper_temp');
catch
end

% draw the perpendicular point
[ptX, ptY, wasCancelled] = obj.drawROI('point', finetuneCheck, [], initialPointPos);

if ~isempty(baselineOverlay) && isvalid(baselineOverlay); delete(baselineOverlay); end
if wasCancelled || isempty(ptX); return; end
p3x = ptX(1); p3y = ptY(1);

% perpendicular distance from P3 to line P1-P2
lineLengthSquared = (p2x - p1x)^2 + (p2y - p1y)^2;
if lineLengthSquared < eps
    return;
end
% signed perpendicular distance (pixel units)
perpDistPx = ((p2x - p1x)*(p1y - p3y) - (p1x - p3x)*(p2y - p1y)) / sqrt(lineLengthSquared);

% physical caliper value
switch orientation
    case 1;    caliperValue = abs(perpDistPx) * pixSize.x;
    case 2;    caliperValue = abs(perpDistPx) * pixSize.y;
    otherwise; caliperValue = abs(perpDistPx) * pixSize.x;
end

% foot of perpendicular P4
t = ((p3x - p1x)*(p2x - p1x) + (p3y - p1y)*(p2y - p1y)) / lineLengthSquared;
p4x = p1x + t * (p2x - p1x);
p4y = p1y + t * (p2y - p1y);

X = [p1x, p2x, p3x, p4x];
Y = [p1y, p2y, p3y, p4y];

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    % profile along the perpendicular segment P3-P4
    imageData   = cell2mat(obj.mibModel.getData2D('image', [], [], colCh, struct('id', datasetId)));
    profileData = core.Measurements.computeProfile(imageData, [p3x, p4x], [p3y, p4y], pixSize, orientation);
    if size(profileData, 1) > 1
        intensityMean = mean(profileData(2:end, :), 2);
    end
end

annotationText = '';
if ischar(showInfoDlg)
    annotationText = utils.dlgs.inputSingleDlg(obj.view.gui, 'Annotation:', showInfoDlg, 'Caliper annotation');
    if isempty(annotationText); return; end
end

newData.n              = NaN;
newData.type           = 'Caliper';
newData.value          = caliperValue;
newData.X              = X;
newData.Y              = Y;
newData.Z              = obj.mibModel.I{datasetId}.slices{3}(1);
newData.T              = obj.mibModel.I{datasetId}.slices{5}(1);
newData.orientation    = orientation;
newData.spline         = [];
newData.circ           = [];
newData.intensity      = intensityMean;
newData.profile        = profileData;
newData.integrateWidth = [];
newData.info           = annotationText;
newData.colCh          = colCh;

if insertIndex > 0
    hMeasure.removeMeasurement(insertIndex);
    hMeasure.storeMeasurement(newData, insertIndex);
else
    hMeasure.storeMeasurement(newData);
end
end
