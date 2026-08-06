function annotationText = measureAngle(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
% MEASUREANGLE - Interactive angle measurement (3 points, vertex = point 2).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureAngle(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg)
%       obj.measureAngle(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
%
% Draws a 3-vertex polyline on the image axes, computes the angle at the
% second vertex, optionally computes an intensity profile, then stores the
% result via :meth:`core.Measurements.storeMeasurement`.
%
% Input Arguments:
%   - **datasetId** - [double] index into ``mibModel.I``
%   - **colCh** - [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** - [logical] when ``false`` accept the ROI immediately after placement (no double-click required)
%   - **calcIntensity** - [logical] compute intensity profile along path
%   - **showInfoDlg** - [logical] show annotation text dialog after drawing
%   - **insertIndex** - *(optional)* [double] replace-at-position (0 = append)
%
% Output Arguments:
%   - **annotationText** - [char] annotation label entered by the user;
%     empty string ``''`` when the dialog was skipped or cancelled
%

if nargin < 7; insertIndex = 0; end
annotationText = '';

hMeasure    = obj.mibModel.I{datasetId}.measure;
orientation = obj.mibModel.I{datasetId}.orientation;
pixSize     = obj.mibModel.I{datasetId}.image.pixSize;

initialPos = [];
if insertIndex > 0 && insertIndex <= hMeasure.getNumberOfMeasurements()
    oldData    = hMeasure.Data(insertIndex);
    initialPos = [oldData.X(1:3)', oldData.Y(1:3)'];
end
[X, Y, wasCancelled] = obj.drawROI('polyline', finetuneCheck, 3, initialPos);
if wasCancelled || numel(X) < 3; return; end
if numel(X) > 3; X = X(1:3); Y = Y(1:3); end

angleValue = core.Measurements.computeAngle(X, Y, pixSize, orientation);

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    imageData   = cell2mat(obj.mibModel.getData2D('image', [], [], colCh, struct('id', datasetId)));
    profileData = core.Measurements.computeProfile(imageData, X, Y, pixSize, orientation);
    if size(profileData, 1) > 1
        intensityMean = mean(profileData(2:end, :), 2);
    end
end

annotationText = '';
if ischar(showInfoDlg)
    annotationText = utils.dlgs.inputSingleDlg(obj.view.gui, 'Annotation:', showInfoDlg, 'Angle annotation');
    if isempty(annotationText); return; end
end

newData.n              = NaN;
newData.type           = 'Angle';
newData.value          = angleValue;
newData.X              = X(:)';
newData.Y              = Y(:)';
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
