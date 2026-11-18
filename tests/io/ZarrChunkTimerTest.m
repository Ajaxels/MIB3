classdef ZarrChunkTimerTest < matlab.unittest.TestCase
% ZARRCHUNKTIMERTEST - The headless engine of the Zarr chunk timing window of Image converter.
%
% Covers the candidate lists, the test geometry, the test volume, the file count
% of a pyramid, the scoring model, one real timing of a small store, reading a
% sample from TIFF slices and ImageConverter.applyZarrChunks. The window itself
% needs a display and is not opened.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            here = fileparts(mfilename('fullpath'));            % tests/io
            repoRoot = fileparts(fileparts(here));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repoRoot, 'mib', 'plugins', 'FileProcessing', 'ImageConverter')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repoRoot, 'mib', 'external', 'zarr-matlab')));
        end
    end

    methods (Test, TestTags = {'Unit'})
        function defaultCandidates_clippedAndWithoutShardsForV2(testCase)
            candidates = ZarrChunkTimer.defaultCandidates(34, [300 5000 40], 3);
            testCase.verifyLessThanOrEqual(max(candidates(:, 1)), 300);
            testCase.verifyLessThanOrEqual(max(candidates(:, 3)), 40);
            % a shard never asks for more slices than the dataset has
            testCase.verifyTrue(all(candidates(:, 3) .* candidates(:, 6) <= 40 | candidates(:, 6) == 1));
            testCase.verifyEqual(size(unique(candidates, 'rows'), 1), size(candidates, 1), 'duplicates left');

            candidatesV2 = ZarrChunkTimer.defaultCandidates(100, [4096 4096 1000], 2);
            testCase.verifyTrue(all(candidatesV2(:, 4:6) == 1, 'all'), 'v2 has no sharding');
            candidates2D = ZarrChunkTimer.defaultCandidates(100, [4096 4096 1000], 3);
            testCase.verifyLessThanOrEqual(max(candidates2D(:, 3)), 16, '2D list: thin chunks');
        end

        function testGeometry_viewInsideWithMargin(testCase)
            geometry = ZarrChunkTimer.testGeometry([3000 4000 1000], [900 1600], 1);
            testCase.verifyEqual(geometry.testSize(1:2), [900 1600] + 2 * ZarrChunkTimer.ViewMargin);
            testCase.verifyEqual(geometry.testSize(3), ZarrChunkTimer.MaxTestDepth);
            testCase.verifyEqual(geometry.rows, ZarrChunkTimer.ViewMargin + [1 900]);
            testCase.verifyTrue(geometry.hasSideViews);

            % a small dataset: the view is the dataset, no side views for 8 slices
            small = ZarrChunkTimer.testGeometry([200 300 8], [900 1600], 2);
            testCase.verifyEqual(small.testSize, [200 300 8]);
            testCase.verifyEqual(small.rows, [1 200]);
            testCase.verifyFalse(small.hasSideViews);

            % a large uint16 view: fewer slices, never below 64
            large = ZarrChunkTimer.testGeometry([20000 20000 1000], [4000 8000], 2);
            testCase.verifyEqual(large.testSize(3), 64);
        end

        function buildTestVolume_keepsZerosAndLabels(testCase)
            planes = uint8(repmat([0 10; 20 30], 1, 1, 2));
            volume = ZarrChunkTimer.buildTestVolume(planes, [2 2 8], false);
            testCase.verifySize(volume, [2 2 8]);
            % zeros stay zeros where the (flipped) sample is zero, other voxels differ by the lowest bit only
            for z = 1:8
                plane = planes(:, :, mod(z - 1, 2) + 1);
                switch mod(floor((z - 1) / 2), 4)
                    case 1; plane = fliplr(plane);
                    case 2; plane = flipud(plane);
                    case 3; plane = rot90(plane, 2);
                end
                testCase.verifyEqual(volume(:, :, z) == 0, plane == 0);
                testCase.verifyEqual(bitshift(volume(:, :, z), -1), bitshift(plane, -1));
            end
            labels = ZarrChunkTimer.buildTestVolume(planes, [2 2 2], true);
            testCase.verifyEqual(labels, planes, 'labels are stacked unchanged');
        end

        function datasetFiles_countsAllLevelsAndShards(testCase)
            settings = ZarrChunkTimerTest.settingsFor([1024 1024 64]);
            % two levels (1024, 512); chunks of 256 x 256 x 16: 4*4*4 + 2*2*4
            testCase.verifyEqual(ZarrChunkTimer.datasetFiles([256 256 16], [1 1 1], settings), 80);
            % shards of 4 x 4 x 1 chunks, clamped to the 512 level: 1*1*4 + 1*1*4
            [files, level0Voxels] = ZarrChunkTimer.datasetFiles([256 256 16], [4 4 1], settings);
            testCase.verifyEqual(files, 8);
            testCase.verifyEqual(level0Voxels, 1024 * 1024 * 16);
            % three channels, one per chunk: three times the files
            settings.channels = 3;
            testCase.verifyEqual(ZarrChunkTimer.datasetFiles([256 256 16], [1 1 1], settings), 240);
        end

        function rankCandidates_scrollModelAndFilesWeight(testCase)
            settings = ZarrChunkTimerTest.settingsFor([1024 1024 64]);
            candidates = [256 256 16 1 1 1; 256 256 16 4 4 1];
            timing = struct('writeSeconds', 1, 'rawBytes', 1e6, 'storeBytes', 5e5, ...
                'first', [0.16 0.32 0.32], 'warm', [0.01 0.01 0.01], 'viewChunkBytes', [1 1 1]);
            slower = timing;
            slower.first = 2 * timing.first;
            timings = [timing, slower];
            ranking = ZarrChunkTimer.rankCandidates(candidates, timings, settings, 100, 0, 1e9);
            % scroll in XY: 0.01 + (0.16 - 0.01) / 16
            testCase.verifyEqual(ranking.scroll(1, 1), 0.01 + 0.15 / 16, 'AbsTol', 1e-12);
            testCase.verifyEqual(ranking.order(1), 1, 'faster wins without the files weight');
            testCase.verifyEqual(ranking.score(1), 1);
            % chunks of a view that do not fit in the cache are read again for every slice
            noCache = ZarrChunkTimer.rankCandidates(candidates, timings, settings, 100, 0, 0);
            testCase.verifyEqual(noCache.scroll(1, 1), 0.16, 'AbsTol', 1e-12);
            % 80 against 8 files: weight 1 makes the sharded candidate the best
            withFiles = ZarrChunkTimer.rankCandidates(candidates, timings, settings, 100, 1, 1e9);
            testCase.verifyEqual(withFiles.files, [80; 8]);
            testCase.verifyEqual(withFiles.order(1), 2);
            testCase.verifyEqual(withFiles.fileMB(1), 256 * 256 * 16 / 2 / 1e6, 'AbsTol', 1e-9);
        end

        function timeCandidate_timesAllViewsAndRemovesTheStore(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            geometry = ZarrChunkTimer.testGeometry([300 400 40], [100 150], 1);
            planes = ZarrChunkTimer.syntheticPlanes(geometry.testSize(1:2), 4, 'uint8', false);
            volume = ZarrChunkTimer.buildTestVolume(planes, geometry.testSize, false);
            for zarrFormat = [3 2]
                storePath = fullfile(folder.Folder, sprintf('store.zarr%d', zarrFormat));
                shardFactors = [2 2 1];
                if zarrFormat == 2; shardFactors = [1 1 1]; end
                timing = ZarrChunkTimer.timeCandidate(volume, [64 64 8 shardFactors], storePath, geometry, 'zstd', zarrFormat);
                testCase.verifyGreaterThan(timing.writeSeconds, 0);
                testCase.verifyEqual(timing.rawBytes, numel(volume));
                testCase.verifyGreaterThan(timing.storeBytes, 0);
                testCase.verifyTrue(all(timing.first > 0) && all(timing.warm > 0), 'all three views timed');
                % the XY view touches the chunks over its rows and columns, one chunk deep
                chunkShape = [64; 64; 8];
                ranges = [geometry.rows; geometry.cols; geometry.zView geometry.zView];
                expectedChunks = prod(floor((ranges(:, 2) - 1) ./ chunkShape) - floor((ranges(:, 1) - 1) ./ chunkShape) + 1);
                testCase.verifyEqual(timing.viewChunkBytes(1), expectedChunks * 64 * 64 * 8);
                testCase.verifyFalse(isfolder(storePath), 'the test store is deleted');
            end
        end

        function readSamplePlanes_cropsTheCentreOfEvenlySpreadSlices(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            stack = reshape(uint8(mod(0:64*80*10-1, 251)), [64 80 10]);
            for z = 1:10
                imwrite(stack(:, :, z), fullfile(folder.Folder, sprintf('s_%02d.tif', z)));
            end
            provider = io.savers.ImageDatastoreSliceProvider(imageDatastore(folder.Folder, 'FileExtensions', '.tif'));
            [planes, cancelled] = ZarrChunkTimer.readSamplePlanes(provider, [32 40], 4, []);
            testCase.verifyFalse(cancelled);
            sliceList = unique(round(linspace(1, 10, 4)));
            testCase.verifyEqual(planes, stack(17:48, 21:60, sliceList));
        end

        function gridCandidates_limitsAndShardOptions(testCase)
            settings = ZarrChunkTimerTest.settingsFor([10936 13424 1974]);
            settings.zarrFormat = 3;
            settings.numWorkers = 6;
            geometry = ZarrChunkTimer.testGeometry(settings.datasetSize, [1100 1800], 1);
            [candidates, grid] = ZarrChunkTimer.gridCandidates(settings, geometry, 512 * 2^20, 128e9);
            testCase.verifySize(grid.candidateIndex, [numel(ZarrChunkTimer.GridZ), numel(ZarrChunkTimer.GridXY), 3]);
            testCase.verifyEqual(sort(nonzeros(grid.candidateIndex))', 1:size(candidates, 1), 'every candidate once');
            testCase.verifyEqual(size(unique(candidates, 'rows'), 1), size(candidates, 1), 'duplicates left');
            chunkBytes = prod(candidates(:, 1:3), 2);
            testCase.verifyTrue(all(chunkBytes >= ZarrChunkTimer.MinChunkBytes & chunkBytes <= ZarrChunkTimer.MaxChunkBytes));
            % 6 processes on 128 GB with slices of 10936 x 13424 uint8: (0.8 * 128e9 / 6 / slice - 2) / 2.5
            sliceBytes = 10936 * 13424;
            testCase.verifyEqual(grid.maxDepth, (0.8 * 128e9 / 6 / sliceBytes - 2) / 2.5, 'RelTol', 1e-12);
            testCase.verifyLessThanOrEqual(max(candidates(:, 3)), grid.maxDepth);
            testCase.verifyEqual(grid.reason(ZarrChunkTimer.GridZ == 64, ZarrChunkTimer.GridXY == 256, 1), 4, ...
                'too deep for the memory');
            testCase.verifyEqual(grid.reason(:, 1, 1), 2 * ones(numel(ZarrChunkTimer.GridZ), 1), 'X = Y of 16 is always small');
            % shards are one chunk deep and grow with the target
            sharded = candidates(candidates(:, 4) > 1, :);
            testCase.verifyTrue(all(sharded(:, 6) == 1) && all(sharded(:, 4) == sharded(:, 5)));
            k = grid.candidateIndex(ZarrChunkTimer.GridZ == 8, ZarrChunkTimer.GridXY == 128, :);
            % 128 x 128 x 8 = 128 KB: 64 MB is 512 chunks, f = 2^round(4.5) = 32; 512 MB, f = 2^round(6) = 64
            testCase.verifyEqual(candidates(k(:), 4)', [1 32 64]);

            % Zarr v2: no shard options; a small dataset: sizes beyond it are left out
            settings.zarrFormat = 2;
            settings.datasetSize = [300 400 20];
            geometry = ZarrChunkTimer.testGeometry(settings.datasetSize, [1100 1800], 1);
            [candidates, grid] = ZarrChunkTimer.gridCandidates(settings, geometry, 512 * 2^20, 0);
            testCase.verifyEqual(size(grid.candidateIndex, 3), 1);
            testCase.verifyTrue(all(candidates(:, 4:6) == 1, 'all'));
            testCase.verifyEqual(grid.maxDepth, Inf, 'unknown memory: no memory limit');
            testCase.verifyEqual(grid.reason(ZarrChunkTimer.GridZ == 64, ZarrChunkTimer.GridXY == 256), 1, ...
                'Z of 64 for 20 slices');
            testCase.verifyLessThanOrEqual(max(candidates(:, 1)), 300);
        end

        function suggestFromGrid_prefersAGoodNeighbourhood(testCase)
            % one shard option, a 3 x 3 grid: the lowest score sits alone among bad neighbours
            grid.candidateIndex = reshape(1:9, 3, 3);
            score = [3 3 3 3 1 3 3 3 3]';
            score(9) = 1.1;   % a corner in a good neighbourhood
            score([6 8]) = 1.2;
            [suggested, ownScore, neighbourScore] = ZarrChunkTimer.suggestFromGrid(grid, score);
            testCase.verifyEqual(suggested, 9);
            testCase.verifyEqual(ownScore, 1.1);
            testCase.verifyEqual(neighbourScore, 1.2, 'AbsTol', 1e-12);
            % cells left out of the grid are not neighbours; a cell without neighbours is rated by its own score
            grid.candidateIndex([6 8]) = 0;
            [suggested, ownScore, neighbourScore] = ZarrChunkTimer.suggestFromGrid(grid, score);
            testCase.verifyEqual(suggested, 9);
            testCase.verifyEqual(neighbourScore, ownScore);
        end

        function applyZarrChunks_writesXYZAndSharding(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel();
            converter = ImageConverter(mibModel, [], NaN);
            testCase.assertEmpty(converter.view);
            converter.applyZarrChunks([128 64 32], [4 2 1]);
            testCase.verifyEqual(converter.BatchOpt.ZarrChunkSizes, '64, 128, 32, 1, 1');
            testCase.verifyEqual(converter.BatchOpt.ZarrShardXFactorsXYZ, '2, 4, 1, 1, 1');
            testCase.verifyTrue(converter.BatchOpt.ZarrUseSharding);
            converter.applyZarrChunks([256 256 1], []);
            testCase.verifyEqual(converter.BatchOpt.ZarrChunkSizes, '256, 256, 1, 1, 1');
            testCase.verifyFalse(converter.BatchOpt.ZarrUseSharding);
        end
    end

    methods (Static, Access = private)
        function settings = settingsFor(datasetSize)
            settings = struct('datasetSize', datasetSize, 'channels', 1, 'chunkChannels', 1, ...
                'dataClass', 'uint8', 'pixSize', struct('x', 1, 'y', 1, 'z', 1), ...
                'levelOptions', struct('MinLevelSize', 512, 'DownsampleStrategy', 'XY only'));
        end
    end
end
