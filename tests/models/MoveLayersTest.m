classdef MoveLayersTest < matlab.unittest.TestCase
% MOVELAYERSTEST - Unit tests for layer-movement operations.
%
% Tests MibDataset.moveSelectionToMaskDataset, moveMaskToSelectionDataset,
% and the MibModel.moveLayers wrapper.
%
% Verifies:
%   1. Destination receives the correct content after each action type.
%   2. Source is cleared (selection→mask) or left intact (mask→selection).
%   3. Image pixel data is never modified by layer moves.
%   4. Labels63 (packed) and Labels255 (separate) paths both work.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % selection → mask  (three action types, labels255)
        % -----------------------------------------------------------------

        function selReplaceMask_labels255_maskBecomesSelection(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.selection(:))), 0);

            moveOpts = MoveLayersTest.plainMoveOpts();
            mibModel.I{1}.moveSelectionToMaskDataset('replace', moveOpts);

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), gt.selection, ...
                'mask must equal the pre-move selection');

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), 0.0, ...
                'selection must be cleared after move');
        end

        function selAddMask_labels255_maskIsUnion(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            moveOpts = MoveLayersTest.plainMoveOpts();
            mibModel.I{1}.moveSelectionToMaskDataset('add', moveOpts);

            expectedMask = bitor(gt.mask, gt.selection);
            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), expectedMask, ...
                'mask must be union of original mask and selection');

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), 0.0);
        end

        function selRemoveMask_labels255_maskReducedBySelection(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            moveOpts = MoveLayersTest.plainMoveOpts();
            mibModel.I{1}.moveSelectionToMaskDataset('remove', moveOpts);

            % uint8 saturated subtraction — matches the implementation's arithmetic
            expectedMask = gt.mask - gt.selection;
            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), expectedMask);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), 0.0);
        end

        % -----------------------------------------------------------------
        % mask → selection  (replace, labels255)
        % -----------------------------------------------------------------

        function maskReplaceSelection_labels255_selectionBecomesMask(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.mask(:))), 0);

            moveOpts = MoveLayersTest.plainMoveOpts();
            mibModel.I{1}.moveMaskToSelectionDataset('replace', moveOpts);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(selResult{1}), gt.mask, ...
                'selection must equal the pre-move mask');

            % mask must be left intact (mask→selection does not clear mask)
            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), gt.mask, ...
                'mask must be unchanged after mask→selection move');
        end

        % -----------------------------------------------------------------
        % Labels63 (packed bits)
        % -----------------------------------------------------------------

        function selReplaceMask_labels63_maskBecomesSelection(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.selection(:))), 0);

            moveOpts = MoveLayersTest.plainMoveOpts();
            mibModel.I{1}.moveSelectionToMaskDataset('replace', moveOpts);

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), gt.selection);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), 0.0);
        end

        % -----------------------------------------------------------------
        % Cross-layer isolation: image must not be touched
        % -----------------------------------------------------------------

        function imagePreservedAfterMoveSelectionToMask(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            imageChecksumBefore = sum(double(gt.image(:)));

            moveOpts = MoveLayersTest.plainMoveOpts();
            mibModel.I{1}.moveSelectionToMaskDataset('replace', moveOpts);

            imageResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imageResult{1}(:))), imageChecksumBefore);
        end

    end

    methods (Test, TestTags = {'Unit'})
        % -----------------------------------------------------------------
        % Integration: through MibModel.moveLayers (BatchOpt path)
        % -----------------------------------------------------------------

        function moveLayers_selToMask_replace_3D(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.selection(:))), 0);

            BatchOptIn.id = 1;
            BatchOptIn.showWaitbar = false;
            mibModel.moveLayers('selection', 'mask', '3D, Stack', 'replace', BatchOptIn);

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), gt.selection);
        end

    end

    methods (Static, Access = private)
        function moveOpts = plainMoveOpts()
            moveOpts.contSelIndex  = 1;
            moveOpts.contAddIndex  = 1;
            moveOpts.selected_sw   = false;
            moveOpts.maskedAreaSw  = false;
        end
    end
end
