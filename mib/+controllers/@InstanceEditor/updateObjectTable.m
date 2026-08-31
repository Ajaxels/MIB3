function updateObjectTable(obj)
% UPDATEOBJECTTABLE - Repaint the object list.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateObjectTable()
%
% The list follows the mode, because in the two modes the word "object" means
% two different things:
%
% - **3D mode** - one row per object of the whole model, taken from the cached
%   index (``MibDataset.instanceIndex``). Sorting and filtering run over the
%   index arrays, which are a few tens of thousands of elements, and never over
%   the volume.
% - **2D mode** - one row per object **on the shown slice**, measured from that
%   slice by ``currentSliceStats``. A model straight out of a 2D predictor
%   numbers its objects again from 1 on every slice, so the whole-volume figures
%   describe the union of unrelated objects and the Z range of every one of them
%   is the whole stack. The Z range and slice-count columns are dropped as
%   meaningless there, and the area shown is the area on this slice.
%
% Only the first ``MaxRows`` rows are handed to the ``uitable``: an App Designer
% table with tens of thousands of rows is unusable however fast the data behind
% it is. Whatever is currently picked is always included, so a selection cannot
% disappear behind the row cap.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

% Updates
%

h = obj.view.handles;
if ~obj.modelIsEditable(); return; end

if h.Mode3D.Value
    [objectIds, columns] = iVolumeRows(obj);
    h.objectTable.ColumnName = {'Index', 'Voxels', 'Slices', 'Z range'};
else
    [objectIds, columns] = iSliceRows(obj);
    h.objectTable.ColumnName = {'Index', 'Pixels'};
end

if isempty(objectIds)
    h.objectTable.Data = table();
    obj.displayedIds = [];
    return;
end

% Always keep the picked objects visible, even when a filter excludes them.
picked = obj.selectedObjects(:);
picked = picked(ismember(picked, objectIds));
[objectIds, keptRows] = iApplyFilters(h, objectIds, columns, picked);
columns = structfun(@(v) v(keptRows, :), columns, 'UniformOutput', false);

obj.displayedIds = objectIds;
if isempty(objectIds)
    h.objectTable.Data = table();
    return;
end

if h.Mode3D.Value
    zRange = arrayfun(@(k) sprintf('%d-%d', columns.zMin(k), columns.zMax(k)), ...
        (1:numel(objectIds))', 'UniformOutput', false);
    h.objectTable.Data = table(objectIds, columns.voxels, columns.slices, string(zRange), ...
        'VariableNames', {'Index', 'Voxels', 'Slices', 'ZRange'});
else
    h.objectTable.Data = table(objectIds, columns.voxels, ...
        'VariableNames', {'Index', 'Pixels'});
end

obj.restoreTableSelection();
end

% =====================================================================
function [objectIds, columns] = iVolumeRows(obj)
% 3D mode: every object of the model, straight out of the cached index.
objectIds = [];
columns = struct('voxels', [], 'slices', [], 'zMin', [], 'zMax', []);

index = obj.mibModel.I{obj.mibModel.getActiveId()}.instanceIndex;
if isempty(index) || ~isstruct(index)
    % No index yet. Building one is a whole-volume pass, so it is not done
    % behind the user's back on every widget refresh - the status line asks.
    return;
end

objectIds = find(index.exists);
objectIds = objectIds(:);
columns.voxels = double(index.voxels(objectIds));
columns.slices = double(index.sliceCount(objectIds));
columns.zMin = double(index.bbox(objectIds, 5));
columns.zMax = double(index.bbox(objectIds, 6));
end

% =====================================================================
function [objectIds, columns] = iSliceRows(obj)
% 2D mode: the objects of the shown slice, measured from it. Note that this
% needs no index at all, so the list stays usable while the index is stale.
stats = obj.currentSliceStats();
objectIds = stats.objectIds;
columns = struct('voxels', stats.pixels);
obj.tableSlice = stats.slice;
end

% =====================================================================
function [objectIds, keptRows] = iApplyFilters(h, objectIds, columns, picked)
% Size filters, then the row cap. 0 means "off" for both filters, and the slice
% filter is skipped in 2D mode where a slice count is not a property of a row.
keptRows = (1:numel(objectIds))';

maxVoxels = h.filterMaxVoxels.Value;
if maxVoxels > 0
    keptRows = keptRows(columns.voxels(keptRows) <= maxVoxels);
end
if h.Mode3D.Value
    maxSlices = h.filterMaxSlices.Value;
    if maxSlices > 0
        keptRows = keptRows(columns.slices(keptRows) <= maxSlices);
    end
end

pickedRows = find(ismember(objectIds, picked));
keptRows = unique([keptRows; pickedRows], 'stable');

maxRows = h.MaxRows.Value;
if numel(keptRows) > maxRows
    keptRows = unique([pickedRows; keptRows(1:maxRows)], 'stable');
    keptRows = keptRows(1:min(numel(keptRows), max(maxRows, numel(pickedRows))));
end

objectIds = objectIds(keptRows);
end
