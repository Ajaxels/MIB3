classdef SampleStripesTest < matlab.unittest.TestCase
% SAMPLESTRIPESTEST - The statistics pass of the BigData Image tools: utils.bigdata.sampleStripes and sliceHistograms.
%
% On a 300 x 260 x 3 uint8 OME-Zarr pyramid with 64 x 64 x 1 chunks: a budget
% covering the level reads every row and gives the exact sums; a small budget
% reads evenly spaced chunk-aligned stripes within it; a block function with a
% halo sees the neighbourhood of the whole slice; a two-input block function
% of the provider receives the slice index; the histograms equal the counts
% of the whole volume.
%
% Write a zarr store, so tagged Integration.
%
% See also: utils.bigdata.sampleStripes, utils.bigdata.sliceHistograms,
% io.savers.FilteredSliceProvider

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function budgetCoveringTheLevelIsExact(testCase)
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 1);
            [sums, info] = utils.bigdata.sampleStripes(mibModel.I{1}.image, 1, ...
                @(rows) [sum(rows(:), 'double'); numel(rows)]);

            testCase.verifyTrue(info.exact);
            testCase.verifyEqual(info.fractionRead, 1);
            for z = 1:size(volume, 3)
                slice = volume(:, :, z);
                testCase.verifyEqual(sums{z}, [sum(slice(:), 'double'); numel(slice)]);
            end
        end

        function smallBudgetReadsChunkAlignedStripes(testCase)
            % 3 slices x 260 bytes per row: a budget of two 64-row chunk rows per
            % slice reads chunk rows 1 and 3 (0-based) of the five, whole.
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 1);
            [sums, info] = utils.bigdata.sampleStripes(mibModel.I{1}.image, 1, ...
                @(rows) [sum(rows(:), 'double'); numel(rows)], SampleBytes = 260 * 64 * 2 * 3, MinimumStripes = 1);

            testCase.verifyFalse(info.exact);
            testCase.verifyEqual([info.stripesPerSlice, info.stripeHeight], [2 64]);
            testCase.verifyEqual(info.rowsRead, 2 * 64 * 3);
            rows = [65:128, 193:256];
            for z = 1:size(volume, 3)
                sample = volume(rows, :, z);
                testCase.verifyEqual(sums{z}, [sum(sample(:), 'double'); numel(sample)]);
            end
        end

        function haloGivesTheWholeSliceNeighbourhood(testCase)
            % A Sobel gradient of stripes read with a 1-row halo equals the gradient
            % of the whole slice on the same rows.
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 1);
            gradientFunction = @(block) imgradient(single(block), 'sobel');
            [sums, info] = utils.bigdata.sampleStripes(mibModel.I{1}.image, 1, @(rows) sum(rows(:), 'double'), ...
                BlockFunction = gradientFunction, HaloYX = 1, SampleBytes = 260 * 64 * 2 * 3, MinimumStripes = 1);

            testCase.verifyFalse(info.exact);
            rows = [65:128, 193:256];
            for z = 1:size(volume, 3)
                wholeGradient = gradientFunction(volume(:, :, z));
                expected = wholeGradient(rows, :);
                testCase.verifyEqual(sums{z}, sum(expected(:), 'double'), 'RelTol', 1e-12);
            end
        end

        function histogramsEqualTheWholeVolume(testCase)
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 2);
            [counts, info] = utils.bigdata.sliceHistograms(mibModel.I{1}.image, 1);

            testCase.verifyTrue(info.exact);
            testCase.verifySize(counts, [256 2 3]);
            for z = 1:3
                for channel = 1:2
                    slice = volume(:, :, z, channel);
                    testCase.verifyEqual(counts(:, channel, z), histcounts(slice(:), -0.5:1:255.5)');
                end
            end
        end

        function minimumStripesExceedTheBudget(testCase)
            % A budget below one chunk row still reads 16 stripes in total, shared by
            % the 3 slices (6 each, but only 5 chunk rows exist: the whole level).
            [mibModel, ~] = mibtest.helpers.buildBigDataModel(testCase, 1);
            [~, info] = utils.bigdata.sampleStripes(mibModel.I{1}.image, 1, @(rows) numel(rows), SampleBytes = 1000);
            testCase.verifyEqual(info.stripesPerSlice, 5);
            testCase.verifyTrue(info.exact);
            [~, info] = utils.bigdata.sampleStripes(mibModel.I{1}.image, 1, @(rows) numel(rows), ...
                SampleBytes = 1000, MinimumStripes = 3);
            testCase.verifyEqual(info.stripesPerSlice, 1, 'one stripe per slice at least');
        end

        function slicesSampleOnlyThoseSlices(testCase)
            % Slices = 2: only slice 2 is read, with the whole budget; the budget of
            % two chunk rows over 3 slices reads all 5 chunk rows of one slice.
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 1);
            [sums, info] = utils.bigdata.sampleStripes(mibModel.I{1}.image, 1, ...
                @(rows) [sum(rows(:), 'double'); numel(rows)], SampleBytes = 260 * 64 * 2 * 3, ...
                MinimumStripes = 1, Slices = 2);

            slice = volume(:, :, 2);
            testCase.verifyEqual(sums{2}, [sum(slice(:), 'double'); numel(slice)]);
            testCase.verifyEmpty(sums{1});
            testCase.verifyEmpty(sums{3});
            testCase.verifyTrue(info.exact);
            testCase.verifyEqual(info.rowsTotal, size(volume, 1));
            testCase.verifyError(@() utils.bigdata.sampleStripes(mibModel.I{1}.image, 1, @(rows) numel(rows), ...
                Slices = 4), 'utils:bigdata:wrongSlice');

            counts = utils.bigdata.sliceHistograms(mibModel.I{1}.image, 1, Slices = 3);
            testCase.verifyEqual(size(counts), [256 1 3]);
            testCase.verifyEqual(counts(:, 1, 3), accumarray(double(reshape(volume(:, :, 3), [], 1)) + 1, 1, [256 1]));
            testCase.verifyEqual(nnz(counts(:, :, 1:2)), 0);
        end

        function providerPassesTheSliceIndex(testCase)
            % A block function of two inputs gets (block, z); one of one input gets block.
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 1);
            image = mibModel.I{1}.image;
            withIndex = io.savers.FilteredSliceProvider(image, 1, [], @(block, z) block + z);
            withoutIndex = io.savers.FilteredSliceProvider(image, 1, [], @(block) block + 1);
            for z = 1:3
                testCase.verifyEqual(withIndex.getSliceRows(z, 11, 30), volume(11:30, :, z) + z);
                testCase.verifyEqual(withoutIndex.getSliceRows(z, 11, 30), volume(11:30, :, z) + 1);
            end
        end

        function providerPassesTheFirstRow(testCase)
            % A block function of three inputs gets (block, z, firstRow), firstRow
            % the level row of the first row of the block, its halo included.
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 1);
            image = mibModel.I{1}.image;
            rowNumbers = @(block, z, firstRow) cast(repmat((firstRow:firstRow + size(block, 1) - 1)', 1, size(block, 2)) + z, 'like', block);
            withRow = io.savers.FilteredSliceProvider(image, 1, [], rowNumbers, HaloYX = 4);
            [~, width] = size(volume, 1:2);
            testCase.verifyEqual(withRow.getSliceRows(2, 11, 30), cast(repmat((11:30)', 1, width) + 2, 'like', volume));
            testCase.verifyEqual(withRow.getSliceRows(1, 1, 5), cast(repmat((1:5)', 1, width) + 1, 'like', volume));
        end
    end
end
