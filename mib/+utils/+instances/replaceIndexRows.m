function index = replaceIndexRows(index, objectIds, rows)
% REPLACEINDEXROWS - Replace the rows of some objects in a sparse instance index.
%
% Syntax:
%   .. code-block:: matlab
%
%       index = utils.instances.replaceIndexRows(index, objectIds, rows)
%
% The instance index (``utils.instances.objectIndex``) holds one row per object
% that has voxels, sorted by index. After an edit the rows of the re-measured
% objects are replaced as a whole: every row of ``objectIds`` is taken out and
% the rows in ``rows`` are put in, so an object that lost all of its voxels
% comes back absent simply by having no row in ``rows``. The result is sorted
% again and ``.maxIndex`` and ``.numObjects`` follow the rows. Fields of
% ``index`` this function does not know (for example ``.timePoint`` and
% ``.stale`` of ``core.MibDataset.buildInstanceIndex``) are kept untouched.
%
% Input Arguments:
%   - **index** - sparse index struct with ``.ids`` [n x 1] double, ``.voxels``
%     [n x 1] uint32, ``.bbox`` [n x 6] int32, ``.centroid`` [n x 3] single,
%     ``.sliceCount`` [n x 1] uint32
%   - **objectIds** - indices whose rows are replaced; ids without a row in
%     ``index`` are allowed
%   - **rows** - struct with the same five fields for the objects that have
%     voxels now, in any order. Its ids are removed from ``index`` first too,
%     so listing an id there and not in ``objectIds`` cannot duplicate a row.
%     Values are cast to the classes of the index
%
% Output Arguments:
%   - **index** - the updated index, rows sorted by ``.ids``;
%     ``.maxIndex = max(.ids)`` (0 when empty), ``.numObjects = numel(.ids)``
%
% Usage:
%   **Example** - object 7 lost all its voxels, object 12 has a new box
%
%   .. code-block:: matlab
%
%      rows = struct('ids', 12, 'voxels', 420, 'bbox', [10 30 5 25 1 4], ...
%          'centroid', [15 20 2.5], 'sliceCount', 4);
%      index = utils.instances.replaceIndexRows(index, [7 12], rows);
%
% See also: utils.instances.objectIndex, core.MibDataset.buildInstanceIndex

% Updates
%

newIds = double(rows.ids(:));
keep = ~ismember(index.ids, [double(objectIds(:)); newIds]);

ids = [index.ids(keep); newIds];
voxels = [index.voxels(keep); uint32(rows.voxels(:))];
bbox = [index.bbox(keep, :); int32(reshape(rows.bbox, [], 6))];
centroid = [index.centroid(keep, :); single(reshape(rows.centroid, [], 3))];
sliceCount = [index.sliceCount(keep); uint32(rows.sliceCount(:))];

[index.ids, order] = sort(ids);
index.voxels = voxels(order);
index.bbox = bbox(order, :);
index.centroid = centroid(order, :);
index.sliceCount = sliceCount(order);
index.numObjects = numel(index.ids);
if isempty(index.ids)
    index.maxIndex = 0;
else
    index.maxIndex = index.ids(end);
end
end
