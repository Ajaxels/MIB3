classdef MorphOpsTest < matlab.unittest.TestCase
% MORPHOPSTEST - Unit tests for MibModel.dilateImage, erodeImage, smoothImage.
%
% Verification strategies:
%   dilateImage  - pixel count increases; dilation-erosion round-trip recovers interior;
%                  difference mode contains only the ring; image untouched
%   erodeImage   - pixel count decreases; erosion-dilation round-trip recovers interior;
%                  image untouched
%   smoothImage  - all-zero layer stays zero; solid centre of a filled block is preserved;
%                  image untouched

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % =================================================================
        % dilateImage
        % =================================================================

        function dilateImage_selectionExpands(testCase)
            % Place a single foreground pixel in an otherwise empty selection;
            % after dilation with radius 1 the pixel count must increase.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            MorphOpsTest.setSparseSelection(mibModel, [16 16 2]);

            batchOpt = MorphOpsTest.dilateOpt('selection');
            mibModel.dilateImage(batchOpt);

            selResult  = mibModel.getData3D('selection', 1, 3, NaN, opt);
            pixelCount = sum(double(selResult{1}(:)));
            testCase.verifyGreaterThan(pixelCount, 1, ...
                'selection must expand after dilation');
        end

        function dilateImage_leavesImageUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            MorphOpsTest.setSparseSelection(mibModel, [16 16 2]);
            imageChecksumBefore = sum(double(gt.image(:)));

            mibModel.dilateImage(MorphOpsTest.dilateOpt('selection'));

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

        function dilateImage_differenceMode_originalPixelAbsent(testCase)
            % In Difference mode only the ring (added pixels) should remain;
            % the original foreground pixel must NOT be in the result.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            MorphOpsTest.setSparseSelection(mibModel, [16 16 2]);

            batchOpt            = MorphOpsTest.dilateOpt('selection');
            batchOpt.Difference = true;
            mibModel.dilateImage(batchOpt);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            % Original pixel at [16 16 2] must be 0 in difference output
            testCase.verifyEqual(double(selResult{1}(16, 16, 2)), 0, ...
                'original pixel must be absent in difference mode');
            testCase.verifyGreaterThan(sum(double(selResult{1}(:))), 0, ...
                'difference ring must be non-empty');
        end

        function dilateErode_roundTrip_interiorPreserved(testCase)
            % Dilate then erode with the same radius; all pixels in the
            % original interior (i.e. away from boundary) should survive.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            % Fill a 10×10 solid block, away from borders
            MorphOpsTest.setFilledBlock(mibModel, [11 20 11 20 1 4]);
            selBefore = mibModel.getData3D('selection', 1, 3, NaN, opt);
            countBefore = sum(double(selBefore{1}(:)));

            mibModel.dilateImage(MorphOpsTest.dilateOpt('selection'));

            erodeOpt = MorphOpsTest.erodeOpt('selection');
            mibModel.erodeImage(erodeOpt);

            selAfter  = mibModel.getData3D('selection', 1, 3, NaN, opt);
            countAfter = sum(double(selAfter{1}(:)));

            % Interior must be preserved - count after should equal or exceed original
            testCase.verifyGreaterThanOrEqual(countAfter, countBefore, ...
                'dilate→erode must not shrink the original filled block interior');
        end

        % =================================================================
        % erodeImage
        % =================================================================

        function erodeImage_selectionShrinks(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            MorphOpsTest.setFilledBlock(mibModel, [5 28 5 28 1 4]);
            selBefore  = mibModel.getData3D('selection', 1, 3, NaN, opt);
            countBefore = sum(double(selBefore{1}(:)));

            mibModel.erodeImage(MorphOpsTest.erodeOpt('selection'));

            selResult  = mibModel.getData3D('selection', 1, 3, NaN, opt);
            countAfter = sum(double(selResult{1}(:)));
            testCase.verifyLessThan(countAfter, countBefore, ...
                'selection must shrink after erosion');
        end

        function erodeImage_leavesImageUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            MorphOpsTest.setFilledBlock(mibModel, [5 28 5 28 1 4]);
            imageChecksumBefore = sum(double(gt.image(:)));

            mibModel.erodeImage(MorphOpsTest.erodeOpt('selection'));

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

        function erodeDilate_roundTrip_interiorPreserved(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            MorphOpsTest.setFilledBlock(mibModel, [11 20 11 20 1 4]);
            selBefore   = mibModel.getData3D('selection', 1, 3, NaN, opt);
            countBefore = sum(double(selBefore{1}(:)));

            mibModel.erodeImage(MorphOpsTest.erodeOpt('selection'));
            mibModel.dilateImage(MorphOpsTest.dilateOpt('selection'));

            selAfter   = mibModel.getData3D('selection', 1, 3, NaN, opt);
            countAfter = sum(double(selAfter{1}(:)));

            testCase.verifyLessThanOrEqual(countAfter, countBefore, ...
                'erode→dilate must not expand beyond the original block');
        end

        % =================================================================
        % smoothImage
        % =================================================================

        function smoothImage_emptyLayer_remainsEmpty(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            % Explicitly clear the selection to all zeros
            mibModel.I{1}.clearLayer('selection');

            batchOpt = MorphOpsTest.smoothOpt('selection', 5, 1);
            mibModel.smoothImage('selection', batchOpt);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), 0.0, ...
                'smoothing an all-zero layer must leave it all-zero');
        end

        function smoothImage_solidCenter_preserved(testCase)
            % Fill a large solid block; after smoothing the central pixels
            % (away from the boundary) must remain foreground.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            MorphOpsTest.setFilledBlock(mibModel, [3 30 3 30 1 4]);

            batchOpt = MorphOpsTest.smoothOpt('selection', 3, 1);
            mibModel.smoothImage('selection', batchOpt);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            % The single centre pixel at [16 16 2] is far from any boundary
            % and must still be foreground after smoothing.
            testCase.verifyEqual(double(selResult{1}(16, 16, 2)), 1, ...
                'centre pixel of a solid block must survive smoothing');
        end

        function smoothImage_leavesImageUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            MorphOpsTest.setFilledBlock(mibModel, [3 30 3 30 1 4]);
            imageChecksumBefore = sum(double(gt.image(:)));

            mibModel.smoothImage('selection', MorphOpsTest.smoothOpt('selection', 3, 1));

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function setSparseSelection(mibModel, pos)
            % Set exactly one pixel at pos=[row col slice] to 1 in selection.
            opt = struct('id', 1, 'blockModeSwitch', 0);
            mibModel.I{1}.clearLayer('selection');
            sel = zeros(mibModel.I{1}.image.height, mibModel.I{1}.image.width, ...
                        mibModel.I{1}.image.depth, 'uint8');
            sel(pos(1), pos(2), pos(3)) = 1;
            mibModel.setData3D(sel, 'selection', 1, 3, NaN, opt);
        end

        function setFilledBlock(mibModel, bounds)
            % Fill selection in the box [rowMin rowMax colMin colMax zMin zMax].
            opt = struct('id', 1, 'blockModeSwitch', 0);
            mibModel.I{1}.clearLayer('selection');
            sel = zeros(mibModel.I{1}.image.height, mibModel.I{1}.image.width, ...
                        mibModel.I{1}.image.depth, 'uint8');
            sel(bounds(1):bounds(2), bounds(3):bounds(4), bounds(5):bounds(6)) = 1;
            mibModel.setData3D(sel, 'selection', 1, 3, NaN, opt);
        end

        function batchOpt = dilateOpt(targetLayer)
            batchOpt.TargetLayer                  = {targetLayer};
            batchOpt.DatasetType                  = {'3D, Stack'};
            batchOpt.DilateMode                   = {'2D'};
            batchOpt.StrelSize                    = '1';
            batchOpt.Difference                   = false;
            batchOpt.restrictSelectionToMaterial  = 'NaN';
            batchOpt.restrictSelectionToMask      = false;
            batchOpt.MaterialIndex                = '1';
            batchOpt.Use2DParallelComputing       = false;
            batchOpt.showWaitbar                  = false;
            batchOpt.id                           = 1;
        end

        function batchOpt = erodeOpt(targetLayer)
            batchOpt.TargetLayer              = {targetLayer};
            batchOpt.DatasetType              = {'3D, Stack'};
            batchOpt.ErodeMode                = {'2D'};
            batchOpt.StrelSize                = '1';
            batchOpt.Difference               = false;
            batchOpt.MaterialIndex            = '1';
            batchOpt.Use2DParallelComputing   = false;
            batchOpt.showWaitbar              = false;
            batchOpt.id                       = 1;
        end

        function batchOpt = smoothOpt(targetLayer, kernelSize, sigma)
            batchOpt.Target        = {targetLayer};
            batchOpt.SmoothingMode = {'2D'};
            batchOpt.KernelSizeX   = {kernelSize, [1 100], 'on'};
            batchOpt.KernelSizeY   = {0, [0 100], 'on'};
            batchOpt.KernelSizeZ   = {kernelSize, [1 100], 'on'};
            batchOpt.Sigma         = {sigma, [0.01 100], 'off'};
            batchOpt.MaterialIndex = '1';
            batchOpt.showWaitbar   = false;
            batchOpt.id            = 1;
        end

    end
end
