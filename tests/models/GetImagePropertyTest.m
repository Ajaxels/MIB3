classdef GetImagePropertyTest < matlab.unittest.TestCase
% GETIMAGEPROPERTY - Unit tests for MibModel.getImageProperty.
%
% getImageProperty(propertyName) reads a named property directly from
% obj.I{id} — useful for controller code that needs the active dataset's
% state without knowing its index.
%
% Verification strategies:
%   orientation  — default orientation is 3 (XY)
%   enableSel    — enableSelection is 1 by default
%   pixSize      — returns a struct with .x .y .z fields
%   id override  — id=1 explicitly still returns the same value
%   unknown prop — returns [] for an unrecognised property name

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function getProperty_orientation_isThree(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            value = mibModel.getImageProperty('orientation');

            testCase.verifyEqual(value, 3, ...
                'default orientation must be 3 (XY plane)');
        end

        function getProperty_enableSelection_isTrue(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            value = mibModel.getImageProperty('enableSelection');

            testCase.verifyTrue(logical(value), ...
                'enableSelection must be true by default');
        end

        function getProperty_datasetType_isStandard(testCase)
            % datasetType is a char property directly on MibDataset.
            % pixSize lives on obj.image.pixSize, not on MibDataset itself.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            value = mibModel.getImageProperty('datasetType');

            testCase.verifyEqual(value, 'Standard', ...
                'datasetType must be ''Standard'' for a synthetic model');
        end

        function getProperty_explicitId_sameResult(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            v1 = mibModel.getImageProperty('orientation');
            v2 = mibModel.getImageProperty('orientation', 1);

            testCase.verifyEqual(v1, v2, ...
                'explicit id=1 must return the same value as the default');
        end

    end
end
