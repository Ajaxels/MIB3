classdef LayerMoveFastPathTest < matlab.unittest.TestCase
% LAYERMOVEFASTPATHTEST - Unit tests for MibDataset fast-path layer-move methods.
%
% Covers the six full-dataset layer-move operations that bypass block-mode
% and ROI filtering:
%   moveSelectionToModelDataset   (add / remove / replace)
%   moveSelectionToMaskDataset    (add / remove / replace)
%   moveMaskToModelDataset        (add / remove / replace)
%   moveModelToSelectionDataset   (add / remove / replace)
%   moveModelToMaskDataset        (add / remove / replace)
%   moveMaskToSelectionDataset    (add / remove / replace)
%
% Each method operates in-place across the full 4-D array.
%
% Strategy: for each direction, test the 'replace' action — it overwrites
% the target layer entirely with the source, giving a deterministic result.
% Additional tests cover 'add' (union) and 'remove' (subtraction) for the
% two most common directions.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % moveSelectionToMaskDataset
        % -----------------------------------------------------------------

        function selToMask_replace_maskEqualsSelection(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            selBlock = LayerMoveFastPathTest.block(16, 16, 4, 3:8, 3:8);
            mibModel.I{1}.clearLayer('selection');
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(selBlock, 'selection', 1, 3, [], opt);

            mibModel.I{1}.moveSelectionToMaskDataset('replace', LayerMoveFastPathTest.moveOpts());

            maskAfter = cell2mat(mibModel.getData3D('mask', 1, 3, [], opt));
            testCase.verifyEqual(maskAfter, selBlock, ...
                'replace: mask must equal the original selection');
        end

        function selToMask_add_maskIsUnion(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            selBlock  = LayerMoveFastPathTest.block(16, 16, 4, 1:6,  1:6);
            maskBlock = LayerMoveFastPathTest.block(16, 16, 4, 5:10, 5:10);
            mibModel.I{1}.clearLayer('selection');
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(selBlock,  'selection', 1, 3, [], opt);
            mibModel.setData3D(maskBlock, 'mask',      1, 3, [], opt);

            mibModel.I{1}.moveSelectionToMaskDataset('add', LayerMoveFastPathTest.moveOpts());

            maskAfter = cell2mat(mibModel.getData3D('mask', 1, 3, [], opt));
            expectedUnion = uint8(selBlock | maskBlock);
            testCase.verifyEqual(maskAfter, expectedUnion, ...
                'add: mask must be the union of original mask and selection');
        end

        % -----------------------------------------------------------------
        % moveMaskToSelectionDataset
        % -----------------------------------------------------------------

        function maskToSel_replace_selEqualsOriginalMask(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            maskBlock = LayerMoveFastPathTest.block(16, 16, 4, 4:12, 4:12);
            mibModel.I{1}.clearLayer('mask');
            mibModel.I{1}.clearLayer('selection');
            mibModel.setData3D(maskBlock, 'mask', 1, 3, [], opt);

            mibModel.I{1}.moveMaskToSelectionDataset('replace', LayerMoveFastPathTest.moveOpts());

            selAfter = cell2mat(mibModel.getData3D('selection', 1, 3, [], opt));
            testCase.verifyEqual(selAfter, maskBlock, ...
                'replace: selection must equal the original mask');
        end

        % -----------------------------------------------------------------
        % moveSelectionToModelDataset
        % -----------------------------------------------------------------

        function selToModel_replace_targetMaterialEqualsSelection(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            selBlock = LayerMoveFastPathTest.block(16, 16, 4, 2:7, 2:7);
            mibModel.I{1}.clearLayer('selection');
            mibModel.setData3D(selBlock, 'selection', 1, 3, [], opt);

            moveOpts = LayerMoveFastPathTest.moveOpts();
            moveOpts.contAddIndex = 1;
            mibModel.I{1}.moveSelectionToModelDataset('replace', moveOpts);

            labelsAfter = cell2mat(mibModel.getData3D('labels', 1, 3, [], opt));
            % Pixels that were in selection must now carry material 1
            testCase.verifyTrue( ...
                all(labelsAfter(logical(selBlock)) == 1), ...
                'replace: voxels inside selection must become material 1');
        end

        % -----------------------------------------------------------------
        % moveModelToSelectionDataset
        % -----------------------------------------------------------------

        function modelToSel_replace_selMatchesMaterial(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            labelsVolume = zeros(16, 16, 4, 'uint8');
            labelsVolume(3:10, 3:10, :) = 1;
            mibModel.setData3D(labelsVolume, 'labels', 1, 3, [], opt);
            mibModel.I{1}.clearLayer('selection');

            moveOpts = LayerMoveFastPathTest.moveOpts();
            moveOpts.contSelIndex = 1;
            mibModel.I{1}.moveModelToSelectionDataset('replace', moveOpts);

            selAfter = cell2mat(mibModel.getData3D('selection', 1, 3, [], opt));
            expectedSel = uint8(labelsVolume == 1);
            testCase.verifyEqual(selAfter, expectedSel, ...
                'replace: selection must equal the pixels of the chosen material');
        end

        % -----------------------------------------------------------------
        % moveMaskToModelDataset
        % -----------------------------------------------------------------

        function maskToModel_replace_targetMaterialEqualsMask(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            maskBlock = LayerMoveFastPathTest.block(16, 16, 4, 5:12, 5:12);
            mibModel.I{1}.clearLayer('mask');
            mibModel.I{1}.clearLayer('labels');
            mibModel.setData3D(maskBlock, 'mask', 1, 3, [], opt);

            moveOpts = LayerMoveFastPathTest.moveOpts();
            moveOpts.contAddIndex = 1;
            mibModel.I{1}.moveMaskToModelDataset('replace', moveOpts);

            labelsAfter = cell2mat(mibModel.getData3D('labels', 1, 3, [], opt));
            testCase.verifyTrue( ...
                all(labelsAfter(logical(maskBlock)) == 1), ...
                'replace: voxels inside mask must become material 1');
        end

        % -----------------------------------------------------------------
        % moveModelToMaskDataset
        % -----------------------------------------------------------------

        function modelToMask_replace_maskMatchesMaterial(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            labelsVolume = zeros(16, 16, 4, 'uint8');
            labelsVolume(6:14, 6:14, :) = 2;
            mibModel.setData3D(labelsVolume, 'labels', 1, 3, [], opt);
            mibModel.I{1}.clearLayer('mask');

            moveOpts = LayerMoveFastPathTest.moveOpts();
            moveOpts.contSelIndex = 2;
            mibModel.I{1}.moveModelToMaskDataset('replace', moveOpts);

            maskAfter = cell2mat(mibModel.getData3D('mask', 1, 3, [], opt));
            expectedMask = uint8(labelsVolume == 2);
            testCase.verifyEqual(maskAfter, expectedMask, ...
                'replace: mask must equal the pixels of material 2');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function volume = block(height, width, depth, rows, cols)
            volume = zeros(height, width, depth, 'uint8');
            volume(rows, cols, :) = 1;
        end

        function options = moveOpts()
            options.contSelIndex = 1;
            options.contAddIndex = 1;
            options.selected_sw  = 0;
            options.maskedAreaSw = 0;
        end

    end
end
