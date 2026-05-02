function measureDistanceFree(obj, datasetId, colCh, ~, calcIntensity, insertIndex)
% MEASUREDISTANCEFREE - Interactive freehand distance measurement.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureDistanceFree(datasetId, colCh, finetuneCheck, calcIntensity)
%       obj.measureDistanceFree(datasetId, colCh, finetuneCheck, calcIntensity, insertIndex)
%
% The user draws a freehand path.  The resulting dense vertex array is
% downsampled using an evenly-spaced parameterisation, then the result is
% handed to :meth:`measureDistancePoly` which computes the cumulative
% arc-length and stores the measurement.
%
% Input Arguments:
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **colCh** — [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** — [logical] reserved
%   - **calcIntensity** — [logical] compute intensity profile along path
%   - **insertIndex** — *(optional)* [double] replace-at-position (0 = append)
%

if nargin < 6; insertIndex = 0; end

noPoints = str2double(obj.view.handles.noPointsEdit.Value);
fixPoints = obj.view.handles.fixNumberPoints.Value;

[rawX, rawY, wasCancelled] = obj.drawROI('freehand');
if wasCancelled || numel(rawX) < 2; return; end

% determine how many knot points to keep
if fixPoints && ~isnan(noPoints) && noPoints >= 2
    targetPoints = round(noPoints);
else
    targetPoints = max(2, round(numel(rawX) / 10));
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

interpolatedPointCount = max(2, round(totalArc));
denseArcFull = linspace(0, totalArc, interpolatedPointCount);
interpX = interp1(arcCumKnot, knotX(:), denseArcFull, splineMethod, 'extrap');
interpY = interp1(arcCumKnot, knotY(:), denseArcFull, splineMethod, 'extrap');

switch orientation
    case 1;    pxX = pixSize.z;  pxY = pixSize.x;
    case 2;    pxX = pixSize.z;  pxY = pixSize.y;
    otherwise; pxX = pixSize.x;  pxY = pixSize.y;
end
distanceValue = sum(hypot(diff(interpX) * pxX, diff(interpY) * pxY));

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    imageData   = obj.mibModel.getData2D('image', [], [], colCh, struct('id', datasetId));
    profileData = core.Measurements.computeProfile(imageData, interpX, interpY, pixSize, orientation);
    if size(profileData, 1) > 1
        intensityMean = mean(profileData(2:end, :), 2);
    end
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
newData.info           = '';
newData.colCh          = colCh;

if insertIndex > 0
    hMeasure.removeMeasurement(insertIndex);
    hMeasure.storeMeasurement(newData, insertIndex);
else
    hMeasure.storeMeasurement(newData);
end
end
