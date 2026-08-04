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

        function failedInitializeKeepsDatasetUsable(testCase)
            % a rejected initialize must not leave the container half-built:
            % previously obj.image was set to NaN before the new layers were
            % constructed, so every later obj.image.<...> access threw
            % "Dot indexing is not supported for variables of type double"
            ds = core.MibDataset(uint8(zeros(16,16,4,1)), dictionary(), ...
                'Standard', 'labels63');

            testCase.verifyError(@() ds.initialize([], [], 'NoSuchType', [], false), ...
                'MIB:MibDataset:unknownDatasetType');

            testCase.verifyClass(ds.image, 'core.MibImage');
            testCase.verifyClass(ds.labels, 'core.MibLabels63');
            testCase.verifyEqual(ds.datasetType, 'Standard');
            testCase.verifyEqual(ds.image.height, 16);
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

        % -----------------------------------------------------------------
        % applySizeMismatch
        % -----------------------------------------------------------------

        function cropBothAxesBiggerExtractsOffsetWindow(testCase)
            % source 10x10, target 6x6, offset (2,3) -> rows 3:8, cols 4:9
            source = reshape(uint8(1:100), 10, 10);
            expected = source(3:8, 4:9);

            result = core.MibDataset.applySizeMismatch(source, 6, 6, 'Crop', 2, 3);

            testCase.verifyEqual(size(result), [6 6]);
            testCase.verifyEqual(result, expected);
        end

        function cropBothAxesSmallerPlacesAtOffsetAndZeroPads(testCase)
            % source 4x4, target 8x8, offset (2,3) -> placed at rows 3:6, cols 4:7
            source = reshape(uint8(1:16), 4, 4);

            result = core.MibDataset.applySizeMismatch(source, 8, 8, 'Crop', 2, 3);

            testCase.verifyEqual(size(result), [8 8]);
            testCase.verifyEqual(result(3:6, 4:7), source);
            result(3:6, 4:7) = 0;
            testCase.verifyEqual(sum(result(:)), 0);
        end

        function cropMixedAxesResolvesEachAxisIndependently(testCase)
            % H bigger (crop, offset 1), W smaller (pad, offset 2)
            source = reshape(uint8(1:40), 8, 5);   % [H=8 W=5]
            imgH = 6; imgW = 9;
            offsetY = 1; offsetX = 2;

            result = core.MibDataset.applySizeMismatch(source, imgH, imgW, 'Crop', offsetY, offsetX);

            testCase.verifyEqual(size(result), [imgH imgW]);
            expectedBlock = source(offsetY + (1:imgH), :);
            testCase.verifyEqual(result(:, offsetX + (1:5)), expectedBlock);
        end

        function cropOffsetZeroMatchesTopLeftLegacyBehavior(testCase)
            source = reshape(uint8(1:100), 10, 10);
            result = core.MibDataset.applySizeMismatch(source, 6, 6, 'Crop', 0, 0);
            testCase.verifyEqual(result, source(1:6, 1:6));
        end

        function cropMaxOffsetReachesOppositeCorner(testCase)
            source = reshape(uint8(1:100), 10, 10);
            maxOffset = 10 - 6;   % = 4
            result = core.MibDataset.applySizeMismatch(source, 6, 6, 'Crop', maxOffset, maxOffset);
            testCase.verifyEqual(result, source(5:10, 5:10));
        end

        function cropPreservesTrailingDimensions(testCase)
            source = reshape(uint8(1:(4*4*3)), 4, 4, 3);   % [H=4 W=4 D=3]
            result = core.MibDataset.applySizeMismatch(source, 8, 8, 'Crop', 0, 0);
            testCase.verifyEqual(size(result), [8 8 3]);
            testCase.verifyEqual(result(1:4, 1:4, :), source);
        end

        function resizePreservesClassAndIntroducesNoNewValues(testCase)
            source = uint8([1 1 2 2; 1 1 2 2; 3 3 4 4; 3 3 4 4]);   % 4x4, values {1,2,3,4}

            result = core.MibDataset.applySizeMismatch(source, 8, 8, 'Resize', 0, 0);

            testCase.verifyClass(result, 'uint8');
            testCase.verifyEqual(size(result), [8 8]);
            testCase.verifyTrue(all(ismember(unique(result(:)), unique(source(:)))), ...
                'nearest-neighbor resize must not introduce new label values');
        end

        function resizeOnBinaryMaskStaysBinary(testCase)
            source = logical([1 0; 0 1]);
            result = core.MibDataset.applySizeMismatch(source, 6, 6, 'Resize', 0, 0);
            testCase.verifyTrue(all(ismember(unique(result(:)), [0 1])));
        end

    end
end
