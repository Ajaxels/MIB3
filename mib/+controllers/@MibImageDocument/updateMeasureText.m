function updateMeasureText(obj, pos)
% UPDATEMEASURETEXT - Refresh the quick-measurement text label for this document's active ROI.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateMeasureText()
%      obj.updateMeasureText(pos)
%
% Called from ``MovingROI`` listener (``pos`` provided) and from model event
% listeners (``pos`` omitted; position read from ``roi.Position``).
%
% If the currently displayed dataset differs from the one the ROI was drawn
% on (e.g. after buffer/dataset change), the ROI is deleted silently via
% ``clearQuickMeasure`` instead of updating.
%
% Input Arguments:
%   - **pos** *(optional)* - [N×2 numeric] position in physical (XData) coordinates;
%     when ``[]`` or omitted, position is read from ``quickMeasure.roi.Position``
%
% Output Arguments:
%   (none)
%

if isempty(obj.quickMeasure); return; end

% Handle stale handles gracefully (also covers the 'pending' placeholder
% set before drawline/drawfreehand returns).
if isempty(obj.quickMeasure.roi) || ~isvalid(obj.quickMeasure.roi) || ...
        isempty(obj.quickMeasure.textH) || ~isvalid(obj.quickMeasure.textH)
    return;
end

% Detect dataset change (buffer switch, new image load, etc.)
% Always recompute from Sets so it stays correct even when mibModel.id drifts.
currentDatasetId = obj.mibModel.Sets.selectedDataset(obj.setOfDatasetsIndex) + ...
    (obj.setOfDatasetsIndex - 1) * obj.mibModel.Sets.datasetsInSet;
if currentDatasetId ~= obj.quickMeasure.datasetId
    obj.clearQuickMeasure();   % silently delete stale ROI
    return;
end

% Resolve position
if nargin < 2 || isempty(pos)
    pos = obj.quickMeasure.roi.Position;
end
if isempty(pos); return; end

% Save latest position (used by finalizeMeasurement after double-click)
obj.quickMeasure.lastPos = pos;

% Read current coordinate-system state fresh from the model
datasetId   = obj.quickMeasure.datasetId;
dataset     = obj.mibModel.I{datasetId};
magFactor   = dataset.magFactor;
[axesX, axesY] = dataset.getAxesLimits();
pixSize     = dataset.image.pixSize;
orientation = dataset.orientation;

[coefX, coefY] = dataset.getDisplayStretch();

% Convert physical (XData/YData) coords to data-pixel coords for distance calc
if magFactor >= 1
    px = pos(:,1) * magFactor / coefX;
    py = pos(:,2) * magFactor / coefY;
else
    px = pos(:,1) * magFactor / coefX + max([0 floor(axesX(1))]);
    py = pos(:,2) * magFactor / coefY + max([0 floor(axesY(1))]);
end

if orientation == 3;      xSz = pixSize.x; ySz = pixSize.y;
elseif orientation == 1;  xSz = pixSize.x; ySz = pixSize.z;   % zx: horizontal X, vertical Z
else;                     xSz = pixSize.z; ySz = pixSize.y;
end

dist = 0;
for i = 2:size(px, 1)
    dist = dist + sqrt(((px(i)-px(i-1))*xSz)^2 + ((py(i)-py(i-1))*ySz)^2);
end

midPt = mean(pos, 1);
obj.quickMeasure.textH.Position = [midPt(1), midPt(2)];
obj.quickMeasure.textH.String   = sprintf('%.4g %s', dist, pixSize.units);

end
