classdef SegmentImageInstancesIoUMergeTest < matlab.unittest.TestCase
    % SEGMENTIMAGEINSTANCESIOUMERGETEST - cross-tile stitching of 2D instance detections.
    %
    % Exercises deepmib.segmentImageInstancesIoUMerge through its injectable
    % options.segmentFcn hook, so no trained SOLOv2 network is needed. The synthetic
    % detector reads object indices straight out of the tile image (red channel), which
    % makes every tile's detections exactly reproducible and lets each test bend one rule
    % of the detector to model a specific real-world failure.

    properties (Constant)
        ImageHeight = 200
        ImageWidth = 300
        CoreSize = [100 100]
        BorderSize = [40 40]
        % with the sizes above the tile extents are
        %   rows 1-140 / 61-200,  cols 1-140 / 61-240 / 161-300
        % so neighbouring tiles share an 80 px band
    end

    methods (TestClassSetup)
        function addMibToPath(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})
        function faithfulDetectionsReconstructObjects(testCase)
            % the ordinary case: every tile reports exactly what it sees, including an
            % object far wider than the 80 px overlap band
            objects = testCase.objectRectangles();
            idMap = testCase.buildIdMap(objects);
            labelMap = testCase.runMerge(idMap, @(tile) localFaithfulDetector(tile));

            testCase.verifyEveryLabelConnected(labelMap);
            testCase.verifyPartitionMatches(labelMap, idMap, ...
                'faithful per-tile detections must reproduce the object partition');
        end

        function spanningDetectionDoesNotShareOneIndex(testCase)
            % SOLOv2 sometimes returns one detection covering two separate objects; that
            % detection must not make the two objects share an instance index
            objects = testCase.objectRectangles();
            idMap = testCase.buildIdMap(objects);
            labelMap = testCase.runMerge(idMap, @(tile) localSpanningDetector(tile));

            testCase.verifyEveryLabelConnected(labelMap);
            testCase.verifyPartitionMatches(labelMap, idMap, ...
                'a detection spanning two objects must still yield two indices');
        end

        function truncatedFragmentIsMergedAcrossTheSeam(testCase)
            % a fragment cut by a tile edge is linked to the neighbour's complete mask
            % through the IoA criterion even when their in-band IoU is low (here 0.37);
            % without that link the bar below is painted as two objects
            idMap = zeros(testCase.ImageHeight, testCase.ImageWidth, 'uint8');
            idMap(100:140, 30:260) = 5;     % bar crossing all three tile columns
            idMap(62:65, 5:8) = 6;          % marker seen by both left-hand tiles only
            labelMap = testCase.runMerge(idMap, @(tile) localShrinkingDetector(tile));

            testCase.verifyEveryLabelConnected(labelMap);
            testCase.verifyNumElements(unique(labelMap(labelMap > 0)), 1, ...
                'the bar must come out as a single object');
            % the left tiles under-segment, so the left end of the bar is only covered by
            % their shortened masks; everything the other tiles saw must carry that index
            testCase.verifyTrue(all(labelMap(idMap == 5 & (1:testCase.ImageWidth) >= 61), 'all'), ...
                'the part of the bar seen in full must belong to the merged object');
            testCase.verifyEqual(nnz(labelMap(:, 30:60)), 15*31, ...
                'the truncated left end must be merged in, not painted separately');
        end

        function smallComponentsAreDroppedAsSpeckle(testCase)
            % a detection carrying a 20 px satellite blob: the blob is speckle at the
            % default minSplitArea and its own object when the threshold is switched off
            idMap = zeros(testCase.ImageHeight, testCase.ImageWidth, 'uint8');
            idMap(20:60, 20:60) = 1;
            idMap(150:153, 150:154) = 1;    % 20 px, same index, far away

            labelMap = testCase.runMerge(idMap, @(tile) localFaithfulDetector(tile));
            testCase.verifyNumElements(unique(labelMap(labelMap > 0)), 1, ...
                'the 20 px satellite must be dropped at the default minSplitArea');
            testCase.verifyEqual(nnz(labelMap), nnz(idMap(20:60, 20:60)), ...
                'only the speckle pixels may be removed');

            labelMap = testCase.runMerge(idMap, @(tile) localFaithfulDetector(tile), ...
                struct('minSplitArea', 0));
            testCase.verifyNumElements(unique(labelMap(labelMap > 0)), 2, ...
                'with minSplitArea 0 every component keeps its own index');
        end

        function emptyImageReturnsEmptyLabelMap(testCase)
            idMap = zeros(testCase.ImageHeight, testCase.ImageWidth, 'uint8');
            labelMap = testCase.runMerge(idMap, @(tile) localFaithfulDetector(tile));
            testCase.verifyEqual(labelMap, zeros(testCase.ImageHeight, testCase.ImageWidth, 'uint32'));
        end

        function noOverlapBandStillSegments(testCase)
            % borderSize 0 leaves no shared band, so nothing can be linked; every object
            % that fits inside one tile must still be found exactly once
            idMap = zeros(testCase.ImageHeight, testCase.ImageWidth, 'uint8');
            idMap(20:60, 20:60) = 1;
            idMap(120:160, 210:260) = 2;
            labelMap = testCase.runMerge(idMap, @(tile) localFaithfulDetector(tile), ...
                struct('borderSize', [0 0]));

            testCase.verifyEveryLabelConnected(labelMap);
            testCase.verifyPartitionMatches(labelMap, idMap, ...
                'objects inside a single tile need no stitching');
        end
    end

    methods (Access = private)
        function objects = objectRectangles(~)
            % [rowStart rowEnd colStart colEnd] per object index
            objects = [ 20  50  20  60; ...   % 1: inside the top-left tile
                        20  50  90 110; ...   % 2: inside the first overlap band
                       100 160  30 260; ...   % 3: wider than the band, crosses all tiles
                        20  40 250 280];      % 4: inside the right-hand tile
        end

        function idMap = buildIdMap(testCase, objects)
            idMap = zeros(testCase.ImageHeight, testCase.ImageWidth, 'uint8');
            for objectId = 1:size(objects, 1)
                rect = objects(objectId, :);
                idMap(rect(1):rect(2), rect(3):rect(4)) = objectId;
            end
        end

        function labelMap = runMerge(testCase, idMap, segmentFcn, overrides)
            img = repmat(idMap, [1 1 3]);
            options.coreSize = testCase.CoreSize;
            options.borderSize = testCase.BorderSize;
            options.threshold = 0.5;                % unused, segmentFcn overrides
            options.executionEnvironment = 'cpu';   % unused, segmentFcn overrides
            options.segmentFcn = segmentFcn;
            if nargin > 3
                fields = fieldnames(overrides);
                for fieldId = 1:numel(fields)
                    options.(fields{fieldId}) = overrides.(fields{fieldId});
                end
            end
            labelMap = deepmib.segmentImageInstancesIoUMerge(img, [], options);
        end

        function verifyEveryLabelConnected(testCase, labelMap)
            labelIds = unique(labelMap(labelMap > 0));
            for labelIndex = 1:numel(labelIds)
                components = bwconncomp(labelMap == labelIds(labelIndex), 8);
                testCase.verifyEqual(components.NumObjects, 1, ...
                    sprintf('index %d covers %d separate objects', ...
                    labelIds(labelIndex), components.NumObjects));
            end
        end

        function verifyPartitionMatches(testCase, labelMap, idMap, message)
            % the label map must partition the foreground exactly as idMap does, up to a
            % renumbering of the indices
            expectedIds = unique(idMap(idMap > 0));
            actualIds = unique(labelMap(labelMap > 0));
            testCase.verifyNumElements(actualIds, numel(expectedIds), message);
            for expectedIndex = 1:numel(expectedIds)
                expectedMask = idMap == expectedIds(expectedIndex);
                actualId = mode(double(labelMap(expectedMask)));
                testCase.verifyEqual(labelMap == actualId, expectedMask, message);
            end
        end
    end
