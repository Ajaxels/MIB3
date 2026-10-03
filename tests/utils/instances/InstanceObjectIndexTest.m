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
% All cases are synthetic, headless and offline. No MibModel is needed: the
% utility is a pure [H x W x Z] label volume -> struct function.
%
% See also: utils.instances.objectIndex, development/deepmib/split_and_merge_toolbox.md

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

        function verifyMatchesBruteForce(testCase, volume, index)
            % Recompute every field the slow, obvious way and compare.
            for objectId = 1:index.maxIndex
                voxelIndices = find(volume == objectId);
                if isempty(voxelIndices)
                    testCase.verifyFalse(index.exists(objectId), ...
                        sprintf('object %d should be absent', objectId));
                    testCase.verifyEqual(index.voxels(objectId), uint32(0));
                    testCase.verifyEqual(index.bbox(objectId, :), zeros(1, 6, 'int32'));
                    continue;
                end
                [y, x, z] = ind2sub(size(volume), voxelIndices);
                testCase.verifyTrue(index.exists(objectId));
                testCase.verifyEqual(index.voxels(objectId), uint32(numel(voxelIndices)));
                testCase.verifyEqual(double(index.bbox(objectId, :)), ...
                    [min(y) max(y) min(x) max(x) min(z) max(z)], ...
                    sprintf('bounding box of object %d', objectId));
                testCase.verifyEqual(double(index.centroid(objectId, :)), ...
                    [mean(x) mean(y) mean(z)], 'AbsTol', 1e-3, ...
                    sprintf('centroid of object %d', objectId));
                testCase.verifyEqual(index.sliceCount(objectId), uint32(numel(unique(z))));
            end
        end

        function verifySameIndex(testCase, actual, expected, message)
            for field = {'exists', 'voxels', 'bbox', 'centroid', 'sliceCount', 'maxIndex', 'numObjects'}
                testCase.verifyEqual(actual.(field{1}), expected.(field{1}), ...
                    sprintf('%s: field %s', message, field{1}));
            end
        end

        function verifySameOverSharedRange(testCase, refreshed, rebuilt, message)
            % A refresh never shrinks the index space, so when an edit removes
            % the highest label value the two indices have different lengths by
            % design. Compare the range they share and require the refreshed
            % tail to be free - those vacated values are what the next split
            % allocates from, which a rebuild cannot know about.
            shared = rebuilt.maxIndex;
            testCase.verifyGreaterThanOrEqual(refreshed.maxIndex, shared);
            for field = {'exists', 'voxels', 'bbox', 'centroid', 'sliceCount'}
                testCase.verifyEqual(refreshed.(field{1})(1:shared, :), ...
                    rebuilt.(field{1})(1:shared, :), ...
                    sprintf('%s: field %s', message, field{1}));
            end
            testCase.verifyEqual(refreshed.numObjects, rebuilt.numObjects, ...
                sprintf('%s: object count', message));
            testCase.verifyFalse(any(refreshed.exists(shared+1:end)), ...
                sprintf('%s: entries above the rebuilt maximum must be free', message));
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

        function gapsInTheIndexSpaceAreMarkedAbsent(testCase)
            % An instance model that has had objects deleted has holes in its
            % index space. Those entries must read as absent rather than as
            % zero-sized objects, because the first hole is where the next
            % split allocates its new index from.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            testCase.verifyEqual(find(~index.exists)', [2 4 5 6]);
            testCase.verifyEqual(find(~index.exists, 1), 2, ...
                'the next free index is the first gap');
        end

        function sliceCountIsOccupiedSlicesNotSpan(testCase)
            % Object 7 sits on z = 1:3 and z = 7 - four occupied slices inside a
            % span of seven. Counting the span would let an object with a gap
            % pass a depth filter it should fail.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            testCase.verifyEqual(index.sliceCount(7), uint32(4));
            testCase.verifyEqual(double(index.bbox(7, 5:6)), [1 7]);
        end

        function boundingBoxSpansDisconnectedBlobs(testCase)
            % One index covering two separate blobs gets one box around both.
            % That is correct and deliberate: the box is a read window, and both
            % blobs must be inside it or an edit would miss one of them.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            testCase.verifyEqual(double(index.bbox(7, 1:4)), [30 36 10 42]);
        end

        function twoDimensionalVolumeStillGivesSixColumnBox(testCase)
            % regionprops drops the third dimension on a 2-D input. Callers pass
            % the box straight to getData3D as .y/.x/.z, so the shape must not
            % depend on the depth of the volume.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume(:, :, 7));

            testCase.verifySize(index.bbox, [7 6]);
            testCase.verifyEqual(double(index.bbox(7, :)), [30 32 10 14 1 1]);
            testCase.verifySize(index.centroid, [7 3]);
            testCase.verifyEqual(double(index.centroid(7, 3)), 1);
            testCase.verifyEqual(index.sliceCount(7), uint32(1));
        end

        function emptyVolumeGivesEmptyIndex(testCase)
            index = utils.instances.objectIndex(zeros(8, 8, 3, 'uint16'));

            testCase.verifyEqual(index.maxIndex, 0);
            testCase.verifyEqual(index.numObjects, 0);
            testCase.verifyEmpty(index.exists);
            testCase.verifyEmpty(index.bbox);
        end

        function computeSliceCountFalseLeavesTheCountsZero(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume, struct('computeSliceCount', false));

            testCase.verifyEqual(index.sliceCount, zeros(7, 1, 'uint32'));
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
            testCase.verifyFalse(refreshed.exists(3), 'the absorbed object is gone');
            testCase.verifyEqual(double(refreshed.bbox(1, :)), [5 26 5 38 2 11], ...
                'the surviving object owns the union box');
        end

        function refreshAfterSplitGrowsTheIndex(testCase)
            % A split allocates a label value above the previous maximum, so the
            % arrays have to grow. Getting this wrong writes out of bounds.
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
            testCase.verifyEqual(double(refreshed.bbox(9, 5:6)), [8 11]);
        end

        function refreshAfterDeleteClearsTheEntry(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            deleted = volume;
            deleted(deleted == 3) = 0;

            refreshed = utils.instances.objectIndex(deleted, ...
                struct('index', index, 'objectIds', 3));

            testCase.verifyFalse(refreshed.exists(3));
            testCase.verifyEqual(refreshed.voxels(3), uint32(0));
            testCase.verifyEqual(refreshed.bbox(3, :), zeros(1, 6, 'int32'));
            testCase.verifyEqual(refreshed.centroid(3, :), zeros(1, 3, 'single'));
            testCase.verifyEqual(refreshed.sliceCount(3), uint32(0));
            testCase.verifyEqual(refreshed.numObjects, 2);
        end

        function refreshWithoutABoxUsesThePreviousBoxes(testCase)
            % .bbox is optional. With only .objectIds the rescan region is the
            % union of those objects' previous boxes, which is enough whenever
            % the edit did not move voxels outside them (a delete, or a merge of
            % objects that are being rescanned anyway).
            %
            % This merge also removes the highest label value, so it is the case
            % where refresh and rebuild legitimately differ in length.
            volume = InstanceObjectIndexTest.makeVolume();
            index = utils.instances.objectIndex(volume);

            merged = volume;
            merged(merged == 7) = 3;

            refreshed = utils.instances.objectIndex(merged, ...
                struct('index', index, 'objectIds', [3 7]));
            rebuilt = utils.instances.objectIndex(merged);

            InstanceObjectIndexTest.verifySameOverSharedRange(testCase, refreshed, rebuilt, 'no box');
            testCase.verifyEqual(rebuilt.maxIndex, 3, 'the rebuild shrinks to the new maximum');
            testCase.verifyEqual(refreshed.maxIndex, 7, 'the refresh keeps the vacated values free');
            testCase.verifyEqual(find(~refreshed.exists)', [2 4 5 6 7], ...
                'index 7 is now available for the next split');
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
            for field = {'exists', 'voxels', 'centroid', 'sliceCount', 'numObjects'}
                testCase.verifyEqual(refreshed.(field{1}), rebuilt.(field{1}), ...
                    sprintf('field %s', field{1}));
            end
        end

        function sliceRefreshTakingAllOfAnObjectClearsTheEntry(testCase)
            volume = InstanceObjectIndexTest.makeVolume();
            volume(2:3, 2:3, 9) = 4;             % an object on a single slice
            index = utils.instances.objectIndex(volume);

            edited = volume;
            edited(2:3, 2:3, 9) = 0;
            refreshed = utils.instances.objectIndex(edited, struct('index', index, ...
                'objectIds', 4, 'bbox', [2 3 2 3 9 9], ...
                'previousSlices', volume(:, :, 9)));

            testCase.verifyFalse(refreshed.exists(4));
            testCase.verifyEqual(refreshed.voxels(4), uint32(0));
            testCase.verifyEqual(refreshed.bbox(4, :), zeros(1, 6, 'int32'));
            testCase.verifyEqual(refreshed.centroid(4, :), zeros(1, 3, 'single'));
            testCase.verifyEqual(refreshed.sliceCount(4), uint32(0));
            testCase.verifyEqual(refreshed.numObjects, index.numObjects - 1);
        end

        function sliceRefreshFallsBackWhenTheIndexCannotBeRight(testCase)
            % Slices claiming more of an object than the index says it has mean
            % the index does not describe the volume. Correcting it would write
            % a wrong entry, so the exact rescan is done instead.
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
