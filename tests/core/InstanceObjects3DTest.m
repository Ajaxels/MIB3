classdef InstanceObjects3DTest < matlab.unittest.TestCase
% INSTANCEOBJECTS3DTEST - Tests for core.MibLabels.objects3D, the 2D/3D nature of an instance model.
%
% An instance model (65535/4294967295) numbers its objects either through the
% whole volume (stitched, 3D) or afresh on every slice (2D). Nothing in the
% array tells the two apart, so the flag has to be set wherever a model is made
% and travel with the model file. What it changes is where "the next free
% index" is looked for: in the whole model, or on the shown slice only.
%
% The interactive paths - the checkbox callback, the question asked when a
% model without the flag is opened, and Squeeze (MibModel.removeMaterial), which ends in
% MibModel.addMaterial with a progress dialog - need a window and are not
% covered here.
%
% See also: core.MibLabels, core.MibDataset.addMaterial, core.MibDataset.loadModel

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Static, Access = private)
        function mibModel = buildInstanceModel(objects3D)
            % Slice 1 holds objects 1-3, slice 3 holds objects 1-9: the shape of
            % an unstitched model, where every slice numbers from 1 again.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [16 24 4]);
            volume = zeros(16, 24, 4, 'uint16');
            volume(2:4, 2:4, 1) = 1;  volume(2:4, 8:10, 1) = 2;  volume(8:10, 2:4, 1) = 3;
            for objectId = 1:9
                volume(objectId + 1, 12:14, 3) = objectId;
            end
            mibModel.setData3D(volume, 'labels', 1, 3, [], struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.labels.countMaterials();
            mibModel.I{1}.labels.objects3D = objects3D;
            mibModel.I{1}.slices{3} = [1, 1];
        end
    end

    methods (Test, TestTags = {'Unit'})

        function aNewInstanceModelHas2DObjects(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [16 24 4]);
            testCase.verifyFalse(mibModel.I{1}.labels.objects3D);
        end

        function addMaterialWith3DObjectsLooksAtTheWholeModel(testCase)
            mibModel = InstanceObjects3DTest.buildInstanceModel(true);
            [ok, newIndex] = mibModel.I{1}.addMaterial('', [], []);
            testCase.verifyTrue(ok);
            testCase.verifyEqual(newIndex, 10, 'one above the highest index anywhere');
        end

        function addMaterialWith2DObjectsLooksAtTheShownSliceOnly(testCase)
            mibModel = InstanceObjects3DTest.buildInstanceModel(false);
            [ok, newIndex] = mibModel.I{1}.addMaterial('', [], []);
            testCase.verifyTrue(ok);
            testCase.verifyEqual(newIndex, 4, 'slice 1 holds 1-3');
            testCase.verifyEqual(mibModel.I{1}.labels.materialsCount, 9, ...
                'the count stands for the whole model, which a slice cannot lower');

            mibModel.I{1}.slices{3} = [2, 2];
            [~, newIndex] = mibModel.I{1}.addMaterial('', [], []);
            testCase.verifyEqual(newIndex, 1, 'an empty slice starts from 1');
        end

        function stitchingGives3DObjects(testCase)
            mibModel = InstanceObjects3DTest.buildInstanceModel(false);
            mibModel.I{1}.stitchModelInstances(struct(), []);
            testCase.verifyTrue(mibModel.I{1}.labels.objects3D);
        end

        function perSliceComponentsGive2DObjectsAndVolumeComponents3D(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel('modelType', 'labels255', 'dims', [16 24 4]);
            mibModel.I{1}.convertModel(2.8, []);
            testCase.verifyFalse(mibModel.I{1}.labels.objects3D, '2.8 labels each slice on its own');

            mibModel = mibtest.helpers.buildSyntheticModel('modelType', 'labels255', 'dims', [16 24 4]);
            mibModel.I{1}.convertModel(3.26, []);
            testCase.verifyTrue(mibModel.I{1}.labels.objects3D, '3.26 labels through the volume');
        end

        function aTypeChangeKeepsTheSettingAndMaterialsBecome3D(testCase)
            mibModel = InstanceObjects3DTest.buildInstanceModel(false);
            mibModel.I{1}.convertModel(4294967295, []);
            testCase.verifyFalse(mibModel.I{1}.labels.objects3D, '65535 -> 4294967295 keeps 2D');

            mibModel = mibtest.helpers.buildSyntheticModel('modelType', 'labels255', 'dims', [16 24 4]);
            mibModel.I{1}.convertModel(65535, []);
            testCase.verifyTrue(mibModel.I{1}.labels.objects3D, 'a material spans the volume');
        end
    end

    methods (Test, TestTags = {'Integration'})

        function theSettingTravelsWithTheModelFile(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'Labels_2d.model');

            mibModel = InstanceObjects3DTest.buildInstanceModel(false);
            mibModel.saveImage('labels', outFile, struct('showWaitbar', false));
            testCase.assertTrue(isfile(outFile));
            stored = load(outFile, '-mat', 'modelObjects3D');
            testCase.verifyEqual(stored.modelObjects3D, false);

            freshModel = InstanceObjects3DTest.buildInstanceModel(true);
            freshModel.loadModel([], struct('Filenames', {{outFile}}, 'showWaitbar', false, 'id', 1));
            testCase.verifyFalse(freshModel.I{1}.labels.objects3D, '2D must survive the round trip');
        end

        function aFileWithoutTheSettingOpensAs3DWhenNobodyCanBeAsked(testCase)
            % A batch load has no one to ask, and 3D is the answer that can
            % never hand out an index already used elsewhere in the volume.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'Labels_legacy.model');

            mibModel = InstanceObjects3DTest.buildInstanceModel(false);
            mibModel.saveImage('labels', outFile, struct('showWaitbar', false));
            legacy = load(outFile, '-mat');
            legacy = rmfield(legacy, 'modelObjects3D');
            save(outFile, '-struct', 'legacy', '-mat', '-v7.3');

            freshModel = InstanceObjects3DTest.buildInstanceModel(false);
            freshModel.loadModel([], struct('Filenames', {{outFile}}, 'showWaitbar', false, 'id', 1));
            testCase.verifyTrue(freshModel.I{1}.labels.objects3D);
        end
    end
end
