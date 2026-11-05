classdef MibBigDataLockedStateTest < matlab.unittest.TestCase
% MIBBIGDATALOCKEDSTATETEST - the locked state of BigData labels and images.
%
% A locked labels store (core.MibImage.lockedState) refuses every write that
% would change its material bits and keeps the selection and the mask
% editable; a refused write through core.MibDataset.setData2D/3D/4D is reported
% with the LockedWriteRefused event, and models.MibModel.moveLayers refuses a
% move into locked labels before it touches anything. core.MibDataset.getLockedState
% reports the state the GUI shows for each kind of dataset and labels.
%
% Builds a small BigData dataset (600 x 640 x 2, 3 levels) on disk per test,
% so tagged Integration.
%
% See also: core.MibBigDataLabels.setData63, core.MibDataset.getLockedState,
% models.MibModel.setLockedState, models.MibModel.showLockedNotice

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function lockedLabelsRefuseALabelsWrite(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            labels.setData63(testCase.square(2), 'labels', 3, [], struct('pyramidLevel', 1));
            before = MibBigDataLockedStateTest.fullRes(mibModel, 'labels');
            labels.lockedState = true;

            result = labels.setData63(testCase.square(3), 'labels', 3, [], struct('pyramidLevel', 1));

            testCase.verifyFalse(result, 'the write is refused');
            testCase.verifyTrue(labels.lastWriteRefused, 'the refusal is flagged for MibDataset');
            testCase.verifyEqual(MibBigDataLockedStateTest.fullRes(mibModel, 'labels'), before, ...
                'the store keeps its materials');
        end

        function selectionAndMaskStayEditable(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            labels.lockedState = true;

            selectionResult = labels.setData63(testCase.square(1), 'selection', 3, [], struct('pyramidLevel', 1));
            maskResult = labels.setData63(testCase.square(1), 'mask', 3, [], struct('pyramidLevel', 1));

            testCase.verifyTrue(selectionResult && maskResult, 'selection and mask writes go through');
            testCase.verifyFalse(labels.lastWriteRefused);
            testCase.verifyEqual(nnz(MibBigDataLockedStateTest.fullRes(mibModel, 'selection')), 100 * 100);
            testCase.verifyEqual(nnz(MibBigDataLockedStateTest.fullRes(mibModel, 'mask')), 100 * 100);
        end

        function everythingWriteIsJudgedByItsMaterialBits(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            labels.setData63(testCase.square(2), 'labels', 3, [], struct('pyramidLevel', 1));
            packed = labels.getData63('everything', 3, [], struct('pyramidLevel', 1));
            labels.lockedState = true;

            withSelection = bitor(packed, uint8(labels.selectionValue));   % same materials, every voxel selected
            selectionOnly = labels.setData63(withSelection, 'everything', 3, [], struct('pyramidLevel', 1));
            testCase.verifyTrue(selectionOnly, 'an everything write that changes only the flags goes through');

            withOtherMaterial = packed;
            withOtherMaterial(1:10, 1:10, 1) = 3;
            materialChange = labels.setData63(withOtherMaterial, 'everything', 3, [], struct('pyramidLevel', 1));
            testCase.verifyFalse(materialChange, 'an everything write that changes materials is refused');
            labelsAfter = MibBigDataLockedStateTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter, bitand(packed, uint8(labels.materialMask)), ...
                'the materials are as before both writes');
        end

        function moveIntoLockedLabelsChangesNothing(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            labels.setData63(testCase.square(1), 'selection', 3, [], struct('pyramidLevel', 1));
            selectionBefore = MibBigDataLockedStateTest.fullRes(mibModel, 'selection');
            mibModel.setLockedState(1, 'labels', true);

            BatchOpt = struct('showWaitbar', false, 'SelectedAddToMaterial', '4', ...
                'restrictSelectionToMaterial', false, 'restrictSelectionToMask', false, ...
                'blockModeSwitch', false, 'roiId', '-1');
            mibModel.moveLayers('selection', 'labels', '3D, Stack', 'add', BatchOpt);

            testCase.verifyEqual(nnz(MibBigDataLockedStateTest.fullRes(mibModel, 'labels')), 0, ...
                'no material is added');
            testCase.verifyEqual(MibBigDataLockedStateTest.fullRes(mibModel, 'selection'), selectionBefore, ...
                'the selection is not consumed');
        end

        function setData2DReportsARefusedWrite(testCase)
            mibModel = testCase.buildModel();
            dataset = mibModel.I{1};
            dataset.labels.lockedState = true;
            refusedLayers = {};
            listener = addlistener(dataset, 'LockedWriteRefused', @(~, eventData) collect(eventData));
            testCase.addTeardown(@() delete(listener));

            slice = zeros(600, 640, 'uint8');
            slice(1:100, 1:100) = 2;
            dataset.setData2D(slice, 'labels', 1, 3, [], struct('magFactor', 1, 'blockModeSwitch', 0));

            testCase.verifyEqual(refusedLayers, {'labels'}, 'one event per refused write, naming the layer');
            testCase.verifyFalse(dataset.labels.lastWriteRefused, 'the flag is cleared once reported');

            function collect(eventData)
                refusedLayers{end+1} = eventData.Parameters.layer;
            end
        end

        function getLockedStateReportsEachKind(testCase)
            mibModel = testCase.buildModel();
            dataset = mibModel.I{1};

            testCase.verifyEqual(mibModel.I{2}.getLockedState('image'), 'none', 'Standard datasets are not locked');
            testCase.verifyEqual(mibModel.I{2}.getLockedState('labels'), 'none');
            testCase.verifyEqual(dataset.getLockedState('image'), 'locked', 'a BigData image opens locked');
            testCase.verifyEqual(dataset.getLockedState('labels'), 'unlocked', 'a new store starts unlocked');

            testCase.verifyTrue(mibModel.setLockedState(1, 'labels', true));
            testCase.verifyEqual(dataset.getLockedState('labels'), 'locked');
            testCase.verifyTrue(mibModel.setLockedState(1, 'image', false));
            testCase.verifyEqual(dataset.getLockedState('image'), 'unlocked');
            testCase.verifyFalse(mibModel.setLockedState(2, 'labels', true), 'no lock for a Standard dataset');

            editable = dataset.labels;
            for overlayClass = {'core.MibBigDataLabelsZarr2', 'core.MibBigDataLabelsIndex'}
                dataset.labels = feval(overlayClass{1}, [], core.MibImage.initializeImgInfo());
                testCase.verifyEqual(dataset.getLockedState('labels'), 'readOnly', overlayClass{1});
                mibModel.setLockedState(1, 'labels', false);
                testCase.verifyTrue(dataset.labels.lockedState, [overlayClass{1} ' cannot be unlocked']);
            end
            dataset.labels = editable;   % teardown closes the store
        end
    end

    methods (Access = private)
        function mibModel = buildModel(testCase)
            % 600 x 640 x 2 BigData dataset, 3 levels XY only, with an empty uint8 model
            folderFixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            scratch = folderFixture.Folder;
            sourceImage = fullfile(scratch, 'src.zarr3');
            rng(7);
            io.savers.Zarr3Saver(struct()).save(uint8(randi(255, 600, 640, 2)), ...
                struct('pixSize', struct('x', 0.01, 'y', 0.01, 'z', 0.03, 'units', 'um')), sourceImage, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 1], ...
                'Levels', 3, 'DownsampleStrategy', 'XY only'));

            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({sourceImage}, loaderOptions);
            [image, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            mibModel.I{1}.initialize(image, imageInfo, 'BigData');
            mibModel.I{1}.enableSelection = true;

            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.createStore([600 640 2], fullfile(scratch, 'Labels_src.zarr3'), mibModel.I{1}.image.pyramid);
            labels.materialNames = {'1'; '2'; '3'; '4'};
            labels.materialColors = rand(4, 3);
            mibModel.I{1}.labels = labels;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() MibBigDataLockedStateTest.closeQuietly(mibModel));
        end
    end

    methods (Static, Access = private)
        function volume = square(value)
            % full-resolution volume with a 100 x 100 square of the value on slice 1
            volume = zeros(600, 640, 2, 'uint8');
            volume(101:200, 101:200, 1) = value;
        end

        function volume = fullRes(mibModel, type)
            volume = mibModel.I{1}.labels.getData63(type, 3, [], struct('pyramidLevel', 1));
        end

        function closeQuietly(mibModel)
            try
                mibModel.I{1}.labels.closeStore();
            catch
            end
        end
    end
end
