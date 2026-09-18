classdef DeepCopyTest < matlab.unittest.TestCase
% DEEPCOPYTEST - Unit tests for MibModel.deepCopyDataset.
%
% deepCopyDataset creates a fully independent copy of a MibDataset -
% handle sub-properties (image, labels, mask, selection) are deep-copied,
% so mutations to the original must not affect the copy and vice versa.
%
% Verification strategies:
%   independence      - mutating the original image after copy must not change
%                       the copy's image; mutating the copy must not change the
%                       original
%   dimensions match  - height, width, depth of copy equal the source
%   install-in-slot   - deepCopyDataset(1, 2, opts) installs copy into I{2}

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function deepCopy_dimensionsMatchSource(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 6]);

            opts.showWaitbar = false;
            opts.UIFigure    = [];
            copyDataset = mibModel.deepCopyDataset(1, [], opts);

            testCase.verifyEqual(copyDataset.image.height, 16);
            testCase.verifyEqual(copyDataset.image.width,  24);
            testCase.verifyEqual(copyDataset.image.depth,   6);
        end

        function deepCopy_mutateOriginal_copyUnchanged(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            opts.showWaitbar = false;
            opts.UIFigure    = [];
            copyDataset = mibModel.deepCopyDataset(1, [], opts);

            % Capture the copy's image before any mutation
            copyImageBefore = copyDataset.image.data;

            % Overwrite the original image with zeros
            zeroImg = zeros(16, 16, 4, 1, 'uint8');
            mibModel.setData3D(zeroImg, 'image', 1, 3, [], opt);

            testCase.verifyEqual(copyDataset.image.data, copyImageBefore, ...
                'zeroing the original must not affect the deep-copied image');
        end

        function deepCopy_mutateCopy_originalUnchanged(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            opts.showWaitbar = false;
            opts.UIFigure    = [];
            copyDataset = mibModel.deepCopyDataset(1, [], opts);

            originalImageBefore = mibModel.I{1}.image.data;

            % Overwrite the copy's image directly
            copyDataset.image.data = zeros(size(copyDataset.image.data), 'uint8');

            testCase.verifyEqual(mibModel.I{1}.image.data, originalImageBefore, ...
                'zeroing the copy must not affect the original image');
        end

        function deepCopy_installIntoSlot_accessibleViaI(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [12 12 3]);

            opts.showWaitbar = false;
            opts.UIFigure    = [];
            mibModel.deepCopyDataset(1, 2, opts);

            testCase.verifyEqual(mibModel.I{2}.image.height, 12, ...
                'installed copy must be accessible via I{2} with correct height');
            testCase.verifyEqual(mibModel.I{2}.image.depth,   3, ...
                'installed copy must be accessible via I{2} with correct depth');
        end

        function deepCopy_installIntoSlot_syncsDatasetsPanelTypeCache(testCase)
            % The Datasets panel's type dropdown reads Sets.datasetTypes
            % (buffers_Callback.m:64), not I{id}.datasetType, so installing a copy
            % without refreshing that entry makes the panel describe the destination
            % by whatever it held before. Duplicating a BigData buffer showed
            % "Standard" for a buffer that really was BigData.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [12 12 3]);

            mibModel.I{1}.datasetType = 'BigData';
            targetSet     = floor((2 - 1) / mibModel.Sets.datasetsInSet) + 1;
            targetLocalId = mod(2 - 1, mibModel.Sets.datasetsInSet) + 1;
            mibModel.Sets.datasetTypes{targetSet, targetLocalId} = 'Standard';

            opts.showWaitbar = false;
            opts.UIFigure    = [];
            mibModel.deepCopyDataset(1, 2, opts);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'BigData', ...
                'the copy carries the source type');
            testCase.verifyEqual(mibModel.Sets.datasetTypes{targetSet, targetLocalId}, ...
                'BigData', 'and the panel cache has to say the same thing');
        end

        function deepCopy_withoutSlot_leavesTypeCacheAlone(testCase)
            % undo/backup take a free-standing copy with toId = []; nothing was
            % installed, so no slot's cache may move.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [12 12 3]);
            mibModel.I{1}.datasetType = 'BigData';
            cacheBefore = mibModel.Sets.datasetTypes;

            opts.showWaitbar = false;
            opts.UIFigure    = [];
            mibModel.deepCopyDataset(1, [], opts);

            testCase.verifyEqual(mibModel.Sets.datasetTypes, cacheBefore);
        end

    end
end
