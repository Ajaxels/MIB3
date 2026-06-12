classdef MaterialsActionsTest < matlab.unittest.TestCase
% Tests for MibModel.materialsActions — Insert, Swap, Reorder via the MibModel wrapper.
%
% Call pattern (batch mode): mibModel.materialsActions([], batchOpt)
%   action = [] and nargin == 3 triggers batch dispatch.
%
% Verification strategies:
%   insertMaterial count  — model grows from 2 to 3 materials
%   insertMaterial name   — inserted name appears at the requested position
%   swapMaterials pixels  — pixel values 1 and 2 are exchanged via wrapper
%   reorderMaterials name — material names follow the permutation vector

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function insertMaterial_increasesCount(testCase)
            mibModel = MaterialsActionsTest.buildModelWithMaterials(2);

            batchOpt.Action         = {'Insert material'};
            batchOpt.MaterialName   = 'inserted';
            batchOpt.MaterialIndex1 = '2';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;

            mibModel.materialsActions([], batchOpt);

            testCase.verifyEqual(numel(mibModel.I{1}.labels.materialNames), 3, ...
                'inserting into a 2-material model must produce 3 materials');
        end

        function insertMaterial_nameAtRequestedPosition(testCase)
            mibModel = MaterialsActionsTest.buildModelWithMaterials(2);

            batchOpt.Action         = {'Insert material'};
            batchOpt.MaterialName   = 'front';
            batchOpt.MaterialIndex1 = '1';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;

            mibModel.materialsActions([], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.labels.materialNames{1}, 'front', ...
                'material inserted at position 1 must appear first in the name list');
        end

        function swapMaterials_exchangesPixels(testCase)
            mibModel = MaterialsActionsTest.buildModelWithMaterials(2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            labelData = zeros(16, 16, 4, 1, 1, 'uint8');
            labelData(1:8,  :, :) = 1;
            labelData(9:16, :, :) = 2;
            mibModel.setData3D({labelData}, 'labels', 1, 3, NaN, opt);

            batchOpt.Action         = {'Swap materials'};
            batchOpt.MaterialIndex1 = '1';
            batchOpt.MaterialIndex2 = '2';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;

            mibModel.materialsActions([], batchOpt);

            result = mibModel.getData3D('labels', 1, 3, NaN, opt);
            testCase.verifyEqual(result{1}(1,1,1),  uint8(2), 'top half must be material 2 after swap');
            testCase.verifyEqual(result{1}(16,1,1), uint8(1), 'bottom half must be material 1 after swap');
        end

        function reorderMaterials_changesNameOrder(testCase)
            mibModel = MaterialsActionsTest.buildModelWithMaterials(3);

            % newOrder '3 1 2': old mat3→slot1, old mat1→slot2, old mat2→slot3
            batchOpt.Action         = {'Reorder materials'};
            batchOpt.MaterialIndex1 = '3 1 2';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;

            mibModel.materialsActions([], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.labels.materialNames{1}, 'mat003', ...
                'first slot must contain the old third material after reorder [3 1 2]');
            testCase.verifyEqual(mibModel.I{1}.labels.materialNames{2}, 'mat001', ...
                'second slot must contain the old first material after reorder [3 1 2]');
        end

    end

    methods (Static, Access = private)

        function mibModel = buildModelWithMaterials(numMaterials)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            mibFolder   = fullfile(fileparts(testsFolder), 'mib');
            rng(0, 'twister');
            imgData  = uint8(randi(255, [16, 16, 4, 1]));
            mibModel = models.MibModel(1, mibFolder);
            mibModel.I{1} = core.MibDataset(imgData, dictionary(), 'Standard', 'labels63');
            mibModel.I{1}.updateBoundingBox([], [0 0 0]);
            mibModel.I{1}.createModel(255);
            for k = 1:numMaterials
                mibModel.I{1}.addMaterial(sprintf('mat%03d', k));
            end
        end

    end
end
