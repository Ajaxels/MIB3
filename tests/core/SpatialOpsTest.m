classdef SpatialOpsTest < matlab.unittest.TestCase
% SPATIALOPTEST - Unit tests for MibDataset spatial transforms.
%
% Covers: flipDataset, swapSlices, deleteSlice, insertSlice.
%
% Verification strategies:
%   flip  — double-flip = identity (round-trip); single-flip matches flip() builtin
%   swap  — content at exchanged positions matches pre-swap values
%   delete — depth decreases by 1; surviving slices hold expected content
%   insert — depth increases by 1; inserted slice is at the specified position

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % flipDataset — round-trip identity
        % -----------------------------------------------------------------

        function flipHorizontal_doubleFlip_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.flipDataset('Flip horizontally', [], false);
            mibModel.I{1}.flipDataset('Flip horizontally', [], false);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image));
        end

        function flipVertical_doubleFlip_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.flipDataset('Flip vertically', [], false);
            mibModel.I{1}.flipDataset('Flip vertically', [], false);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image));
        end

        function flipZ_doubleFlip_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.flipDataset('Flip Z', [], false);
            mibModel.I{1}.flipDataset('Flip Z', [], false);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image));
        end

        function flipHorizontal_allLayersFlippedConsistently(testCase)
            % Verify that a single flip produces the correct spatial result
            % for image, selection, and mask simultaneously.
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.flipDataset('Flip horizontally', [], false);

            imgResult  = mibModel.getData3D('image',     1, 3, NaN, opt);
            selResult  = mibModel.getData3D('selection', 1, 3, NaN, opt);
            maskResult = mibModel.getData3D('mask',      1, 3, NaN, opt);

            testCase.verifyEqual(squeeze(imgResult{1}),  squeeze(flip(gt.image, 2)));
            testCase.verifyEqual(squeeze(selResult{1}),  flip(gt.selection, 2));
            testCase.verifyEqual(squeeze(maskResult{1}), flip(gt.mask, 2));
        end

        % -----------------------------------------------------------------
        % swapSlices
        % -----------------------------------------------------------------

        function swapSlices_contentExchanged(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            slice1Before = squeeze(gt.image(:, :, 1));
            slice8Before = squeeze(gt.image(:, :, 8));

            mibModel.I{1}.swapSlices(1, 8, 3);

            result     = mibModel.getData3D('image', 1, 3, NaN, opt);
            imageAfter = squeeze(result{1});
            testCase.verifyEqual(imageAfter(:, :, 1), slice8Before, ...
                'position 1 must hold content that was at position 8');
            testCase.verifyEqual(imageAfter(:, :, 8), slice1Before, ...
                'position 8 must hold content that was at position 1');
        end

        function swapSlices_depthUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 8]);

            mibModel.I{1}.swapSlices(2, 6, 3);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 8);
        end

        % -----------------------------------------------------------------
        % deleteSlice
        % -----------------------------------------------------------------

        function deleteSlice_depthDecreasedByOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 8]);

            mibModel.I{1}.deleteSlice(4, 3, struct('showWaitbar', false));

            testCase.verifyEqual(mibModel.I{1}.image.depth, 7);
        end

        function deleteSlice_survivingSlicesHaveCorrectContent(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.deleteSlice(4, 3, struct('showWaitbar', false));

            result     = mibModel.getData3D('image', 1, 3, NaN, opt);
            imageAfter = squeeze(result{1});

            % Slices before the deleted one must be unchanged
            testCase.verifyEqual(imageAfter(:, :, 1:3), squeeze(gt.image(:, :, 1:3)));
            % Slice that was at position 5 is now at position 4
            testCase.verifyEqual(imageAfter(:, :, 4),   squeeze(gt.image(:, :, 5)));
        end

        % -----------------------------------------------------------------
        % insertSlice
        % -----------------------------------------------------------------

        function insertSlice_depthIncreasedByOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 8]);

            newSlice = zeros(16, 16, 'uint8');
            insertOpts.showWaitbar = false;
            insertOpts.silentMode  = true;
            mibModel.I{1}.insertSlice(newSlice, 2, [], insertOpts);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 9);
        end

        function insertSlice_contentAtCorrectPosition(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            newSlice = uint8(ones(16, 16) * 42);   % sentinel value
            insertOpts.showWaitbar = false;
            insertOpts.silentMode  = true;
            mibModel.I{1}.insertSlice(newSlice, 2, [], insertOpts);

            result     = mibModel.getData3D('image', 1, 3, NaN, opt);
            imageAfter = squeeze(result{1});

            testCase.verifyEqual(imageAfter(:, :, 1), squeeze(gt.image(:, :, 1)), ...
                'slice 1 must be unchanged');
            testCase.verifyEqual(imageAfter(:, :, 2), newSlice, ...
                'slice 2 must be the inserted slice');
            testCase.verifyEqual(imageAfter(:, :, 3), squeeze(gt.image(:, :, 2)), ...
                'slice 3 must be what was originally slice 2');
        end

    end
end
