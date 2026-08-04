classdef UndoModelTypeTest < matlab.unittest.TestCase
% UNDOMODELTYPETEST - Unit tests for type-aware undo of model-type changes.
%
% A pixel snapshot of a segmentation layer is only valid for the model type it
% was captured at: a type-63 layer keeps mask and selection in bits 7-8 of
% obj.labels, the larger types keep them as standalone layers. These tests
% cover the two mechanisms that keep undo honest across a type change:
%
%   MibModel.backup('modelLayers', ...) — whole-layer snapshot used by
%       convertModel and stitchModelInstances; restores the layer OBJECTS, so
%       the model type, material names and colours come back with the pixels
%   MibModel.undo model-type guard      — a pixel entry captured at a different
%       model type converts the layer back before it is applied, and keeps the
%       current layers for redo

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % backup('modelLayers') roundtrip
        % -----------------------------------------------------------------

        function modelLayersUndo_restoresModelType(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');

            mibModel.backup('modelLayers', 1, struct('id', 1));
            mibModel.I{1}.convertModel(65535);
            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 65535);

            mibModel.undo();

            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 63);
            testCase.verifyClass(mibModel.I{1}.labels, 'core.MibLabels63');
        end

        function modelLayersUndo_restoresAllThreeLayers(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('modelLayers', 1, struct('id', 1));
            mibModel.I{1}.convertModel(65535);
            % wipe the model after the conversion — undo must bring it back
            mibModel.setData3D(zeros(size(groundTruth.labels), 'uint16'), 'labels', 1, 3, NaN, opt);

            mibModel.undo();

            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('labels',    1, 3, NaN, opt))), groundTruth.labels);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('selection', 1, 3, NaN, opt))), groundTruth.selection);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('mask',      1, 3, NaN, opt))), groundTruth.mask);
        end

        function modelLayersUndo_thenRedo_returnsConvertedModel(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('modelLayers', 1, struct('id', 1));
            mibModel.I{1}.convertModel(65535);

            mibModel.undo();     % undo   -> type 63
            mibModel.undo();     % redo   -> type 65535

            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 65535);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('labels', 1, 3, NaN, opt))), ...
                uint16(groundTruth.labels));
        end

        function modelLayersBackup_skippedWhenEnableSelectionOff(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            mibModel.I{1}.enableSelection = 0;

            mibModel.backup('modelLayers', 1, struct('id', 1));

            testCase.verifyEqual(mibModel.Backup.prevUndoIndex, 0);
        end

        % -----------------------------------------------------------------
        % MibModel.convertModel is undoable
        % -----------------------------------------------------------------

        function convertModel_undo_restoresPreviousType(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.convertModel([], struct('ModelType', {{'65535'}}, 'showWaitbar', false, 'id', 1));
            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 65535);

            mibModel.undo();

            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 63);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('labels', 1, 3, NaN, opt))), groundTruth.labels);
        end

        % -----------------------------------------------------------------
        % stitchModelInstances is undoable
        % -----------------------------------------------------------------

        function stitchInstances_undo_restoresPerSliceModel(testCase)
            [mibModel, groundTruth] = UndoModelTypeTest.buildInstanceStack();
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.stitchModelInstances(struct('Method', {{'graph'}}, 'showWaitbar', false, 'id', 1));
            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 65535);

            mibModel.undo();

            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 63);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('labels',    1, 3, NaN, opt))), groundTruth.labels);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('selection', 1, 3, NaN, opt))), groundTruth.selection);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('mask',      1, 3, NaN, opt))), groundTruth.mask);
        end

        % -----------------------------------------------------------------
        % model-type guard for entries captured before a type change
        % -----------------------------------------------------------------

        function staleEntryAcrossTypeChange_convertsLayerBackAndRestores(testCase)
            % a plain 'selection' backup on a type-63 model is stored as
            % 'everything' (packed uint8); after an unguarded type change it
            % must not be written into the uint16 layer as-is
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('selection', 1, opt);
            mibModel.setData3D(uint8(~logical(groundTruth.selection)), 'selection', 1, 3, NaN, opt);
            mibModel.I{1}.convertModel(65535);   % type change with no backup of its own

            mibModel.undo();

            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 63);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('selection', 1, 3, NaN, opt))), groundTruth.selection);
            testCase.verifyEqual(squeeze(cell2mat(mibModel.getData3D('labels',    1, 3, NaN, opt))), groundTruth.labels);
        end

        function staleEntryAcrossTypeChange_redoReturnsToNewType(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('selection', 1, opt);
            mibModel.I{1}.convertModel(65535);

            mibModel.undo();     % guard converts back to 63
            mibModel.undo();     % redo must return the uint16 layer

            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 65535);
        end

    end

    methods (Static, Access = private)
        function [mibModel, groundTruth] = buildInstanceStack()
            % per-slice 2D instance labels: two columns whose indices swap
            % between slices, as independent 2D predictions would produce
            dims = [32 32 8];
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', dims);

            instanceStack = zeros(dims, 'uint8');
            for sliceNo = 1:dims(3)
                if mod(sliceNo, 2) == 1
                    indexA = 1; indexB = 2;
                else
                    indexA = 2; indexB = 1;
                end
                instanceStack(5:12,  5:12,  sliceNo) = indexA;
                instanceStack(20:28, 20:28, sliceNo) = indexB;
            end

            mibModel.setData3D(instanceStack, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            groundTruth.labels = instanceStack;
        end
    end
end
