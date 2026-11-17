classdef ExportImportModelBoundingBoxTest < matlab.unittest.TestCase
% EXPORTIMPORTMODELBOUNDINGBOXTEST - Bounding box in Export/Import model to MATLAB.
%
% MibModel.exportDataset('model') writes .BoundingBox into the workspace
% struct (the field name of the *.model file), and importDataset('model')
% hands it to MibDataset.loadModel, which uses it to place a model whose size
% differs from the dataset and copies it to the dataset only when the model
% matched the image. Runs headless: no parent figure, so a size mismatch takes
% the unattended top-left crop/pad fallback instead of the dialog.

    properties (Constant, Access = private)
        WorkspaceVariable = 'mibtestExportImportModelBB'
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function clearWorkspaceVariableAfterTest(testCase)
            variableName = testCase.WorkspaceVariable;
            testCase.addTeardown(@() evalin('base', sprintf('clear(''%s'')', variableName)));
        end
    end

    methods (Static, Access = private)
        function mibModel = buildModel(dims, boundingBox)
            mibModel = mibtest.helpers.buildSyntheticModel('modelType', 'labels255', 'dims', dims);
            mibModel.I{1}.updateBoundingBox(boundingBox);
        end

        function exportModel(mibModel, variableName)
            exportOptions = struct('LabelsVariable', variableName, 'showWaitbar', false, 'id', 1);
            mibModel.exportDataset('model', exportOptions);
        end

        function importModel(mibModel, variableName)
            importOptions = struct('ModelVariable', variableName, 'showWaitbar', false, 'id', 1);
            mibModel.importDataset('model', importOptions);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function exportWritesTheDatasetBoundingBox(testCase)
            mibModel = ExportImportModelBoundingBoxTest.buildModel([16 24 4], [10 33 5 20 0 3]);
            ExportImportModelBoundingBoxTest.exportModel(mibModel, testCase.WorkspaceVariable);

            exported = evalin('base', testCase.WorkspaceVariable);
            testCase.verifyTrue(isfield(exported, 'BoundingBox'), 'the export must carry .BoundingBox');
            testCase.verifyEqual(exported.BoundingBox, mibModel.I{1}.image.boundingBox, 'AbsTol', 1e-12);
        end

        function importOfAMatchingModelTakesItsBoundingBox(testCase)
            source = ExportImportModelBoundingBoxTest.buildModel([16 24 4], [10 33 5 20 0 3]);
            ExportImportModelBoundingBoxTest.exportModel(source, testCase.WorkspaceVariable);
            exportedLabels = evalin('base', [testCase.WorkspaceVariable '.model']);

            target = ExportImportModelBoundingBoxTest.buildModel([16 24 4], [0 23 0 15 0 3]);
            ExportImportModelBoundingBoxTest.importModel(target, testCase.WorkspaceVariable);

            testCase.verifyEqual(target.I{1}.image.boundingBox, source.I{1}.image.boundingBox, 'AbsTol', 1e-12, ...
                'a model of the same size describes the dataset, so its bounding box is applied');
            testCase.verifyEqual(target.I{1}.labels.data, exportedLabels);
        end

        function importOfAMismatchedModelKeepsTheDatasetGrid(testCase)
            % 16x24 model into a 20x30 image: a bounding box copied from the
            % model would make updateBoundingBox recompute the image pixel size
            source = ExportImportModelBoundingBoxTest.buildModel([16 24 4], [0 23 0 15 0 3]);
            ExportImportModelBoundingBoxTest.exportModel(source, testCase.WorkspaceVariable);
            exportedLabels = evalin('base', [testCase.WorkspaceVariable '.model']);

            target = ExportImportModelBoundingBoxTest.buildModel([20 30 4], [0 29 0 19 0 3]);
            boundingBoxBefore = target.I{1}.image.boundingBox;
            pixSizeBefore = target.I{1}.image.pixSize;
            ExportImportModelBoundingBoxTest.importModel(target, testCase.WorkspaceVariable);

            testCase.verifyEqual(target.I{1}.image.boundingBox, boundingBoxBefore, 'AbsTol', 1e-12);
            testCase.verifyEqual(target.I{1}.image.pixSize.x, pixSizeBefore.x, 'AbsTol', 1e-12);
            testCase.verifyEqual(target.I{1}.image.pixSize.y, pixSizeBefore.y, 'AbsTol', 1e-12);
            importedLabels = target.I{1}.labels.data;
            testCase.verifyEqual(size(importedLabels, [1 2]), [20 30], 'the model is fitted to the image');
            testCase.verifyEqual(importedLabels(1:16, 1:24, :), exportedLabels, ...
                'the unattended fallback places the model at the top-left');
        end
    end
end
