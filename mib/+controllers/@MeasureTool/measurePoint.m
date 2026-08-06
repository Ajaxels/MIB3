function annotationText = measurePoint(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
% MEASUREPOINT - Interactive single-point measurement.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measurePoint(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg)
%       obj.measurePoint(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
%
% The user places a single point.  Pixel intensity at that location is
% read from the 2-D image slice for all channels.
%
% Input Arguments:
%   - **datasetId** - [double] index into ``mibModel.I``
%   - **colCh** - [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** - [logical] when ``false`` accept the point immediately after placement (no double-click required)
%   - **calcIntensity** - [logical] read pixel intensity at the point
%   - **showInfoDlg** - [logical] show annotation text dialog
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

initialPos = [];
if insertIndex > 0 && insertIndex <= hMeasure.getNumberOfMeasurements()
    oldData    = hMeasure.Data(insertIndex);
    initialPos = [oldData.X(1), oldData.Y(1)];
end
[X, Y, wasCancelled] = obj.drawROI('point', finetuneCheck, [], initialPos);
if wasCancelled || isempty(X); return; end
pointX = X(1); pointY = Y(1);

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    pixRow = max(1, round(pointY));
    pixCol = max(1, round(pointX));
    pixOpts = struct('id', datasetId, 'x', [pixCol, pixCol], 'y', [pixRow, pixRow]);
    imageData = cell2mat(obj.mibModel.getData2D('image', [], [], colCh, pixOpts));
    intensityAtPixel = double(imageData(:));
    intensityMean    = intensityAtPixel;
    profileData      = [0; intensityAtPixel(:)];   % row 1 = distance 0; rows 2+ = per-channel intensity
end

if ischar(showInfoDlg)
    annotationText = utils.dlgs.inputSingleDlg(obj.view.gui, 'Annotation:', showInfoDlg, 'Point annotation');
    if isempty(annotationText); return; end
end

newData.n              = NaN;
newData.type           = 'Point';
newData.value          = mean(double(intensityMean));
newData.X              = pointX;
newData.Y              = pointY;
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
