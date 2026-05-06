function annotationText = measureDistanceFree(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
% MEASUREDISTANCEFREE - Interactive freehand distance measurement.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureDistanceFree(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg)
%       obj.measureDistanceFree(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
%
% The user draws a freehand path.  The resulting dense vertex array is
% downsampled using an evenly-spaced parameterisation, then the result is
% handed to :meth:`measureDistancePoly` which computes the cumulative
% arc-length and stores the measurement.
%
% Input Arguments:
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **colCh** — [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** — [logical] when ``false`` accept the freehand path immediately after drawing (no double-click required)
%   - **calcIntensity** — [logical] compute intensity profile along path
%   - **showInfoDlg** — [logical] show annotation text dialog after drawing
%   - **insertIndex** — *(optional)* [double] replace-at-position (0 = append)
%
% Output Arguments:
%   - **annotationText** — [char] annotation label entered by the user;
%     empty string ``''`` when the dialog was skipped or cancelled
%

if nargin < 7; insertIndex = 0; end
annotationText = '';

autoPointSpacing = obj.view.handles.autoPointSpacing.Value;

initialPos = [];
if insertIndex > 0 && insertIndex <= hMeasure.getNumberOfMeasurements()
    oldData    = hMeasure.Data(insertIndex);
    initialPos = [oldData.spline.x(:), oldData.spline.y(:)];
end
[rawX, rawY, wasCancelled] = obj.drawROI('freehand', finetuneCheck, [], initialPos);
if wasCancelled || numel(rawX) < 2; return; end

% determine how many knot points to keep
if autoPointSpacing && numel(rawX) > 2
    targetPoints = max(2, round(numel(rawX) / 10));
else
    targetPoints = max(2, round(numel(rawX) / 10));
    defAns = struct('Value', targetPoints, 'Limits', [1 Inf], 'Step', 1, 'Round', true);
    reductionFactor = utils.dlgs.inputSingleDlg(obj.view.gui, ...
        sprintf('Captured points: %d\nEnter density reduction factor (1 = keep all):', numel(rawX)), ...
        defAns, 'Freehand point density');
    if isempty(reductionFactor); return; end
    targetPoints = max(2, round(numel(rawX) / reductionFactor));
end
targetPoints = min(targetPoints, numel(rawX));

% evenly-spaced downsample along arc length
arcCum  = [0; cumsum(hypot(diff(rawX), diff(rawY)))];
denseArc = linspace(0, arcCum(end), targetPoints);
knotX = interp1(arcCum, rawX, denseArc);
knotY = interp1(arcCum, rawY, denseArc);

% reuse polyline logic with the downsampled knots by temporarily storing them
% and routing through measureDistancePoly internals inline
hMeasure     = obj.mibModel.I{datasetId}.measure;
orientation  = obj.mibModel.I{datasetId}.orientation;
pixSize      = obj.mibModel.I{datasetId}.image.pixSize;
splineMethod = hMeasure.Options.splinemethod;

arcCumKnot = [0; cumsum(hypot(diff(knotX(:)), diff(knotY(:))))];
totalArc   = arcCumKnot(end);
if totalArc < eps; return; end

nDense = max(2, round(totalArc));
denseArc = sort(unique([linspace(0, totalArc, nDense), arcCumKnot(:)']));
interpX = interp1(arcCumKnot, knotX(:), denseArc, splineMethod, 'extrap');
interpY = interp1(arcCumKnot, knotY(:), denseArc, splineMethod, 'extrap');

switch orientation
    case 1;    pxX = pixSize.z;  pxY = pixSize.x;
    case 2;    pxX = pixSize.z;  pxY = pixSize.y;
    otherwise; pxX = pixSize.x;  pxY = pixSize.y;
end
distanceValue = sum(hypot(diff(interpX) * pxX, diff(interpY) * pxY));

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    imageData   = cell2mat(obj.mibModel.getData2D('image', [], [], colCh, struct('id', datasetId)));
    profileData = core.Measurements.computeProfile(imageData, interpX, interpY, pixSize, orientation);
    if size(profileData, 1) > 1
        intensityMean = mean(profileData(2:end, :), 2);
    end
end

annotationText = '';
if ischar(showInfoDlg)
    annotationText = utils.dlgs.inputSingleDlg(obj.view.gui, 'Annotation:', showInfoDlg, 'Freehand annotation');
    if isempty(annotationText); return; end
end

newData.n              = NaN;
newData.type           = 'Distance (polyline)';
newData.value          = distanceValue;
newData.X              = interpX;
newData.Y              = interpY;
newData.Z              = obj.mibModel.I{datasetId}.slices{3}(1);
newData.T              = obj.mibModel.I{datasetId}.slices{5}(1);
newData.orientation    = orientation;
newData.spline         = struct('x', knotX(:)', 'y', knotY(:)');
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
