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

        % -----------------------------------------------------------------
        % insertEmptySlice (MibModel level)
        % -----------------------------------------------------------------

        function insertEmptySlice_depthIncreasedByOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            batchOpt.Dimension       = {'depth'};
            batchOpt.InsertPosition  = {3, [0, 8], 'on'};
            batchOpt.NumberOfSlices  = {1, [1, 100], 'on'};
            batchOpt.BackgroundColor = {0, [0, 255], 'on'};
            batchOpt.showWaitbar     = false;
            batchOpt.id              = 1;
            mibModel.insertEmptySlice(batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 9, ...
                'inserting one slice must increase depth by 1');
        end

        function insertEmptySlice_atBeginning_insertedSliceIsBackground(testCase)
            % InsertPosition = 1 places a new blank slice before all existing ones.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.Dimension       = {'depth'};
            batchOpt.InsertPosition  = {1, [0, 8], 'on'};
            batchOpt.NumberOfSlices  = {1, [1, 100], 'on'};
            batchOpt.BackgroundColor = {0, [0, 255], 'on'};
            batchOpt.showWaitbar     = false;
            batchOpt.id              = 1;
            mibModel.insertEmptySlice(batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(double(result{1}(8, 8, 1)), 0, ...
                'inserted slice must have background (zero) pixel values');
        end

        % -----------------------------------------------------------------
        % copySwapSlice (MibModel level)
        % -----------------------------------------------------------------

        function copySwapSlice_replace_depthUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            batchOpt.Mode        = {'replace'};
            batchOpt.SourceSlice = {2, [1, 8], 'on'};
            batchOpt.TargetSlice = {6, [1, 8], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.copySwapSlice([], [], [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 8, ...
                'replace mode must not change depth');
        end

        function copySwapSlice_replace_contentCopied(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            slice2Before = squeeze(gt.image(:, :, 2));

            batchOpt.Mode        = {'replace'};
            batchOpt.SourceSlice = {2, [1, 8], 'on'};
            batchOpt.TargetSlice = {6, [1, 8], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.copySwapSlice([], [], [], batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}(:, :, 6)), slice2Before, ...
                'target slot must receive a copy of the source slice');
        end

        function copySwapSlice_swap_bothSlotsExchanged(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            slice2Before = squeeze(gt.image(:, :, 2));
            slice6Before = squeeze(gt.image(:, :, 6));

            batchOpt.Mode        = {'swap'};
            batchOpt.SourceSlice = {2, [1, 8], 'on'};
            batchOpt.TargetSlice = {6, [1, 8], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.copySwapSlice([], [], [], batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}(:, :, 2)), slice6Before, ...
                'slot 2 must hold the original content of slot 6 after swap');
            testCase.verifyEqual(squeeze(result{1}(:, :, 6)), slice2Before, ...
                'slot 6 must hold the original content of slot 2 after swap');
        end

        % -----------------------------------------------------------------
        % cropDataset (MibDataset level)
        % -----------------------------------------------------------------

        function cropDataset_dimensionsReduced(testCase)
            % cropF = [x1, y1, dx, dy, z1, dz]; x=cols, y=rows.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [64 64 8]);

            options.showWaitbar = false;
            options.UIFigure    = [];
            cropF = [5, 5, 32, 32, 2, 4];
            result = mibModel.I{1}.cropDataset(cropF, options);

            testCase.verifyEqual(result, 1, 'cropDataset must return 1 on success');
            testCase.verifyEqual(mibModel.I{1}.image.width,  32, 'width must equal dx');
            testCase.verifyEqual(mibModel.I{1}.image.height, 32, 'height must equal dy');
            testCase.verifyEqual(mibModel.I{1}.image.depth,   4, 'depth must equal dz');
        end

        function cropDataset_contentPreserved(testCase)
            % Slice 1 of the cropped result must match the selected subregion
            % of the original (x=cols 5:36, y=rows 5:36, original z-index 2).
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [64 64 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            expectedSlice = squeeze(gt.image(5:36, 5:36, 2));

            options.showWaitbar = false;
            options.UIFigure    = [];
            mibModel.I{1}.cropDataset([5, 5, 32, 32, 2, 4], options);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}(:, :, 1)), expectedSlice, ...
                'first slice of cropped dataset must match the selected region');
        end

        % -----------------------------------------------------------------
        % rotateDataset (MibDataset level)
        % -----------------------------------------------------------------

        function rotateDataset_rotate4x90_isIdentity(testCase)
            % Four 90-degree clockwise rotations must recover the original.
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            for k = 1:4
                mibModel.I{1}.rotateDataset('Rotate 90 degrees', [], false);
            end

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image), ...
                '4 × 90-degree rotations must recover the original image');
        end

        % -----------------------------------------------------------------
        % Multi-channel (numColors=2) — transforms must apply to all channels
        % -----------------------------------------------------------------

        function flip_twoChannel_bothChannelsTransformed(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.flipDataset('Flip horizontally', [], false);

            result1 = mibModel.getData3D('image', 1, 3, 1, opt);
            result2 = mibModel.getData3D('image', 1, 3, 2, opt);

            testCase.verifyEqual(squeeze(result1{1}), squeeze(flip(gt.image(:,:,:,1), 2)), ...
                'channel 1 must be flipped horizontally');
            testCase.verifyEqual(squeeze(result2{1}), squeeze(flip(gt.image(:,:,:,2), 2)), ...
                'channel 2 must be flipped horizontally');
        end

        function deleteSlice_twoChannel_colorCountPreserved(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8], 'numColors', 2);

            mibModel.I{1}.deleteSlice(4, 3, struct('showWaitbar', false));

            testCase.verifyEqual(mibModel.I{1}.image.colors, 2, ...
                'deleteSlice must not change the channel count');
            testCase.verifyEqual(mibModel.I{1}.image.depth, 7, ...
                'deleteSlice must reduce depth by 1');
        end

        function cropDataset_twoChannel_bothChannelsInSubregion(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [64 64 8], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            options.showWaitbar = false;
            options.UIFigure    = [];
            mibModel.I{1}.cropDataset([5, 5, 32, 32, 2, 4], options);

            result1 = mibModel.getData3D('image', 1, 3, 1, opt);
            result2 = mibModel.getData3D('image', 1, 3, 2, opt);

            testCase.verifyEqual(squeeze(result1{1}(:,:,1)), squeeze(gt.image(5:36, 5:36, 2, 1)), ...
                'channel 1: first cropped slice must match original subregion');
            testCase.verifyEqual(squeeze(result2{1}(:,:,1)), squeeze(gt.image(5:36, 5:36, 2, 2)), ...
                'channel 2: first cropped slice must match original subregion');
        end

        function rotateDataset_twoChannel_rotate4x90_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            for k = 1:4
                mibModel.I{1}.rotateDataset('Rotate 90 degrees', [], false);
            end

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(result{1}, gt.image(:,:,:,:,1), ...
                '4 × 90° rotations on a 2-channel dataset must recover the original');
        end

    end
end
