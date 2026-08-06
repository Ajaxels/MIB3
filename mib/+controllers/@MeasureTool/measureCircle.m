function annotationText = measureCircle(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
% MEASURECIRCLE - Interactive circle-fit measurement via an ellipse ROI.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.measureCircle(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg)
%       obj.measureCircle(datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
%
% The user draws an ellipse ROI.  The boundary vertices are passed to
% :meth:`core.Measurements.computeCircleFit` for a least-squares circle
% fit.  Stores a 60-point circle arc as ``X``/``Y`` for overlay rendering.
%
% Input Arguments:
%   - **datasetId** - [double] index into ``mibModel.I``
%   - **colCh** - [double] colour channel (0 = all, 1+ = specific)
%   - **finetuneCheck** - [logical] when ``false`` accept the ellipse immediately after placement (no double-click required)
%   - **calcIntensity** - [logical] compute radial intensity profile
%   - **showInfoDlg** - [logical] show annotation text dialog
%   - **insertIndex** - *(optional)* [double] replace-at-position (0 = append)
%

if nargin < 7; insertIndex = 0; end
annotationText = '';

hMeasure    = obj.mibModel.I{datasetId}.measure;
orientation = obj.mibModel.I{datasetId}.orientation;
pixSize     = obj.mibModel.I{datasetId}.image.pixSize;

initialPos = [];
if insertIndex > 0 && insertIndex <= hMeasure.getNumberOfMeasurements()
    oldData = hMeasure.Data(insertIndex);
    if ~isempty(oldData.circ) && isfield(oldData.circ, 'xc')
        if finetuneCheck
            % Edit mode: show existing circle as a draggable ellipse ROI.
            % initialDataPos = [cx, cy, sax, say] in data pixel space.
            initialPos = [oldData.circ.xc, oldData.circ.yc, oldData.circ.R, oldData.circ.R];
        else
            % Recalculate mode: return stored boundary arc so computeCircleFit
            % refits the same circle geometry with the updated pixSize.
            initialPos = [oldData.X(:), oldData.Y(:)];
        end
    end
end
[vertX, vertY, wasCancelled] = obj.drawROI('ellipse', finetuneCheck, [], initialPos);
if wasCancelled || numel(vertX) < 3; return; end

circ = core.Measurements.computeCircleFit(vertX, vertY);
if ~isfinite(circ.R) || circ.R <= 0; return; end

% physical radius
switch orientation
    case 1;    radiusValue = circ.R * pixSize.z;
    case 2;    radiusValue = circ.R * pixSize.z;
    otherwise; radiusValue = circ.R * pixSize.x;
end

% 60-point circle arc for overlay
theta = linspace(0, 2*pi, 60);
circX = circ.xc + circ.R * cos(theta);
circY = circ.yc + circ.R * sin(theta);

intensityMean = NaN;
profileData   = NaN;
if calcIntensity
    % profile along the circle boundary
    imageData   = cell2mat(obj.mibModel.getData2D('image', [], [], colCh, struct('id', datasetId)));
    profileData = core.Measurements.computeProfile(imageData, circX, circY, pixSize, orientation);
    if size(profileData, 1) > 1
        intensityMean = mean(profileData(2:end, :), 2);
    end
end

annotationText = '';
if ischar(showInfoDlg)
    annotationText = utils.dlgs.inputSingleDlg(obj.view.gui, 'Annotation:', showInfoDlg, 'Circle annotation');
    if isempty(annotationText); return; end
end

newData.n              = NaN;
newData.type           = 'Circle (R)';
newData.value          = radiusValue;
newData.X              = circX;
newData.Y              = circY;
newData.Z              = obj.mibModel.I{datasetId}.slices{3}(1);
newData.T              = obj.mibModel.I{datasetId}.slices{5}(1);
newData.orientation    = orientation;
newData.spline         = [];
newData.circ           = circ;
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
