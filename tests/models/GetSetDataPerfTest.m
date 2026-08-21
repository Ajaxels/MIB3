classdef GetSetDataPerfTest < matlab.unittest.TestCase
    % Performance regression suite for MibModel getData2D/3D/4D and setData2D/3D/4D.
    %
    % Mirrors the timing list from benchmarkGetSetData in homeDevTest_Callback.m.
    % Uses fixed iteration counts (same as the ribbon benchmark) rather than
    % matlab.perftest so the suite is deterministic and runs in under a minute.
    %
    % Measurements are compared against committed baselines in tests/baselines/.
    % To create or update a baseline: set env MIB3_UPDATE_PERF_BASELINE=1 and
    % run buildtool perf.
    %
    % Key convention: measurement keys follow 'GetSetDataPerf/<op>/<modelType>'

    properties (TestParameter)
        modelType = {'labels63', 'labels255', 'labels65535'};
    end

    properties (Constant)
        % Block size for every synthetic measurement. 512x512x32 (8 MB) rather than the
        % original 256x256x32: at 256 the 2D accessors cost ~0.064 ms per call, close
        % enough to the scheduler jitter floor (~30 us) that a single context switch
        % during the run moves the mean by 30-90%, which is what produced the spurious
        % FAIL rows in the perf report. At 512 the same calls cost ~0.158 ms.
        %
        % Not raised further because model construction is per test method (~84 builds
        % across the parametrized suite): 0.28 s per build here against 1.04 s at
        % 1024x1024x32, where the builds alone would add ~87 s to buildtool perf.
        %
        % Note this does NOT rescue the get3D/get4D rows for labels255/labels65535.
        % Those accessors return the stored array whole, so MATLAB gives back a
        % copy-on-write reference and the call never touches the pixels - they measure
        % ~0.02 ms at every block size tried, from 2 MB to 32 MB.
        BenchmarkDims = [512 512 32];
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    % =====================================================================
    % 2D per-slice benchmarks  (100 iterations each)
    % =====================================================================
    methods (Test, TestTags = {'Performance'})

        function perfGet2DImage(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData2D('image', midSlice, 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get2D_image/%s', modelType), samples);
        end

        function perfGet2DLabels(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData2D('labels', midSlice, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get2D_labels/%s', modelType), samples);
        end

        function perfGet2DMask(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData2D('mask', midSlice, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get2D_mask/%s', modelType), samples);
        end

        function perfGet2DSelection(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData2D('selection', midSlice, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get2D_selection/%s', modelType), samples);
        end

        function perfGet2DLabelsMaterial(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData2D('labels', midSlice, 3, 1, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get2D_labelsMaterial/%s', modelType), samples);
        end

        function perfSet2DImage(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            imgSlice = mibModel.getData2D('image', midSlice, 3, NaN, opt); imgSlice = imgSlice{1};
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData2D(imgSlice, 'image', midSlice, 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set2D_image/%s', modelType), samples);
        end

        function perfSet2DLabels(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            labSlice = mibModel.getData2D('labels', midSlice, 3, [], opt); labSlice = labSlice{1};
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData2D(labSlice, 'labels', midSlice, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set2D_labels/%s', modelType), samples);
        end

        function perfSet2DMask(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            maskSlice = mibModel.getData2D('mask', midSlice, 3, [], opt); maskSlice = maskSlice{1};
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData2D(maskSlice, 'mask', midSlice, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set2D_mask/%s', modelType), samples);
        end

        function perfSet2DSelection(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            selSlice = mibModel.getData2D('selection', midSlice, 3, [], opt); selSlice = selSlice{1};
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData2D(selSlice, 'selection', midSlice, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set2D_selection/%s', modelType), samples);
        end

        function perfSet2DLabelsMaterial(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            matSlice = mibModel.getData2D('labels', midSlice, 3, 1, opt); matSlice = matSlice{1};
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData2D(matSlice, 'labels', midSlice, 3, 1, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set2D_labelsMaterial/%s', modelType), samples);
        end

    end

    % =====================================================================
    % 3D full-volume benchmarks  (5 iterations each)
    % =====================================================================
    methods (Test, TestTags = {'Performance'})

        function perfGet3DImage(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('image', 1, 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get3D_image/%s', modelType), samples);
        end

        function perfGet3DLabels(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('labels', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get3D_labels/%s', modelType), samples);
        end

        function perfGet3DMask(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('mask', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get3D_mask/%s', modelType), samples);
        end

        function perfGet3DSelection(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('selection', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get3D_selection/%s', modelType), samples);
        end

        function perfGet3DLabelsMaterial(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('labels', 1, 3, 1, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get3D_labelsMaterial/%s', modelType), samples);
        end

        function perfGet3DImageOrient1(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('image', 1, 1, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get3D_imageOrient1/%s', modelType), samples);
        end

        function perfGet3DEverything(testCase, modelType)
            testCase.assumeTrue(strcmp(modelType, 'labels63'), ...
                'everything type only applies to labels63');
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('everything', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get3D_everything/%s', modelType), samples);
        end

        function perfSet3DImage(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            imgVol = mibModel.getData3D('image', 1, 3, NaN, opt); imgVol = imgVol{1};
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData3D(imgVol, 'image', 1, 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set3D_image/%s', modelType), samples);
        end

        function perfSet3DLabels(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            labVol = mibModel.getData3D('labels', 1, 3, [], opt); labVol = labVol{1};
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData3D(labVol, 'labels', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set3D_labels/%s', modelType), samples);
        end

        function perfSet3DMask(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            maskVol = mibModel.getData3D('mask', 1, 3, [], opt); maskVol = maskVol{1};
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData3D(maskVol, 'mask', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set3D_mask/%s', modelType), samples);
        end

        function perfSet3DSelection(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            selVol = mibModel.getData3D('selection', 1, 3, [], opt); selVol = selVol{1};
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData3D(selVol, 'selection', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set3D_selection/%s', modelType), samples);
        end

        function perfSet3DLabelsMaterial(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            matVol = mibModel.getData3D('labels', 1, 3, 1, opt); matVol = matVol{1};
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData3D(matVol, 'labels', 1, 3, 1, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set3D_labelsMaterial/%s', modelType), samples);
        end

        function perfSet3DEverything(testCase, modelType)
            testCase.assumeTrue(strcmp(modelType, 'labels63'), ...
                'everything type only applies to labels63');
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            allVol = mibModel.getData3D('everything', 1, 3, [], opt); allVol = allVol{1};
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData3D(allVol, 'everything', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set3D_everything/%s', modelType), samples);
        end

    end

    % =====================================================================
    % 4D benchmarks  (5 iterations each)
    % =====================================================================
    methods (Test, TestTags = {'Performance'})

        function perfGet4DImage(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData4D('image', 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get4D_image/%s', modelType), samples);
        end

        function perfGet4DLabels(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt     = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData4D('labels', 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get4D_labels/%s', modelType), samples);
        end

        function perfSet4DImage(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            imgVol4  = mibModel.getData4D('image', 3, NaN, opt); imgVol4 = imgVol4{1};
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData4D(imgVol4, 'image', 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set4D_image/%s', modelType), samples);
        end

        function perfSet4DLabels(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            labVol4  = mibModel.getData4D('labels', 3, [], opt); labVol4 = labVol4{1};
            samples  = mibtest.perf.timeCallSamples( ...
                @() mibModel.setData4D(labVol4, 'labels', 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/set4D_labels/%s', modelType), samples);
        end

    end

    % =====================================================================
    % Display pipeline benchmark
    % =====================================================================
    methods (Test, TestTags = {'Performance'})

        function perfGetRGBimage(testCase, modelType)
            % getRGBimage is the full display pipeline end-to-end.
            % Verified headless-safe in Phase 0 (no GUI state needed).
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType, dims=testCase.BenchmarkDims);
            rgbOptions = struct('blockModeSwitch', 0, 'resizeToMagnification', true);
            samples    = mibtest.perf.timeCallSamples( ...
                @() mibModel.getRGBimage(rgbOptions), ...
                mibtest.perf.PerfBaselineStore.DefaultIterationsRGB);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/getRGBimage/%s', modelType), samples);
        end

    end

    % =====================================================================
    % Real-data benchmarks  (Integration + Performance + RequiresNetwork)
    % =====================================================================
    % These run against the full 887×813×171 Trypanosoma SBEM stack
    % (downloaded once and cached by ExampleDataFixture).
    % They are skipped automatically when the cache is absent and the
    % server is unreachable (offline / CI without network).
    % =====================================================================
    methods (Test, TestTags = {'Integration', 'Performance', 'RequiresNetwork'})

        function perfRealDataGet3DImage(testCase)
            spec = mibtest.helpers.datasetSpec('Trypanosoma');
            testCase.assumeTrue(mibtest.helpers.hasTestData(spec), ...
                'Trypanosoma dataset not cached and server offline - skipping');
            dataFixture = testCase.applyFixture( ...
                mibtest.fixtures.ExampleDataFixture('Trypanosoma'));
            [mibModel, ~] = mibtest.helpers.buildBenchmarkModel( ...
                dataFixture.Image, dataFixture.Labels);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('image', 1, 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                'GetSetDataPerf/get3D_image/trypanosoma', samples);
        end

        function perfRealDataGet3DLabels(testCase)
            spec = mibtest.helpers.datasetSpec('Trypanosoma');
            testCase.assumeTrue(mibtest.helpers.hasTestData(spec), ...
                'Trypanosoma dataset not cached and server offline - skipping');
            dataFixture = testCase.applyFixture( ...
                mibtest.fixtures.ExampleDataFixture('Trypanosoma'));
            [mibModel, ~] = mibtest.helpers.buildBenchmarkModel( ...
                dataFixture.Image, dataFixture.Labels);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData3D('labels', 1, 3, [], opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations3D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                'GetSetDataPerf/get3D_labels/trypanosoma', samples);
        end

        function perfRealDataGet2DImage(testCase)
            spec = mibtest.helpers.datasetSpec('Trypanosoma');
            testCase.assumeTrue(mibtest.helpers.hasTestData(spec), ...
                'Trypanosoma dataset not cached and server offline - skipping');
            dataFixture = testCase.applyFixture( ...
                mibtest.fixtures.ExampleDataFixture('Trypanosoma'));
            [mibModel, ~] = mibtest.helpers.buildBenchmarkModel( ...
                dataFixture.Image, dataFixture.Labels);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData2D('image', [], 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                'GetSetDataPerf/get2D_image/trypanosoma', samples);
        end

    end

end
