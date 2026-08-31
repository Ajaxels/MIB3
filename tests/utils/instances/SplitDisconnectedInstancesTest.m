classdef SplitDisconnectedInstancesTest < matlab.unittest.TestCase
    % SPLITDISCONNECTEDINSTANCESTEST - one index per connected object.
    %
    % utils.instances.splitDisconnected repairs instance label arrays in which one index was
    % painted over two spatially separate objects, which tiled SOLOv2 prediction produces
    % whenever a detection mask spans two neighbours.

    methods (TestClassSetup)
        function addMibToPath(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})
        function sharedIndexIsSplitInTwo(testCase)
            labelMap = zeros(40, 40, 'uint16');
            labelMap(5:15, 5:15) = 7;       % two separate blobs...
            labelMap(25:35, 25:35) = 7;     % ...sharing index 7
            labelMap(5:15, 25:35) = 3;

            [splitMap, stats] = utils.instances.splitDisconnected(labelMap);

            testCase.verifyEqual(numel(unique(splitMap(splitMap > 0))), 3);
            testCase.verifyEqual(stats.numObjectsBefore, 2);
            testCase.verifyEqual(stats.numObjectsAfter, 3);
            testCase.verifyEqual(stats.numSplitLabels, 1);
            testCase.verifyEqual(stats.numExtraObjects, 1);
            testCase.verifyEqual(splitMap > 0, labelMap > 0, 'no pixel may change object');
            testCase.verifyNotEqual(splitMap(10, 10), splitMap(30, 30));
        end

        function connectedIndexIsUntouched(testCase)
            labelMap = zeros(30, 30, 'uint16');
            labelMap(5:20, 5:20) = 4;
            labelMap(22:25, 22:25) = 9;

            [splitMap, stats] = utils.instances.splitDisconnected(labelMap);

            testCase.verifyEqual(stats.numSplitLabels, 0);
            testCase.verifyEqual(stats.numObjectsAfter, 2);
            % the values are renumbered to 1..N, the partition is not changed
            testCase.verifyEqual(splitMap == splitMap(10, 10), labelMap == 4);
            testCase.verifyEqual(splitMap == splitMap(23, 23), labelMap == 9);
            testCase.verifyEqual(double(max(splitMap(:))), 2);
        end

        function minObjectPixelsDropsSpeckle(testCase)
            labelMap = zeros(40, 40, 'uint16');
            labelMap(5:20, 5:20) = 1;       % 256 px
            labelMap(35:36, 35:37) = 1;     % 6 px satellite

            [kept, keptStats] = utils.instances.splitDisconnected(labelMap);
            testCase.verifyEqual(keptStats.numObjectsAfter, 2);
            testCase.verifyEqual(nnz(kept), nnz(labelMap));

            [dropped, droppedStats] = utils.instances.splitDisconnected(labelMap, ...
                struct('minObjectPixels', 100));
            testCase.verifyEqual(droppedStats.numObjectsAfter, 1);
            testCase.verifyEqual(droppedStats.numDroppedComponents, 1);
            testCase.verifyEqual(droppedStats.numDroppedPixels, 6);
            bigBlob = false(size(labelMap));
            bigBlob(5:20, 5:20) = true;
            testCase.verifyEqual(dropped > 0, bigBlob, 'only the speckle may be removed');
        end

        function perSliceNumberingRestartsOnEachSlice(testCase)
            labelVol = zeros(20, 20, 3, 'uint16');
            labelVol(2:6, 2:6, 1) = 1;
            labelVol(2:6, 12:16, 1) = 2;
            labelVol(2:6, 2:6, 2) = 1;
            labelVol(12:16, 2:6, 3) = 1;
            labelVol(12:16, 12:16, 3) = 1;      % shares index 1 with the blob above

            [splitVol, stats] = utils.instances.splitDisconnected(labelVol, ...
                struct('perSliceNumbering', true));

            testCase.verifyEqual(double(unique(splitVol(:, :, 1))'), [0 1 2]);
            testCase.verifyEqual(double(unique(splitVol(:, :, 2))'), [0 1]);
            testCase.verifyEqual(double(unique(splitVol(:, :, 3))'), [0 1 2], ...
                'the shared index must become two objects on slice 3');
            testCase.verifyEqual(stats.numObjectsAfter, 5);
            testCase.verifyEqual(stats.numSplitLabels, 1);
        end

        function globalNumberingIsContiguousAcrossSlices(testCase)
            labelVol = zeros(20, 20, 2, 'uint16');
            labelVol(2:6, 2:6, 1) = 1;
            labelVol(2:6, 2:6, 2) = 1;

            splitVol = utils.instances.splitDisconnected(labelVol);

            % connectivity 8 works per slice, so the two slices are separate objects
            testCase.verifyEqual(double(unique(splitVol(splitVol > 0))'), [1 2]);
        end

        function connectivity26LinksAcrossSlices(testCase)
            labelVol = zeros(20, 20, 3, 'uint16');
            labelVol(2:6, 2:6, 1:2) = 5;        % one 3D object over two slices
            labelVol(12:16, 12:16, 3) = 5;      % a separate object sharing the index

            [splitVol, stats] = utils.instances.splitDisconnected(labelVol, ...
                struct('connectivity', 26));

            testCase.verifyEqual(stats.numObjectsBefore, 1);
            testCase.verifyEqual(stats.numObjectsAfter, 2);
            testCase.verifyEqual(splitVol(3, 3, 1), splitVol(3, 3, 2), ...
                'slices of one 3D object must keep one index');
            testCase.verifyNotEqual(splitVol(3, 3, 1), splitVol(14, 14, 3));
        end

        function emptyArrayIsHandled(testCase)
            labelMap = zeros(10, 10, 'uint16');
            [splitMap, stats] = utils.instances.splitDisconnected(labelMap);
            testCase.verifyEqual(splitMap, zeros(10, 10, 'uint16'));
            testCase.verifyEqual(stats.numObjectsAfter, 0);
        end

        function classIsDemotedToUint16WhenPossible(testCase)
            labelMap = zeros(20, 20, 'uint32');
            labelMap(2:6, 2:6) = 70000;         % index above the uint16 range
            splitMap = utils.instances.splitDisconnected(labelMap);
            testCase.verifyClass(splitMap, 'uint16', ...
                'a single object must be renumbered to 1 and fit in uint16');
            testCase.verifyEqual(double(max(splitMap(:))), 1);
        end
    end
end
