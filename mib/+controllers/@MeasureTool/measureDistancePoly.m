function measureDistancePoly(obj, datasetId, colCh, noPoints, ~, calcIntensity, insertIndex)
% MEASUREDISTANCEPOLY - Interactive polyline distance measurement.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureDistancePoly(datasetId, colCh, noPoints, finetuneCheck, calcIntensity)
%       obj.measureDistancePoly(datasetId, colCh, noPoints, finetuneCheck, calcIntensity, insertIndex)
%
% The user draws an open polygon.  The vertices are interpolated with the
% spline method selected in ``interpolationModePopup`` and the cumulative arc-length is
% computed in physical units.  The original knot coordinates are stored in
% ``.spline`` for overlay rendering; the interpolated path is stored in
% ``X``/``Y``.
%
% Input Arguments:
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **colCh** — [double] colour channel (0 = all, 1+ = specific)
%   - **noPoints** — [double] target number of interpolated points (NaN = auto)
%   - **finetuneCheck** — [logical] reserved
%   - **calcIntensity** — [logical] compute intensity profile along path
%   - **insertIndex** — *(optional)* [double] replace-at-position (0 = append)
%

if nargin < 7; insertIndex = 0; end

hMeasure        = obj.mibModel.I{datasetId}.measure;
orientation     = obj.mibModel.I{datasetId}.orientation;
pixSize         = obj.mibModel.I{datasetId}.image.pixSize;
splineMethod    = hMeasure.Options.splinemethod;

[knotX, knotY, wasCancelled] = obj.drawROI('polyline');
if wasCancelled || numel(knotX) < 2; return; end

% cumulative arc-length parameterisation of the knots
arcCum = [0; cumsum(hypot(diff(knotX(:)), diff(knotY(:))))];
totalArc = arcCum(end);
if totalArc < eps; return; end

% number of interpolated samples
if isnan(noPoints) || noPoints < 2
    interpolatedPointCount = max(2, round(totalArc));
else
    interpolatedPointCount = round(noPoints);
end
denseArc = linspace(0, totalArc, interpolatedPointCount);

% interpolate path
interpX = interp1(arcCum, knotX(:), denseArc, splineMethod, 'extrap');
interpY = interp1(arcCum, knotY(:), denseArc, splineMethod, 'extrap');

% physical cumulative distance
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