end

% =====================================================================
function [masks, labels, scores] = localFaithfulDetector(tileImg)
% one detection per object index visible in the tile, masks exactly as drawn
[masks, objectIds] = localMasksPerIndex(tileImg);
labels = categorical(repmat("object", numel(objectIds), 1));
scores = 0.9*ones(numel(objectIds), 1);
end

% =====================================================================
function [masks, labels, scores] = localSpanningDetector(tileImg)
% objects 1 and 2 are returned as a single detection wherever both are visible, which is
% what an over-confident SOLOv2 mask looks like; its score beats the individual ones so it
% wins the painting conflicts as well
[masks, objectIds] = localMasksPerIndex(tileImg);
scores = 0.9*ones(numel(objectIds), 1);
first = find(objectIds == 1, 1);
second = find(objectIds == 2, 1);
if ~isempty(first) && ~isempty(second)
    masks(:, :, first) = masks(:, :, first) | masks(:, :, second);
    masks(:, :, second) = [];
    objectIds(second) = [];
    scores(second) = [];
    scores(first) = 0.99;
end
labels = categorical(repmat("object", numel(objectIds), 1));
end

% =====================================================================
function [masks, labels, scores] = localShrinkingDetector(tileImg)
% tiles that also see the marker (index 6) under-segment object 5 to its top 15 rows,
% modelling a network that returns different masks for the same object in different tiles;
% the marker itself is not reported as an object
[masks, objectIds] = localMasksPerIndex(tileImg);
if any(objectIds == 6)
    target = find(objectIds == 5, 1);
    if ~isempty(target)
        mask = masks(:, :, target);
        firstRow = find(any(mask, 2), 1, 'first');
        mask(firstRow+15:end, :) = false;
        masks(:, :, target) = mask;
    end
    drop = objectIds == 6;
    masks(:, :, drop) = [];
    objectIds(drop) = [];
end
labels = categorical(repmat("object", numel(objectIds), 1));
scores = 0.9*ones(numel(objectIds), 1);
end

% =====================================================================
function [masks, objectIds] = localMasksPerIndex(tileImg)
indexPlane = tileImg(:, :, 1);
objectIds = unique(indexPlane);
objectIds(objectIds == 0) = [];
masks = false(size(indexPlane, 1), size(indexPlane, 2), numel(objectIds));
for objectIndex = 1:numel(objectIds)
    masks(:, :, objectIndex) = indexPlane == objectIds(objectIndex);
end
end
