classdef PreferencesSelectionLayerTest < matlab.unittest.TestCase
% PREFERENCESSELECTIONLAYERTEST - Unit tests for the "Enable selection" preference switch.
%
% Switching the preference off shows a warning that says the Model and Mask
% layers will be deleted, and switching it back on has to leave a layer the
% segmentation tools can write to. Both directions live in
% ``controllers.Preferences.releaseSegmentationLayers`` /
% ``.allocateLabelsLayer``, which are static so these tests can drive them
% without opening the dialog.
%
% What the tests pin down, in both cases having been wrong before:
%
%   - "delete the Model and Mask layers" means all three layers and the flags
%     that report them, for a 63-material model and for a 255+ one, where the
%     model layer is a separate container that used to survive untouched
%   - re-enabling rebuilds a layer with its dimension bookkeeping set, not just
%     a ``data`` array - ``setData63`` clips writes against those properties

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function disableDropsAllLayersOfPackedModel(testCase)
            dataset = testCase.buildPaintedDataset(63);

            controllers.Preferences.releaseSegmentationLayers(dataset);

            testCase.verifyEmpty(dataset.labels.data);
            testCase.verifyEmpty(dataset.mask.data);
            testCase.verifyEmpty(dataset.selection.data);
            testCase.verifyFalse(dataset.modelExist);
            testCase.verifyFalse(dataset.maskExist);
            testCase.verifyEmpty(dataset.labels.materialNames);
        end

        function disableDropsSeparateModelLayer(testCase)
            % a 255-material model lives in its own core.MibLabels container: the
            % branch used to clear only selection and mask, so the model - the
            % largest layer, and the one the warning names first - stayed in memory
            dataset = testCase.buildPaintedDataset(255);
            testCase.assertGreaterThan(sum(dataset.labels.data(:) > 0), 0);

            controllers.Preferences.releaseSegmentationLayers(dataset);

            testCase.verifyEmpty(dataset.labels.data);
            testCase.verifyEmpty(dataset.mask.data);
            testCase.verifyEmpty(dataset.selection.data);
            testCase.verifyFalse(dataset.modelExist);
            testCase.verifyFalse(dataset.maskExist);
        end

        function disableResetsModelTypeToDefault(testCase)
            % the deleted model takes its type with it, so re-enabling reaches the
            % 63-material branch that can actually rebuild a layer
            dataset = testCase.buildPaintedDataset(65535);

            controllers.Preferences.releaseSegmentationLayers(dataset);

            testCase.verifyClass(dataset.labels, 'core.MibLabels63');
            testCase.verifyEqual(dataset.labels.maxMaterials, 63);
            testCase.verifyEqual(dataset.selectedMaterial, 1);
            testCase.verifyEqual(dataset.selectedAddToMaterial, 1);
        end

        function disableLeavesImageIntact(testCase)
            dataset = testCase.buildPaintedDataset(63);

            controllers.Preferences.releaseSegmentationLayers(dataset);

            testCase.verifyTrue(dataset.image.exists);
            testCase.verifyEqual(dataset.dim_yxzct, [32 32 4 1 1]);
        end

        function reEnableRebuildsAWritableLayer(testCase)
            dataset = testCase.buildPaintedDataset(255);
            controllers.Preferences.releaseSegmentationLayers(dataset);

            controllers.Preferences.allocateLabelsLayer(dataset);

            testCase.verifyTrue(dataset.labels.exists);
            % the bookkeeping setData63 clips against, not just the data array
            testCase.verifyEqual(dataset.labels.height, 32);
            testCase.verifyEqual(dataset.labels.width, 32);
            testCase.verifyEqual(dataset.labels.depth, 4);
            testCase.verifyEqual(dataset.labels.time, 1);
            testCase.verifyEqual(dataset.labels.dataClass, 'uint8');

            writeOptions = struct('y', [1 32], 'x', [1 32], 'z', [2 2], 't', [1 1]);
            patch = zeros(32, 32, 'uint8');
            patch(5:15, 5:15) = 1;
            dataset.labels.setData63(patch, 'selection', 3, [], writeOptions);
            readBack = dataset.labels.getData63('selection', 3, [], writeOptions);

            testCase.verifyEqual(squeeze(readBack), patch);
        end

    end

    methods (Access = private)
        function dataset = buildPaintedDataset(~, modelType)
            % a fresh dataset per call - MibDataset is a handle
            dataset = core.MibDataset();
            dataset.initialize(uint8(zeros(32, 32, 4, 1)), [], 'Standard', 'imageOnly', true);
            dataset.createModel(modelType);
            dataset.labels.materialNames = {'mitochondria'; 'nucleus'};
            dataset.labels.materialsCount = 2;
            dataset.modelExist = true;
            dataset.maskExist = true;
            dataset.selectedMaterial = 3;
            dataset.selectedAddToMaterial = 3;

            writeOptions = struct('y', [1 32], 'x', [1 32], 'z', [2 2], 't', [1 1]);
            patch = zeros(32, 32, 'uint8');
            patch(8:18, 8:18) = 1;
            if modelType == 63
                dataset.labels.setData63(patch, 'labels',    3, 1,  writeOptions);
                dataset.labels.setData63(patch, 'mask',      3, [], writeOptions);
                dataset.labels.setData63(patch, 'selection', 3, [], writeOptions);
            else
                dataset.labels.data(8:18, 8:18, 2, 1, 1) = 1;
                dataset.allocateMask();
                dataset.mask.data(8:18, 8:18, 2, 1, 1) = 1;
                dataset.selection.data(8:18, 8:18, 2, 1, 1) = 1;
            end
        end
    end
end
