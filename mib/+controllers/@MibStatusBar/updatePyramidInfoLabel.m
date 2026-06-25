function updatePyramidInfoLabel(obj)
% UPDATEPYRAMIDINFOLABEL - Update infoLabel with pyramid level info for BigData/Virtual datasets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updatePyramidInfoLabel()
%
% Called after every zoom change. Populates ``obj.handles.infoLabel`` with the
% currently rendered pyramid level index, total level count, and downsampling
% factor. Only shown for pyramidal datasets (BigData / tiled Virtual); cleared
% for standard in-memory images.
%
% Output Arguments:
%   (none)

arguments (Input)
    obj controllers.MibStatusBar
end

dataset = obj.mibModel.I{obj.mibModel.id};

% Only pyramidal datasets have populated levelNames
if isempty(dataset.image.pyramid.levelNames)
    obj.handles.infoLabel.Text = '';
    return;
end

nLevels     = size(dataset.image.pyramid.levelScaleFactors, 1);
magFactor   = dataset.magFactor;
[~, levelIdx]  = min(abs(dataset.image.pyramid.levelScaleFactors(:, 1) - magFactor));
actualScale    = dataset.image.pyramid.levelScaleFactors(levelIdx, 1);

% --- Active: level index / total  and  downsampling factor ---
infoText = sprintf('Level: %d/%d (%c%g)', levelIdx, nLevels, char(215), actualScale);

% --- Effective pixel size at this pyramid level ---
% physPixelSize = dataset.image.pixSize.x * actualScale;   % µm/px
% infoText = [infoText, sprintf('  %.2f\xB5m/px', physPixelSize)];

% --- Current level dimensions [width x height px] ---
% levelDims = dataset.image.pyramid.levelImageSizes(levelIdx, 1:2);  % [Y X]
% infoText = [infoText, sprintf('  [%d%c%d]', levelDims(2), char(215), levelDims(1))];

% --- Model materialization state (BigData only): dirty tile count in viewport ---
% if strcmp(dataset.datasetType, 'BigData') && dataset.modelExist ...
%         && isa(dataset.labels, 'core.MibBigDataLabels') && ~isempty(dataset.labels.matLevel)
%     viewY = [max(1, floor(dataset.axesY(1))), min(dataset.dim_yxzct(1), ceil(dataset.axesY(2)))];
%     viewX = [max(1, floor(dataset.axesX(1))), min(dataset.dim_yxzct(2), ceil(dataset.axesX(2)))];
%     [ty, tx, tz] = dataset.labels.tilesForFullRegion(viewY, viewX, [1, max(1, dataset.dim_yxzct(3))]);
%     viewTiles = dataset.labels.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2));
%     nDirty = nnz(viewTiles > 0 & viewTiles > levelIdx);
%     if nDirty == 0
%         infoText = [infoText, '  M', char(10003)];   % M✓
%     else
%         infoText = [infoText, sprintf('  M~%d', nDirty)];
%     end
% end

% --- Physical field of view (current level extents in mm) ---
% levelDims    = dataset.image.pyramid.levelImageSizes(levelIdx, 1:2);  % [Y X]
% physPixelSize = dataset.image.pixSize.x * actualScale;                % µm/px
% fovWidthMm  = levelDims(2) * physPixelSize / 1000;
% fovHeightMm = levelDims(1) * physPixelSize / 1000;
% infoText = [infoText, sprintf('  %.1f%c%.1fmm', fovWidthMm, char(215), fovHeightMm)];

obj.handles.infoLabel.Text = infoText;
end
