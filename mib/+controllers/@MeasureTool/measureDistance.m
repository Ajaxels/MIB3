function measureDistance(obj, datasetId, colCh, ~, integrationWidth, calcIntensity, insertIndex)
% MEASUREDISTANCE - Interactive linear distance measurement (2-point line).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureDistance(datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity)
%       obj.measureDistance(datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity, insertIndex)
%
% The user draws a two-endpoint line.  Physical distance is computed via
% :meth:`core.Measurements.computeDistance`.  When ``integrationWidth > 0``
% the intensity profile is integrated laterally across that width.
%
% Input Arguments:
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **colCh** — [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** — [logical] reserved
%   - **integrationWidth** — [double] lateral integration half-width in pixels (0 = off)
%   - **calcIntensity** — [logical] compute intensity profile along the line
%   - **insertIndex** — *(optional)* [double] replace-at-position (0 = append)
%

if nargin < 7; insertIndex = 0; end

hMeasure    = obj.mibModel.I{datasetId}.measure;
orientation = obj.mibModel.I{datasetId}.orientation;
pixSize     = obj.mibModel.I{datasetId}.image.pixSize;

[X, Y, wasCancelled] = obj.drawROI('line');
if wasCancelled || numel(X) < 2; return; end
X = X(1:2); Y = Y(1:2);

distanceValue = core.Measurements.computeDistance(X, Y, pixSize, orientation);

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    imageData   = obj.mibModel.getData2D('image', [], [], colCh, struct('id', datasetId));
    profileData = core.Measurements.computeProfile(imageData, X, Y, pixSize, orientation);
    if size(profileData, 1) > 1
        intensityMean = mean(profileData(2:end, :), 2);
    end
end

% store integration width only when it was actually applied
storedIntegrateWidth = [];
if ~isnan(integrationWidth) && integrationWidth > 0
    storedIntegrateWidth = integrationWidth;
end

newData.n              = NaN;
newData.type           = 'Distance (linear)';
newData.value          = distanceValue;
newData.X              = X(:)';
newData.Y              = Y(:)';
newData.Z              = obj.mibModel.I{datasetId}.slices{3}(1);
newData.T              = obj.mibModel.I{datasetId}.slices{5}(1);
newData.orientation    = orientation;
newData.spline         = [];
newData.circ           = [];
newData.intensity      = intensityMean;
newData.profile        = profileData;
newData.integrateWidth = storedIntegrateWidth;
newData.info           = '';
newData.colCh          = colCh;

if insertIndex > 0
    hMeasure.removeMeasurement(insertIndex);
    hMeasure.storeMeasurement(newData, insertIndex);
else
    hMeasure.storeMeasurement(newData);
end
end
