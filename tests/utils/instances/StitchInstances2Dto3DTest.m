classdef StitchInstances2Dto3DTest < matlab.unittest.TestCase
% STITCHINSTANCES2DTO3DTEST - Regression + measurement harness for
% utils.instances.stitch2Dto3D (2D->3D instance label stitching).
%
% Purpose (Phase A of development/deepmib/instance_3d_plan.md):
%   - lock in the validated correctness (scrambled per-slice IDs must be
%     reconstructed into the original 3D objects with no false merges/splits);
%   - provide the false-merge / false-split objective function that later
%     phases (anisotropy, hysteresis edges) are tuned against;
%   - simulate anisotropy by z-subsampling an isotropic synthetic volume.
%
% All cases are synthetic, headless and offline (Unit). No MibModel is needed:
% the utility is a pure [H x W x Z] label-volume -> label-volume function.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Static, Access = private)

        function [gt, scrambled] = makeStack(numObjects, dims, seed)
            % Build a GT 3D instance volume of vertical "columns": each object
            % is a filled disk at a fixed (x,y) spanning a contiguous z-range,
            % so consecutive slices overlap strongly (isotropic-like). Then
            % return a per-slice-scrambled copy that hides the 3D identity.
            %
            % Objects are laid on a non-overlapping grid (one per cell) so they
            % are guaranteed spatially disjoint - the correctness invariant is
            % "no false merge", which only holds if the GT objects never touch.
            if nargin < 4 || isempty(seed); seed = 42; end
            rng(seed, 'twister');
            H = dims(1); W = dims(2); Z = dims(3);
            gt = zeros(H, W, Z, 'uint16');

            [xGrid, yGrid] = meshgrid(1:W, 1:H);
            nCols = ceil(sqrt(numObjects));
            nRows = ceil(numObjects / nCols);
            cellW = floor(W / nCols);
            cellH = floor(H / nRows);
            % radius small enough that a disk plus a 1px gap fits inside a cell
            radius = max(3, floor(min(cellW, cellH) / 2) - 2);

            for objectId = 1:numObjects
                col = mod(objectId - 1, nCols);
                row = floor((objectId - 1) / nCols);
                cx = col * cellW + round(cellW / 2);
                cy = row * cellH + round(cellH / 2);
                zStart = randi([1, max(1, Z - 3)]);
                zEnd   = min(Z, zStart + randi([2, Z]));
                disk = (xGrid - cx).^2 + (yGrid - cy).^2 <= radius^2;
                for z = zStart:zEnd
                    slice = gt(:, :, z);
                    slice(disk) = objectId;
                    gt(:, :, z) = slice;
                end
            end

            % Scramble: relabel each slice's objects to arbitrary IDs so that
            % the same 3D object carries different IDs on different slices.
            scrambled = zeros(size(gt), 'uint16');
            for z = 1:Z
                slice = gt(:, :, z);
                ids = unique(slice(slice > 0));
                if isempty(ids); continue; end
                newIds = randperm(1000, numel(ids));   % arbitrary, per-slice
                out = zeros(size(slice), 'uint16');
                for k = 1:numel(ids)
                    out(slice == ids(k)) = newIds(k);
                end
                scrambled(:, :, z) = out;
            end
        end

        function V = readMultipageTiff(tiffFile)
            % Read a multi-page TIFF into an [H x W x nPages] uint16 stack.
            info = imfinfo(tiffFile);
            nPages = numel(info);
            V = zeros(info(1).Height, info(1).Width, nPages, 'uint16');
            t = Tiff(tiffFile, 'r');
            cleanup = onCleanup(@() t.close());
            for z = 1:nPages
                t.setDirectory(z);
                V(:, :, z) = t.read();
            end
        end

        function V = readSliceFolder(folder, templateSize)
            % Read a folder of per-slice label TIFFs (name-sorted) into a stack.
            files = dir(fullfile(folder, '*.tif'));
            [~, order] = sort({files.name});
            files = files(order);
            V = zeros(templateSize(1), templateSize(2), numel(files), 'uint16');
            for z = 1:numel(files)
                V(:, :, z) = imread(fullfile(files(z).folder, files(z).name));
            end
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % Correctness: scrambled per-slice IDs reconstructed into 3D objects
        % -----------------------------------------------------------------

        function graph_reconstructsScrambledStack(testCase)
            numObjects = 6;
            [gt, scrambled] = StitchInstances2Dto3DTest.makeStack(numObjects, [96 96 20]);

            opt = struct('method', 'graph');
            [stitched, stats] = utils.instances.stitch2Dto3D(scrambled, opt);

            metrics = mibtest.helpers.instanceStitchMetrics(stitched, gt);

            testCase.verifyEqual(stats.numOutput3DObjects, numObjects, ...
                'graph method must recover exactly the GT object count');
            testCase.verifyEqual(metrics.numFalseMerge, 0, ...
                'no two GT objects may be fused into one output label');
            testCase.verifyEqual(metrics.numFalseSplit, 0, ...
                'no GT object may be split across output labels');
            testCase.verifyEqual(metrics.numOneToOne, numObjects, ...
                'every GT object must map one-to-one to an output label');
        end

        function hungarian_reconstructsScrambledStack(testCase)
            numObjects = 5;
            [gt, scrambled] = StitchInstances2Dto3DTest.makeStack(numObjects, [96 96 18], 7);

            opt = struct('method', 'hungarian', 'bidirectional', true);
            [stitched, stats] = utils.instances.stitch2Dto3D(scrambled, opt);

            metrics = mibtest.helpers.instanceStitchMetrics(stitched, gt);
            testCase.verifyEqual(stats.numOutput3DObjects, numObjects);
            testCase.verifyEqual(metrics.numFalseMerge, 0);
            testCase.verifyEqual(metrics.numFalseSplit, 0);
        end

        % -----------------------------------------------------------------
        % Cancellation through the caller's progress dialog
        % -----------------------------------------------------------------

        function progressDialogDoesNotChangeTheResult(testCase)
            % A dialog the user never cancels must be invisible to the result.
            [~, scrambled] = StitchInstances2Dto3DTest.makeStack(6, [96 96 20]);

            [withoutDialog, statsWithout] = utils.instances.stitch2Dto3D(scrambled);
            waitbar = mibtest.helpers.FakeProgressDialog();
            [withDialog, statsWith] = utils.instances.stitch2Dto3D(scrambled, struct(), waitbar);

            testCase.verifyEqual(withDialog, withoutDialog, ...
                'passing a progress dialog must not alter the stitched volume');
            testCase.verifyFalse(statsWith.cancelled);
            testCase.verifyFalse(statsWithout.cancelled, ...
                'stats.cancelled must be present and false when no dialog is passed');
            testCase.verifyEqual(statsWith.numOutput3DObjects, statsWithout.numOutput3DObjects);
            testCase.verifyNotEmpty(waitbar.Message, ...
                'the current phase must be reported to the dialog');
        end

        function cancelReturnsNoVolumeAtAllPhases(testCase)
            % Cancelling must never hand back a partly stitched volume - it
            % would look like a valid result and be written over the model.
            % A full uncancelled run is measured first to learn how many polls
            % the whole job makes, and the cancel is then placed at the start,
            % the middle and near the end of that budget. Deriving the numbers
            % keeps the case meaningful if the polls are ever moved around; a
            % hard-coded budget past the total would silently stop cancelling.
            [~, scrambled] = StitchInstances2Dto3DTest.makeStack(6, [96 96 20]);
            opt = struct('minObjectSlices', 1, 'absorbFragmentVoxels', 2);

            reference = mibtest.helpers.FakeProgressDialog();
            utils.instances.stitch2Dto3D(scrambled, opt, reference);
            totalPolls = reference.polls;
            testCase.assumeGreaterThan(totalPolls, 4, ...
                'the run must poll often enough for the budgets below to differ');

            budgets = [0, floor(totalPolls/2), totalPolls-1];
            for k = 1:numel(budgets)
                waitbar = mibtest.helpers.FakeProgressDialog(budgets(k));
                [stitched, stats] = utils.instances.stitch2Dto3D(scrambled, opt, waitbar);
                testCase.verifyTrue(stats.cancelled, ...
                    sprintf('cancel after %d polls must be reported', budgets(k)));
                testCase.verifyEmpty(stitched, ...
                    sprintf('cancel after %d polls must return no volume', budgets(k)));
                testCase.verifyGreaterThan(waitbar.polls, budgets(k), ...
                    'the function must keep working until the cancel is raised');
            end
        end

        function cancelIsHonouredByHungarianToo(testCase)
            [~, scrambled] = StitchInstances2Dto3DTest.makeStack(5, [96 96 18], 7);
            waitbar = mibtest.helpers.FakeProgressDialog(25);
            [stitched, stats] = utils.instances.stitch2Dto3D(scrambled, ...
                struct('method', 'hungarian'), waitbar);
            testCase.verifyTrue(stats.cancelled);
            testCase.verifyEmpty(stitched);
        end

        % -----------------------------------------------------------------
        % Edge cases
        % -----------------------------------------------------------------

        function emptyVolumeReturnsEmptyStats(testCase)
            empty = zeros(32, 32, 8, 'uint16');
            [stitched, stats] = utils.instances.stitch2Dto3D(empty);
            testCase.verifyEqual(stats.numInput2DObjects, 0);
            testCase.verifyEqual(stats.numOutput3DObjects, 0);
            testCase.verifyEqual(nnz(stitched), 0);
        end

        function singleSliceIsPreserved(testCase)
            % A single-slice stack: every 2D object is its own 3D object.
            slice = zeros(40, 40, 1, 'uint16');
            slice(5:10,  5:10)  = 3;
            slice(20:30, 20:30) = 7;
            [~, stats] = utils.instances.stitch2Dto3D(slice);
            testCase.verifyEqual(stats.numOutput3DObjects, 2);
        end

        function outputClassPromotesToUint16(testCase)
            [~, scrambled] = StitchInstances2Dto3DTest.makeStack(4, [48 48 10]);
            stitched = utils.instances.stitch2Dto3D(scrambled);
            testCase.verifyClass(stitched, 'uint16');
        end

        % -----------------------------------------------------------------
        % zLookback bridges a single-slice dropout
        % -----------------------------------------------------------------

        function zLookbackBridgesDropout(testCase)
            % One object present on z=1,2 and z=4,5 but absent on z=3.
            % zLookback=1 -> two objects; zLookback=2 -> one object.
            V = zeros(40, 40, 5, 'uint16');
            disk = false(40, 40);
            [xg, yg] = meshgrid(1:40, 1:40);
            disk((xg - 20).^2 + (yg - 20).^2 <= 8^2) = true;
            for z = [1 2 4 5]
                slice = zeros(40, 40, 'uint16');
                slice(disk) = randi(500);   % scrambled per-slice id
                V(:, :, z) = slice;
            end

            [~, statsAdjacent] = utils.instances.stitch2Dto3D(V, struct('zLookback', 1));
            [~, statsBridged]  = utils.instances.stitch2Dto3D(V, struct('zLookback', 2));

            testCase.verifyEqual(statsAdjacent.numOutput3DObjects, 2, ...
                'adjacent-only linking cannot cross the empty slice');
            testCase.verifyEqual(statsBridged.numOutput3DObjects, 1, ...
                'zLookback=2 must bridge the single-slice dropout');
        end

        % -----------------------------------------------------------------
        % minObjectVoxels removes noise fragments
        % -----------------------------------------------------------------

        function minObjectVoxelsRemovesFragments(testCase)
            [~, scrambled] = StitchInstances2Dto3DTest.makeStack(4, [64 64 12], 11);
            % add a tiny single-voxel fragment on one slice
            scrambled(1, 1, 1) = 999;

            [~, statsKeep] = utils.instances.stitch2Dto3D(scrambled, struct('minObjectVoxels', 0));
            [~, statsDrop] = utils.instances.stitch2Dto3D(scrambled, struct('minObjectVoxels', 50));

            testCase.verifyLessThan(statsDrop.numOutput3DObjects, statsKeep.numOutput3DObjects, ...
                'minObjectVoxels must drop at least the 1-voxel fragment');
            testCase.verifyGreaterThanOrEqual(min(statsDrop.objectVoxelCounts), 50);
        end

        % -----------------------------------------------------------------
        % Anisotropy: relaxed IoU recovers a laterally drifting object
        % -----------------------------------------------------------------

        function anisotropyRelaxationRecoversDriftingTube(testCase)
            % One object drifting 12 px/slice: adjacent cross-sections overlap
            % but with low IoU (~0.17) and low IoA (~0.29), so default settings
            % over-split it into per-slice fragments. anisotropyZ = 2 lowers the
            % effective IoU threshold enough to relink it into one object.
            H = 64; W = 100; Z = 6; radius = 10;
            [xg, yg] = meshgrid(1:W, 1:H);
            V = zeros(H, W, Z, 'uint16');
            for z = 1:Z
                cx = 15 + 12 * (z - 1);
                disk = (xg - cx).^2 + (yg - 32).^2 <= radius^2;
                slice = zeros(H, W, 'uint16');
                slice(disk) = randi(500);   % scrambled per-slice id
                V(:, :, z) = slice;
            end

            [~, statsDefault] = utils.instances.stitch2Dto3D(V, struct('anisotropyZ', 1));
            [~, statsAniso]   = utils.instances.stitch2Dto3D(V, struct('anisotropyZ', 2));

            testCase.verifyGreaterThan(statsDefault.numOutput3DObjects, 1, ...
                'isotropic thresholds should over-split the drifting object');
            testCase.verifyEqual(statsAniso.numOutput3DObjects, 1, ...
                'anisotropyZ=2 should relink the drifting object into one');
        end

        % -----------------------------------------------------------------
        % Centroid gate: prevents a far-apart containment link from fusing
        % two distinct objects
        % -----------------------------------------------------------------

        function centroidGatePreventsFalseMerge(testCase)
            % z=1: big square P (rows/cols 10:60). z=2: shrunk P (10:40) plus a
            % small separate square Q (50:58) sitting inside P's z=1 footprint.
            % Q is fully contained in P(z1) -> IoA = 1 -> a strong (false) link.
            % Both P->P and P->Q pass without a gate (one component). A centroid
            % cap of 20 px keeps the P->P continuation (centroid shift ~14) but
            % rejects the P->Q link (centroid shift ~27), splitting Q back out.
            H = 80; W = 80; Z = 2;
            V = zeros(H, W, Z, 'uint16');
            V(10:60, 10:60, 1) = 1;              % P on z=1 (big)
            V(10:40, 10:40, 2) = 1;              % P on z=2 (shrunk, top-left)
            V(50:58, 50:58, 2) = 2;              % Q on z=2 (separate, inside P z1)

            [~, statsNoGate] = utils.instances.stitch2Dto3D(V, struct('maxCentroidShift', inf));
            [~, statsGate]   = utils.instances.stitch2Dto3D(V, struct('maxCentroidShift', 20));

            testCase.verifyEqual(statsNoGate.numOutput3DObjects, 1, ...
                'without the gate, containment fuses P and Q into one object');
            testCase.verifyEqual(statsGate.numOutput3DObjects, 2, ...
                'the centroid gate must keep the far-apart Q separate from P');
        end

        % -----------------------------------------------------------------
        % Centroid-NN gap bridging: reconnect a continuation with no overlap
        % -----------------------------------------------------------------

        function centroidLinkBridgesNonOverlappingDrift(testCase)
            % One object drifting 12 px/slice with radius 5: consecutive discs
            % do NOT overlap at all, so the overlap graph splits it into 5
            % objects. centroidLinkRadius=15 links the mutually-nearest orphans
            % across each gap and recovers a single object.
            H = 64; W = 100; Z = 5; radius = 5;
            [xg, yg] = meshgrid(1:W, 1:H);
            V = zeros(H, W, Z, 'uint16');
            for z = 1:Z
                cx = 15 + 12 * (z - 1);
                slice = zeros(H, W, 'uint16');
                slice((xg - cx).^2 + (yg - 32).^2 <= radius^2) = randi(500);
                V(:, :, z) = slice;
            end

            [~, statsOff] = utils.instances.stitch2Dto3D(V, struct('centroidLinkRadius', 0));
            [~, statsOn]  = utils.instances.stitch2Dto3D(V, struct('centroidLinkRadius', 15));

            testCase.verifyEqual(statsOff.numOutput3DObjects, 5, ...
                'no overlap between drifted discs -> overlap graph splits into 5');
            testCase.verifyEqual(statsOn.numOutput3DObjects, 1, ...
                'centroid-NN must bridge the non-overlapping continuation');
        end

        function centroidLinkKeepsParallelTubesSeparate(testCase)
            % Two parallel drifting tubes (y=20 and y=50), each drifting 12
            % px/slice with radius 5. Same-tube neighbours are 12 px apart;
            % cross-tube neighbours are ~32 px apart. centroidLinkRadius=15 must
            % recover each tube (2 objects) without cross-linking them.
            H = 70; W = 100; Z = 5; radius = 5;
            [xg, yg] = meshgrid(1:W, 1:H);
            V = zeros(H, W, Z, 'uint16');
            for z = 1:Z
                cx = 15 + 12 * (z - 1);
                slice = zeros(H, W, 'uint16');
                slice((xg - cx).^2 + (yg - 20).^2 <= radius^2) = randi(500);
                slice((xg - cx).^2 + (yg - 50).^2 <= radius^2) = randi(500) + 500;
                V(:, :, z) = slice;
            end

            [~, statsOff] = utils.instances.stitch2Dto3D(V, struct('centroidLinkRadius', 0));
            [~, statsOn]  = utils.instances.stitch2Dto3D(V, struct('centroidLinkRadius', 15));

            testCase.verifyEqual(statsOff.numOutput3DObjects, 10);
            testCase.verifyEqual(statsOn.numOutput3DObjects, 2, ...
                'mutual-NN must recover both tubes without fusing them');
        end

        function absOverlapPixelsLinksLargeAgainstSmall(testCase)
            % Reproduces a real miss: a wide cross-section on z=1 meeting a
            % much narrower one on z=2. Both ratios are dragged down by the
            % size difference (IoU ~0.15, IoA ~0.42, against defaults of 0.25
            % and 0.50) even though the two share hundreds of pixels.
            V = zeros(120, 120, 2, 'uint16');
            V(11:70,  11:74, 1) = 5;    % 60 x 64 = 3840 px
            V(56:95,  11:66, 2) = 8;    % 40 x 56 = 2240 px, overlaps rows 56:70
            shared = 15 * 56;           % 840 px -> IoU 0.160, IoA 0.375

            [~, ratiosOnly] = utils.instances.stitch2Dto3D(V);
            testCase.verifyEqual(ratiosOnly.numOutput3DObjects, 2, ...
                'IoU/IoA are expected to miss this pair - that is the point of the test');

            [~, withAbs] = utils.instances.stitch2Dto3D(V, ...
                struct('absOverlapPixels', shared));
            testCase.verifyEqual(withAbs.numOutput3DObjects, 1, ...
                'an absolute overlap at the threshold must link the pair');

            [~, tooHigh] = utils.instances.stitch2Dto3D(V, ...
                struct('absOverlapPixels', shared + 1));
            testCase.verifyEqual(tooHigh.numOutput3DObjects, 2, ...
                'one pixel above the shared area must not link');
        end

        function absOverlapPixelsStillObeysCentroidGate(testCase)
            % The absolute-overlap link is a sufficient condition on the ratio
            % tests, not an override of the guards: maxCentroidShift must still
            % be able to veto it.
            V = zeros(120, 120, 2, 'uint16');
            V(11:70,  11:74, 1) = 5;
            V(56:95,  11:66, 2) = 8;
            opts = struct('absOverlapPixels', 800);

            [~, gateOff] = utils.instances.stitch2Dto3D(V, opts);
            opts.maxCentroidShift = 5;   % the centroids are ~35 px apart
            [~, gateOn] = utils.instances.stitch2Dto3D(V, opts);

            testCase.verifyEqual(gateOff.numOutput3DObjects, 1);
            testCase.verifyEqual(gateOn.numOutput3DObjects, 2, ...
                'the centroid gate must still veto an absolute-overlap link');
        end

        function minObjectSlicesRemovesShallowObjects(testCase)
            % A real object spanning the stack, plus two false detections that
            % are LARGER in-plane but live on 1 and 2 slices. minObjectVoxels
            % cannot separate them (the noise outweighs the signal); the slice
            % threshold can, and its levels must be monotone.
            H = 60; W = 90; Z = 6;
            V = zeros(H, W, Z, 'uint16');
            V(5:14,  5:14,  :)   = 1;    % real: 10x10 over 6 slices
            V(5:24,  30:49, 3)   = 2;    % noise: 20x20 on one slice
            V(5:24,  60:79, 4:5) = 3;    % noise: 20x20 on two slices

            [~, keepAll] = utils.instances.stitch2Dto3D(V, struct('minObjectSlices', 0));
            [~, dropOne] = utils.instances.stitch2Dto3D(V, struct('minObjectSlices', 1));
            [~, dropTwo] = utils.instances.stitch2Dto3D(V, struct('minObjectSlices', 2));
            testCase.verifyEqual(keepAll.numOutput3DObjects, 3);
            testCase.verifyEqual(dropOne.numOutput3DObjects, 2, ...
                'the single-slice detection must go');
            testCase.verifyEqual(dropTwo.numOutput3DObjects, 1, ...
                'the two-slice detection must go as well');

            % the survivor is the real object, and it is the SMALLEST of the three
            [labels, stats] = utils.instances.stitch2Dto3D(V, struct('minObjectSlices', 2));
            testCase.verifyEqual(stats.objectVoxelCounts, 10*10*Z);
            testCase.verifyEqual(unique(labels(labels > 0)), uint16(1));
            testCase.verifyEqual(stats.objectSliceCounts, Z);
        end

        function minObjectSlicesCountsOccupiedSlicesNotSpan(testCase)
            % An object bridged by zLookback over a missing slice occupies 2
            % slices but spans 3. The threshold must count what is occupied,
            % so minObjectSlices=2 removes it and =1 keeps it.
            V = zeros(30, 30, 3, 'uint16');
            V(10:20, 10:20, 1) = 4;
            V(10:20, 10:20, 3) = 9;      % slice 2 is empty - a dropout

            opts = struct('zLookback', 2);
            [~, bridged] = utils.instances.stitch2Dto3D(V, opts);
            testCase.verifyEqual(bridged.numOutput3DObjects, 1, ...
                'zLookback must bridge the dropout for this test to mean anything');

            opts.minObjectSlices = 1;
            [~, keptAt1] = utils.instances.stitch2Dto3D(V, opts);
            opts.minObjectSlices = 2;
            [~, goneAt2] = utils.instances.stitch2Dto3D(V, opts);
            testCase.verifyEqual(keptAt1.numOutput3DObjects, 1);
            testCase.verifyEqual(goneAt2.numOutput3DObjects, 0);
        end

        % -----------------------------------------------------------------
        % Disconnected 2D labels (splitDisconnected2D)
        % -----------------------------------------------------------------

        function sharedIndexDoesNotCascadeIntoOneObject(testCase)
            % Three spatially disjoint columns. Every slice hands the same
            % index to two of them, alternating which pair shares it, exactly
            % as a 2D predictor does when one mask fires at several locations.
            % Keyed on the index alone, the shared labels weld all three
            % columns together; splitting by connected component must not.
            H = 40; W = 100; Z = 5;
            [xg, yg] = meshgrid(1:W, 1:H);
            columns = {(xg-15).^2 + (yg-20).^2 <= 5^2, ...
                       (xg-50).^2 + (yg-20).^2 <= 5^2, ...
                       (xg-85).^2 + (yg-20).^2 <= 3^2};
            V = zeros(H, W, Z, 'uint16');
            for z = 1:Z
                slice = zeros(H, W, 'uint16');
                if mod(z, 2) == 1       % columns 1+2 share index 7
                    slice(columns{1}) = 7;  slice(columns{2}) = 7;  slice(columns{3}) = 9;
                else                    % columns 2+3 share index 6
                    slice(columns{1}) = 4;  slice(columns{2}) = 6;  slice(columns{3}) = 6;
                end
                V(:, :, z) = slice;
            end

            [~, statsSplit] = utils.instances.stitch2Dto3D(V);   % default: on
            testCase.verifyEqual(statsSplit.numOutput3DObjects, 3, ...
                'each column must stay its own 3D object');
            testCase.verifyEqual(statsSplit.numInput2DObjects, 3*Z);

            [~, statsWhole] = utils.instances.stitch2Dto3D(V, ...
                struct('splitDisconnected2D', false));
            testCase.verifyEqual(statsWhole.numOutput3DObjects, 1, ...
                'index-keyed nodes are expected to cascade - this is what the split fixes');
            testCase.verifyEqual(statsWhole.numInput2DObjects, 2*Z);
        end

        function splitDisconnected2DOffKeepsOneLabelTogether(testCase)
            % Opt-out: a single index deliberately covering two blobs stays
            % one 3D object when the split is disabled, and becomes two when
            % it is enabled. Documents the trade the option controls.
            H = 40; W = 60; Z = 4;
            V = zeros(H, W, Z, 'uint16');
            V(10:20, 5:15,  :) = 3;
            V(10:20, 40:50, :) = 3;

            [~, statsOff] = utils.instances.stitch2Dto3D(V, ...
                struct('splitDisconnected2D', false));
            [~, statsOn]  = utils.instances.stitch2Dto3D(V);

            testCase.verifyEqual(statsOff.numOutput3DObjects, 1);
            testCase.verifyEqual(statsOn.numOutput3DObjects, 2);
        end

        % -----------------------------------------------------------------
        % absorbFragmentVoxels: dust rejoins the object around it
        % -----------------------------------------------------------------

        function absorbFragmentVoxelsFillsEnclosedSpeck(testCase)
            % The real failure this option exists for: a 2D predictor drops a
            % couple of pixels of another index inside an object's mask.
            % splitDisconnected2D correctly makes them their own object, but at
            % 2 voxels they can never reach minOverlapPixels, so they survive as
            % a hole. Absorption must hand them back and lose nothing.
            H = 40; W = 40; Z = 5;
            V = zeros(H, W, Z, 'uint16');
            for z = 1:Z
                V(10:20, 10:20, z) = 100 + z;   % scrambled per-slice index
            end
            V(14:15, 15, 3) = 777;              % 2 px of a foreign index inside

            [~, plain] = utils.instances.stitch2Dto3D(V, struct('absorbFragmentVoxels', 0));
            testCase.verifyEqual(plain.numOutput3DObjects, 2, ...
                'with absorption off the speck survives as its own object');
            testCase.verifyEqual(sort(plain.objectVoxelCounts), [2; 11*11*Z - 2]);
            testCase.verifyEqual(plain.numAbsorbedFragments, 0);

            [labels, absorbed] = utils.instances.stitch2Dto3D(V, ...
                struct('absorbFragmentVoxels', 2));
            testCase.verifyEqual(absorbed.numOutput3DObjects, 1, ...
                'the speck must rejoin the object it sits inside');
            testCase.verifyEqual(absorbed.objectVoxelCounts, 11*11*Z, ...
                'the column must come out solid, with no hole left');
            testCase.verifyEqual(absorbed.numAbsorbedFragments, 1);
            testCase.verifyEqual(absorbed.numAbsorbedVoxels, 2);
            testCase.verifyEqual(nnz(labels), nnz(V), ...
                'absorption reassigns voxels, it must never delete any');
        end

        function absorbFragmentVoxelsDoesNotJoinObjectsAcrossZ(testCase)
            % Why this is a voxel pass and not another link rule. A speck lying
            % over object A on one slice and under object B on the next would,
            % as a graph link, weld A and B into one object - which is exactly
            % what lowering minOverlapPixels does here. Absorption decides on
            % the fragment's own slice, so it cannot weld anything; and a
            % fragment with no labelled neighbour is left alone.
            H = 40; W = 40; Z = 5;
            V = zeros(H, W, Z, 'uint16');
            V(5:15, 5:15, 1:2) = 3;     % object A
            V(5:15, 5:15, 4:5) = 8;     % object B, same footprint, 2 slices away
            V(10:11, 10, 3)    = 42;    % 2 px bridging them, slice 3 otherwise empty

            [~, plain] = utils.instances.stitch2Dto3D(V, struct('absorbFragmentVoxels', 0));
            testCase.verifyEqual(plain.numOutput3DObjects, 3, ...
                'A, B and the speck must start out as three objects');

            [~, welded] = utils.instances.stitch2Dto3D(V, ...
                struct('minOverlapPixels', 1, 'absorbFragmentVoxels', 0));
            testCase.verifyEqual(welded.numOutput3DObjects, 1, ...
                'relaxing the link guard is expected to weld A and B - the trap being avoided');

            [~, absorbed] = utils.instances.stitch2Dto3D(V, ...
                struct('absorbFragmentVoxels', 2));
            testCase.verifyEqual(absorbed.numOutput3DObjects, 3, ...
                'absorption must leave A and B apart, and the neighbourless speck alone');
            testCase.verifyEqual(absorbed.numAbsorbedFragments, 0);
        end

        function absorbFragmentVoxelsWillNotAbsorbIntoAnotherFragment(testCase)
            % A fragment joins the object around it only when that object
            % survives on its own; two specks touching each other absorb
            % neither, so absorption cannot chain from dust to dust.
            H = 40; W = 40; Z = 3;
            V = zeros(H, W, Z, 'uint16');
            V(5:25, 5:25, :) = 1;    % a real object
            V(10:11, 26,  2) = 50;   % 2 px on its rim, no z-overlap with it
            V(35, 35, 2)     = 60;   % two 1-px specks touching only each other
            V(35, 36, 2)     = 61;

            [~, plain] = utils.instances.stitch2Dto3D(V, struct('absorbFragmentVoxels', 0));
            testCase.verifyEqual(plain.numOutput3DObjects, 4);

            [~, absorbed] = utils.instances.stitch2Dto3D(V, ...
                struct('absorbFragmentVoxels', 2));
            testCase.verifyEqual(absorbed.numOutput3DObjects, 3, ...
                'only the rim speck has a surviving neighbour to join');
            testCase.verifyEqual(absorbed.numAbsorbedFragments, 1);
            testCase.verifyEqual(absorbed.numAbsorbedVoxels, 2);
            testCase.verifyEqual(max(absorbed.objectVoxelCounts), 21*21*Z + 2);
        end

        % -----------------------------------------------------------------
        % Metric helper self-check (guards the objective function itself)
        % -----------------------------------------------------------------

        function metricsDetectFalseMerge(testCase)
            % GT: two separate objects; "stitched": both labelled the same ->
            % exactly one false merge, zero false splits.
            gt = zeros(20, 20, 4, 'uint16');
            gt(3:8,   3:8,   :) = 1;
            gt(12:17, 12:17, :) = 2;
            merged = uint16(gt > 0);   % everything is object 1

            m = mibtest.helpers.instanceStitchMetrics(merged, gt);
            testCase.verifyEqual(m.numFalseMerge, 1);
            testCase.verifyEqual(m.numFalseSplit, 0);
        end

        function metricsDetectFalseSplit(testCase)
            % GT: one object; "stitched": split into two labels across z ->
            % one false split, zero false merges.
            gt = zeros(20, 20, 4, 'uint16');
            gt(5:15, 5:15, :) = 1;
            split = zeros(size(gt), 'uint16');
            split(5:15, 5:15, 1:2) = 1;
            split(5:15, 5:15, 3:4) = 2;

            m = mibtest.helpers.instanceStitchMetrics(split, gt);
            testCase.verifyEqual(m.numFalseMerge, 0);
            testCase.verifyEqual(m.numFalseSplit, 1);
        end

    end

    methods (Test, TestTags = {'Integration'})

        % -----------------------------------------------------------------
        % Real MitoNet benchmark (easy set): perfect 3D reconstruction from
        % independent per-slice 2D masks. Self-skips when the data is absent.
        % -----------------------------------------------------------------

        function easyBenchmarkReconstructsGroundTruth(testCase)
            benchmarkDir = mibtest.helpers.stitchBenchmarkDir();
            testCase.assumeFalse(isempty(benchmarkDir), ...
                'MitoNet benchmark data not present - skipping');

            gt = StitchInstances2Dto3DTest.readMultipageTiff( ...
                fullfile(benchmarkDir, 'easy', 'lucchi_pp_mito.tif'));
            V = StitchInstances2Dto3DTest.readSliceFolder( ...
                fullfile(benchmarkDir, 'easy', 'slices_2d_objects'), size(gt));

            [L, stats] = utils.instances.stitch2Dto3D(V, struct('method', 'graph'));
            m = mibtest.helpers.instanceStitchMetrics(L, gt);

            % Measured baseline: 2707 2D objects -> 33 3D instances, exact.
            testCase.verifyEqual(stats.numOutput3DObjects, 33);
            testCase.verifyEqual(m.numFalseMerge, 0);
            testCase.verifyEqual(m.numFalseSplit, 0);
            testCase.verifyEqual(m.numOneToOne, 33);
        end

        % -----------------------------------------------------------------
        % Real MitoNet benchmark (hard set): dense salivary-gland mito. This is
        % the Phase C decision evidence, recorded as a regression guard. Heavy
        % (~10 GB RAM, ~60 s) so it is opt-in via MIB3_STITCH_BENCHMARK_HARD=1.
        %
        % Finding: minObjectVoxels cleanup drops false splits from 54 -> ~10
        % (noise fragments); the 14 false merges are threshold-invariant and
        % 13/14 are sustained overlaps (bridge 7-120 slices), so hysteresis
        % edges cannot help. Phase C is therefore not pursued.
        % -----------------------------------------------------------------

        function hardBenchmarkBaseline(testCase)
            testCase.assumeTrue(strcmp(getenv('MIB3_STITCH_BENCHMARK_HARD'), '1'), ...
                'Heavy hard-set benchmark disabled (set MIB3_STITCH_BENCHMARK_HARD=1)');
            benchmarkDir = mibtest.helpers.stitchBenchmarkDir();
            testCase.assumeFalse(isempty(benchmarkDir), ...
                'MitoNet benchmark data not present - skipping');

            gt = StitchInstances2Dto3DTest.readMultipageTiff( ...
                fullfile(benchmarkDir, 'hard', 'salivary_gland_mito.tif'));
            V = StitchInstances2Dto3DTest.readSliceFolder( ...
                fullfile(benchmarkDir, 'hard', 'slices_2d_objects'), size(gt));

            opt = struct('method', 'graph', 'minObjectVoxels', 200, 'zLookback', 2);
            [L, ~] = utils.instances.stitch2Dto3D(V, opt);
            clear V;
            m = mibtest.helpers.instanceStitchMetrics(L, gt);

            % Recorded baseline under the cleaned config: FM=14, FS=8, 94/131.
            % Guard against regressions with a small tolerance.
            testCase.verifyLessThanOrEqual(m.numFalseMerge, 16);
            testCase.verifyLessThanOrEqual(m.numFalseSplit, 12);
            testCase.verifyGreaterThanOrEqual(m.numOneToOne, 90);
        end

    end
end
