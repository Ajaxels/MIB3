function updateBrushCursorOffset(obj)
% UPDATEBRUSHCURSOROFFSET - Update brush cursor offset based on current brush radius and magnification.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateBrushCursorOffset()
%
% Calculates the circle points for the brush cursor based on
% the current brush radius setting and image magnification factor.
% The offset is stored as a 2×N array with X and Y offsets.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% **Example** - called automatically when brush size changes:
%
%   .. code-block:: matlab
%
%      obj.updateBrushCursorOffset();
%

% Get brush radius from segmentation panel
radius = obj.view.handles.panels.segmentation.handles.brushRadius.Value - 1;

% Get magnification factor for THIS document's panel.
% Do NOT use getMagFactor() without an id - it reads the global mibModel.id
% which is stale in split view (still pointing at the other panel until the
% user clicks). Use setOfDatasetsIndex to resolve the local dataset id.
localId = obj.mibModel.Sets.selectedDataset(obj.setOfDatasetsIndex) + ...
    (obj.setOfDatasetsIndex - 1) * obj.mibModel.Sets.datasetsInSet;

magFactor = obj.mibModel.getMagFactor(localId);

% Calculate scaled size (in CData pixels)
fixToScreen = obj.view.handles.panels.segmentation.handles.brushFixToScreen.Value;
if fixToScreen
    se_size = max(1, radius);
else
    if radius == 0
        se_size = round(1/magFactor/2);
    else
        se_size = round(radius/magFactor);
    end
end

% Derive the stretch from imageHandle XData/YData so the cursor matches the
% displayed image for anisotropic orientations: Z is stretched horizontally in
% ZY and vertically in ZX (MibDataset.getDisplayStretch).
% XData = [1, shownW * coefX]; YData = [1, shownH * coefY].
coefX = 1;
coefY = 1;
if ~isempty(obj.imageHandle) && isvalid(obj.imageHandle)
    XData  = obj.imageHandle.XData;
    YData  = obj.imageHandle.YData;
    shownW = size(obj.imageHandle.CData, 2);   % use this panel's CData, not global Ishown
    shownH = size(obj.imageHandle.CData, 1);
    if numel(XData) >= 2 && shownW > 1
        coefX = (XData(end) - XData(1)) / (shownW - 1);
    end
    if numel(YData) >= 2 && shownH > 1
        coefY = (YData(end) - YData(1)) / (shownH - 1);
    end
end

% Generate ellipse points (17 points for smooth appearance):
%   X radius scaled by coefX, Y radius by coefY.
theta = linspace(0, 2*pi, 17);
obj.brushCursorOffset(1, :) = cos(theta) * se_size * coefX;  % X offsets
obj.brushCursorOffset(2, :) = sin(theta) * se_size * coefY;  % Y offsets

% Remember which magFactor produced this offset so updateBrushCursor can
% detect when the magnification has changed (e.g. after switching panels).
obj.brushCursorMagFactor = magFactor;

end
