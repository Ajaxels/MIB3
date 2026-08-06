classdef SaveLoadImageTest < matlab.unittest.TestCase
% Integration tests for MibModel.saveImage('image',...) + loadImages.
%
% Verifies that a synthetic image saved as a TIF stack can be reloaded
% through the batch-mode loadImages path and produces pixel-exact output
% with correct dimensions.
%
% Verification strategies:
%   file created     - saveImage must write an output file to the temp folder
%   pixel round-trip - getData3D on the reloaded dataset matches gt.image exactly
%   dimensions       - height / width / depth are preserved through the round-trip

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function saveLoadImage_tif_pixelRoundtrip(testCase)
            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'image.tif');

            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 24 4]);

            saveOpts.showWaitbar = false;
            mibModel.saveImage('image', outFile, saveOpts);
            testCase.assumeTrue(isfile(outFile), 'saveImage must write image.tif to temp folder');

            [freshModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 24 4]);
            loadOpt.Filenames   = {outFile};
            loadOpt.showWaitbar = false;
            loadOpt.id          = 1;
            freshModel.loadImages('Combine datasets', loadOpt);

            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = freshModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image(:,:,:,1,1)), ...
                'reloaded TIF image must be pixel-exact with the original');
        end

        function saveLoadImage_tif_dimensionsPreserved(testCase)
            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'image.tif');

            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 24 4]);

            saveOpts.showWaitbar = false;
            mibModel.saveImage('image', outFile, saveOpts);
            testCase.assumeTrue(isfile(outFile), 'saveImage must write image.tif to temp folder');

            [freshModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels63', 'dims', [16 24 4]);
            loadOpt.Filenames   = {outFile};
            loadOpt.showWaitbar = false;
            loadOpt.id          = 1;
            freshModel.loadImages('Combine datasets', loadOpt);

            testCase.verifyEqual(freshModel.I{1}.image.height, 16, 'height must survive TIF round-trip');
            testCase.verifyEqual(freshModel.I{1}.image.width,  24, 'width must survive TIF round-trip');
            testCase.verifyEqual(freshModel.I{1}.image.depth,   4, 'depth must survive TIF round-trip');
        end

    end

end
