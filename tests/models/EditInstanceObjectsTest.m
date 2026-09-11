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

        function note(recorder, label)
            % Append an event name to a handle recorder, so the order of two
            % events fired inside one call can be asserted afterwards.
            recorder.Text = strtrim([recorder.Text ' ' label]);
        end

        function volume = readLabels(mibModel)
            volume = cell2mat(mibModel.getData3D('labels', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
        end

        function volume = readSelection(mibModel)
            volume = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
        end

        function drawIntoSelection(mibModel, dims, y, x, z)
            selection = zeros(dims, 'uint8');
            selection(y, x, z) = 1;
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
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
            testCase.verifyEqual(nnz(after == 2), nnz(before == 2), ...
                'the object the shape does not touch is untouched');
            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), 0, 'the shape is used up');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge, auto');
        end

        function mergeFromADrawingClosesTheGapItWasDrawnAcross(testCase)
            % The rule that used to change with the number of objects: a drawing
            % over ONE object joined it, a drawing over two did not. Now the
            % background under the stroke joins the survivor either way, so the
            % two halves come out as one connected piece rather than one index
            % in two pieces.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:20, 2) = 1;        % columns 11:15 are background
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            drawnOnBackground = nnz(selection > 0 & before == 0);
            testCase.assumeGreaterThan(drawnOnBackground, 0, 'the fixture must leave a gap');

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 1), ...
                nnz(before == 1) + nnz(before == 5) + drawnOnBackground, ...
                'both objects and the background the stroke crossed');
            testCase.verifyEqual(bwconncomp(after == 1, 26).NumObjects, 1, ...
                'the survivor is one connected piece, not one index in two');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge, gap closed');
        end

        function mergeWithNamedObjectsLeavesTheDrawingAlone(testCase)
            % Absorption follows the input, not the layer: objects picked by
            % name are a different gesture, and a drawing left over from an
            % earlier one must not be written into the model behind the user.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:20, 2) = 1;
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '1, 5');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 1), nnz(before == 1) + nnz(before == 5), ...
                'the two objects, and nothing the stroke crossed');
            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), nnz(selection), 'the drawing is left where it was');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge, named');
        end

        function mergeOverBackgroundCreatesANewObject(testCase)
            % "Make this one object" reads just as well over empty space, which
            % is what MIB's own 'a' does to a material.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(28:31, 2:6, 8:9) = 1;      % an empty corner of the volume
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            newIndex = unique(after(28:31, 2:6, 8:9));
            testCase.verifyNumElements(newIndex, 1, 'the drawing became one object');
            testCase.verifyEqual(double(newIndex), 3, 'it took the lowest free index');
            testCase.verifyEqual(nnz(after == newIndex), nnz(selection), 'exactly the drawn voxels');
            testCase.verifyEqual(nnz(after > 0), nnz(before > 0) + nnz(selection), ...
                'nothing that was there before was touched');
            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), 0, 'the drawing is used up');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge, new object');
        end

        function addObjectCanBeAskedForByName(testCase)
            % The same thing as a named action, for a batch protocol.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(28:31, 2:6, 8:9) = 1;
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'AddObject'}}, 'ObjectIndices', '', 'showWaitbar', false));

            testCase.verifyTrue(applied);
            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 3), nnz(selection));
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'addObject');
        end

        function addObjectWithNothingDrawnIsRejected(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            mibModel.setData3D(zeros(32, 32, 10, 'uint8'), 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            before = EditInstanceObjectsTest.readLabels(mibModel);

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'AddObject'}}, 'ObjectIndices', '', 'showWaitbar', false));

            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
        end

        function mergeOverOneObjectGivesItTheDrawing(testCase)
            % One object under the drawing is the same gesture over a smaller
            % region, not a merge that came up short: the object grows by it.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;        % on object 1
            selection(11:13, 4:10, 5) = 1;       % and out into the background
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            grownBy = 3 * 7;                     % the part that was background
            testCase.verifyEqual(nnz(after == 1), nnz(before == 1) + grownBy, ...
                'object 1 grew by exactly the new part of the drawing');
            testCase.verifyEqual(numel(setdiff(unique(after(:)), 0)), ...
                numel(setdiff(unique(before(:)), 0)), 'no new index was handed out');
            testCase.verifyTrue(all(after(11:13, 4:10, 5) == 1, 'all'), 'the drawn area joined it');
            remaining = cell2mat(mibModel.getData3D('selection', 1, 3, NaN, ...
                struct('id', 1, 'blockModeSwitch', 0)));
            testCase.verifyEqual(nnz(remaining), 0, 'the drawing is used up');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge, grow');
        end

        function addToObjectCanBeAskedForByName(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(11:13, 4:10, 5) = 1;       % background beside object 1
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'AddToObject'}}, 'ObjectIndices', '1', 'showWaitbar', false));

            testCase.verifyTrue(applied);
            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 1), nnz(before == 1) + nnz(selection));
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'addToObject');
        end

        function addToObjectTakesOneObjectOnly(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);
            selection = zeros(32, 32, 10, 'uint8');
            selection(11:13, 4:10, 5) = 1;
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'AddToObject'}}, 'ObjectIndices', '1, 2', 'showWaitbar', false));

            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
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

        function splitBySelectionCoveringTheWholeObjectRemovesIt(testCase)
            % 's' is "subtract the Selection from the material" here as it is
            % everywhere in MIB, so a drawing over the whole object subtracts
            % the whole object. It used to refuse with "nothing would be left",
            % which made the one gesture that means "delete this" unavailable
            % from the key the user already had a hand on.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 16:20, 1:2) = 1;     % exactly object 5
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 5), 0, 'object 5 is gone');
            testCase.verifyEqual(nnz(after == 1), 7 * 7 * 6, 'object 1 untouched');
            testCase.verifyEqual(nnz(after == 2), 5 * 5 * 4 + 5 * 4 * 4, 'object 2 untouched');
            testCase.verifyFalse(mibModel.I{1}.instanceIndex.exists(5), 'the index is freed');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'splitBySelection, whole object');
        end

        function splitBySelectionClearingASliceKeepsTheObjectIn2D(testCase)
            % The same gesture in 2D reaches one slice only, so an object
            % cleared from the shown slice keeps its index and its voxels on the
            % others. The index refresh is what has to get this right: its box
            % is clipped to the slice, and only because it unions in the
            % object's previous box does the rest of the object survive the
            % recount.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            mibModel.I{1}.slices{3} = [5, 5];    % object 1 spans slices 2:7
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;        % the whole of object 1 on that slice
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '', ...
                struct('Mode3D', false));

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after(:, :, 5) == 1), 0, 'the slice was cleared');
            testCase.verifyEqual(nnz(after == 1), 7 * 7 * 5, 'the other five slices keep index 1');
            testCase.verifyTrue(mibModel.I{1}.instanceIndex.exists(1), 'the object still exists');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'splitBySelection, slice cleared');
        end

        function splitBySelectionWithPickedObjectsAndNoDrawingRemovesThem(testCase)
            % Picking an object paints it into the Selection layer as the
            % highlight, so on screen a pick is indistinguishable from a drawing
            % covering the whole object - and that subtracts the whole object.
            % The pick therefore is the selection when nothing has been drawn.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            mibModel.setData3D(zeros(32, 32, 10, 'uint8'), 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '1, 5');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 1), 0, 'object 1 is gone');
            testCase.verifyEqual(nnz(after == 5), 0, 'object 5 is gone');
            testCase.verifyEqual(nnz(after == 2), 5 * 5 * 4 + 5 * 4 * 4, 'object 2 untouched');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'splitBySelection, picked only');
        end

        function splitBySelectionWithPickedObjectsStillCutsWhenSomethingIsDrawn(testCase)
            % The pick only stands in for the drawing when there is no drawing.
            % With a break drawn, naming an object keeps its old meaning: cut
            % that object and leave the neighbour the line also crosses alone.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;        % a break through object 1
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '1');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 1), 7 * 7 * 3, 'object 1 was cut, not removed');
            testCase.verifyEqual(nnz(after == 5), 7 * 5 * 2, 'object 5 untouched');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'splitBySelection, picked and drawn');
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
            % Object 5 ends at slice 2, object 1 starts at slice 2 - they overlap
            % in Z, so this is the degenerate case: merge with no bridge. It is
            % still allowed, because two objects that genuinely touch have no gap
            % to fill and joining them is the right answer; these two do not
            % touch, so the operation also says so. See
            % connectWithSelectionNeedsNoZGap for the way to join this pair
            % properly.
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

        function connectWithSelectionBridgesWithTheDrawing(testCase)
            % The 'selection' mode now takes the same path as a drawing-driven
            % Merge: the drawn background becomes part of the survivor.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:3) = 1;
            volume(10:16, 10:16, 7:9) = 4;      % same footprint, gap on 4:6
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            selection = zeros(32, 32, 10, 'uint8');
            selection(12:14, 12:14, 4:6) = 1;   % a hand-drawn bridge, narrower
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '1, 4', ...
                struct('ConnectMode', {{'selection'}}));

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 4), 0, 'the two became one object');
            testCase.verifyEqual(nnz(after(:, :, 5) == 1), 3 * 3, ...
                'exactly the drawn bridge, not the interpolated one');
            testCase.verifyEqual(bwconncomp(after == 1, 26).NumObjects, 1, ...
                'one connected piece');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect, drawn');
        end

        function connectWithSelectionNeedsNoZGap(testCase)
            % 'interpolate' needs two facing cross-sections and therefore a gap;
            % a drawn bridge needs neither, so this pair - overlapping in Z but
            % never touching - is reachable only through the drawing.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(4:10,  4:10,  2:7) = 1;
            volume(20:26, 20:26, 3:6) = 4;      % overlaps in Z, far away in XY
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            selection = zeros(32, 32, 10, 'uint8');
            selection(10:20, 10:20, 4) = 1;     % drawn across the space between
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'Connect'}}, 'ObjectIndices', '1, 4', ...
                'ConnectMode', {{'selection'}}, 'showWaitbar', false));

            testCase.verifyTrue(applied);
            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 4), 0);
            testCase.verifyEqual(bwconncomp(after == 1, 26).NumObjects, 1, ...
                'the drawn bridge joined them into one piece');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect, no gap');
        end

        function connectNeeds3DMode(testCase)
            % The same refusal CutAtSlice makes, for the same reason. Without it
            % Connect ran in 2D and merged the whole of both objects through the
            % stack while the mode said one slice.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'Connect'}}, 'ObjectIndices', '1, 5', ...
                'Mode3D', false, 'showWaitbar', false));

            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
        end

        function connectOverAZOverlapIsAPlainMerge(testCase)
            % Nothing for 'interpolate' to fill, so the operation is Merge - and
            % the two paths must agree exactly, being the same code now.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '1, 5');
            afterConnect = EditInstanceObjectsTest.readLabels(mibModel);

            other = EditInstanceObjectsTest.buildInstanceModel();
            EditInstanceObjectsTest.runAction(other, 'Merge', '1, 5');
            afterMerge = EditInstanceObjectsTest.readLabels(other);

            testCase.verifyEqual(afterConnect, afterMerge, ...
                'Connect with no gap to bridge is Merge, voxel for voxel');
        end

        function connectRejectsMoreThanTwoObjects(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '1, 2, 5');

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before);
        end

        % -----------------------------------------------------------------
        % nothing picked: the drawing chooses the objects, and in 3D it
        % reaches one slice beyond either end of itself
        % -----------------------------------------------------------------

        function mergeFromADrawingReachesTheNextSliceInZ(testCase)
            % The headline case, on the key the hand is already on: two halves
            % of one object a slice apart, brush the gap, press 'a'. The same
            % stroke in 2D joins two objects side by side; this is that gesture
            % in a volume, where the thing being joined to is on the next slice
            % and there is nothing painted on it.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:4) = 6;
            volume(10:16, 10:16, 6:9) = 2;      % same footprint, slice 5 empty
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 11:15, 11:15, 5);

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 6), 0, 'the larger index was absorbed');
            testCase.verifyEqual(bwconncomp(after == 2, 26).NumObjects, 1, ...
                'one connected piece, closed by the drawing');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge across Z');
        end

        function mergeFromADrawingIn2DStaysOnTheSlice(testCase)
            % The reach is a property of 3D mode, not of the gesture. In 2D
            % there is no next slice to look at, so the same drawing is a new
            % object - which is what 'a' has always done over background.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:4) = 6;
            volume(10:16, 10:16, 6:9) = 2;
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            mibModel.I{1}.slices{3} = [5, 5];   % the shown slice is the empty one
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 11:15, 11:15, 5);

            EditInstanceObjectsTest.runAction(mibModel, 'Merge', '', struct('Mode3D', false));

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 6), nnz(volume == 6), 'object 6 untouched');
            testCase.verifyEqual(nnz(after == 2), nnz(volume == 2), 'object 2 untouched');
            testCase.verifyEqual(nnz(after(:, :, 5) > 0), 5 * 5, 'the drawing became its own object');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'merge, 2D');
        end

        function connectFromADrawingJoinsWhatItLiesBetween(testCase)
            % The same gesture on the Connect button, which with nothing picked
            % is the same code: brush the gap, press it, and the objects one
            % slice beyond each end of the stroke are the ones joined. No pick
            % at all, where it used to take two.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:4) = 6;
            volume(10:16, 10:16, 6:9) = 2;      % same footprint, slice 5 empty
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 11:15, 11:15, 5);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 6), 0, 'the larger index was absorbed');
            testCase.verifyEqual(bwconncomp(after == 2, 26).NumObjects, 1, ...
                'one connected piece, bridged by the drawing');
            testCase.verifyEqual(nnz(after(:, :, 5) == 2), 5 * 5, ...
                'exactly what was drawn, nothing interpolated');
            testCase.verifyEqual(nnz(EditInstanceObjectsTest.readSelection(mibModel)), 0, ...
                'the drawing was used up');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect from drawing');
        end

        function connectFromADrawingTakesTheLargestAtEachEnd(testCase)
            % A bridge clipping the corner of a neighbour is the ordinary case,
            % so each end contributes one object - the one it mostly lands on.
            % Everywhere else a drawing joins everything it touches; this is the
            % one place that rule is deliberately not followed.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:4) = 6;      % 49 voxels under the stroke
            volume(16:18, 16:18, 1:4) = 3;      % 1 voxel: the clipped neighbour
            volume(10:16, 10:16, 6:9) = 2;
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 10:16, 10:16, 5);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 6), 0, 'the dominant neighbour was joined');
            testCase.verifyEqual(nnz(after == 3), nnz(volume == 3), ...
                'the clipped neighbour was left alone');
            testCase.verifyTrue(mibModel.I{1}.instanceIndex.exists(3));
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect, largest');
        end

        function connectFromADrawingWithOneEndGrowsThatObject(testCase)
            % Nothing above, so there is nothing to join and the stroke is given
            % to the one object it lands on - the same reading a Merge stroke
            % over a single object gets. No new index is handed out.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(10:16, 10:16, 1:4) = 6;
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 11:15, 11:15, 5);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 6), nnz(volume == 6) + 5 * 5, ...
                'the object grew by exactly the drawing');
            testCase.verifyEqual(numel(unique(after(after > 0))), 1, 'no new object');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect, one end');
        end

        function connectFromADrawingOnEmptySpaceBecomesANewObject(testCase)
            % Neither end lands on anything, so the stroke is a new object -
            % again the same answer the Merge gesture gives over background.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(25:30, 25:30, 1:3) = 1;      % somewhere else entirely
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 5:9, 5:9, 5);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 2), 5 * 5, 'the drawing took the next free index');
            testCase.verifyEqual(nnz(after == 1), nnz(volume == 1), 'the other object is untouched');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect, background');
        end

        function connectFromADrawingUsesWhatItCoversFirst(testCase)
            % The stroke is asked what it covers before anything else, so a
            % drawing laid across two objects in-plane means those two. The
            % lookahead is only for a bridge, which lies on background by
            % construction - object 9, directly above and below the stroke, is
            % what it would have found and must not touch.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 10]);
            volume = zeros(32, 32, 10, 'uint16');
            volume(4:10,  10:14, 4) = 1;
            volume(20:26, 10:14, 4) = 6;
            volume(12:18, 10:14, [3 5]) = 9;    % straddling the stroke in Z
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 4:26, 10:14, 4);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '');

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 6), 0, 'the two the stroke covers were joined');
            testCase.verifyEqual(nnz(after == 9), nnz(volume == 9), ...
                'the object the lookahead would have found is untouched');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'connect, covered');
        end

        function connectFromADrawingNeedsSomethingDrawn(testCase)
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            % buildSyntheticModel seeds a random Selection layer, and "nothing
            % drawn" is the whole of what this asserts.
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], [], [], []);
            before = EditInstanceObjectsTest.readLabels(mibModel);

            EditInstanceObjectsTest.runAction(mibModel, 'Connect', '');

            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
        end

        function connectFromADrawingNeeds3DMode(testCase)
            % The lookahead is a step along Z, so it is refused in 2D for the
            % reason the picked form is - and before the drawing is consumed.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            EditInstanceObjectsTest.drawIntoSelection(mibModel, [32 32 10], 11:15, 11:15, 5);
            before = EditInstanceObjectsTest.readLabels(mibModel);

            applied = mibModel.editInstanceObjects(struct( ...
                'Action', {{'Connect'}}, 'ObjectIndices', '', ...
                'Mode3D', false, 'showWaitbar', false));

            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before, 'model untouched');
            testCase.verifyEqual(nnz(EditInstanceObjectsTest.readSelection(mibModel)), 5 * 5, ...
                'the drawing survives a refusal, so it can be moved rather than made again');
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
            extra.cleanupMinObjectVoxels = {100, [0, 1e9], 'on'};
            extra.cleanupAbsorbFragmentVoxels = {0, [0, 1e6], 'on'};

            output = evalc("EditInstanceObjectsTest.runAction(mibModel, 'Cleanup', '', extra)");

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(nnz(after == 5), 0, 'object 5 has 70 voxels and goes');
            testCase.verifyGreaterThan(nnz(after == 1), 0, 'object 1 keeps its number');
            testCase.verifyGreaterThan(nnz(after == 2), 0, 'object 2 keeps its number');
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'cleanup');
            % Headless there is no window to put a dialog on, so localReport falls
            % back to stdout and the figures are readable from there.
            testCase.verifySubstring(output, '1 objects removed, 0 fragments absorbed.');
            testCase.verifySubstring(output, '2 objects left in the model.');
            testCase.verifySubstring(output, 'use Compact to renumber');
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

        function compactReportsWhatItRenumbered(testCase)
            % Compact changes every number the user has been working with and
            % nothing they can see, so what it did has to be said out loud.
            % The fixture uses 1, 2 and 5, so 1 and 2 stay put and 5 becomes 3.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            output = evalc("EditInstanceObjectsTest.runAction(mibModel, 'Compact', '')");

            % Headless there is no window to put a dialog on, so localReport falls
            % back to stdout and the figures are readable from there.
            testCase.verifySubstring(output, 'Renumbered 1 of 3 objects.');
            testCase.verifySubstring(output, '2 objects already had their final number.');
            testCase.verifySubstring(output, 'Highest index: 5 -> 3');
            testCase.verifySubstring(output, '2 unused indices reclaimed.');
            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(double(max(after(:))), 3, 'the numbering is now 1..3');
        end

        function compactIn2DRenumbersEachSliceOnItsOwn(testCase)
            % An unstitched model numbers from 1 again on every slice, so its
            % gaps are per-slice gaps. A global squeeze cannot close them: every
            % value is in use on some slice, so nothing moves anywhere.
            % Slice 4 is left empty on purpose: it must not be counted as a
            % slice that was "already in place", or the report would read
            % "2 of 501" on any real stack whose objects sit on a few slices.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 4]);
            volume = zeros(32, 32, 4, 'uint16');
            volume(1:4,   1:4, 1) = 1;   volume(1:4,  10:13, 1) = 3;   volume(1:4, 20:23, 1) = 5;
            volume(10:13, 1:4, 2) = 3;   volume(10:13, 10:13, 2) = 5;  volume(10:13, 20:23, 2) = 6;
            volume(20:23, 1:4, 3) = 1;   volume(20:23, 10:13, 3) = 2;  % already tight
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.labels.materialsCount = 6;
            mibModel.I{1}.buildInstanceIndex();

            output = evalc(['EditInstanceObjectsTest.runAction(mibModel, ''Compact'', '''', ' ...
                'struct(''Mode3D'', false))']);

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(double(unique(after(:, :, 1))'), [0 1 2 3], 'slice 1: 1,3,5 -> 1,2,3');
            testCase.verifyEqual(double(unique(after(:, :, 2))'), [0 1 2 3], 'slice 2: 3,5,6 -> 1,2,3');
            testCase.verifyEqual(double(unique(after(:, :, 3))'), [0 1 2], 'slice 3 was already tight');
            testCase.verifyEqual(double(unique(after(:, :, 4))'), 0, 'slice 4 is still empty');
            % the objects themselves must not move, only their numbers
            testCase.verifyEqual(after(1:4, 20:23, 1), repmat(uint16(3), 4, 4), 'the third blob kept its pixels');
            testCase.verifySubstring(output, 'Renumbered 2 of 3 slices with objects.');
            testCase.verifySubstring(output, '1 slices were already numbered 1, 2, 3...');
            testCase.verifySubstring(output, '4 slices in the stack.');
            testCase.verifySubstring(output, 'Highest index: 6 -> 3');
        end

        function compactIn3DLeavesThePerSliceNumberingAlone(testCase)
            % The same model through the 3D branch: every value 1..6 is in use
            % somewhere, so a global squeeze finds nothing to close. This is the
            % behaviour that made per-slice compaction necessary, and it is
            % still what 3D mode should do on a stitched model.
            mibModel = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels65535', 'dims', [32 32 3]);
            volume = zeros(32, 32, 3, 'uint16');
            volume(1:4,   1:4, 1) = 1;   volume(1:4,  10:13, 1) = 3;   volume(1:4, 20:23, 1) = 5;
            volume(10:13, 1:4, 2) = 3;   volume(10:13, 10:13, 2) = 5;  volume(10:13, 20:23, 2) = 6;
            mibModel.setData3D(volume, 'labels', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));
            mibModel.I{1}.labels.materialsCount = 6;
            mibModel.I{1}.buildInstanceIndex();

            EditInstanceObjectsTest.runAction(mibModel, 'Compact', '', struct('Mode3D', true));

            after = EditInstanceObjectsTest.readLabels(mibModel);
            testCase.verifyEqual(double(unique(after(after > 0))'), [1 2 3 4], ...
                'the four values in use became 1..4 across the whole volume');
            testCase.verifyEqual(double(unique(after(:, :, 1))'), [0 1 2 3], ...
                'slice 1 keeps three distinct numbers, but they are not renumbered per slice');
        end

        function undoCarriesAnIndexRepairNote(testCase)
            % Rebuilding the index is the one cost here that grows with the
            % dataset rather than with the edit, so an undo must not force one.
            % The note attached to the undo entry has to be enough on its own:
            % re-indexing that region alone must leave the index identical to a
            % full rebuild from the volume.
            %
            % The lookup below is the one repairIndexAfterUndo performs. It is
            % done here rather than through the controller because a view-less
            % InstanceEditor has no construction path (tests/CLAUDE.md).
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            selection = zeros(32, 32, 10, 'uint8');
            selection(4:10, 4:10, 5) = 1;        % the brush workflow: a break through object 1
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0));

            EditInstanceObjectsTest.runAction(mibModel, 'SplitBySelection', '');
            mibModel.undo();

            backup = mibModel.Backup;
            options = backup.undoList(backup.undoIndex).options;
            testCase.assertTrue(isfield(options, 'instanceIndexRepair'), ...
                'the undo entry carries no repair note');

            note = options.instanceIndexRepair;
            testCase.verifyEqual(note.timePoint, 1);
            testCase.verifyTrue(ismember(1, note.objectIds), 'the split object is named');
            testCase.verifyNumElements(note.bbox, 6);

            % Refreshing that region alone must agree with a full rebuild.
            mibModel.I{1}.buildInstanceIndex(note);
            EditInstanceObjectsTest.verifyIndexAgreesWithVolume(testCase, mibModel, 'undo repair');
        end

        function undoWritesTheVoxelsBeforeAnnouncingItself(testCase)
            % The premise controllers.InstanceEditor.repairIndexAfterUndo rests
            % on, and cannot check for itself: MibModel.undo calls setData
            % before it fires Undo, so the editor's SetData listener has
            % already marked the index stale by the time the Undo handler runs.
            % That is why the handler distinguishes staleness this undo caused
            % from staleness that was already there, rather than refusing to
            % repair a stale index outright - the bug this test exists to stop
            % coming back.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();
            recorder = mibtest.helpers.FakeWidget();   % a handle: a struct would take a copy
            setListener = addlistener(mibModel.I{1}, 'SetData', ...
                @(~, ~) EditInstanceObjectsTest.note(recorder, 'setData'));
            undoListener = addlistener(mibModel, 'Undo', ...
                @(~, ~) EditInstanceObjectsTest.note(recorder, 'undo'));
            cleanup = onCleanup(@() delete([setListener, undoListener])); %#ok<NASGU>

            EditInstanceObjectsTest.runAction(mibModel, 'Delete', '5');
            recorder.Text = '';
            mibModel.undo();

            testCase.verifySubstring(recorder.Text, 'setData undo', ...
                'undo must write the voxels before it fires its event');
        end

        function undoRepairCostsOnlyTheEditedRegion(testCase)
            % The point of the note is that it names a region, not the volume.
            % A box covering the whole dataset would be correct and useless.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            EditInstanceObjectsTest.runAction(mibModel, 'Delete', '5');

            backup = mibModel.Backup;
            note = backup.undoList(backup.undoIndex - 1).options.instanceIndexRepair;
            volumeSize = size(EditInstanceObjectsTest.readLabels(mibModel));
            boxVoxels = prod(double(note.bbox([2 4 6])) - double(note.bbox([1 3 5])) + 1);
            testCase.verifyLessThan(boxVoxels, prod(volumeSize) / 4, ...
                'the repair box should be the object, not the dataset');
        end

        function wholeModelActionsCarryNoRepairNote(testCase)
            % Cleanup and Compact rewrite everything, so no box can describe
            % them. They must not leave a note that would be acted on.
            mibModel = EditInstanceObjectsTest.buildInstanceModel();

            EditInstanceObjectsTest.runAction(mibModel, 'Compact', '');

            backup = mibModel.Backup;
            options = backup.undoList(backup.undoIndex - 1).options;
            testCase.verifyFalse(isfield(options, 'instanceIndexRepair'), ...
                'Compact must fall back to a full rebuild');
        end

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
                {'Merge', 'AddObject', 'AddToObject', 'SplitComponents', 'SplitBySelection', ...
                 'CutAtSlice', 'Connect', 'Delete', 'Cleanup', 'Compact'});
            testCase.verifyFalse(isfield(captured, 'id'), ...
                'the dataset index is not part of the published options');
            testCase.verifyEqual(EditInstanceObjectsTest.readLabels(mibModel), before);

            function onSync(~, eventData)
                captured = eventData.Parameters;
            end
        end
    end
end
