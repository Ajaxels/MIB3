classdef MibDatasetTest < matlab.unittest.TestCase
% MIBDATASETTEST - Unit tests for core.MibDataset construction and layer management.
%
% Covers: modelType variants, layer class/presence, updateBoundingBox, clearLayer.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % modelType variants
        % -----------------------------------------------------------------

        function labels63TypeUsesPackedBits(testCase)
            ds = core.MibDataset(uint8(zeros(16,16,4,1)), dictionary(), ...
                'Standard', 'labels63');
            testCase.verifyClass(ds.labels, 'core.MibLabels63');
        end

        function labels255TypeHasSeparateLayers(testCase)
            ds = core.MibDataset(uint8(zeros(16,16,4,1)), dictionary(), ...
                'Standard', 'labels63');
            ds.createModel(255);

            testCase.verifyClass(ds.labels, 'core.MibLabels');
            testCase.verifyEqual(ds.labels.maxMaterials, 255);
            testCase.verifyEqual(ds.labels.dataClass, 'uint8');
        end

        function labels65535TypeHasSeparateLayers(testCase)
            ds = core.MibDataset(uint8(zeros(16,16,4,1)), dictionary(), ...
                'Standard', 'labels63');
            ds.createModel(65535);

            testCase.verifyClass(ds.labels, 'core.MibLabels');
            testCase.verifyEqual(ds.labels.maxMaterials, 65535);
            testCase.verifyEqual(ds.labels.dataClass, 'uint16');
        end

        function imageOnlyTypeHasNoLabelLayer(testCase)
            ds = core.MibDataset(uint8(zeros(16,16,4,1)), dictionary(), ...
                'Standard', 'imageOnly');
            testCase.verifyFalse(ds.modelExist);
        end

        % -----------------------------------------------------------------
        % updateBoundingBox
        % -----------------------------------------------------------------

        function updateBoundingBoxFromShiftSetsPixSize(testCase)
            volume = uint8(zeros(10, 10, 5, 1));
            ds = core.MibDataset(volume, dictionary(), 'Standard', 'labels63');
            ds.updateBoundingBox([], [0 0 0]);

            testCase.verifyGreaterThan(ds.image.pixSize.x, 0);
            testCase.verifyGreaterThan(ds.image.pixSize.y, 0);
            testCase.verifyEqual(numel(ds.image.boundingBox), 6);
        end

        function updateBoundingBoxExplicitSetsExpectedPixSize(testCase)
            volume = uint8(zeros(11, 11, 6, 1));   % [H=11 W=11 D=6 C=1]
            ds = core.MibDataset(volume, dictionary(), 'Standard', 'labels63');
            % 10 x 10 x 5 um bounding box → pixSize = [1 1 1] um
            ds.updateBoundingBox([0 10 0 10 0 5], []);

            testCase.verifyEqual(ds.image.pixSize.x, 1.0, 'AbsTol', 1e-9);
            testCase.verifyEqual(ds.image.pixSize.y, 1.0, 'AbsTol', 1e-9);
            testCase.verifyEqual(ds.image.pixSize.z, 1.0, 'AbsTol', 1e-9);
        end

        % -----------------------------------------------------------------
        % clearLayer
        % -----------------------------------------------------------------

        function clearSelectionZerosEntireVolume(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.selection(:))), 0, ...
                'synthetic selection should be non-zero');

            mibModel.I{1}.clearLayer('selection');

            result = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(result{1}(:))), 0);
        end

        function clearMaskZerosEntireVolume(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.mask(:))), 0, ...
                'synthetic mask should be non-zero');

            mibModel.I{1}.clearLayer('mask');

            result = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(result{1}(:))), 0);
        end

        function clearSelectionLeavesImageIntact(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            imageChecksumBefore = sum(double(gt.image(:)));
            mibModel.I{1}.clearLayer('selection');

            imageResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imageResult{1}(:))), imageChecksumBefore);
        end

        function clearLabelsLeavesSelectionIntact(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            selectionChecksumBefore = sum(double(gt.selection(:)));
            mibModel.I{1}.clearLayer('labels');

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), selectionChecksumBefore);
        end

        function clearSelection2DLeavesOtherSlicesIntact(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            % choose a middle slice and verify it has non-zero selection
            depth = size(gt.selection, 3);
            midSlice = ceil(depth / 2);
            mibModel.I{1}.slices{3} = [midSlice, midSlice];   % set current slice
            testCase.assumeGreaterThan(sum(double(gt.selection(:,:,midSlice)), 'all'), 0, ...
                'middle slice selection should be non-zero');

            % clear only the current 2D slice
            mibModel.I{1}.clearLayer('selection', '2D');

            % middle slice must be zero
            sliceResult = mibModel.getData2D('selection', midSlice, 3, NaN, opt);
            testCase.verifyEqual(sum(double(sliceResult{1}(:))), 0);

            % other slices must be intact — verify a different slice (slice 1)
            if midSlice > 1
                otherSlice = mibModel.getData2D('selection', 1, 3, NaN, opt);
                testCase.verifyEqual(squeeze(otherSlice{1}), ...
                    squeeze(gt.selection(:,:,1)));
            end
        end

    end
end
