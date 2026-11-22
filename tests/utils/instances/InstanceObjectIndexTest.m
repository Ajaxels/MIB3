classdef InstanceObjectIndexTest < matlab.unittest.TestCase
% INSTANCEOBJECTINDEXTEST - Unit tests for utils.instances.objectIndex.
%
% The index is the cache that makes the instance editor interactive: every
% operation reads an object's bounding box from it and writes only inside that
% box. A stale or wrong box therefore does not fail loudly - it silently edits
% the wrong voxels. The invariant these tests exist to protect is:
%
%   **an incrementally refreshed index is bit-identical to one rebuilt from
%   scratch on the same volume.**
%
% The index is sparse: one row per present object, sorted by index, named by
% ``.ids``. Above a highest index of 2^20 the full build measures slice by
% slice instead of with regionprops; both routes must give the same index.
%
% All cases are synthetic, headless and offline. No MibModel is needed: the
% utility is a pure [H x W x Z] label volume -> struct function.
%
% See also: utils.instances.objectIndex, utils.instances.replaceIndexRows,
% development/deepmib/split_and_merge_toolbox.md

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Static, Access = private)

        function volume = makeVolume()
            % Three objects with deliberately awkward shapes:
            %   1 - a plain block
            %   3 - a plain block, lower index than 1 so merge order can be checked
            %   7 - two spatially disjoint blobs sharing one index, with a z-gap
            %       between them, so bounding box and occupied-slice count differ
            % Index 2 and 4-6 are never used, which is what an instance model
            % looks like after objects have been deleted.
            volume = zeros(40, 50, 12, 'uint16');
            volume(20:26, 30:38, 4:11) = 1;
            volume(5:10,   5:12, 2:6)  = 3;
            volume(30:32, 10:14, 7)    = 7;
            volume(35:36, 40:42, 1:3)  = 7;
        end

        function row = rowOf(testCase, index, objectId)
            % row of an object in the index; fails the test when it has none
            [found, row] = ismember(objectId, index.ids);
            testCase.assertTrue(found, sprintf('object %d should have a row', objectId));
        end

        function verifyMatchesBruteForce(testCase, volume, index)
            % Recompute every field the slow, obvious way and compare.
            present = unique(volume(volume > 0));
            testCase.verifyEqual(index.ids, double(present(:)), 'one row per present object');
            testCase.verifyEqual(index.numObjects, numel(present));
            for row = 1:numel(present)
                objectId = double(present(row));
                voxelIndices = find(volume == objectId);
                [y, x, z] = ind2sub(size(volume), voxelIndices);
                testCase.verifyEqual(index.voxels(row), uint32(numel(voxelIndices)));
                testCase.verifyEqual(double(index.bbox(row, :)), ...
                    [min(y) max(y) min(x) max(x) min(z) max(z)], ...
                    sprintf('bounding box of object %d', objectId));
                testCase.verifyEqual(double(index.centroid(row, :)), ...
                    [mean(x) mean(y) mean(z)], 'AbsTol', 1e-3, ...
                    sprintf('centroid of object %d', objectId));
                testCase.verifyEqual(index.sliceCount(row), uint32(numel(unique(z))));
            end
        end

        function verifySameIndex(testCase, actual, expected, message)
            for field = {'ids', 'voxels', 'bbox', 'centroid', 'sliceCount', 'maxIndex', 'numObjects'}
                testCase.verifyEqual(actual.(field{1}), expected.(field{1}), ...
                    sprintf('%s: field %s', message, field{1}));
            end
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % full build
        % -----------------------------------------------------------------

        function fullBuildMatchesBruteForce(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            testCase.verifyEqual(index.maxIndex, 7);
            testCase.verifyEqual(index.numObjects, 3);
            InstanceObjectIndexTest.verifyMatchesBruteForce(testCase, volume, index);
        end

        function onlyPresentObjectsHaveRows(testCase)
            % An instance model that has had objects deleted has holes in its
            % index space. They get no rows, so the size of the index follows
            % the objects and not the highest index.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            testCase.verifyEqual(index.ids, [1; 3; 7]);
            testCase.verifySize(index.bbox, [3 6]);
            testCase.verifySize(index.centroid, [3 3]);
        end

        function highIndicesAreMeasuredSliceBySlice(testCase)
            % Above 2^20 regionprops would return one struct per value up to
            % the maximum; the slice-by-slice route must give the same index,
            % only with the higher numbers.
            volume = uint32(InstanceObjectIndexTest.makeVolume());
            reference = utils.instances.objectIndex(volume);

            offset = 1e9;
            shifted = volume;
            shifted(volume > 0) = volume(volume > 0) + offset;
            index = utils.instances.objectIndex(shifted);

            testCase.verifyEqual(index.ids, reference.ids + offset);
            testCase.verifyEqual(index.maxIndex, 7 + offset);
            for field = {'voxels', 'bbox', 'centroid', 'sliceCount', 'numObjects'}
                testCase.verifyEqual(index.(field{1}), reference.(field{1}), ...
                    'AbsTol', cast(1e-4, 'like', reference.(field{1})), sprintf('field %s', field{1}));
            end
        end

        function highIndicesOnASinglePlane(testCase)
            volume = uint32(InstanceObjectIndexTest.makeVolume());
            plane = volume(:, :, 7);
            plane(plane > 0) = plane(plane > 0) + 2^21;
            index = utils.instances.objectIndex(plane);

            testCase.verifyEqual(index.ids, [1; 7] + 2^21);
            testCase.verifyEqual(double(index.bbox(2, :)), [30 32 10 14 1 1]);
            testCase.verifyEqual(double(index.centroid(2, 3)), 1);
        end

        function highIndicesWithoutSliceCount(testCase)
            volume = uint32(InstanceObjectIndexTest.makeVolume());
            volume(volume > 0) = volume(volume > 0) + 2^21;
            index = utils.instances.objectIndex(volume, struct('computeSliceCount', false));

            testCase.verifyEqual(index.sliceCount, zeros(3, 1, 'uint32'));
            testCase.verifyEqual(index.voxels(1), uint32(7 * 9 * 8));
        end

        function sliceCountIsOccupiedSlicesNotSpan(testCase)
            % Object 7 sits on z = 1:3 and z = 7 - four occupied slices inside a
            % span of seven. Counting the span would let an object with a gap
            % pass a depth filter it should fail.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);
            row = InstanceObjectIndexTest.rowOf(testCase, index, 7);

            testCase.verifyEqual(index.sliceCount(row), uint32(4));
            testCase.verifyEqual(double(index.bbox(row, 5:6)), [1 7]);
        end

        function boundingBoxSpansDisconnectedBlobs(testCase)
            % One index covering two separate blobs gets one box around both.
            % That is correct and deliberate: the box is a read window, and both
            % blobs must be inside it or an edit would miss one of them.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);
            row = InstanceObjectIndexTest.rowOf(testCase, index, 7);

            testCase.verifyEqual(double(index.bbox(row, 1:4)), [30 36 10 42]);
        end

        function twoDimensionalVolumeStillGivesSixColumnBox(testCase)
            % regionprops drops the third dimension on a 2-D input. Callers pass
            % the box straight to getData3D as .y/.x/.z, so the shape must not
            % depend on the depth of the volume.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume(:, :, 7));
            row = InstanceObjectIndexTest.rowOf(testCase, index, 7);

            testCase.verifySize(index.bbox, [2 6]);
            testCase.verifyEqual(double(index.bbox(row, :)), [30 32 10 14 1 1]);
            testCase.verifySize(index.centroid, [2 3]);
            testCase.verifyEqual(double(index.centroid(row, 3)), 1);
            testCase.verifyEqual(index.sliceCount(row), uint32(1));
        end

        function emptyVolumeGivesEmptyIndex(testCase)
            index = utils.instances.objectIndex(zeros(8, 8, 3, 'uint16'));

            testCase.verifyEqual(index.maxIndex, 0);
            testCase.verifyEqual(index.numObjects, 0);
            testCase.verifySize(index.ids, [0 1]);
            testCase.verifySize(index.bbox, [0 6]);
        end

        function computeSliceCountFalseLeavesTheCountsZero(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume, struct('computeSliceCount', false));

            testCase.verifyEqual(index.sliceCount, zeros(3, 1, 'uint32'));
            testCase.verifyEqual(index.voxels(1), uint32(7 * 9 * 8), ...
                'the rest of the index is still built');
        end

        % -----------------------------------------------------------------
        % incremental refresh - the invariant the editor depends on
        % -----------------------------------------------------------------

        function refreshAfterMergeMatchesFullRebuild(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            merged = volume;
            merged(merged == 3) = 1;

            refreshed = utils.instances.objectIndex(merged, ...
                struct('index', index, 'objectIds', [1 3]));
            rebuilt = utils.instances.objectIndex(merged);

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, rebuilt, 'merge');
            testCase.verifyFalse(ismember(3, refreshed.ids), 'the absorbed object is gone');
            testCase.verifyEqual(double(refreshed.bbox(1, :)), [5 26 5 38 2 11], ...
                'the surviving object owns the union box');
        end

        function refreshAfterSplitAddsARow(testCase)
            % A split allocates a label value above the previous maximum; it
            % gets a row in index order.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            split = volume;
            tail = false(size(volume));  tail(:, :, 8:end) = true;
            split(volume == 1 & tail) = 9;

            refreshed = utils.instances.objectIndex(split, ...
                struct('index', index, 'objectIds', [1 9], 'bbox', [20 26 30 38 8 12]));
            rebuilt = utils.instances.objectIndex(split);

            testCase.verifyEqual(refreshed.maxIndex, 9);
            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, rebuilt, 'split');
            testCase.verifyEqual(double(refreshed.bbox(1, 5:6)), [4 7]);
            testCase.verifyEqual(double(refreshed.bbox(end, 5:6)), [8 11]);
        end

        function refreshWithAHighIndex(testCase)
            % A split into an index near the top of the 1073741823 type: the
            % refresh adds one row, it does not grow anything to that size.
            volume = uint32(InstanceObjectIndexTest.makeVolume());
            index = utils.instances.objectIndex(volume);

            highId = 1073741000;
            split = volume;
            split(volume == 3) = highId;
            refreshed = utils.instances.objectIndex(split, ...
                struct('index', index, 'objectIds', [3 highId]));
            rebuilt = utils.instances.objectIndex(split);

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, rebuilt, 'high index');
            testCase.verifyEqual(refreshed.ids, [1; 7; highId]);
        end

        function refreshAfterDeleteRemovesTheRow(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            deleted = volume;
            deleted(deleted == 3) = 0;

            refreshed = utils.instances.objectIndex(deleted, ...
                struct('index', index, 'objectIds', 3));

            testCase.verifyEqual(refreshed.ids, [1; 7]);
            testCase.verifyEqual(refreshed.numObjects, 2);
            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, ...
                utils.instances.objectIndex(deleted), 'delete');
        end

        function refreshWithoutABoxUsesThePreviousBoxes(testCase)
            % .bbox is optional. With only .objectIds the rescan region is the
            % union of those objects' previous boxes, which is enough whenever
            % the edit did not move voxels outside them (a delete, or a merge of
            % objects that are being rescanned anyway). This merge also removes
            % the highest label value, so the highest index comes down.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            merged = volume;
            merged(merged == 7) = 3;

            refreshed = utils.instances.objectIndex(merged, ...
                struct('index', index, 'objectIds', [3 7]));
            rebuilt = utils.instances.objectIndex(merged);

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, rebuilt, 'no box');
            testCase.verifyEqual(refreshed.maxIndex, 3);
        end

        function refreshKeepsFieldsItDoesNotOwn(testCase)
            % The dataset layer stores its cache bookkeeping in the same struct.
            % A refresh must not drop it.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);
            index.timePoint = 4;
            index.stale = false;

            refreshed = utils.instances.objectIndex(volume, ...
                struct('index', index, 'objectIds', 1));

            testCase.verifyEqual(refreshed.timePoint, 4);
            testCase.verifyFalse(refreshed.stale);
        end

        function refreshOfAnUnchangedVolumeChangesNothing(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            refreshed = utils.instances.objectIndex(volume, ...
                struct('index', index, 'objectIds', [1 3 7]));

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, index, 'no-op refresh');
        end

        function refreshWithNoObjectIdsIsANoOp(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            refreshed = utils.instances.objectIndex(volume, ...
                struct('index', index, 'objectIds', []));

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, index, 'empty ids');
        end

        function refreshRejectsAnIdTheVolumeClassCannotHold(testCase)
            % Catching this here beats a silently saturated cast, which would
            % match the wrong voxels and produce a plausible-looking box.
            volume = InstanceObjectIndexTest.makeVolume();   % uint16
            index = utils.instances.objectIndex(volume);

            testCase.verifyError(@() utils.instances.objectIndex(volume, ...
                struct('index', index, 'objectIds', 70000)), ...
                'utils:instances:objectIndex:idOutOfRange');
        end

        % -----------------------------------------------------------------
        % refresh from whole slices (a 2-D edit)
        % -----------------------------------------------------------------

        function sliceRefreshMatchesRebuild(testCase)
            % Part of object 1 on one slice becomes object 9. No box edge of
            % object 1 moves, so the difference over the slice must give exactly
            % what a rebuild gives - and object 9, which lives on that slice
            % only, its exact box.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            edited = volume;
            edited(20:26, 30:33, 7) = 9;

            refreshed = utils.instances.objectIndex(edited, struct('index', index, ...
                'objectIds', [1 9], 'bbox', [20 26 30 33 7 7], ...
                'previousSlices', volume(:, :, 7)));
            rebuilt = utils.instances.objectIndex(edited);

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, rebuilt, 'slice split');
        end

        function sliceRefreshReadsNothingOutsideTheSlices(testCase)
            % The point of the slice refresh: the rest of the object is taken on
            % trust from the index. Wiping object 1 from every other slice
            % behind its back must therefore not show up in the result.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            edited = volume;
            edited(20:26, 30:33, 7) = 9;
            tampered = edited;
            tampered(:, :, [1:6, 8:end]) = 0;

            refreshed = utils.instances.objectIndex(tampered, struct('index', index, ...
                'objectIds', [1 9], 'bbox', [20 26 30 33 7 7], ...
                'previousSlices', volume(:, :, 7)));
            honest = utils.instances.objectIndex(edited);

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, honest, 'slices outside the edit');
        end

        function sliceRefreshNeverNarrowsTheBox(testCase)
            % Clearing object 1 from its first slice moves its zMin, which only
            % a scan of the other slices could find. The box stays as it was -
            % larger than the object, never smaller - while everything that is
            % a sum over voxels stays exact.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            edited = volume;
            page = edited(:, :, 4);
            page(page == 1) = 0;
            edited(:, :, 4) = page;
            refreshed = utils.instances.objectIndex(edited, struct('index', index, ...
                'objectIds', 1, 'bbox', [20 26 30 38 4 4], ...
                'previousSlices', volume(:, :, 4)));
            rebuilt = utils.instances.objectIndex(edited);

            testCase.verifyEqual(refreshed.bbox(1, :), index.bbox(1, :), 'the box is not narrowed');
            testCase.verifyEqual(double(rebuilt.bbox(1, 5)), 5, 'the object now starts on slice 5');
            for field = {'ids', 'voxels', 'centroid', 'sliceCount', 'numObjects'}
                testCase.verifyEqual(refreshed.(field{1}), rebuilt.(field{1}), ...
                    sprintf('field %s', field{1}));
            end
        end

        function sliceRefreshTakingAllOfAnObjectRemovesTheRow(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            volume(2:3, 2:3, 9) = 4;             % an object on a single slice
            index = utils.instances.objectIndex(volume);

            edited = volume;
            edited(2:3, 2:3, 9) = 0;
            refreshed = utils.instances.objectIndex(edited, struct('index', index, ...
                'objectIds', 4, 'bbox', [2 3 2 3 9 9], ...
                'previousSlices', volume(:, :, 9)));

            testCase.verifyFalse(ismember(4, refreshed.ids));
            testCase.verifyEqual(refreshed.numObjects, index.numObjects - 1);
            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, ...
                utils.instances.objectIndex(edited), 'object removed from its slice');
        end

        function sliceRefreshFallsBackWhenTheIndexCannotBeRight(testCase)
            % Slices claiming more of an object than the index says it has mean
            % the index does not describe the volume. Correcting it would write
            % a wrong row, so the exact rescan is done instead.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            edited = volume;
            edited(20:26, 30:33, 7) = 9;
            impossible = ones(size(volume, 1), size(volume, 2), 'uint16');

            refreshed = utils.instances.objectIndex(edited, struct('index', index, ...
                'objectIds', [1 9], 'bbox', [20 26 30 33 7 7], ...
                'previousSlices', impossible));
            rebuilt = utils.instances.objectIndex(edited);

            InstanceObjectIndexTest.verifySameIndex(testCase, refreshed, rebuilt, 'fallback');
        end

        function sliceRefreshRejectsSlicesOfTheWrongSize(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            testCase.verifyError(@() utils.instances.objectIndex(volume, struct('index', index, ...
                'objectIds', 1, 'bbox', [20 26 30 33 7 7], ...
                'previousSlices', volume(20:26, 30:33, 7))), ...
                'utils:instances:objectIndex:previousSlicesSize');
        end

        % -----------------------------------------------------------------
        % replaceIndexRows
        % -----------------------------------------------------------------

        function replaceIndexRowsKeepsTheRowsSorted(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);
            rows = struct('ids', [5; 2], 'voxels', [10; 20], 'bbox', [1 2 1 2 1 1; 3 4 3 4 2 2], ...
                'centroid', [1.5 1.5 1; 3.5 3.5 2], 'sliceCount', [1; 1]);

            updated = utils.instances.replaceIndexRows(index, [7 5 2], rows);

            testCase.verifyEqual(updated.ids, [1; 2; 3; 5]);
            testCase.verifyEqual(updated.voxels, uint32([index.voxels(1); 20; index.voxels(2); 10]));
            testCase.verifyEqual(updated.bbox(2, :), int32([3 4 3 4 2 2]));
            testCase.verifyEqual(updated.maxIndex, 5);
            testCase.verifyEqual(updated.numObjects, 4);
        end

        % -----------------------------------------------------------------
        % cancellation
        % -----------------------------------------------------------------

        function cancelReturnsNoIndexAtAll(testCase)
            % No partial index: a half-filled one looks valid and its stale
            % boxes would be used for the next edit.
            volume = InstanceObjectIndexTest.makeVolume();
            wb = mibtest.helpers.FakeProgressDialog(0);   % cancel on the first poll

            [index, cancelled] = utils.instances.objectIndex(volume, struct(), wb);

            testCase.verifyTrue(cancelled);
            testCase.verifyEmpty(index);
        end

        function cancelDuringTheSliceCountPassAlsoReturnsNothing(testCase)
            % The slice-count loop is the second cancel point; the first poll is
            % spent before regionprops runs.
            volume = InstanceObjectIndexTest.makeVolume();
            wb = mibtest.helpers.FakeProgressDialog(1);

            [index, cancelled] = utils.instances.objectIndex(volume, struct(), wb);

            testCase.verifyTrue(cancelled);
            testCase.verifyEmpty(index);
        end

        function cancelDuringTheSliceBySliceBuildReturnsNothing(testCase)
            volume = uint32(InstanceObjectIndexTest.makeVolume());
            volume(volume > 0) = volume(volume > 0) + 2^21;
            wb = mibtest.helpers.FakeProgressDialog(3);

            [index, cancelled] = utils.instances.objectIndex(volume, struct(), wb);

            testCase.verifyTrue(cancelled);
            testCase.verifyEmpty(index);
        end

        function aProgressDialogDoesNotChangeTheResult(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            wb = mibtest.helpers.FakeProgressDialog();   % present, never cancels

            withDialog = utils.instances.objectIndex(volume, struct(), wb);
            withoutDialog = utils.instances.objectIndex(volume);

            InstanceObjectIndexTest.verifySameIndex(testCase, withDialog, withoutDialog, 'with wb');
            testCase.verifyNotEmpty(wb.Message, 'the phase should be reported');
        end
    end
end
