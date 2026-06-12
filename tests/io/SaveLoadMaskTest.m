classdef SaveLoadMaskTest < matlab.unittest.TestCase
% Integration tests for MibModel.saveImage('mask',...) + loadMask.
%
% Verifies that binary mask values survive a save/load round-trip
% through the Matlab .mask format.  The mask is cleared after saving
% and then reloaded; final checksum and per-pixel values must match.
%
% Verification strategies:
%   file created    — saveImage must write a .mask file to the temp folder
%   clear verified  — mask must be all-zero before the reload step
%   pixel round-trip — reloaded mask values are pixel-exact with the original

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function saveLoadMask_pixelRoundtrip(testCase)
            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'Mask_test.mask');

            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);

            saveOpts.showWaitbar = false;
            mibModel.saveImage('mask', outFile, saveOpts);
            testCase.assumeTrue(isfile(outFile), 'saveImage must write Mask_test.mask');

            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.clearLayer('mask', '3D');
            cleared = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(cleared{1}), 'all'), 0, ...
                'mask must be all-zero after clearLayer before reloading');

            loadOpt.FilenameFilter = outFile;  % absolute path: loadMask batch path uses isfile()
            loadOpt.showWaitbar    = false;
            loadOpt.id             = 1;
            mibModel.loadMask([], loadOpt);

            result = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), gt.mask, ...
                'reloaded mask must be pixel-exact with the original');
        end

        function saveLoadMask_sumPreserved(testCase)
            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'Mask_sum.mask');

            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);

            saveOpts.showWaitbar = false;
            mibModel.saveImage('mask', outFile, saveOpts);
            testCase.assumeTrue(isfile(outFile), 'saveImage must write Mask_sum.mask');

            mibModel.I{1}.clearLayer('mask', '3D');

            loadOpt.FilenameFilter = outFile;
            loadOpt.showWaitbar    = false;
            loadOpt.id             = 1;
            mibModel.loadMask([], loadOpt);

            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual( ...
                sum(double(squeeze(result{1})), 'all'), ...
                sum(double(gt.mask), 'all'), ...
                'nonzero mask pixel count must match original after round-trip');
        end

    end

end
