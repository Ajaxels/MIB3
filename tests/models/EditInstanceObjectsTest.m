classdef EditInstanceObjectsTest < matlab.unittest.TestCase
% EDITINSTANCEOBJECTSTEST - Unit tests for models.MibModel.editInstanceObjects.
%
% The operations behind controllers.InstanceEditor, driven headlessly through
% BatchOpt so no window opens. What is asserted:
%
%   - the semantics the author specified: merge takes the SMALLEST index, a
%     split gives the new piece a genuinely unused index;
%   - that every action leaves MibDataset.instanceIndex agreeing with a full
%     rebuild from the volume - the incremental refresh is what keeps the tool
%     interactive, and a wrong bounding box in it silently corrupts the NEXT
%     edit rather than failing here;
%   - that Ctrl+Z restores the exact prior volume;
%   - that Connect writes only into background voxels;
%   - that every rejection path leaves the model untouched. These are cheap to
%     exercise only because editInstanceObjects reports to the console when
%     there is no window to put a message box on; building a modal dialog with
%     no parent blocks the session until someone dismisses it by hand, which
%     turned this file from 1 s into 250 s before it was fixed.
%
% See also: models.MibModel.editInstanceObjects, utils.instances.objectIndex

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end


    methods (Static, Access = private)

        function [mibModel, volume] = buildInstanceModel(extraObjects)
            % A 65535-type instance model with three well-separated objects:
            %   1 - a column through slices 2:7
            %   2 - two blobs that are NOT connected to each other (so a split
            %       into components has something to find)
            %   5 - a short column on slices 1:3, leaving a Z gap below object 1
            %       for Connect to bridge. Index 3 and 4 are free on purpose.
            if nargin < 1; extraObjects = struct(); end
            dims = [32 32 10];
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', dims);

            volume = zeros(dims, 'uint16');
            volume(4:10,  4:10,  2:7) = 1;
            volume(20:24, 20:24, 3:6) = 2;
            volume(20:24, 28:31, 3:6) = 2;    % second, disconnected blob of object 2
            volume(4:10,  16:20, 1:2) = 5;

            if isfield(extraObjects, 'blocker')
                % something lying in the Z gap that Connect must not overwrite
                volume(extraObjects.blocker{:}) = 7;
            end

            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.labels.materialsCount = double(max(volume, [], 'all'));
            mibModel.I{1}.buildInstanceIndex();
        end

        function volume = readLabels(mibModel)
            volume = cell2mat(mibModel.getData3D('labels', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
        end

        function runAction(mibModel, action, indices, extra)
            BatchOpt = struct();
            BatchOpt.Action = {action};
            BatchOpt.ObjectIndices = indices;
            BatchOpt.showWaitbar = false;
            if nargin >= 4
                names = fieldnames(extra);
                for k = 1:numel(names); BatchOpt.(names{k}) = extra.(names{k}); end
            end
            mibModel.editInstanceObjects(BatchOpt);
        end

        function verifyIndexAgreesWithVolume(testCase, mibModel, message)
            % The invariant that matters: the incrementally refreshed index must
            % describe the volume as it now is.
            actual = mibModel.I{1}.instanceIndex;
            volume = EditInstanceObjectsTest.readLabels(mibModel);
            expected = utils.instances.objectIndex(volume);

            shared = expected.maxIndex;
            testCase.verifyGreaterThanOrEqual(actual.maxIndex, shared, message);
            for field = {'exists', 'voxels', 'bbox', 'centroid', 'sliceCount'}
                testCase.verifyEqual(actual.(field{1})(1:shared, :), ...
                    expected.(field{1})(1:shared, :), ...
                    sprintf('%s: index field %s disagrees with the volume', message, field{1}));
            end
            testCase.verifyFalse(any(actual.exists(shared+1:end)), ...
                sprintf('%s: index claims objects the volume does not have', message));
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % merge
        % -----------------------------------------------------------------

        function mergeAssignsTheSmallestIndex(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '2, 5');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 5), 0, 'the larger index is gone');
            testCase.verifyEqual(nnz(after == 2), nnz(before == 2) + nnz(before == 5), ...
                'its voxels moved to the smaller index');
            testCase.verifyEqual(nnz(after == 1), nnz(before == 1), 'other objects untouched');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge');
        end

        function mergeFreesTheAbsorbedIndexForReuse(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '2, 5');

            index = mibModel.I{1}.instanceIndex;
            testCase.verifyFalse(index.exists(5));
            testCase.verifyEqual(find(~index.exists, 1), 3, ...
                'the lowest gap is offered first');
        end

        function mergeNeedsTwoObjects(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '1');

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, ...
                'a rejected action must not change the model');
        end

        function mergeTakesTheObjectsFromTheDrawing(testCase)
            % One shape drawn across objects 1 and 5, nothing named: the whole
            % of both objects is merged, not just the part under the shape.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:20, 2) = 1;        % slice 2 carries both objects
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 5), 0, 'the larger index is gone');
            testCase.verifyEqual(nnz(after == 1), nnz(before == 1) + nnz(before == 5), ...
                'both objects became object 1, in full');
            testCase.verifyEqual(nnz(after == 2), nnz(before == 2), ...
                'the object the shape does not touch is untouched');
            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), 0, 'the shape is used up');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge, auto');
        end

        function mergeFromADrawingOverOneObjectIsRejected(testCase)
            % The complaint has to name the drawing, not repeat "Merge needs two
            % objects": nothing was typed in, so it is the shape that is short.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;        % object 1 alone
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'Merge'}}, 'ObjectIndices', '', 'showWaitbar', false));

            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), nnz(selection), 'the drawing is left for the user');
        end

        % -----------------------------------------------------------------
        % split
        % -----------------------------------------------------------------

        function splitComponentsGivesTheNewPieceAnUnusedIndex(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'SplitComponents', '2');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            % index 3 was the lowest free value before the split
            testCase.verifyEqual(nnz(before == 3), 0, 'index 3 was free beforehand');
            testCase.verifyEqual(nnz(after == 3), 5 * 4 * 4, 'the smaller blob became object 3');
            testCase.verifyEqual(nnz(after == 2), 5 * 5 * 4, 'the larger blob kept the index');
            testCase.verifyEqual(nnz(after > 0), nnz(before > 0), 'no voxel was lost');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'split');
        end

        function splitOfAConnectedObjectDoesNothing(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'SplitComponents', '1');

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, ...
                'a single-component object has nothing to split');
        end

        function cutAtSliceSplitsAlongZ(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            % slices{orientation} is the depth slider; orientation 3 is XY
            mibModel.I{1}.slices{3} = [5, 5];    % show slice 5; object 1 spans 2:7

            EditInstanceObjectsTest.runAction(mibModel, 'CutAtSlice', '1');

            % Look only inside object 1's own footprint - the other objects of
            % the fixture live on these slices too.
            after = EditInstanceObjectsTest.readLabels(mibModel);
            head = after(4:10, 4:10, 2:4);
            tail = after(4:10, 4:10, 5:7);
            testCase.verifyEqual(unique(head)', uint16(1), ...
                'slices below the cut keep the original index');
            newIndex = unique(tail);
            testCase.verifyNumElements(newIndex, 1, 'exactly one new object appears');
            testCase.verifyNotEqual(newIndex, uint16(1));
            testCase.verifyEqual(nnz(after == newIndex), 7 * 7 * 3, ...
                'the tail from the shown slice onwards');
            testCase.verifyEqual(nnz(after == 1), 7 * 7 * 3);
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'cut');
        end

        function cutAtSliceOutsideTheObjectIsRejected(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            mibModel.I{1}.slices{3} = [9, 9];    % object 1 ends at slice 7
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'CutAtSlice', '1');

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before);
        end

        function splitBySelectionCutsTheObjectAndRelabels(testCase)
            % The brush workflow in one action: the Selection layer holds the
            % break, which is cleared out of the object and the remainder split.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;        % a full cut through object 1 at z = 5
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '1');

            % Restricted to object 1's footprint: the fixture's other objects
            % occupy these slices as well.
            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after(:, :, 5) == 1), 0, 'the break was cleared');
            newIndex = unique(after(4:10, 4:10, 6:7));
            testCase.verifyNumElements(newIndex, 1);
            testCase.verifyNotEqual(newIndex, uint16(1), 'the far side got a new index');
            testCase.verifyEqual(nnz(after == 1), 7 * 7 * 3, 'slices 2:4 keep index 1');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'splitBySelection');
        end

        function splitBySelectionFindsTheObjectFromTheDrawing(testCase)
            % With no object named, the drawing says what to cut. Same break as
            % the test above, so the result has to be the same.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after(:, :, 5) == 1), 0, 'the break was cleared');
            newIndex = unique(after(4:10, 4:10, 6:7));
            testCase.verifyNumElements(newIndex, 1);
            testCase.verifyNotEqual(newIndex, uint16(1), 'the far side got a new index');
            testCase.verifyEqual(nnz(after == 1), 7 * 7 * 3, 'slices 2:4 keep index 1');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'splitBySelection, auto');
        end

        function splitBySelectionCutsEveryObjectTheDrawingCovers(testCase)
            % A drawing crossing two objects cuts both. Naming one of them is
            % how a line that clips a neighbour is kept to its target.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(4:10,  4:10, 2:7) = 1;
            volume(20:26, 4:10, 2:7) = 2;
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.labels.materialsCount = 2;
            mibModel.I{1}.buildInstanceIndex();

            selection = zeros(32, 32, 10, 'uint8');
            selection(:, :, 5) = 1;              % one plane, across both objects
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after(:, :, 5)), 0, 'the plane was cleared from both');
            testCase.verifyNumElements(setdiff(unique(after(:)), 0), 4, 'two objects became four');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'splitBySelection, two objects');
        end

        function splitBySelectionConsumesTheDrawing(testCase)
            % The drawing has been applied to the model, so it goes. Otherwise
            % the next Split by selection - which reads the whole layer when no
            % object is named - would cut with a line drawn for something else.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '');

            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), 0, 'the Selection layer is emptied');
        end

        function splitBySelectionOnBackgroundIsRejected(testCase)
            % A drawing lying on nothing names no object. The layer is left as
            % it is, so the drawing can be moved rather than made again.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(30:32, 1:3, 9) = 1;        % an empty corner of the volume
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            before = EditInstanceObjectsTest.readLabels(mibModel);

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'SplitBySelection'}}, 'ObjectIndices', '', 'showWaitbar', false));

            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), nnz(selection), 'the drawing is left for the user');
        end

        function splitBySelectionWithNothingDrawnIsRejected(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            mibModel.setData3D(zeros(32, 32, 10, 'uint8'), 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            before = EditInstanceObjectsTest.readLabels(mibModel);

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'SplitBySelection'}}, 'ObjectIndices', '', 'showWaitbar', false));

            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
        end

        % -----------------------------------------------------------------
        % connect
        % -----------------------------------------------------------------

        function connectBridgesTheGapAndMerges(testCase)
            % Object 5 ends at slice 2, object 1 starts at slice 2 - they touch
            % in Z, so this is the degenerate case: merge with no bridge.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '1, 5');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 5), 0);
            testCase.verifyGreaterThan(nnz(after == 1), 0);
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect');
        end

        function connectFillsARealZGap(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:3) = 1;
            volume(10:16, 10:16, 7:9) = 4;      % same footprint, gap on 4:6
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '1, 4');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 4), 0, 'the two became one object');
            testCase.verifyGreaterThan(nnz(after(:, :, 5) == 1), 0, ...
                'the gap slices were filled');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect gap');
        end

        function connectNeverOverwritesAThirdObject(testCase)
            % The guard that makes Connect safe in a crowded volume.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:3) = 1;
            volume(10:16, 10:16, 7:9) = 4;
            volume(12:14, 12:14, 5)   = 9;      % a bystander sitting in the gap
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '1, 4');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 9), 3 * 3, ...
                'every voxel of the bystander survives the bridge');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect bystander');
        end

        function connectRejectsMoreThanTwoObjects(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '1, 2, 5');

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before);
        end

        % -----------------------------------------------------------------
        % delete, cleanup, compact
        % -----------------------------------------------------------------

        function deleteRemovesTheObjectAndFreesTheIndex(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            EditInstanceObjectsTest.runAction(mibModel, 'Delete', '2');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 2), 0);
            testCase.verifyFalse(mibModel.I{1}.instanceIndex.exists(2));
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'delete');
        end

        function cleanupKeepsTheSurvivorsLabelValues(testCase)
            % Cleanup must not renumber: a user working with object 5 has to
            % still find it under that number.
            % Object sizes in the fixture: 1 -> 294 voxels, 2 -> 180, 5 -> 70.
            % A threshold of 100 removes only object 5.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            extra.MinObjectVoxels = {100, [0, 1e9], 'on'};
            extra.AbsorbFragmentVoxels = {0, [0, 1e6], 'on'};

            EditInstanceObjectsTest.runAction(mibModel, 'Cleanup', '', extra);

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 5), 0, 'object 5 has 70 voxels and goes');
            testCase.verifyGreaterThan(nnz(after == 1), 0, 'object 1 keeps its number');
            testCase.verifyGreaterThan(nnz(after == 2), 0, 'object 2 keeps its number');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'cleanup');
        end

        function compactRenumbersToContiguousIndices(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            EditInstanceObjectsTest.runAction(mibModel, 'Compact', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(unique(after(after > 0))', uint16([1 2 3]), ...
                'the gap at 3 and 4 is closed');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'compact');
        end

        % -----------------------------------------------------------------
        % undo and guards
        % -----------------------------------------------------------------

        function undoRestoresTheExactPriorVolume(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '2, 5');
            testCase.verifyNotEqual(EditInstanceObjectsTest.readLabels(mibModel), before);

            mibModel.undo();

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, ...
                'Ctrl+Z must restore the model exactly');
        end

        function unknownObjectIndexIsRejected(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Delete', '3');   % 3 is a free index

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before);
        end

        function aSmallMaterialModelIsRejected(testCase)
            % A 63-material model has no per-object identity to edit.
            mibModel = mibtest.helpers.buildSyntheticModel('modelType', 'labels63', 'dims', [16 16 4]);
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Delete', '1');

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before);
        end

        function theReturnValueDistinguishesDoneFromDeclined(testCase)
            % controllers.InstanceEditor updates its own selection from this:
            % after a real Merge the survivor is the only object left, but after
            % a rejected one nothing may change.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            BatchOpt = struct('Action', {{'Merge'}}, 'ObjectIndices', '2, 5', 'showWaitbar', false);
            testCase.verifyTrue(mibModel.editInstanceObjects(BatchOpt), ...
                'a merge of two real objects is applied');

            BatchOpt.ObjectIndices = '1';
            testCase.verifyFalse(mibModel.editInstanceObjects(BatchOpt), ...
                'a merge of one object is declined');

            BatchOpt.Action = {'Connect'};
            BatchOpt.ObjectIndices = '1, 2, 4';
            testCase.verifyFalse(mibModel.editInstanceObjects(BatchOpt), ...
                'Connect on three objects is declined');
        end

        function nanReturnsTheBatchOptions(testCase)
            % The batch-processing contract: NaN publishes the defaults and
            % changes nothing.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            captured = [];

            listener = addlistener(mibModel, 'SyncBatch', @onSync);
            cleanup = onCleanup(@() delete(listener));
            mibModel.editInstanceObjects(NaN);
            clear cleanup;

            testCase.verifyNotEmpty(captured, 'the SyncBatch event must fire');
            testCase.verifyTrue(isfield(captured, 'Action'));
            testCase.verifyEqual(captured.Action{2}, ...
                {'Merge', 'SplitComponents', 'SplitBySelection', 'CutAtSlice', ...
                 'Connect', 'Delete', 'Cleanup', 'Compact'});
            testCase.verifyFalse(isfield(captured, 'id'), ...
                'the dataset index is not part of the published options');
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before);

            function onSync(~, eventData)
                captured = eventData.Parameters;
            end
        end
    end
end
