classdef SwapMaterialsTest < matlab.unittest.TestCase
% SWAPMATERIALSTEST - Unit tests for MibDataset.swapMaterials.
%
% swapMaterials exchanges all pixel values equal to material1 with material2
% and vice versa across the full 4-D labels array.
%
% Verification strategies:
%   pixel swap  - a voxel labeled 1 before must be labeled 2 after, and
%                 vice versa
%   zero intact - background voxels (label 0) must not change
%   name swap   - material name strings are exchanged in labels.materialNames
%   depth stable - depth must not change after swap

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function swapMaterials_pixelValuesExchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            % Paint material 1 in top-left, material 2 in bottom-right
            labelsVolume = zeros(16, 16, 4, 'uint8');
            labelsVolume(1:4,  1:4,  :) = 1;
            labelsVolume(13:16, 13:16, :) = 2;
            mibModel.setData3D(labelsVolume, 'labels', 1, 3, [], opt);

            mibModel.I{1}.swapMaterials(1, 2, []);

            result = cell2mat(mibModel.getData3D('labels', 1, 3, [], opt));
            testCase.verifyEqual(result(1, 1, 1),   uint8(2), ...
                'top-left block must be labeled 2 after swap');
            testCase.verifyEqual(result(16, 16, 1), uint8(1), ...
                'bottom-right block must be labeled 1 after swap');
        end

        function swapMaterials_backgroundVoxelsUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            labelsVolume = zeros(16, 16, 4, 'uint8');
            labelsVolume(1:4, 1:4, :) = 1;
            labelsVolume(5:8, 5:8, :) = 2;
            mibModel.setData3D(labelsVolume, 'labels', 1, 3, [], opt);

            mibModel.I{1}.swapMaterials(1, 2, []);

            result = cell2mat(mibModel.getData3D('labels', 1, 3, [], opt));
            % Centre voxel (row 10, col 10) was background - must stay 0
            testCase.verifyEqual(result(10, 10, 1), uint8(0), ...
                'background voxels must not change after swap');
        end

        function swapMaterials_depthUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            mibModel.I{1}.swapMaterials(1, 2, []);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 8, ...
                'depth must not change after swapMaterials');
        end

        function swapMaterials_materialNamesExchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            % Register two named materials so the metadata exists to swap.
            mibModel.I{1}.addMaterial('Alpha');
            mibModel.I{1}.addMaterial('Beta');

            mibModel.I{1}.swapMaterials(1, 2, []);

            names = mibModel.I{1}.labels.materialNames;
            testCase.verifyEqual(names{1}, 'Beta', ...
                'position 1 must hold the original name of material 2 after swap');
            testCase.verifyEqual(names{2}, 'Alpha', ...
                'position 2 must hold the original name of material 1 after swap');
        end

    end
end
