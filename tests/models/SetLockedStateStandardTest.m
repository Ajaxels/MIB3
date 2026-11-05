classdef SetLockedStateStandardTest < matlab.unittest.TestCase
% SETLOCKEDSTATESTANDARDTEST - the labels lock of a Standard dataset, which is its disabled selection.
%
% For a Standard dataset core.MibDataset.getLockedState reports the labels
% 'locked' while enableSelection is false, and models.MibModel.setLockedState
% releases the labels, mask and selection to lock them and allocates the
% labels layer to unlock them. An empty placeholder buffer reports 'none', so
% the padlock does not cover the empty buffers when the EnableSelection
% preference is off.
%
% See also: models.MibModel.setLockedState, core.MibDataset.getLockedState,
% controllers.Preferences.releaseSegmentationLayers, controllers.Preferences.allocateLabelsLayer

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function enabledSelectionIsUnlocked(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel();
            testCase.verifyEqual(mibModel.I{1}.getLockedState('labels'), 'unlocked');
            testCase.verifyEqual(mibModel.I{1}.getLockedState('image'), 'none', ...
                'a Standard image has no lock');
        end

        function emptyBufferHasNoLock(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel();
            placeholder = mibModel.I{2};
            placeholder.enableSelection = false;
            testCase.verifyEqual(placeholder.getLockedState('labels'), 'none');
        end

        function lockReleasesTheLayersAndDisablesTheSelection(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel();
            dataset = mibModel.I{1};
            testCase.assertTrue(dataset.modelExist);

            status = mibModel.setLockedState(1, 'labels', true);

            testCase.verifyTrue(status);
            testCase.verifyFalse(logical(dataset.enableSelection));
            testCase.verifyEqual(dataset.getLockedState('labels'), 'locked');
            testCase.verifyEmpty(dataset.labels.data, 'the labels are released');
            testCase.verifyFalse(dataset.modelExist);
            testCase.verifyFalse(dataset.maskExist);
        end

        function unlockAllocatesTheLabelsLayer(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel(dims = [32 48 5]);
            dataset = mibModel.I{1};
            mibModel.setLockedState(1, 'labels', true);

            status = mibModel.setLockedState(1, 'labels', false);

            testCase.verifyTrue(status);
            testCase.verifyTrue(logical(dataset.enableSelection));
            testCase.verifyEqual(dataset.getLockedState('labels'), 'unlocked');
            testCase.verifyTrue(dataset.labels.exists, 'the labels layer is allocated');
            testCase.verifyEqual(size(dataset.labels.data, [1 2 3]), [32 48 5]);
            testCase.verifyEqual(nnz(dataset.labels.data), 0, 'and empty');
        end

        function unlockReplacesAnEmptyContainerOfAnotherType(testCase)
            % opened with the preference off and a 255 default model type: an
            % empty core.MibLabels, which cannot be allocated in place
            mibModel = mibtest.helpers.buildSyntheticModel(modelType = 'labels255', dims = [32 48 5]);
            dataset = mibModel.I{1};
            mibModel.setLockedState(1, 'labels', true);
            dataset.labels = core.MibLabels([], core.MibImage.initializeImgInfo( ...
                'Height', 32, 'Width', 48, 'Depth', 5, 'Time', 1, 'Colors', 1));

            mibModel.setLockedState(1, 'labels', false);

            testCase.verifyClass(dataset.labels, 'core.MibLabels63');
            testCase.verifyTrue(dataset.labels.exists);
        end

        function requestForTheCurrentStateChangesNothing(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel();
            labelsBefore = mibModel.I{1}.labels.data;

            status = mibModel.setLockedState(1, 'labels', false);

            testCase.verifyTrue(status, 'already unlocked');
            testCase.verifyEqual(mibModel.I{1}.labels.data, labelsBefore, 'the model is kept');
        end

        function moveIntoDisabledSelectionIsRefused(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.setLockedState(1, 'labels', true);
            refusals = 0;
            listener = addlistener(mibModel, 'ShowErrorDialog', @(~, ~) countRefusal());
            testCase.addTeardown(@() delete(listener));

            BatchOpt = struct('showWaitbar', false, 'SelectedAddToMaterial', '1', 'id', 1);
            mibModel.moveLayers('selection', 'labels', '3D, Stack', 'add', BatchOpt);

            testCase.verifyEqual(refusals, 1, 'a batch run reports the lock');
            testCase.verifyFalse(logical(mibModel.I{1}.enableSelection), 'and does not unlock');

            function countRefusal()
                refusals = refusals + 1;
            end
        end
    end
end
