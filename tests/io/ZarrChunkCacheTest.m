classdef ZarrChunkCacheTest < matlab.unittest.TestCase
% ZARRCHUNKCACHETEST - Tests for io.zarr.ChunkCache.
%
% The cache stands between the loaders and the engine, so a bug here corrupts
% pixels rather than merely slowing things down - an off-by-one when splitting a
% fetched block into chunks, or when copying a chunk's overlap back out, would
% silently shift or mix image data. Every test therefore checks the **values**,
% not just the shape, against a synthetic array whose every element is a known
% function of its own coordinates.
%
% No store and no network: ``readFcn`` is a plain function over that synthetic
% array, which also makes it possible to count exactly how many engine calls a
% sequence of requests provokes, and how many elements each one asked for.

    properties (Access = private)
        ArrayShape = [40, 37, 53]
        % deliberately not a multiple of the chunk size, so every test crosses
        % the clipped chunks at the far edge
        ChunkShape = [16, 8, 10]
        SyntheticArray
        CallCount
        ElementsRead
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function buildArrayAndResetCache(testCase)
            % Values encode their own position, so a misplaced copy cannot pass.
            [gridA, gridB, gridC] = ndgrid(1:testCase.ArrayShape(1), ...
                1:testCase.ArrayShape(2), 1:testCase.ArrayShape(3));
            testCase.SyntheticArray = uint16(gridA * 10000 + gridB * 100 + gridC);

            testCase.CallCount    = 0;
            testCase.ElementsRead = 0;
            io.zarr.ChunkCache.clear();
            io.zarr.ChunkCache.setBudgetMB(64);
            testCase.addTeardown(@() io.zarr.ChunkCache.clear());
            testCase.addTeardown(@() io.zarr.ChunkCache.setBudgetMB(512));
        end
    end

    methods (Test, TestTags = {'Unit'})

        function servesEveryRegionExactlyAsTheEngineWould(testCase)
            % The property that matters: for any request, cached or not, the
            % cache returns byte-for-byte what a direct read would have.
            rng(17);
            for trial = 1:40
                bbox = testCase.randomBbox();
                expected = testCase.directRead(bbox);
                actual = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                    testCase.ArrayShape, @(b) testCase.countingRead(b));
                testCase.verifyEqual(actual, expected, ...
                    sprintf('mismatch for bbox %s', mat2str(bbox)));
            end
        end

        function aRepeatedRequestTouchesTheEngineOnce(testCase)
            bbox = [5 20; 3 15; 7 30];
            first = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(testCase.CallCount, 1);

            second = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(testCase.CallCount, 1, 'a full hit must not read again');
            testCase.verifyEqual(second, first);
        end

        function steppingOneSliceInsideACachedChunkIsFree(testCase)
            % The case this cache exists for. Chunks span 16 along dimension 1,
            % so slices 1..16 all live in the chunks fetched for slice 1.
            for sliceIdx = 1:testCase.ChunkShape(1)
                bbox = [sliceIdx, sliceIdx + 1; 1 20; 1 25];
                actual = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                    testCase.ArrayShape, @(b) testCase.countingRead(b));
                testCase.verifyEqual(actual, testCase.directRead(bbox), ...
                    sprintf('wrong pixels at slice %d', sliceIdx));
            end
            testCase.verifyEqual(testCase.CallCount, 1, ...
                'all 16 slices share one chunk block, so one fetch must serve them');
        end

        function panningRefetchesOnlyTheNewEdge(testCase)
            % Chunks are 8 wide on dimension 2. Shifting the window by 8 needs
            % exactly one new chunk column, and the fetch must be sized to that
            % column rather than to the whole new window.
            io.zarr.ChunkCache.read('store', [1 17; 1 25; 1 21], testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            firstFetchElements = testCase.ElementsRead;
            testCase.ElementsRead = 0;

            bbox = [1 17; 9 33; 1 21];
            actual = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));

            testCase.verifyEqual(actual, testCase.directRead(bbox));
            testCase.verifyEqual(testCase.CallCount, 2, 'one extra fetch, not one per chunk');
            testCase.verifyLessThan(testCase.ElementsRead, firstFetchElements / 2, ...
                'the second fetch must cover the new column only, not the whole window');
        end

        function clippedEdgeChunksSurviveARoundTrip(testCase)
            % The array is not a whole number of chunks, so the last chunk of
            % each dimension is short. Storing it padded would corrupt the
            % neighbouring request that reads across the boundary.
            bbox = [33, testCase.ArrayShape(1) + 1; ...
                    33, testCase.ArrayShape(2) + 1; ...
                    51, testCase.ArrayShape(3) + 1];
            actual = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(actual, testCase.directRead(bbox));

            % and again from cache
            cached = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(cached, testCase.directRead(bbox));
            testCase.verifyEqual(testCase.CallCount, 1);
        end

        function differentArraysDoNotShareChunks(testCase)
            bbox = [1 17; 1 9; 1 11];
            io.zarr.ChunkCache.read('storeA', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            io.zarr.ChunkCache.read('storeB', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(testCase.CallCount, 2, ...
                'the cache key must include the array, or pyramid levels would collide');
        end

        function budgetIsEnforcedAndZeroDisablesTheCache(testCase)
            io.zarr.ChunkCache.setBudgetMB(0);
            testCase.verifyFalse(io.zarr.ChunkCache.isEnabled());

            bbox = [1 17; 1 9; 1 11];
            actual = io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(actual, testCase.directRead(bbox), ...
                'a disabled cache must still return correct data');
            io.zarr.ChunkCache.read('store', bbox, testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(testCase.CallCount, 2, 'nothing may be retained at budget 0');

            % A budget far below one request's working set must not deadlock or
            % corrupt: it simply keeps evicting.
            io.zarr.ChunkCache.setBudgetMB(0.002);
            wide = [1 33; 1 33; 1 41];
            testCase.verifyEqual( ...
                io.zarr.ChunkCache.read('store', wide, testCase.ChunkShape, ...
                    testCase.ArrayShape, @(b) testCase.countingRead(b)), ...
                testCase.directRead(wide));
            info = io.zarr.ChunkCache.stats();
            testCase.verifyLessThanOrEqual(info.bytes, info.budgetBytes);
        end

        function statsAndClearReportWhatIsHeld(testCase)
            io.zarr.ChunkCache.read('store', [1 17; 1 9; 1 11], testCase.ChunkShape, ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            info = io.zarr.ChunkCache.stats();
            testCase.verifyGreaterThan(info.chunkCount, 0);
            testCase.verifyGreaterThan(info.bytes, 0);

            io.zarr.ChunkCache.clear();
            info = io.zarr.ChunkCache.stats();
            testCase.verifyEqual(info.chunkCount, 0);
            testCase.verifyEqual(info.bytes, 0);
        end

        function fallsBackWhenTheChunkShapeIsUnusable(testCase)
            % A store whose metadata did not report chunks must still be read,
            % uncached, rather than erroring.
            bbox = [1 17; 1 9; 1 11];
            actual = io.zarr.ChunkCache.read('store', bbox, [], ...
                testCase.ArrayShape, @(b) testCase.countingRead(b));
            testCase.verifyEqual(actual, testCase.directRead(bbox));
            testCase.verifyEqual(testCase.CallCount, 1);
        end
    end

    methods (Access = private)
        function block = directRead(testCase, bbox)
            % DIRECTREAD - Ground truth, straight out of the synthetic array.
            ranges = arrayfun(@(dimIdx) bbox(dimIdx, 1):(bbox(dimIdx, 2) - 1), ...
                1:size(bbox, 1), 'UniformOutput', false);
            block = testCase.SyntheticArray(ranges{:});
        end

        function block = countingRead(testCase, bbox)
            % COUNTINGREAD - directRead, plus the bookkeeping the tests assert on.
            testCase.CallCount = testCase.CallCount + 1;
            block = testCase.directRead(bbox);
            testCase.ElementsRead = testCase.ElementsRead + numel(block);
        end

        function bbox = randomBbox(testCase)
            % RANDOMBBOX - A random in-bounds region, in [start, end+1) form.
            nDims = numel(testCase.ArrayShape);
            bbox = zeros(nDims, 2);
            for dimIdx = 1:nDims
                extent = testCase.ArrayShape(dimIdx);
                startIdx = randi(extent);
                endIdx   = randi([startIdx, extent]);
                bbox(dimIdx, :) = [startIdx, endIdx + 1];
            end
        end
    end
end
