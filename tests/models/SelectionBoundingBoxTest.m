classdef SelectionBoundingBoxTest < matlab.unittest.TestCase
% SELECTIONBOUNDINGBOXTEST - Tests for the selection bounding box of Standard datasets.
%
% Covers MibDataset.getSelectionBoundingBox and its users, which back up and
% process only the box that holds the selection:
%   1. The box is exact, [] for an empty selection, and honours the time range,
%      for the packed uint8/uint16 layouts and the separate selection layer.
%   2. moveSelectionToModelDataset / moveSelectionToMaskDataset given the box
%      ('add', 'remove', every restriction) leave every layer exactly as the
%      whole-volume pass does.
%   3. MibModel.moveLayers (Shift+A) and MibModel.clearSelection (Shift+C) in
%      3D give the whole-volume result and undo restores the starting layers.

    properties (TestParameter)
        modelType = {'labels63', 'labels255', 'labels16383'};
        moveMethod = {'moveSelectionToModelDataset', 'moveSelectionToMaskDataset'};
        actionType = {'add', 'remove'};
        % [selected_sw maskedAreaSw]: restrict to the selected material and/or the mask
        restriction = struct('none', [0 0], 'material', [1 0], 'mask', [0 1], 'both', [1 1]);
    end

    properties (Constant)
        Dims = [32 40 4];
        % the selection is kept inside rows 5:20, columns 8:30, slices 2:3
        SelectionRows = 5:20;
        SelectionColumns = 8:30;
        SelectionSlices = 2:3;
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function emptySelectionGivesEmptyBox(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', modelType, 'dims', testCase.Dims);
            mibModel.I{1}.clearLayer('selection');
            testCase.verifyEmpty(mibModel.I{1}.getSelectionBoundingBox());
        end

        function boxHoldsExactlyTheSelection(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', modelType, 'dims', testCase.Dims);
            selection = zeros(testCase.Dims, 'uint8');
            selection(5:9, 3:12, 2) = 1;
            selection(20, 25, 4) = 1;       % a single voxel stretches the box
            mibModel.setData3D(selection, 'selection', 1, 3, NaN, struct('id', 1));

            box = mibModel.I{1}.getSelectionBoundingBox();
            testCase.verifyEqual(box, [5 20 3 25 2 4 1 1]);
        end

        function boxFractionIsTheShareOfTheVolume(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', modelType, 'dims', testCase.Dims);
            selection = zeros(testCase.Dims, 'uint8');
            selection(1:16, 1:20, 1:2) = 1;     % an eighth of 32 x 40 x 4
            mibModel.setData3D(selection, 'selection', 1, 3, NaN, struct('id', 1));
            [~, boxFraction] = mibModel.I{1}.getSelectionBoundingBox();
            testCase.verifyEqual(boxFraction, 1/8, 'AbsTol', 1e-12);

            mibModel.I{1}.clearLayer('selection');
            [~, boxFraction] = mibModel.I{1}.getSelectionBoundingBox();
            testCase.verifyEqual(boxFraction, 0);
        end

        function moveLayers3DAddWithLargeBoxMatchesWholeVolume(testCase, modelType)
            % the random selection of buildSyntheticModel spans the volume, so
            % moveLayers falls back to the whole-volume pass
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', modelType, 'dims', testCase.Dims);
            [reference, ~] = mibtest.helpers.buildSyntheticModel('modelType', modelType, 'dims', testCase.Dims);
            [~, boxFraction] = mibModel.I{1}.getSelectionBoundingBox();
            testCase.assertGreaterThan(boxFraction, 0.25);

            BatchOptIn = struct('id', 1, 'showWaitbar', false, 'SelectedMaterial', '1', ...
                'SelectedAddToMaterial', '2', 'restrictSelectionToMaterial', false, ...
                'restrictSelectionToMask', false, 'blockModeSwitch', false, 'roiId', '-1');
            mibModel.moveLayers('selection', 'labels', '3D, Stack', 'add', BatchOptIn);
            reference.I{1}.moveSelectionToModelDataset('add', ...
                struct('contSelIndex', 1, 'contAddIndex', 2, 'selected_sw', false, 'maskedAreaSw', false));
            SelectionBoundingBoxTest.verifyLayersEqual(testCase, mibModel, ...
                SelectionBoundingBoxTest.readLayers(reference), 'moveLayers 3D add, large box');
        end

        function boxHonoursTheTimeRange(testCase, modelType)
            mibModel = SelectionBoundingBoxTest.buildTimeSeries(modelType);
            % selection at time point 2 only
            selection = zeros(testCase.Dims, 'uint8');
            selection(3:4, 6:7, 3) = 1;
            mibModel.setData3D(selection, 'selection', 2, 3, NaN, struct('id', 1));

            testCase.verifyEqual(mibModel.I{1}.getSelectionBoundingBox([1 3]), [3 4 6 7 3 3 2 2]);
            testCase.verifyEqual(mibModel.I{1}.getSelectionBoundingBox([2 2]), [3 4 6 7 3 3 2 2]);
            testCase.verifyEmpty(mibModel.I{1}.getSelectionBoundingBox([1 1]));
            testCase.verifyEmpty(mibModel.I{1}.getSelectionBoundingBox([3 3]));
        end

        function boxedMoveMatchesWholeVolume(testCase, modelType, moveMethod, actionType, restriction)
            boxedModel = SelectionBoundingBoxTest.buildWithLocalSelection(modelType);
            wholeModel = SelectionBoundingBoxTest.buildWithLocalSelection(modelType);
            moveOpts = struct('contSelIndex', 1, 'contAddIndex', 2, ...
                'selected_sw', logical(restriction(1)), 'maskedAreaSw', logical(restriction(2)));

            boxedOpts = moveOpts;
            boxedOpts.box = boxedModel.I{1}.getSelectionBoundingBox();
            testCase.assertNotEmpty(boxedOpts.box);
            boxedModel.I{1}.(moveMethod)(actionType, boxedOpts);
            wholeModel.I{1}.(moveMethod)(actionType, moveOpts);

            SelectionBoundingBoxTest.verifyLayersEqual(testCase, boxedModel, ...
                SelectionBoundingBoxTest.readLayers(wholeModel), ...
                sprintf('%s(''%s'') with the box', moveMethod, actionType));
        end

        function moveLayers3DAddMatchesWholeVolumeAndUndoes(testCase, modelType)
            mibModel = SelectionBoundingBoxTest.buildWithLocalSelection(modelType);
            reference = SelectionBoundingBoxTest.buildWithLocalSelection(modelType);
            before = SelectionBoundingBoxTest.readLayers(mibModel);

            BatchOptIn = struct('id', 1, 'showWaitbar', false, 'SelectedMaterial', '1', ...
                'SelectedAddToMaterial', '2', 'restrictSelectionToMaterial', false, ...
                'restrictSelectionToMask', false, 'blockModeSwitch', false, 'roiId', '-1');
            mibModel.moveLayers('selection', 'labels', '3D, Stack', 'add', BatchOptIn);
            reference.I{1}.moveSelectionToModelDataset('add', ...
                struct('contSelIndex', 1, 'contAddIndex', 2, 'selected_sw', false, 'maskedAreaSw', false));
            SelectionBoundingBoxTest.verifyLayersEqual(testCase, mibModel, ...
                SelectionBoundingBoxTest.readLayers(reference), 'moveLayers 3D add');

            mibModel.undo();
            % the separate-layer models back up only the destination layer, so
            % only the packed layouts get the selection back
            if strcmp(modelType, 'labels255')
                before = rmfield(before, 'selection');
            end
            SelectionBoundingBoxTest.verifyLayersEqual(testCase, mibModel, before, 'undo of moveLayers 3D add');
        end

        function moveLayersWithoutSelectionChangesNothing(testCase, modelType)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel('modelType', modelType, 'dims', testCase.Dims);
            mibModel.I{1}.clearLayer('selection');
            before = SelectionBoundingBoxTest.readLayers(mibModel);

            BatchOptIn = struct('id', 1, 'showWaitbar', false, 'SelectedAddToMaterial', '2');
            mibModel.moveLayers('selection', 'labels', '3D, Stack', 'add', BatchOptIn);
            SelectionBoundingBoxTest.verifyLayersEqual(testCase, mibModel, before, 'moveLayers without selection');
        end

        function clearSelection3DClearsAndUndoes(testCase, modelType)
            mibModel = SelectionBoundingBoxTest.buildWithLocalSelection(modelType);
            before = SelectionBoundingBoxTest.readLayers(mibModel);

            mibModel.clearSelection('3D, Stack', struct('id', 1, 'showWaitbar', false));
            afterClear = before;
            afterClear.selection(:) = 0;
            SelectionBoundingBoxTest.verifyLayersEqual(testCase, mibModel, afterClear, 'clearSelection 3D');

            mibModel.undo();
            SelectionBoundingBoxTest.verifyLayersEqual(testCase, mibModel, before, 'undo of clearSelection 3D');
        end
    end

    methods (Static, Access = private)
        function mibModel = buildWithLocalSelection(modelType)
            % synthetic model whose random selection is kept inside a sub-box, so
            % the box is smaller than the volume in every dimension
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', modelType, 'dims', SelectionBoundingBoxTest.Dims);
            rows = SelectionBoundingBoxTest.SelectionRows;
            columns = SelectionBoundingBoxTest.SelectionColumns;
            slices = SelectionBoundingBoxTest.SelectionSlices;
            selection = zeros(SelectionBoundingBoxTest.Dims, 'uint8');
            selection(rows, columns, slices) = groundTruth.selection(rows, columns, slices);
            mibModel.setData3D(selection, 'selection', 1, 3, NaN, struct('id', 1));
        end

        function mibModel = buildTimeSeries(modelType)
            dims = SelectionBoundingBoxTest.Dims;
            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            image = zeros([dims(1:3) 1 3], 'uint8');
            mibModel.I{1} = core.MibDataset(image, dictionary(), 'Standard', 'labels63');
            switch modelType
                case 'labels63';    mibModel.I{1}.createModel(63);
                case 'labels255';   mibModel.I{1}.createModel(255);
                case 'labels16383'; mibModel.I{1}.createModel(16383);
            end
        end

        function layers = readLayers(mibModel)
            opt = struct('id', 1, 'blockModeSwitch', 0);
            for layer = {'labels', 'mask', 'selection'}
                layers.(layer{1}) = squeeze(cell2mat(mibModel.getData3D(layer{1}, 1, 3, NaN, opt)));
            end
        end

        function verifyLayersEqual(testCase, mibModel, expected, what)
            actual = SelectionBoundingBoxTest.readLayers(mibModel);
            for layer = fieldnames(expected)'
                testCase.verifyEqual(actual.(layer{1}), expected.(layer{1}), ...
                    sprintf('%s: the %s layer differs', what, layer{1}));
            end
        end
    end
end
