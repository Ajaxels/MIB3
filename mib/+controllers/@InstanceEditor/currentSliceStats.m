function stats = currentSliceStats(obj, forceRefresh)
% CURRENTSLICESTATS - Per-object statistics of the shown slice.
%
% Syntax:
%   .. code-block:: matlab
%
%       stats = obj.currentSliceStats()
%       stats = obj.currentSliceStats(true)   % ignore the cache
%
% In 2D mode the object numbering is per slice: a model that came straight out
% of a 2D predictor starts again from 1 on every slice, so index 5 is a
% different object on every one of them. The whole-volume index in
% ``MibDataset.instanceIndex`` describes their union - which is why such a model
% reports every object as spanning the full Z range - and is therefore useless
% for listing what is on screen. This reads the shown slice instead and measures
% the objects that are actually on it.
%
% One slice is cheap enough to read on demand (a couple of milliseconds on a
% 1000x1400 slice), so the result is cached only to keep repeated widget
% refreshes off the data: the cache is keyed on the slice and the time point and
% is dropped by ``invalidateSliceStats`` whenever the model is written to.
%
% Input Arguments:
%   - **forceRefresh** - *(optional)* logical, true re-reads the slice even when
%     the cache matches. Default false
%
% Output Arguments:
%   - **stats** - structure describing the shown slice:
%
%     - ``.slice`` - slice number the measurements come from
%     - ``.timePoint`` - time point they come from
%     - ``.objectIds`` - [Nx1] double, indices present on the slice, ascending
%     - ``.pixels`` - [Nx1] double, area of each object **on this slice**
%     - ``.centroid`` - [Nx2] double, in-plane centroid as [x, y]
%
% See also: controllers.InstanceEditor.updateObjectTable,
% core.MibDataset.buildInstanceIndex

% Updates
%

if nargin < 2; forceRefresh = false; end

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};
sliceNumber = dataset.getCurrentSliceNumber();
timePoint = dataset.getCurrentTimePoint();

if ~forceRefresh && ~isempty(obj.sliceStats) && ...
        obj.sliceStats.slice == sliceNumber && obj.sliceStats.timePoint == timePoint
    stats = obj.sliceStats;
    return;
end

stats = struct('slice', sliceNumber, 'timePoint', timePoint, ...
    'objectIds', zeros(0, 1), 'pixels', zeros(0, 1), 'centroid', zeros(0, 2));

% Orientation 3 to match models.MibModel.editInstanceObjects, which reads and
% writes its boxes in XY: the list has to describe the same slice the operations
% will act on.
readOptions = struct('blockModeSwitch', 0, 'id', id, 't', timePoint);
labelSlice = cell2mat(obj.mibModel.getData2D('labels', sliceNumber, 3, NaN, readOptions));

labelledPixels = find(labelSlice);
if ~isempty(labelledPixels)
    % unique/accumarray rather than regionprops or accumarray on the label values
    % themselves: a 4294967295 model can carry very high indices, and both of
    % those allocate up to the largest label rather than to the number of objects.
    [objectIds, ~, groups] = unique(double(labelSlice(labelledPixels)));
    pixels = accumarray(groups, 1);
    [rowOfPixel, columnOfPixel] = ind2sub(size(labelSlice), labelledPixels);

    stats.objectIds = objectIds(:);
    stats.pixels = pixels(:);
    stats.centroid = [accumarray(groups, double(columnOfPixel)) ./ pixels, ...
                      accumarray(groups, double(rowOfPixel)) ./ pixels];
end

obj.sliceStats = stats;
end
