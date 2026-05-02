function measurePoint(obj, datasetId, colCh, ~, calcIntensity, showInfoDlg, insertIndex)
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
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **colCh** — [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** — [logical] reserved
%   - **calcIntensity** — [logical] read pixel intensity at the point
%   - **showInfoDlg** — [logical] show annotation text dialog
%   - **insertIndex** — *(optional)* [double] replace-at-position (0 = append)
%

if nargin < 7; insertIndex = 0; end

hMeasure    = obj.mibModel.I{datasetId}.measure;
orientation = obj.mibModel.I{datasetId}.orientation;

[X, Y, wasCancelled] = obj.drawROI('point');
if wasCancelled || isempty(X); return; end
pointX = X(1); pointY = Y(1);

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    imageData = obj.mibModel.getData2D('image', [], [], 0, struct('id', datasetId));
    rowIdx = min(size(imageData, 1), max(1, round(pointY)));
    colIdx = min(size(imageData, 2), max(1, round(pointX)));
    intensityAtPixel = double(squeeze(imageData(rowIdx, colIdx, :)));
    intensityMean    = intensityAtPixel;
    profileData      = [ones(1, numel(intensityAtPixel)); intensityAtPixel(:)'];
end

annotationText = '';
if showInfoDlg
    dlgAnswer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', {'Annotation:'}, {''}, ...
        'Point annotation', struct());
    if isempty(dlgAnswer); return; end
    annotationText = dlgAnswer{1};
end

newData.n              = NaN;
newData.type           = 'Point';
newData.value          = NaN;
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
