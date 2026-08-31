classdef InstanceCleanupTest < matlab.unittest.TestCase
% INSTANCECLEANUPTEST - Unit tests for utils.instances.cleanup.
%
% The cleanup filters were extracted out of utils.instances.stitch2Dto3D so the
% instance editor can offer them on an already-stitched model. The stitcher's
% own suite covers the ``compact = true`` path it uses; what is tested here is
% the behaviour that only the editor exercises:
%
%   - ``compact = false``, which deletes without renumbering, because a user who
%     has been working with object 1299 must still find it under that number;
%   - label volumes whose values have gaps, which is what a hand-edited model
%     looks like and what the stitcher never produces.
%
% See also: utils.instances.cleanup, utils.instances.stitch2Dto3D

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Static, Access = private)

        function volume = makeVolume()
            % Label values 1, 3 and 7 - gaps included on purpose, as in a model
            % that has had objects deleted.
            %   1 - large, 8 slices
            %   3 - medium, 5 slices
            %   7 - a single-slice blob of 6 voxels, well clear of the others
            volume = zeros(40, 50, 12, 'uint16');
            volume(20:26, 30:38, 4:11) = 1;
            volume(5:10,   5:12, 2:6)  = 3;
            volume(30:32, 15:16, 7)    = 7;
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % compact = false - the editor's path
        % -----------------------------------------------------------------

        function compactFalseKeepsSurvivingLabelValues(testCase)
            volume = InstanceCleanupTest.makeVolume();
            options = struct('compact', false, 'absorbFragmentVoxels', 0, 'minObjectSlices', 1);

            [cleaned, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(unique(cleaned(cleaned > 0))', uint16([1 3]), ...
                'survivors keep their original label values');
            testCase.verifyEqual(stats.numObjects, 2);
            testCase.verifyEqual(stats.numRemoved, 1);
            testCase.verifyEqual(nnz(cleaned == 7), 0, 'the shallow object is gone');
        end

        function compactTrueRenumbersToContiguous(testCase)
            volume = InstanceCleanupTest.makeVolume();
            options = struct('compact', true, 'absorbFragmentVoxels', 0, 'minObjectSlices', 1);

            [cleaned, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(unique(cleaned(cleaned > 0))', uint16([1 2]), ...
                'label values are packed down to 1..K');
            testCase.verifyEqual(stats.numObjects, 2);
            testCase.verifyEqual(stats.remap(1), 1);
            testCase.verifyEqual(stats.remap(3), 2, 'object 3 became object 2');
            testCase.verifyEqual(stats.remap(7), 0, 'a removed object maps to background');
        end

        function compactTrueClosesGapsEvenWithNothingRemoved(testCase)
            % A hand-edited model has gaps in its label space. Compaction has to
            % close them even when no filter deletes anything.
            volume = InstanceCleanupTest.makeVolume();
            options = struct('compact', true, 'absorbFragmentVoxels', 0);

            [cleaned, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(unique(cleaned(cleaned > 0))', uint16([1 2 3]));
            testCase.verifyEqual(stats.numRemoved, 0);
            testCase.verifyEqual(stats.numObjects, 3);
        end

        function compactFalseWithNothingRemovedLeavesTheVolumeAlone(testCase)
            volume = InstanceCleanupTest.makeVolume();
            options = struct('compact', false, 'absorbFragmentVoxels', 0);

            [cleaned, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(cleaned, volume);
            testCase.verifyEmpty(stats.remap);
            testCase.verifyEqual(stats.numRemoved, 0);
        end

        function compactFalseStatsStayIndexAligned(testCase)
            % The editor reads stats by label value, so the arrays must stay
            % full length with zeros where an object was removed - not squeezed
            % down the way the compacting path returns them.
            volume = InstanceCleanupTest.makeVolume();
            options = struct('compact', false, 'absorbFragmentVoxels', 0, 'minObjectSlices', 1);

            [~, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyLength(stats.objectVoxelCounts, 7);
            testCase.verifyEqual(stats.objectVoxelCounts(1), 7 * 9 * 8);
            testCase.verifyEqual(stats.objectVoxelCounts(3), 6 * 8 * 5);
            testCase.verifyEqual(stats.objectVoxelCounts(7), 0, 'removed object zeroed in place');
            testCase.verifyEqual(stats.objectSliceCounts(1), 8);
            testCase.verifyEqual(stats.objectSliceCounts(7), 0);
        end

        % -----------------------------------------------------------------
        % the filters themselves
        % -----------------------------------------------------------------

        function minObjectVoxelsRemovesSmallObjects(testCase)
            volume = InstanceCleanupTest.makeVolume();
            options = struct('compact', false, 'absorbFragmentVoxels', 0, 'minObjectVoxels', 100);

            [cleaned, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(unique(cleaned(cleaned > 0))', uint16([1 3]));
            testCase.verifyEqual(stats.numRemoved, 1);
        end

        function minObjectSlicesSeesWhatTheVoxelFilterCannot(testCase)
            % A large in-plane blob present on one slice only. No voxel
            % threshold can remove it without also deleting genuine objects.
            volume = InstanceCleanupTest.makeVolume();
            volume(1:20, 40:50, 12) = 9;      % 220 voxels, one slice
            options = struct('compact', false, 'absorbFragmentVoxels', 0);

            byVoxels = utils.instances.cleanup(volume, ...
                setfield(options, 'minObjectVoxels', 200)); %#ok<SFLD>
            bySlices = utils.instances.cleanup(volume, ...
                setfield(options, 'minObjectSlices', 1)); %#ok<SFLD>

            testCase.verifyEqual(nnz(byVoxels == 9), 220, ...
                'the voxel filter cannot reach a large shallow object');
            testCase.verifyEqual(nnz(byVoxels == 7), 0, ...
                'but it does delete the genuine small object');
            testCase.verifyEqual(nnz(bySlices == 9), 0, 'the depth filter reaches it');
        end

        function sliceCountIsOccupiedSlicesNotSpan(testCase)
            % An object bridged across a z-gap must be judged on the slices it
            % actually occupies, or a zLookback bridge would inflate the count.
            volume = zeros(20, 20, 10, 'uint16');
            volume(5:8, 5:8, 1) = 1;
            volume(5:8, 5:8, 9) = 1;          % two occupied slices, span of nine
            options = struct('compact', false, 'absorbFragmentVoxels', 0, 'minObjectSlices', 2);

            cleaned = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(nnz(cleaned), 0, ...
                'two occupied slices does not pass a threshold of two');
        end

        function absorbFillsAnEnclosedSpeck(testCase)
            % A speck stranded inside a bigger object is a hole punched in it.
            % Absorption gives the voxels back rather than deleting them.
            volume = zeros(20, 20, 3, 'uint16');
            volume(5:15, 5:15, :) = 1;
            volume(10, 10, 2) = 4;            % 1-voxel fragment inside object 1
            options = struct('compact', false, 'absorbFragmentVoxels', 5);

            [cleaned, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(cleaned(10, 10, 2), uint16(1), 'the hole is filled');
            testCase.verifyEqual(stats.numAbsorbedVoxels, 1);
            testCase.verifyEqual(stats.numAbsorbedFragments, 1);
            testCase.verifyEqual(nnz(cleaned), nnz(volume), ...
                'absorption moves voxels, it never removes them');
        end

        function absorbLeavesAFreeFloatingSpeckAlone(testCase)
            % Nothing to absorb into: the speck stays an object and is left for
            % the size filters to decide on.
            volume = zeros(20, 20, 3, 'uint16');
            volume(5:15, 5:15, :) = 1;
            volume(2, 2, 2) = 4;              % floating in background
            options = struct('compact', false, 'absorbFragmentVoxels', 5);

            [cleaned, stats] = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(cleaned(2, 2, 2), uint16(4));
            testCase.verifyEqual(stats.numAbsorbedVoxels, 0);
        end

        % -----------------------------------------------------------------
        % housekeeping
        % -----------------------------------------------------------------

        function precomputedVoxelCountsGiveTheSameResult(testCase)
            % The stitcher passes counts it already has; the answer must not
            % depend on whether they were supplied.
            volume = InstanceCleanupTest.makeVolume();
            counts = accumarray(double(volume(volume > 0)), 1, [7 1]);
            options = struct('compact', false, 'minObjectSlices', 1);

            withCounts = utils.instances.cleanup(volume, ...
                setfield(options, 'objectVoxelCounts', counts)); %#ok<SFLD>
            withoutCounts = utils.instances.cleanup(volume, options);

            testCase.verifyEqual(withCounts, withoutCounts);
        end

        function classIsDemotedOnlyWhenTheLabelsFit(testCase)
            % Judged on the highest surviving label value, not on the object
            % count - without compaction the two are different numbers.
            volume = zeros(10, 10, 2, 'uint32');
            volume(1:5, 1:5, :) = 70000;
            volume(7:9, 7:9, :) = 3;

            kept = utils.instances.cleanup(volume, struct('compact', false, 'absorbFragmentVoxels', 0));
            testCase.verifyClass(kept, 'uint32', ...
                'two objects, but a label value above 65535 must keep uint32');

            packed = utils.instances.cleanup(volume, struct('compact', true, 'absorbFragmentVoxels', 0));
            testCase.verifyClass(packed, 'uint16', 'compaction brings it into range');
            testCase.verifyEqual(unique(packed(packed > 0))', uint16([1 2]));
        end

        function emptyVolumeIsHandled(testCase)
            [cleaned, stats] = utils.instances.cleanup(zeros(8, 8, 2, 'uint16'));

            testCase.verifyEqual(nnz(cleaned), 0);
            testCase.verifyEqual(stats.numObjects, 0);
            testCase.verifyEmpty(stats.remap);
        end

        function cancelReturnsNoVolumeAtAll(testCase)
            % No partial volume: a half-cleaned stack looks valid and would be
            % written over the user's model.
            volume = InstanceCleanupTest.makeVolume();
            volume(1, 1, 1) = 4;   % a fragment, so the absorption phase runs

            wb = mibtest.helpers.FakeProgressDialog(0);
            [cleaned, ~, cancelled] = utils.instances.cleanup(volume, ...
                struct('absorbFragmentVoxels', 5), wb);

            testCase.verifyTrue(cancelled);
            testCase.verifyEmpty(cleaned);
        end

        function cancelDuringTheSliceCountPassAlsoReturnsNothing(testCase)
            volume = InstanceCleanupTest.makeVolume();
            wb = mibtest.helpers.FakeProgressDialog(0);

            [cleaned, ~, cancelled] = utils.instances.cleanup(volume, ...
                struct('absorbFragmentVoxels', 0, 'minObjectSlices', 1), wb);

            testCase.verifyTrue(cancelled);
            testCase.verifyEmpty(cleaned);
        end
    end
end
