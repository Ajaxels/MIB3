classdef MaterialsTest < matlab.unittest.TestCase
% MATERIALSTEST - Unit tests for material management and model type conversion.
%
% Covers (all at MibDataset / MibLabels level, no GUI):
%   MibDataset.addMaterial     - count/name registration
%   MibDataset.removeMaterial  - count/name removal, pixel remapping
%   MibLabels.renameMaterial   - name update at given index
%   MibLabels.reorderMaterials - metadata permutation
%   MibDataset.convertModel    - class change (63 ↔ 255); round-trip preserves image

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % addMaterial
        % -----------------------------------------------------------------

        function addMaterial_labels255_incrementsCount(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            testCase.verifyEqual(ds.labels.materialsCount, 0);

            ds.addMaterial('Nucleus');

            testCase.verifyEqual(ds.labels.materialsCount, 1);
        end

        function addMaterial_labels255_nameRegistered(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('Nucleus');

            testCase.verifyEqual(ds.labels.materialNames{1}, 'Nucleus');
        end

        function addMaterial_multipleNames_countAndNamesCorrect(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('A');
            ds.addMaterial('B');
            ds.addMaterial('C');

            testCase.verifyEqual(ds.labels.materialsCount, 3);
            % normalise orientation - cell may be row or column vector
            testCase.verifyEqual(ds.labels.materialNames(:), {'A'; 'B'; 'C'});
        end

        function addMaterial_returnsTrue(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            result = ds.addMaterial('Nucleus');

            testCase.verifyTrue(result);
        end

        % -----------------------------------------------------------------
        % renameMaterial
        % -----------------------------------------------------------------

        function renameMaterial_labels255_nameUpdated(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('OldName');

            ds.labels.renameMaterial(1, 'NewName');

            testCase.verifyEqual(ds.labels.materialNames{1}, 'NewName');
        end

        function renameMaterial_onlyTargetChanged(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('A');
            ds.addMaterial('B');
            ds.addMaterial('C');

            ds.labels.renameMaterial(2, 'Renamed');

            testCase.verifyEqual(ds.labels.materialNames{1}, 'A');
            testCase.verifyEqual(ds.labels.materialNames{2}, 'Renamed');
            testCase.verifyEqual(ds.labels.materialNames{3}, 'C');
        end

        % -----------------------------------------------------------------
        % reorderMaterials
        % -----------------------------------------------------------------

        function reorderMaterials_labels255_namesPermuted(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('First');
            ds.addMaterial('Second');
            ds.addMaterial('Third');

            % Move Third to position 1
            ds.labels.reorderMaterials([3 1 2]);

            testCase.verifyEqual(ds.labels.materialNames{1}, 'Third');
            testCase.verifyEqual(ds.labels.materialNames{2}, 'First');
            testCase.verifyEqual(ds.labels.materialNames{3}, 'Second');
        end

        function reorderMaterials_countUnchanged(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('A');
            ds.addMaterial('B');
            ds.labels.reorderMaterials([2 1]);

            testCase.verifyEqual(ds.labels.materialsCount, 2);
        end

        % -----------------------------------------------------------------
        % removeMaterial
        % -----------------------------------------------------------------

        function removeMaterial_labels255_decrementsCount(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('Keep');
            ds.addMaterial('Remove');

            ds.removeMaterial(2, []);

            testCase.verifyEqual(ds.labels.materialsCount, 1);
        end

        function removeMaterial_labels255_nameRemoved(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('Keep');
            ds.addMaterial('Gone');

            ds.removeMaterial(2, []);

            nameList = ds.labels.materialNames;
            testCase.verifyFalse(any(strcmp(nameList, 'Gone')));
        end

        function removeMaterial_labels255_remainingNamePreserved(testCase)
            ds = MaterialsTest.emptyLabels255Dataset();
            ds.addMaterial('Survivor');
            ds.addMaterial('Removed');

            ds.removeMaterial(2, []);

            testCase.verifyEqual(ds.labels.materialNames{1}, 'Survivor');
        end

        % -----------------------------------------------------------------
        % convertModel
        % -----------------------------------------------------------------

        function convertModel_labels63To255_classChanges(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');

            mibModel.I{1}.convertModel(255, []);

            testCase.verifyClass(mibModel.I{1}.labels, 'core.MibLabels');
            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 255);
        end

        function convertModel_labels255To63_classChanges(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');

            mibModel.I{1}.convertModel(63, []);

            testCase.verifyClass(mibModel.I{1}.labels, 'core.MibLabels63');
            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 63);
        end

        function convertModel_labels63To255_imageUnchanged(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            imageChecksumBefore = sum(double(gt.image(:)));

            mibModel.I{1}.convertModel(255, []);

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

        function convertModel_labels63To255AndBack_imageUnchanged(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            imageChecksumBefore = sum(double(gt.image(:)));

            mibModel.I{1}.convertModel(255, []);
            mibModel.I{1}.convertModel(63, []);

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

        % -----------------------------------------------------------------
        % convertModel / createModel - packed uint16 instance model (16383)
        % -----------------------------------------------------------------

        function convertModel_labels63To16383_keepsLayers(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');

            mibModel.I{1}.convertModel(16383, []);

            labels = mibModel.I{1}.labels;
            testCase.verifyClass(labels, 'core.MibLabels63');
            testCase.verifyEqual(labels.containerClass, 'uint16');
            testCase.verifyEqual(labels.maxMaterials, 16383);
            testCase.verifyTrue(labels.objects3D, 'materials upgraded to instances span the volume');
            MaterialsTest.verifyLayers(testCase, mibModel, uint16(gt.labels), gt.mask, gt.selection);
        end

        function convertModel_labels16383To65535AndBack_keepsLayers(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels16383');

            mibModel.I{1}.convertModel(65535, []);
            testCase.verifyClass(mibModel.I{1}.labels, 'core.MibLabels');
            MaterialsTest.verifyLayers(testCase, mibModel, gt.labels, gt.mask, gt.selection);

            mibModel.I{1}.convertModel(16383, []);
            testCase.verifyEqual(mibModel.I{1}.labels.containerClass, 'uint16');
            MaterialsTest.verifyLayers(testCase, mibModel, gt.labels, gt.mask, gt.selection);
        end

        function convertModel_labels16383To63_clipsAboveTopIndex(testCase)
            % MibDataset.convertModel clips (undo relies on it); indices above 63
            % land on 63 and must not spill into the mask/selection bits
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels16383');

            mibModel.I{1}.convertModel(63, []);

            testCase.verifyEqual(mibModel.I{1}.labels.containerClass, 'uint8');
            MaterialsTest.verifyLayers(testCase, mibModel, uint8(min(gt.labels, 63)), gt.mask, gt.selection);
        end

        function createModel_16383FromLabels63_keepsMaskAndSelection(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');

            mibModel.I{1}.createModel(16383);

            testCase.verifyEqual(mibModel.I{1}.labels.containerClass, 'uint16');
            testCase.verifyEqual(mibModel.I{1}.labels.materialNames, {'1'; '2'});
            MaterialsTest.verifyLayers(testCase, mibModel, zeros(size(gt.labels), 'uint16'), gt.mask, gt.selection);
        end

        function countMaterials_labels16383_scansIndices(testCase)
            % an instance model keeps two name slots; the count is the highest index
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', 'labels16383');

            testCase.verifyEqual(mibModel.I{1}.labels.countMaterials(), 16383);
        end

    end

    methods (Static, Access = private)
        function verifyLayers(testCase, mibModel, labels, mask, selection)
            % compare the three segmentation layers with their expected arrays
            opt = struct('id', 1, 'blockModeSwitch', 0);
            labelsResult    = squeeze(cell2mat(mibModel.getData3D('labels', 1, 3, [], opt)));
            maskResult      = squeeze(cell2mat(mibModel.getData3D('mask', 1, 3, [], opt)));
            selectionResult = squeeze(cell2mat(mibModel.getData3D('selection', 1, 3, [], opt)));
            testCase.verifyEqual(labelsResult, labels, 'labels differ');
            testCase.verifyEqual(maskResult, mask, 'mask differs');
            testCase.verifyEqual(selectionResult, selection, 'selection differs');
        end
    end

    methods (Static, Access = private)
        function ds = emptyLabels255Dataset()
            ds = core.MibDataset(uint8(zeros(16, 16, 4, 1)), dictionary(), ...
                'Standard', 'labels63');
            ds.createModel(255);
        end
    end
end
