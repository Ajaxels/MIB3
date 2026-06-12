classdef SaveLoadLabelsTest < matlab.unittest.TestCase
% Integration tests for MibModel.saveImage('labels',...) + loadModel.
%
% Verifies that material names and raw label pixel values survive a
% save/load round-trip through the Matlab .model format.
%
% Verification strategies:
%   file created      — saveImage must write a .model file to the temp folder
%   material names    — three material names are preserved verbatim after reload
%   pixel values      — the full labels array is pixel-exact with the original

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function saveLoadLabels_materialNamesPreserved(testCase)
            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'Labels_test.model');

            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            mibModel.I{1}.addMaterial('mitochondria');
            mibModel.I{1}.addMaterial('nucleus');
            mibModel.I{1}.addMaterial('vacuole');

            saveOpts.showWaitbar = false;
            mibModel.saveImage('labels', outFile, saveOpts);
            testCase.assumeTrue(isfile(outFile), 'saveImage must write Labels_test.model');

            [freshModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            loadOpt.Filenames   = {outFile};
            loadOpt.showWaitbar = false;
            loadOpt.id          = 1;
            freshModel.loadModel([], loadOpt);

            testCase.verifyEqual(numel(freshModel.I{1}.labels.materialNames), 3, ...
                'three material names must survive the save/load round-trip');
            testCase.verifyEqual(freshModel.I{1}.labels.materialNames{1}, 'mitochondria');
            testCase.verifyEqual(freshModel.I{1}.labels.materialNames{2}, 'nucleus');
            testCase.verifyEqual(freshModel.I{1}.labels.materialNames{3}, 'vacuole');
        end

        function saveLoadLabels_pixelValuesPreserved(testCase)
            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'Labels_pixels.model');

            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            mibModel.I{1}.addMaterial('mat1');
            mibModel.I{1}.addMaterial('mat2');

            saveOpts.showWaitbar = false;
            mibModel.saveImage('labels', outFile, saveOpts);
            testCase.assumeTrue(isfile(outFile), 'saveImage must write Labels_pixels.model');

            [freshModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            loadOpt.Filenames   = {outFile};
            loadOpt.showWaitbar = false;
            loadOpt.id          = 1;
            freshModel.loadModel([], loadOpt);

            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = freshModel.getData3D('labels', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), gt.labels, ...
                'label pixel values must be identical after save/load round-trip');
        end

    end

end
