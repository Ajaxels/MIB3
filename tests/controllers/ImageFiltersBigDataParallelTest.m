classdef ImageFiltersBigDataParallelTest < matlab.unittest.TestCase
% IMAGEFILTERSBIGDATAPARALLELTEST - Image filters on a BigData dataset with Use parallel computing.
%
% The outputs of ``controllers.BigDataOptions`` with
% ``BatchOpt.UseParallelComputing``: the bands are computed on the workers of a
% process pool, each worker opening the source store itself
% (``io.savers.FilteredSliceProvider``), and the result equals the one of the
% client. Covers a new store, the filters that take the whole-slice part from
% a coarser level (a provider captured by the band function), a per-slice
% statistics pass (a band function of ``(block, z)``), Edge into the model, a
% Standard result, the overwrite of the whole store and of a ROI box, the
% error of a band, and the chunk caches of the workers after a run.
%
% Starts a pool of 2 process workers (or uses the open one); run it in a
% separate MATLAB (``matlab -batch``), not in a session with a MIB window.
% Tagged Integration.
%
% See also: ImageFiltersBigDataTest, controllers.BigDataOptions, Zarr3SaverParallelTest

    properties
        Pool
        CreatedPool = false
    end

    methods (TestClassSetup)
        function addPathsAndPool(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            testCase.Pool = gcp('nocreate');
            if isempty(testCase.Pool)
                testCase.Pool = parpool('Processes', 2);
                testCase.CreatedPool = true;
            end
        end
    end

    methods (TestClassTeardown)
        function deletePool(testCase)
            if testCase.CreatedPool; delete(testCase.Pool); end
        end
    end

    methods (Test, TestTags = {'Integration'})

        function newStoreOnTheWorkers(testCase)
            % A Gaussian into a new store in several bands equals imgaussfilt of every slice;
            % afterwards the chunk cache of every worker is empty.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'gaussian.zarr3'), 'Container 2');
            testCase.runTool(mibModel, BatchOpt, 8 * 260 * 40);

            testCase.verifyEqual(ImageFiltersBigDataTest.readImage(mibModel.I{2}), testCase.gaussianOfSlices(volume, BatchOpt));
            testCase.verifyEqual(testCase.workerCacheBytes(), zeros(1, testCase.Pool.NumWorkers), ...
                'the chunk caches of the workers are cleared after the run');
        end

        function bandsAreComputedOnTheWorkers(testCase)
            % A band function that marks where it runs gives 1 everywhere, in a store and in memory.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'marked.zarr3'), 'Container 2');
            tool = controllers.ImageFilters(mibModel, [], NaN);
            BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);   % run is called directly
            BatchOpt.id = 1;
            tool.bigDataOptions.BandBytes = 8 * 260 * 40;
            tool.bigDataOptions.run(BatchOpt, @ImageFiltersBigDataParallelTest.workerMark);
            testCase.verifyTrue(all(ImageFiltersBigDataTest.readImage(mibModel.I{2}) == 1, 'all'), 'a new store');

            BatchOpt.BigData_Result = {'Standard (in memory)'};
            BatchOpt.BigData_OpenIn = {'Container 3'};
            tool.bigDataOptions.run(BatchOpt, @ImageFiltersBigDataParallelTest.workerMark);
            testCase.verifyTrue(all(mibModel.I{3}.image.data == 1, 'all'), 'a Standard result');
        end

        function filtersMatchTheClient(testCase)
            % The whole-slice filters (a guide reader captured by the band function, read on the
            % worker), a noise estimate per slice ((block, z)) and a 3D filter give the store of the client.
            cases = {
                'LocalContrast', 'Contrast Adjustment', struct('EdgeThreshold', {{0.3}}, 'Amount', {{0.5}}); ...
                'FastLocalLaplacian', 'Contrast Adjustment', struct('EdgeAmplitude', {{0.2}}, 'Smoothing', {{0.3}}); ...
                'NonLocalMeans', 'Image Denoising', struct('DegreeOfSmoothing', 'NaN'); ...
                'Gaussian', 'Basic Image Filtering in the Spatial Domain', struct('Mode3D', true, 'Sigma', {{1.2}}, 'HSize', '5')};
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            for caseIndex = 1:size(cases, 1)
                filterName = cases{caseIndex, 1};
                BatchOpt = testCase.filterBatchOpt(mibModel, filterName, cases{caseIndex, 2}, cases{caseIndex, 3}, ...
                    fullfile(scratch, [filterName '_client.zarr3']));
                % a guide coarser than the level and several bands per slice
                testCase.runTool(mibModel, BatchOpt, 8 * 260 * 40, 300 * 260 / 3, false);
                clientResult = ImageFiltersBigDataTest.readImage(mibModel.I{2});

                BatchOpt.BigData_OutputPath = fullfile(scratch, [filterName '_pool.zarr3']);
                testCase.runTool(mibModel, BatchOpt, 8 * 260 * 40, 300 * 260 / 3, true);
                testCase.verifyEqual(ImageFiltersBigDataTest.readImage(mibModel.I{2}), clientResult, filterName);
            end
        end

        function edgesIntoTheModel(testCase)
            % Edge into the selection in bands on the workers equals edge() of every whole slice.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            controllers.ImageFilters(mibModel, [], NaN);   % creates the session defaults
            BatchOpt = rmfield(mibModel.sessionSettings.ImageFilters.Edge, 'mibBatchTooltip');
            BatchOpt.FilterGroup = {'Image Binarization'};
            BatchOpt.FilterName = {'Edge'};
            BatchOpt.Method = {'Sobel'};
            BatchOpt.Threshold = '0.05';
            BatchOpt.DestinationLayer = {'selection'};
            BatchOpt.ColorChannel = {'1'};
            BatchOpt.DatasetType = {'3D, Stack'};
            BatchOpt.showWaitbar = false;
            BatchOpt.BigData_PyramidLevel = {'s0'};
            testCase.runTool(mibModel, BatchOpt, 8 * 260 * 40);

            expected = zeros(size(volume, 1:3), 'uint8');
            for z = 1:size(volume, 3)
                expected(:,:,z) = edge(volume(:,:,z), 'Sobel', 0.05);
            end
            testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 1)), expected);
        end

        function standardResultInMemory(testCase)
            % "Standard (in memory)" of two channels equals imgaussfilt of every slice and channel.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 2);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'notWritten.zarr3'), 'Container 2');
            BatchOpt.BigData_Result = {'Standard (in memory)'};
            testCase.runTool(mibModel, BatchOpt, 8 * 260 * 2 * 40);
            testCase.verifyEqual(mibModel.I{2}.image.data(:,:,:,:,1), testCase.gaussianOfSlices(volume, BatchOpt));
        end

        function overwriteOfTheWholeStore(testCase)
            % The store is swapped for the result computed on the workers, whose readers of the
            % source must not block the rename; no temporary store is left.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            mibModel.setLockedState(1, 'image', false);
            sourcePath = mibModel.I{1}.image.filename;
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            testCase.runTool(mibModel, BatchOpt, 8 * 260 * 40);

            testCase.verifyEqual(mibModel.I{1}.image.filename, sourcePath);
            testCase.verifyEqual(ImageFiltersBigDataTest.readImage(mibModel.I{1}), testCase.gaussianOfSlices(volume, BatchOpt));
            listing = dir(scratch);
            testCase.verifyEmpty(listing(contains({listing.name}, '.mib_')), 'temporary stores must be removed');
        end

        function overwriteOfARoiBox(testCase)
            % Overwrite with a rectangle ROI: the box is computed on the workers and written on the
            % client; a second run on the workers reads the new pixels, not cached old chunks.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            roi.label = cellstr('1');
            roi.type = cellstr('rectangle');
            roi.X = [37; 150];
            roi.Y = [45; 201];
            roi.orientation = 3;
            roi.BoundingBox.x = roi.X;
            roi.BoundingBox.y = roi.Y;
            mibModel.I{1}.hROI.storeROI(roi);
            mibModel.I{1}.selectedROI = 0;
            mibModel.I{1}.restrictToROI = true;
            mibModel.setLockedState(1, 'image', false);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            testCase.runTool(mibModel, BatchOpt, 8 * 114 * 40);

            expected = volume;
            filtered = testCase.gaussianOfSlices(volume, BatchOpt);
            expected(45:201, 37:150, :) = filtered(45:201, 37:150, :);
            testCase.verifyEqual(ImageFiltersBigDataTest.readImage(mibModel.I{1}), expected);

            testCase.runTool(mibModel, BatchOpt, 8 * 114 * 40);
            twice = testCase.gaussianOfSlices(expected, BatchOpt);
            expected(45:201, 37:150, :) = twice(45:201, 37:150, :);
            testCase.verifyEqual(ImageFiltersBigDataTest.readImage(mibModel.I{1}), expected, ...
                'the second run filters the result of the first');
        end

        function failedBandKeepsItsError(testCase)
            % A band that fails on a worker raises its own error, not the wrapper of the pool.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Container 2');
            BatchOpt.BigData_Result = {'Standard (in memory)'};
            tool = controllers.ImageFilters(mibModel, [], NaN);
            BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);   % run is called directly
            BatchOpt.id = 1;
            testCase.verifyError(@() tool.bigDataOptions.run(BatchOpt, @ImageFiltersBigDataParallelTest.failOnSlice2), ...
                'test:bandFailed');
            testCase.verifyEqual(mibModel.I{2}.image.filename, 'none.tif', 'nothing opens after a failed run');
        end
    end

    methods
        function runTool(~, mibModel, BatchOpt, bandBytes, guidePixels, useParallel)
            % Run Image filters on buffer 1 with Use parallel computing (default on) and the given budgets.
            if nargin < 6; useParallel = true; end
            BatchOpt.UseParallelComputing = useParallel;
            tool = controllers.ImageFilters(mibModel, [], NaN);
            tool.bigDataOptions.BandBytes = bandBytes;
            if nargin > 4 && ~isempty(guidePixels); tool.bigDataOptions.GuidePixels = guidePixels; end
            tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
            tool.Filter([], 1);
        end

        function bytes = workerCacheBytes(testCase)
            % Bytes held by the chunk cache of every worker (runs after the clear queued by the run).
            future = parfevalOnAll(testCase.Pool, @() io.zarr.ChunkCache.stats().bytes, 1);
            bytes = reshape(fetchOutputs(future), 1, []);
        end

        function BatchOpt = gaussianBatchOpt(~, mibModel, outputPath, openIn)
            % Batch options of a Gaussian (the session defaults) to a new store.
            if ~isfield(mibModel.sessionSettings, 'ImageFilters')
                controllers.ImageFilters(mibModel, [], NaN);   % creates the session defaults
            end
            BatchOpt = rmfield(mibModel.sessionSettings.ImageFilters.Gaussian, 'mibBatchTooltip');
            BatchOpt.DatasetType = {'3D, Stack'};
            BatchOpt.FilterGroup = {'Basic Image Filtering in the Spatial Domain'};
            BatchOpt.FilterName = {'Gaussian'};
            BatchOpt.Sigma = {1.5};
            BatchOpt.HSize = '7';
            BatchOpt.showWaitbar = false;
            BatchOpt.UseParallelComputing = true;
            BatchOpt.BigData_OutputPath = outputPath;
            BatchOpt.BigData_OpenIn = {openIn};
        end

        function BatchOpt = filterBatchOpt(~, mibModel, filterName, filterGroup, settings, outputPath)
            % Batch options of ``filterName`` (the session defaults, then ``settings``) on channel 1 into buffer 2.
            if ~isfield(mibModel.sessionSettings, 'ImageFilters')
                controllers.ImageFilters(mibModel, [], NaN);
            end
            BatchOpt = rmfield(mibModel.sessionSettings.ImageFilters.(filterName), 'mibBatchTooltip');
            BatchOpt.DatasetType = {'3D, Stack'};
            for fieldName = fieldnames(settings)'
                BatchOpt.(fieldName{1}) = settings.(fieldName{1});
            end
            BatchOpt.FilterGroup = {filterGroup};
            BatchOpt.FilterName = {filterName};
            BatchOpt.ColorChannel = {'1'};
            BatchOpt.showWaitbar = false;
            BatchOpt.BigData_PyramidLevel = {'s0'};
            BatchOpt.BigData_OutputPath = outputPath;
            BatchOpt.BigData_OpenIn = {'Container 2'};
        end

        function expected = gaussianOfSlices(~, volume, BatchOpt)
            % imgaussfilt of every whole slice and channel, with the batch parameters.
            expected = volume;
            for channel = 1:size(volume, 4)
                for z = 1:size(volume, 3)
                    expected(:,:,z,channel) = imgaussfilt(volume(:,:,z,channel), BatchOpt.Sigma{1}, ...
                        'FilterSize', str2double(BatchOpt.HSize), 'Padding', BatchOpt.Padding{1}, ...
                        'FilterDomain', BatchOpt.FilterDomain{1});
                end
            end
        end
    end

    methods (Static)
        function marked = workerMark(block)
            % Band function: 1 where computed on a pool worker, 0 on the client.
            marked = zeros(size(block), 'uint8') + uint8(~isempty(getCurrentWorker()));
        end

        function out = failOnSlice2(block, z)
            % Band function that fails on slice 2.
            if z == 2; error('test:bandFailed', 'Band of slice 2 failed on purpose.'); end
            out = block;
        end
    end
end
