classdef SetPixSizeTest < matlab.unittest.TestCase
% SETPIXSIZETEST - Unit tests for MibDataset.setPixSize.
%
% setPixSize propagates a new pixSize struct to all dataset layers
% (image, labels, mask, selection). The authoritative copy to read back is
% obj.image.pixSize.
%
% Verification strategies:
%   scalar update   - setting a new x/y/z updates obj.image.pixSize
%   units update    - units and tunits fields are propagated
%   all layers sync - after setPixSize, all layers hold the same pixSize

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function setPixSize_updatesXYZ(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            newPix = mibModel.I{1}.image.pixSize;
            newPix.x = 0.125;
            newPix.y = 0.125;
            newPix.z = 0.500;
            mibModel.I{1}.setPixSize(newPix);

            testCase.verifyEqual(mibModel.I{1}.image.pixSize.x, 0.125, 'AbsTol', 1e-10);
            testCase.verifyEqual(mibModel.I{1}.image.pixSize.y, 0.125, 'AbsTol', 1e-10);
            testCase.verifyEqual(mibModel.I{1}.image.pixSize.z, 0.500, 'AbsTol', 1e-10);
        end

        function setPixSize_updatesUnits(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            newPix = mibModel.I{1}.image.pixSize;
            newPix.units  = 'nm';
            newPix.tunits = 'ms';
            mibModel.I{1}.setPixSize(newPix);

            testCase.verifyEqual(mibModel.I{1}.image.pixSize.units,  'nm');
            testCase.verifyEqual(mibModel.I{1}.image.pixSize.tunits, 'ms');
        end

        function setPixSize_labelsLayerSynced(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            newPix = mibModel.I{1}.image.pixSize;
            newPix.x = 0.05;
            mibModel.I{1}.setPixSize(newPix);

            testCase.verifyEqual(mibModel.I{1}.labels.pixSize.x, 0.05, 'AbsTol', 1e-10, ...
                'labels layer must hold the updated pixSize after setPixSize');
        end

    end
end
