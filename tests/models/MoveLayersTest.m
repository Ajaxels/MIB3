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
%   5. The packed uint16 layout (labels16383) gives the same result as the uint8
%      one for every move operation, action and restriction.

    properties (TestParameter)
        moveMethod = {'moveSelectionToMaskDataset', 'moveMaskToSelectionDataset', ...
            'moveSelectionToModelDataset', 'moveModelToSelectionDataset', ...
            'moveMaskToModelDataset', 'moveModelToMaskDataset'};
        actionType = {'add', 'remove', 'replace'};
        % [selected_sw maskedAreaSw]: restrict to the selected material and/or the mask
        restriction = struct('none', [0 0], 'material', [1 0], 'mask', [0 1], 'both', [1 1]);
    end

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

            % uint8 saturated subtraction - matches the implementation's arithmetic
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

    methods (Test, TestTags = {'Unit'})
        % -----------------------------------------------------------------
        % Packed uint16 layout (labels16383) against the uint8 one
        % -----------------------------------------------------------------

        function packedLayoutsAgree(testCase, moveMethod, actionType, restriction)
            % Both models start from the same random layers; labels16383 holds 300
            % and 16383 where labels63 holds 5 and 6 (see buildSyntheticModel).
            % Material 1 is moved from and material 2 added to, so every bit
            % position of the uint16 layout is exercised against the uint8 result.
            dims = [32 32 4];
            [model63, ~]    = mibtest.helpers.buildSyntheticModel('modelType', 'labels63', 'dims', dims);
            [model16383, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels16383', 'dims', dims);
            moveOpts = struct('contSelIndex', 1, 'contAddIndex', 2, ...
                'selected_sw', logical(restriction(1)), 'maskedAreaSw', logical(restriction(2)));

            model63.I{1}.(moveMethod)(actionType, moveOpts);
            model16383.I{1}.(moveMethod)(actionType, moveOpts);

            opt = struct('id', 1, 'blockModeSwitch', 0);
            for layer = {'labels', 'mask', 'selection'}
                result63    = squeeze(cell2mat(model63.getData3D(layer{1}, 1, 3, [], opt)));
                result16383 = squeeze(cell2mat(model16383.getData3D(layer{1}, 1, 3, [], opt)));
                if strcmp(layer{1}, 'labels')
                    result16383(result16383 == 300)   = 5;
                    result16383(result16383 == 16383) = 6;
                    result16383 = uint8(result16383);
                end
                testCase.verifyEqual(result16383, result63, ...
                    sprintf('%s(''%s''): the %s layer differs between the uint16 and uint8 layouts', ...
                    moveMethod, actionType, layer{1}));
            end
        end

        function maskRemoveSelection_restrictedToMaterial_matchesUnpacked(testCase)
            % Removing the mask from the selection, restricted to a material, must
            % leave selected voxels outside material-and-mask selected and their
            % labels and mask untouched. The packed path used to set such voxels
            % to 255 (material 63 + mask + selection); the separate-layer model
            % is the reference.
            dims = [32 32 4];
            [model255, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255', 'dims', dims);
            [model63, ~]  = mibtest.helpers.buildSyntheticModel('modelType', 'labels63', 'dims', dims);
            moveOpts = struct('contSelIndex', 1, 'contAddIndex', 1, 'selected_sw', true, 'maskedAreaSw', false);

            model255.I{1}.moveMaskToSelectionDataset('remove', moveOpts);
            model63.I{1}.moveMaskToSelectionDataset('remove', moveOpts);

            opt = struct('id', 1, 'blockModeSwitch', 0);
            for layer = {'labels', 'mask', 'selection'}
                result255 = squeeze(cell2mat(model255.getData3D(layer{1}, 1, 3, [], opt)));
                result63  = squeeze(cell2mat(model63.getData3D(layer{1}, 1, 3, [], opt)));
                testCase.verifyEqual(result63, result255, ...
                    sprintf('the %s layer differs from the separate-layer model', layer{1}));
            end
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
