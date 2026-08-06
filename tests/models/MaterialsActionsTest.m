classdef MaterialsActionsTest < matlab.unittest.TestCase
% Tests for MibModel.materialsActions - Insert, Swap, Reorder, and Import via
% the MibModel wrapper, plus a focused unit test for
% MibBigDataLabels.findClosestLevelForImport.
%
% Call pattern (batch mode): mibModel.materialsActions([], batchOpt)
%   action = [] and nargin == 3 triggers batch dispatch.
%
% Verification strategies:
%   insertMaterial count  - model grows from 2 to 3 materials
%   insertMaterial name   - inserted name appears at the requested position
%   swapMaterials pixels  - pixel values 1 and 2 are exchanged via wrapper
%   reorderMaterials name - material names follow the permutation vector
%   importMaterial        - new material slots + pixel overwrite from a .model file
%   findClosestLevelForImport - pyramid level selection by size ratio

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

        function importMaterial_addsSelectedMaterialFromFile(testCase)
            % Target: a fresh 1-material model (all pixels background/0).
            mibModel = MaterialsActionsTest.buildModelWithMaterials(1);

            % Source: 16×16×4 volume - top half (rows 1..8) = mat 1,
            %         bottom half (rows 9..16) = mat 2.
            sourceLabels = zeros(16, 16, 4, 'uint8');
            sourceLabels(1:8,  :, :) = 1;
            sourceLabels(9:16, :, :) = 2;
            sourceMaterialNames  = {'source_mat1', 'source_mat2'};
            sourceMaterialColors = [1 0 0; 0 1 0];   % red for mat1, green for mat2

            sourceFilename = [tempname, '.model'];
            MaterialsActionsTest.buildSourceModelFile(sourceFilename, sourceLabels, ...
                sourceMaterialNames, sourceMaterialColors);

            % Import ONLY source material 2 (the bottom half).
            batchOpt.Filename        = sourceFilename;
            batchOpt.MaterialIndices = '2';
            batchOpt.showWaitbar     = false;
            batchOpt.id              = 1;

            mibModel.importMaterial(batchOpt);

            % Cleanup temp file before assertions so a test failure does not leak it.
            if isfile(sourceFilename); delete(sourceFilename); end

            % --- Material slot assertions ---
            % Original mat001 (index 1) + imported source_mat2 (index 2) = 2 slots.
            testCase.verifyEqual(numel(mibModel.I{1}.labels.materialNames), 2, ...
                'importing 1 material into a 1-material model must yield 2 total materials');
            testCase.verifyEqual(mibModel.I{1}.labels.materialNames{2}, 'source_mat2', ...
                'the imported material slot must carry the source material name');

            % Source color for material 2 was [0 1 0]; verify it was transferred.
            importedColor = mibModel.I{1}.labels.materialColors(2, :);
            testCase.verifyEqual(importedColor, [0 1 0], 'AbsTol', 1e-6, ...
                'the imported material slot must carry the source material color');

            % --- Pixel assertions ---
            opt = struct('id', 1, 'blockModeSwitch', 0);
            resultLabels = mibModel.getData3D('labels', 1, 3, NaN, opt);
            resultLabels = resultLabels{1};

            % Rows 9..16 in the source were labeled 2; those voxels must now
            % be target index 2 (currentCount 1 + loop index 1 = 2).
            testCase.verifyEqual(resultLabels(9, 1, 1), uint8(2), ...
                'source-material-2 voxels must be written as target index 2');

            % Rows 1..8 in the source were labeled 1 (NOT imported); the
            % target model started all-background so those must remain 0.
            testCase.verifyEqual(resultLabels(1, 1, 1), uint8(0), ...
                'non-imported source-material-1 voxels must remain background (0)');
        end

        function findClosestLevelForImport_returnsNearestLevel(testCase)
            % Build a stub MibBigDataLabels - only the two size/scale-factor
            % tables need to be set; no on-disk zarr store is required.
            labels = core.MibBigDataLabels();
            %   Level 1 (finest):  100×100×10  scale [1 1 1]
            %   Level 2 (mid):      50× 50×10  scale [2 2 1]
            %   Level 3 (coarsest): 25× 25×10  scale [4 4 1]
            labels.modelLevelSizes   = [100 100 10; 50 50 10; 25 25 10];
            labels.modelScaleFactors = [1 1 1; 2 2 1; 4 4 1];

            % Source at full resolution → magFactor = 100/100 = 1.0 → level 1.
            [levelIdx, levelSize] = labels.findClosestLevelForImport([100, 100, 10]);
            testCase.verifyEqual(levelIdx, 1, ...
                'source at full resolution must map to pyramid level 1');
            testCase.verifyEqual(levelSize, [100, 100, 10], ...
                'returned levelSize must match modelLevelSizes for level 1');

            % Source at 2× downsampled → magFactor = 100/50 = 2.0 → level 2.
            [levelIdx, ~] = labels.findClosestLevelForImport([50, 50, 10]);
            testCase.verifyEqual(levelIdx, 2, ...
                'source at 2x downsampled must map to pyramid level 2');

            % Source at 4× downsampled → magFactor = 100/25 = 4.0 → level 3.
            [levelIdx, ~] = labels.findClosestLevelForImport([25, 25, 10]);
            testCase.verifyEqual(levelIdx, 3, ...
                'source at 4x downsampled must map to pyramid level 3');

            % Empty sourceDims → must return level 1 without error.
            [levelIdx, ~] = labels.findClosestLevelForImport([]);
            testCase.verifyEqual(levelIdx, 1, ...
                'empty sourceDims must return pyramid level 1 as a safe default');
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

        function buildSourceModelFile(filename, pixelData, materialNames, materialColors)
            % Save a minimal MIB-format .model file readable by MatModelLoader.
            % Variables follow the MIB3/MIB2 native MAT-model convention:
            %   modelVariable        - name of the variable holding the label array
            %   mibModel             - the actual uint8 label pixel array
            %   modelMaterialNames   - cell array of material names
            %   modelMaterialColors  - Nx3 float RGB matrix (values 0..1)
            mibModel            = pixelData;
            modelVariable       = 'mibModel';
            modelMaterialNames  = materialNames;
            modelMaterialColors = materialColors;
            save(filename, 'mibModel', 'modelVariable', ...
                'modelMaterialNames', 'modelMaterialColors', '-mat');
        end

    end
end
