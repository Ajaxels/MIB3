function annotationText = measureDistance(obj, datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity, showInfoDlg, insertIndex)
% MEASUREDISTANCE - Interactive linear distance measurement (2-point line).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureDistance(datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity, showInfoDlg)
%       obj.measureDistance(datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity, showInfoDlg, insertIndex)
%
% The user draws a two-endpoint line.  Physical distance is computed via
% :meth:`core.Measurements.computeDistance`.  When ``integrationWidth > 0``
% the intensity profile is integrated laterally across that width.
%
% Input Arguments:
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **colCh** — [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** — [logical] when ``true`` enable fine-tuning of the drawn measurement, when ``false``, it is automatically accepted upon finishing of drawing
%   - **integrationWidth** — [double] lateral integration half-width in pixels (0 = off)
%   - **calcIntensity** — [logical] compute intensity profile along the line
%   - **showInfoDlg** — [logical] show annotation text dialog after drawing
%   - **insertIndex** — *(optional)* [double] replace-at-position (0 = append)
%

if nargin < 8; insertIndex = 0; end
annotationText = '';

hMeasure    = obj.mibModel.I{datasetId}.measure;
orientation = obj.mibModel.I{datasetId}.orientation;
pixSize     = obj.mibModel.I{datasetId}.image.pixSize;

initialPos = [];
if insertIndex > 0 && insertIndex <= hMeasure.getNumberOfMeasurements()
    oldData    = hMeasure.Data(insertIndex);
    initialPos = [oldData.X(1:2)', oldData.Y(1:2)'];
end
[X, Y, wasCancelled] = obj.drawROI('line', finetuneCheck, [], initialPos);
if wasCancelled || numel(X) < 2; return; end
X = X(1:2); Y = Y(1:2);

distanceValue = core.Measurements.computeDistance(X, Y, pixSize, orientation);

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    imageData = cell2mat(obj.mibModel.getData2D('image', [], [], colCh, struct('id', datasetId)));
    if ~isnan(integrationWidth) && integrationWidth > 0
        [integratedProfile, profileLength] = utils.imageProfileIntegrate( ...
            imageData, X(1), Y(1), X(2), Y(2), integrationWidth);
        arcLengths = linspace(0, profileLength, size(integratedProfile, 2));
        profileData = [arcLengths; integratedProfile];
    else
        profileData = core.Measurements.computeProfile(imageData, X, Y, pixSize, orientation);
    end
    if size(profileData, 1) > 1
        intensityMean = mean(profileData(2:end, :), 2);
    end
end

annotationText = '';
if ischar(showInfoDlg)
    annotationText = utils.dlgs.inputSingleDlg(obj.view.gui, 'Annotation:', showInfoDlg, 'Distance annotation');
    if isempty(annotationText); return; end
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
newData.info           = annotationText;
newData.colCh          = colCh;

if insertIndex > 0
    hMeasure.removeMeasurement(insertIndex);
    hMeasure.storeMeasurement(newData, insertIndex);
else
    hMeasure.storeMeasurement(newData);
end
end
