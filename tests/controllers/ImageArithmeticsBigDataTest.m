classdef ImageArithmeticsBigDataTest < matlab.unittest.TestCase
% IMAGEARITHMETICSBIGDATATEST - Image Arithmetics on a BigData dataset, through the batch path of controllers.ImageArithmetics.
%
% A synthetic OME-Zarr v3 pyramid is opened as a BigData dataset of a headless
% MibModel, an expression is run with
% ``controllers.ImageArithmetics(mibModel, [], BatchOpt)``, and the result is
% compared with the same expression on the whole array in memory. Covers an
% image result in another buffer, channel indexing, an operation along X, a
% coarser level, overwriting the source store, a threshold into the mask, the
% refused expressions (not band-wise, float result) and variables, and the check
% of every buffer an expression names when the active dataset is Standard.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.ImageArithmetics, controllers.BigDataOptions

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function multiplyOpensInAnotherBuffer(testCase)
            % "I = I*2" opens as BigData in container 2; the source buffer is unchanged.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            sourcePath = mibModel.I{1}.image.filename;
            BatchOpt = testCase.arithmeticsBatchOpt('I = I*2', fullfile(scratch, 'double.zarr3'), 'Container 2');
            controllers.ImageArithmetics(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'BigData');
            testCase.verifyEqual(mibModel.I{1}.image.filename, sourcePath);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), volume * 2);
            testCase.verifyEqual(testCase.readImage(mibModel.I{1}), volume, 'the source store must not change');
        end

        function channelIndexingAsOnStandard(testCase)
            % The band is [rows width 1 colors], so I(:,:,:,2) is channel 2 as in getData4D.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 3);
            BatchOpt = testCase.arithmeticsBatchOpt('I(:,:,:,2) = I(:,:,:,3)', fullfile(scratch, 'channel.zarr3'), 'Container 2');
            controllers.ImageArithmetics(mibModel, [], BatchOpt);

            expected = volume;
            expected(:,:,:,2) = volume(:,:,:,3);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), expected);
        end

        function operationAlongXIsAllowed(testCase)
            % A band holds whole rows, so a flip along X gives the whole-image result.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.arithmeticsBatchOpt('I = fliplr(I)', fullfile(scratch, 'fliplr.zarr3'), 'Container 2');
            controllers.ImageArithmetics(mibModel, [], BatchOpt);

            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), flip(volume, 2));
        end

        function coarseLevel(testCase)
            % At s1 the result has the size of level 2 and equals the expression on that level.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.arithmeticsBatchOpt('I = I + 10', fullfile(scratch, 's1.zarr3'), 'Container 2');
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.ImageArithmetics(mibModel, [], BatchOpt);

            levelImage = mibModel.I{1}.image.getData('image', 3, [], struct('pyramidLevel', 2));
            levelImage = reshape(levelImage, size(levelImage, 1), size(levelImage, 2), size(levelImage, 3), size(levelImage, 4));
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), levelImage + 10);
        end

        function overwriteRewritesTheStore(testCase)
            % "Current overwrite (BigData)" of an unlocked image keeps the path and holds the result.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            sourcePath = mibModel.I{1}.image.filename;
            mibModel.setLockedState(1, 'image', false);
            BatchOpt = testCase.arithmeticsBatchOpt('I = 255 - I', fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            controllers.ImageArithmetics(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.filename, sourcePath);
            testCase.verifyEqual(testCase.readImage(mibModel.I{1}), 255 - volume);
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath));
        end

        function thresholdIntoTheMask(testCase)
            % "M = I > 128" replaces the mask of the whole dataset; selection and labels untouched.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            BatchOpt = testCase.arithmeticsBatchOpt('M = I > 128', fullfile(scratch, 'unused.zarr3'), 'Do not open');
            BatchOpt.OutputVariables = 'M';
            controllers.ImageArithmetics(mibModel, [], BatchOpt);

            testCase.verifyTrue(logical(mibModel.I{1}.maskExist));
            levelOne = struct('pyramidLevel', 1);
            testCase.verifyEqual(labels.getData63('mask', 3, [], levelOne), uint8(volume > 128));
            testCase.verifyEqual(nnz(labels.getData63('selection', 3, [], levelOne)), 0);
            testCase.verifyEqual(nnz(labels.getData63('labels', 3, [], levelOne)), 0);
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath), 'a model result writes no store');
        end

        function notBandwiseIsRefused(testCase)
            % Each expression would give another result band by band than on the whole
            % image; it is refused before anything is written.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            expressions = {'I = I - min(I(:))', 'I = I + mean(I(:))', 'I = flip(I, 1)', ...
                'I = circshift(I, 1, 1)', 'I(1:2,:,:,:) = 0', 'I = cumsum(I, 3)', ...
                'I = I + uint8(randi(20, size(I)))', 'I = double(I) / 2', 'I = I(:, 1:10, :, :)', ...
                'I = undefinedFunctionName(I)'};
            for expressionIndex = 1:numel(expressions)
                outputPath = fullfile(scratch, sprintf('refused%d.zarr3', expressionIndex));
                BatchOpt = testCase.arithmeticsBatchOpt(expressions{expressionIndex}, outputPath, 'Container 2');
                testCase.verifyError(@() controllers.ImageArithmetics(mibModel, [], BatchOpt), ...
                    'controllers:ImageArithmetics:bigData', expressions{expressionIndex});
                testCase.verifyFalse(isfolder(outputPath), expressions{expressionIndex});
            end
            testCase.verifyEqual(mibModel.I{2}.image.filename, 'none.tif', 'no buffer may be changed');
        end

        function variablesNotAvailableOnBigData(testCase)
            % Inputs other than the image of this dataset, the model as output, and a
            % result for another buffer are refused.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            outputPath = fullfile(scratch, 'refused.zarr3');
            cases = {'I, I2', 'I', 'I = I + I2';     % another buffer
                     'I, M',  'I', 'I(M==1) = 0';    % the mask
                     'I',     'O', 'O = uint8(I > 128)';
                     'I',     'I2', 'I2 = I * 2';
                     '',      'I', 'I = 1';
                     'I',     '',  'disp(1)'};
            for caseIndex = 1:size(cases, 1)
                BatchOpt = testCase.arithmeticsBatchOpt(cases{caseIndex, 3}, outputPath, 'Container 2');
                BatchOpt.InputVariables = cases{caseIndex, 1};
                BatchOpt.OutputVariables = cases{caseIndex, 2};
                testCase.verifyError(@() controllers.ImageArithmetics(mibModel, [], BatchOpt), ...
                    'controllers:ImageArithmetics:bigData', strjoin(cases(caseIndex, :), ' | '));
            end
            testCase.verifyFalse(isfolder(outputPath));
            testCase.verifyEqual(mibModel.I{2}.image.filename, 'none.tif');
        end

        function standardExpressionNamingBigDataIsRefused(testCase)
            % Active buffer Standard, I2 BigData: reading I2 whole would load it at full
            % resolution, so the run is refused and buffer 1 is unchanged.
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [64 64 4]);
            [bigDataModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            controllers.BigDataOptions.openStoreInBuffer(mibModel, bigDataModel.I{1}.image.filename, 2);
            BatchOpt = testCase.arithmeticsBatchOpt('I = I + I2(1:64, 1:64, 1:4, :)', fullfile(scratch, 'unused.zarr3'), 'Container 3');
            BatchOpt.InputVariables = 'I, I2';
            testCase.verifyError(@() controllers.ImageArithmetics(mibModel, [], BatchOpt), ...
                'controllers:ImageArithmetics:datasetType');
            testCase.verifyEqual(mibModel.I{1}.image.data, groundTruth.image);

            maskInto = testCase.arithmeticsBatchOpt('M2 = I > 100', fullfile(scratch, 'unused.zarr3'), 'Container 3');
            maskInto.OutputVariables = 'M2';
            testCase.verifyError(@() controllers.ImageArithmetics(mibModel, [], maskInto), ...
                'controllers:ImageArithmetics:datasetType', 'a mask written into a BigData buffer');
        end

        function standardDatasetIgnoresBigDataFields(testCase)
            % On a Standard dataset the expression runs in memory as before; the
            % BigData_* fields are ignored and no store is written.
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [64 64 4]);
            scratch = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            BatchOpt = testCase.arithmeticsBatchOpt('I = I*2', fullfile(scratch, 'unused.zarr3'), 'Container 2');
            controllers.ImageArithmetics(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.data, groundTruth.image * 2);
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath));
        end
    end

    methods (Static)
        function BatchOpt = arithmeticsBatchOpt(expression, outputPath, openIn)
            % Batch options of an image expression "I -> I" into a new store at s0.
            BatchOpt = struct('InputVariables', 'I', 'OutputVariables', 'I', 'Expression', expression, ...
                'showWaitbar', false, 'BigData_OutputPath', outputPath, ...
                'BigData_OpenIn', {{openIn}}, 'BigData_PyramidLevel', {{'s0'}});
        end

        function data = readImage(dataset)
            % Level 1 of a BigData image as [H W Z C].
            data = dataset.image.getData('image', 3, [], struct('pyramidLevel', 1));
            data = reshape(data, size(data, 1), size(data, 2), size(data, 3), size(data, 4));
        end
    end
end
