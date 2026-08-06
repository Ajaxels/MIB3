function metrics = instanceStitchMetrics(stitched, groundTruth)
% INSTANCESTITCHMETRICS - False-merge / false-split counts of a stitched 3D
% instance volume against a ground-truth 3D instance volume.
%
% Both inputs are [H x W x Z] integer label volumes (0 = background). Object ID
% *values* are irrelevant on either side; correspondence is established purely
% from voxel overlap, so the two volumes may use completely different numbering.
%
% Definitions (based on the object-overlap contingency table):
%   - **false merge** - one *output* (stitched) label whose voxels overlap two
%     or more distinct GT objects. The stitcher fused things that should be
%     separate.
%   - **false split** - one *GT* object whose voxels are covered by two or more
%     distinct output labels. The stitcher broke one object into pieces.
%
% A GT object and an output label are only considered "linked" when their
% intersection is at least ``options.minOverlapVoxels`` voxels (default 1), so
% a handful of boundary voxels shared between neighbours does not register as a
% spurious merge/split.
%
% Syntax:
%   .. code-block:: matlab
%
%       m = mibtest.helpers.instanceStitchMetrics(stitched, groundTruth)
%
% Output Arguments:
%   - **metrics** - struct with fields:
%
%     - ``.numFalseMerge``   - number of output labels covering >=2 GT objects
%     - ``.numFalseSplit``   - number of GT objects covered by >=2 output labels
%     - ``.numGtObjects``    - number of distinct nonzero GT objects
%     - ``.numOutObjects``   - number of distinct nonzero output labels
%     - ``.numOneToOne``     - GT objects with exactly one matching output label
%       that in turn matches only that GT object (clean reconstructions)
%     - ``.linkTable``       - sparse [numGt x numOut] intersection-voxel counts
%
% Notes:
%   - Pure, headless, no MIB dependencies - safe to call from Unit tests.

minOverlapVoxels = 1;

% Convert only the foreground voxels to double (whole-volume double() on a
% multi-GB label stack blows up memory).
fg = stitched > 0 & groundTruth > 0;
gtVals  = double(groundTruth(fg));
outVals = double(stitched(fg));

% Compact GT and output IDs to contiguous 1..K so we can index a table.
[gtUnique,  ~, gtIdx]  = unique(gtVals);
[outUnique, ~, outIdx] = unique(outVals);
numGt  = numel(gtUnique);
numOut = numel(outUnique);

metrics = struct('numFalseMerge', 0, 'numFalseSplit', 0, ...
    'numGtObjects', numel(unique(groundTruth(groundTruth > 0))), ...
    'numOutObjects', numel(unique(stitched(stitched > 0))), ...
    'numOneToOne', 0, 'linkTable', sparse(0, 0));

if numGt == 0 || numOut == 0
    return;
end

% Intersection-voxel contingency table: rows = GT objects, cols = output labels.
linkTable = accumarray([gtIdx, outIdx], 1, [numGt, numOut]);
linkTable(linkTable < minOverlapVoxels) = 0;

linksPerOutput = sum(linkTable > 0, 1);   % how many GT objects each output touches
linksPerGt     = sum(linkTable > 0, 2);   % how many outputs each GT object touches

metrics.numFalseMerge = nnz(linksPerOutput >= 2);
metrics.numFalseSplit = nnz(linksPerGt >= 2);

% Clean one-to-one: GT object links to exactly one output, and that output
% links back to exactly one GT object.
oneToOne = false(numGt, 1);
for g = 1:numGt
    outCols = find(linkTable(g, :) > 0);
    if isscalar(outCols) && linksPerOutput(outCols) == 1
        oneToOne(g) = true;
    end
end
metrics.numOneToOne = nnz(oneToOne);
metrics.linkTable   = sparse(linkTable);
end
