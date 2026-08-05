classdef StitchCoreTest < matlab.unittest.TestCase
% STITCHCORETEST - Unit + integration tests for the utils.stitch algorithmic core.
%
% Covers the Phase 1 stitching primitives:
%   utils.stitch.pairwiseShift            — integer/subpixel shift + quality
%   utils.stitch.computeOverlapRegion     — local overlap crops
%   utils.stitch.solveGlobalLeastSquares  — global weighted LS + springs
%   utils.stitch.planCanvas               — placement + canvas size
%   utils.stitch.blendWeights             — feather ramp
%   utils.stitch.fuseInMemory             — all four blend modes
%   io.savers.StitchSliceProvider         — provider slice == fuseInMemory slice
%   utils.stitch.fuseStreaming            — zarr round-trip (Integration)
%
% `layout` and `pairs` structs are built INLINE in every test (the layout
% builders are owned by a different agent and must not be called here).

    methods (TestClassSetup)
        function addPaths(testCase)
            % Ensure tests/ and mib/ are on the path whether launched via buildtool
            % (which adds tests/) or directly against this file (which does not).
            thisFile = mfilename('fullpath');
            testsFolder = fileparts(fileparts(thisFile));          % tests/
            repoRoot = fileparts(testsFolder);
            mibFolder = fullfile(repoRoot, 'mib');
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture({testsFolder, mibFolder, ...
                fullfile(mibFolder, 'external'), ...
                fullfile(mibFolder, 'external', 'zarr-matlab')}));
        end
    end

    % =================================================================
    % pairwiseShift
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function pairwiseShift_recoversKnownIntegerShift_signConvention(testCase)
            % cropB is cropA shifted DOWN dy rows and RIGHT dx cols.
            % Sign convention: shiftYXZ = [dy dx 0].
            base = testCase.texturedImage(160, 160, 7);
            dy = 6; dx = -4;
            % cropB(r,c) = cropA(r-dy, c-dx) -> circshift by [dy dx].
            cropA = base(21:140, 21:140);
            cropB = circshift(base, [dy dx]);
            cropB = cropB(21:140, 21:140);

            [shiftYXZ, quality] = utils.stitch.pairwiseShift(cropA, cropB, ...
                struct('subpixel', false));

            testCase.verifyEqual(shiftYXZ(1), dy, ...
                'dy sign/magnitude wrong');
            testCase.verifyEqual(shiftYXZ(2), dx, ...
                'dx sign/magnitude wrong');
            testCase.verifyEqual(shiftYXZ(3), 0, 'dz must be 0 in 2D');
            testCase.verifyGreaterThan(quality, 0.5, ...
                'textured overlap should score high quality');
        end

        function pairwiseShift_positiveShiftBothAxes(testCase)
            % Independent sign check with both shifts positive.
            base = testCase.texturedImage(160, 160, 11);
            dy = 9; dx = 7;
            cropA = base(21:140, 21:140);
            shifted = circshift(base, [dy dx]);
            cropB = shifted(21:140, 21:140);

            shiftYXZ = utils.stitch.pairwiseShift(cropA, cropB, struct('subpixel', false));
            testCase.verifyEqual(shiftYXZ(1:2), [dy dx]);
        end

        function pairwiseShift_zeroShiftIsZero(testCase)
            base = testCase.texturedImage(128, 128, 3);
            cropA = base(9:120, 9:120);
            cropB = cropA;
            shiftYXZ = utils.stitch.pairwiseShift(cropA, cropB, struct('subpixel', false));
            testCase.verifyEqual(shiftYXZ(1:2), [0 0]);
        end

        function pairwiseShift_subpixelWithin025px(testCase)
            % Build a smooth image, shift by a subpixel amount via interpolation.
            base = testCase.texturedImage(200, 200, 5);
            trueDy = 3.4; trueDx = -2.7;
            [xx, yy] = meshgrid(1:size(base, 2), 1:size(base, 1));
            shifted = interp2(xx, yy, base, xx - trueDx, yy - trueDy, 'linear', 0);
            % crop interior to avoid the zero-filled border from interpolation.
            cropA = base(41:160, 41:160);
            cropB = shifted(41:160, 41:160);

            shiftYXZ = utils.stitch.pairwiseShift(cropA, cropB, struct('subpixel', true));

            testCase.verifyLessThan(abs(shiftYXZ(1) - trueDy), 0.25, ...
                'subpixel dy not within 0.25 px');
            testCase.verifyLessThan(abs(shiftYXZ(2) - trueDx), 0.25, ...
                'subpixel dx not within 0.25 px');
        end

        function pairwiseShift_flatCropsLowQuality(testCase)
            % Constant crops with a hair of noise -> no meaningful peak.
            rng(1);
            cropA = single(100 + 0.01 * randn(128));
            cropB = single(100 + 0.01 * randn(128));
            [~, quality] = utils.stitch.pairwiseShift(cropA, cropB);
            testCase.verifyLessThan(quality, 0.1, ...
                'flat/noise crops must give quality < 0.1');
        end

        function pairwiseShift_texturedHighQuality(testCase)
            base = testCase.texturedImage(160, 160, 13);
            cropA = base(21:140, 21:140);
            cropB = circshift(base, [3 3]);
            cropB = cropB(21:140, 21:140);
            [~, quality] = utils.stitch.pairwiseShift(cropA, cropB, struct('subpixel', false));
            testCase.verifyGreaterThan(quality, 0.5, ...
                'textured overlap must give quality > 0.5');
        end
    end

    % =================================================================
    % computeOverlapRegion
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function computeOverlapRegion_horizontalNeighbour(testCase)
            % Two 100x100 tiles, tile 2 to the RIGHT of tile 1 with 20 px overlap.
            layout = testCase.makeTwoTileLayout([1 1 1], [1 81 1], [100 100 1 1]);
            [bboxA, bboxB] = utils.stitch.computeOverlapRegion(layout, 1, 2, 0);
            % Overlap columns in global: 81..100 (20 columns).
            % In tile 1 local: cols 81..100; in tile 2 local: cols 1..20.
            testCase.verifyEqual(bboxA(2, :), [81 100]);
            testCase.verifyEqual(bboxB(2, :), [1 20]);
            % Rows fully overlap for both.
            testCase.verifyEqual(bboxA(1, :), [1 100]);
            testCase.verifyEqual(bboxB(1, :), [1 100]);
        end

        function computeOverlapRegion_equalExtents(testCase)
            layout = testCase.makeTwoTileLayout([1 1 1], [1 81 1], [100 100 1 1]);
            [bboxA, bboxB] = utils.stitch.computeOverlapRegion(layout, 1, 2, 8);
            hA = bboxA(1, 2) - bboxA(1, 1); wA = bboxA(2, 2) - bboxA(2, 1);
            hB = bboxB(1, 2) - bboxB(1, 1); wB = bboxB(2, 2) - bboxB(2, 1);
            testCase.verifyEqual([hA wA], [hB wB], ...
                'the two overlap crops must have equal extents');
        end
    end

    % =================================================================
    % solveGlobalLeastSquares
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function solver_recoversJitteredGridWithin1px(testCase)
            % 3x3 grid, known ground-truth origins with jitter. Build edges inline
            % from ground-truth relative offsets (perfect measurements, q=1).
            [layout, truthOrigins] = testCase.makeGrid(3, 3, [100 100 1 1], 80);
            % apply a jitter to the ground truth so nominal != truth.
            rng(7);
            jitter = round(6 * randn(9, 3)); jitter(:, 3) = 0;
            trueOrigins = truthOrigins + jitter;
            trueOrigins(1, :) = truthOrigins(1, :);   % anchor stays at nominal

            edges = testCase.perfectEdges(layout, trueOrigins);

            [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, edges);

            % Positions are only defined up to the anchor gauge; anchor is pinned to
            % nominal. trueOrigins anchor also == nominal, so compare directly.
            err = positions - trueOrigins;
            testCase.verifyLessThanOrEqual(max(abs(err(:))), 1.0, ...
                'solver did not recover origins within +/-1 px');
            testCase.verifyLessThan(stats.rmseTotal, 0.5);
        end

        function fullChain_measureAndSolveRecoverJitteredTiles(testCase)
            % FULL-CHAIN regression: tiles on disk -> findNeighborPairs ->
            % computeOverlapRegion -> pairwiseShift -> measureAllPairs ->
            % solveGlobalLeastSquares, validated against ground-truth origins.
            % Guards the measured-shift sign convention and the FFT
            % anti-aliasing (zero-pad + expected-shift peak search) — a sign
            % flip or wrap-around here passes solver-only tests but produces
            % positions ~2x the jitter off; this test fails on both.
            original = uint8(testCase.texturedImage(560, 560, 33));
            overlapPx = 48; tileH = 218; tileW = 218;
            stepY = tileH - overlapPx; stepX = tileW - overlapPx;

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            % Cut tiles at JITTERED positions (true origins) while the layout
            % carries the clean nominal grid — exactly what a stage acquisition
            % with positioning error looks like. Border clamping is intentional:
            % it produces the asymmetric-crop case that caused the aliasing bug.
            layout = testCase.emptyLayout(9);
            trueOrigins = zeros(9, 3);
            rng(11, 'twister');
            k = 0;
            for r = 1:3
                for c = 1:3
                    k = k + 1;
                    oy = min(max(1 + (r - 1) * stepY + randi([-5 5]), 1), 560 - tileH + 1);
                    ox = min(max(1 + (c - 1) * stepX + randi([-5 5]), 1), 560 - tileW + 1);
                    trueOrigins(k, :) = [oy, ox, 1];
                    tileFilename = fullfile(tempDir, sprintf('tile_%02d.tif', k));
                    imwrite(original(oy:(oy + tileH - 1), ox:(ox + tileW - 1)), tileFilename);
                    layout(k).index      = k;
                    layout(k).filename   = tileFilename;
                    layout(k).gridRC     = [r c];
                    layout(k).nomOrigin  = [1 + (r - 1) * stepY, 1 + (c - 1) * stepX, 1];
                    layout(k).tileSize   = [tileH, tileW, 1, 1];
                    layout(k).dataClass  = 'uint8';
                end
            end

            pairs = utils.stitch.findNeighborPairs(layout);
            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3, 'subpixel', true));

            % Every valid measured edge must match the ground-truth displacement.
            for e = edges([edges.valid])
                trueDelta = trueOrigins(e.j, :) - trueOrigins(e.i, :);
                testCase.verifyLessThan(max(abs(e.measured(1:2) - trueDelta(1:2))), 1.0, ...
                    sprintf('edge (%d,%d) measured %s but truth is %s', ...
                    e.i, e.j, mat2str(round(e.measured(1:2), 1)), mat2str(trueDelta(1:2))));
            end

            positions = utils.stitch.solveGlobalLeastSquares(layout, edges, ...
                struct('springWeight', 0.1));

            % Compare up to the gauge (mean offset removed).
            residual = positions(:, 1:2) - trueOrigins(:, 1:2);
            residual = residual - mean(residual, 1);
            testCase.verifyLessThan(max(abs(residual(:))), 1.5, ...
                'full measure+solve chain did not recover jittered tile origins');
        end

        function featureShift_recoversKnownShift_signConvention(testCase)
            % featureShift must return the SAME sign convention as pairwiseShift:
            % cropB(r,c) ≈ cropA(r-dy, c-dx) ⇒ shiftYXZ = [dy dx 0]. A flipped sign
            % here silently doubles the error through measureOne's composition.
            base = testCase.texturedImage(200, 200, 7);
            dy = 6; dx = -4;
            cropA = base(21:180, 21:180);
            shifted = circshift(base, [dy dx]);
            cropB = shifted(21:180, 21:180);

            [shiftYXZ, quality] = utils.stitch.featureShift(cropA, cropB);

            testCase.verifyEqual(shiftYXZ(1:2), [dy dx], 'AbsTol', 0.5, ...
                'feature-based shift sign/magnitude wrong');
            testCase.verifyEqual(shiftYXZ(3), 0, 'dz must be 0 in 2D');
            testCase.verifyGreaterThan(quality, 0.5, ...
                'a clean textured overlap should score a high inlier ratio');
        end

        function featureShift_lowQualityOnFlatCrops(testCase)
            % No detectable features → quality 0, never a confident wrong answer.
            flat = 20 * ones(160, 160, 'single');
            [~, quality] = utils.stitch.featureShift(flat, flat);
            testCase.verifyEqual(quality, 0, ...
                'featureless crops must not produce a confident match');
        end

        function featureShift_honorsDetectorAndDownsampling(testCase)
            % featureShift must accept an automaticOptions-shaped struct: a
            % non-default detector + a downsampling factor (points scaled back to
            % full resolution) still recover the same shift.
            base = testCase.texturedImage(220, 220, 13);
            dy = 8; dx = 5;
            cropA = base(21:200, 21:200);
            shifted = circshift(base, [dy dx]);
            cropB = shifted(21:200, 21:200);

            harrisOpts = struct( ...
                'featureDetector', 'Corners: Harris-Stephens algorithm', ...
                'detectHarrisFeatures', struct('MinQuality', 0.01, 'FilterSize', 5), ...
                'downsampleFactor', 2, ...
                'estGeomTransform', struct('MaxNumTrials', 1000, 'Confidence', 99, 'MaxDistance', 1.5));
            [shiftYXZ, quality] = utils.stitch.featureShift(cropA, cropB, harrisOpts);

            testCase.verifyEqual(shiftYXZ(1:2), [dy dx], 'AbsTol', 1.0, ...
                'Harris + downsampling must still recover the shift');
            testCase.verifyGreaterThan(quality, 0.5, ...
                'a clean overlap should score high with a corner detector too');
        end

        function fullChain_featureBasedRecoversLargeJitter(testCase)
            % The differentiator for Feature-based: tile offsets jittered far
            % beyond phase correlation's restricted search radius. Feature-based
            % matches over the FULL tiles, so it recovers the arbitrary offsets
            % that the (restricted) phase-correlation search cannot.
            original = uint8(testCase.texturedImage(620, 620, 41));
            overlapPx = 70; tileH = 240; tileW = 240;
            stepY = tileH - overlapPx; stepX = tileW - overlapPx;
            jitter = 40;   % >> the phase-correlation jitter budget for this overlap

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(9);
            trueOrigins = zeros(9, 3);
            rng(23, 'twister');
            k = 0;
            for r = 1:3
                for c = 1:3
                    k = k + 1;
                    oy = min(max(1 + (r - 1) * stepY + randi([-jitter jitter]), 1), 620 - tileH + 1);
                    ox = min(max(1 + (c - 1) * stepX + randi([-jitter jitter]), 1), 620 - tileW + 1);
                    trueOrigins(k, :) = [oy, ox, 1];
                    tileFilename = fullfile(tempDir, sprintf('tile_%02d.tif', k));
                    imwrite(original(oy:(oy + tileH - 1), ox:(ox + tileW - 1)), tileFilename);
                    layout(k).index     = k;
                    layout(k).filename  = tileFilename;
                    layout(k).gridRC    = [r c];
                    layout(k).nomOrigin = [1 + (r - 1) * stepY, 1 + (c - 1) * stepX, 1];
                    layout(k).tileSize  = [tileH, tileW, 1, 1];
                    layout(k).dataClass = 'uint8';
                end
            end

            pairs = utils.stitch.findNeighborPairs(layout);
            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3, 'registrationMethod', 'Feature-based'));
            testCase.verifyGreaterThanOrEqual(sum([edges.valid]), 8, ...
                'feature-based should validate most edges under large jitter');

            positions = utils.stitch.solveGlobalLeastSquares(layout, edges, ...
                struct('springWeight', 0.1));
            residual = positions(:, 1:2) - trueOrigins(:, 1:2);
            residual = residual - mean(residual, 1);
            testCase.verifyLessThan(max(abs(residual(:))), 1.5, ...
                'feature-based full chain did not recover large-jitter origins');
        end

        function stageCoordsToOrigins_convertsMicronsAndRanksZ(testCase)
            % Pure Bio-Formats conversion core: µm → 1-based pixel/slice origins,
            % min-shifted, with distinct Z ranked into layers.
            pixSize = struct('x', 0.5, 'y', 0.5, 'z', 1);
            stageXYZum = [0 0 0; 100 0 0; 0 50 2; 100 50 2];   % 100µm/0.5 = 200px
            [nomOrigin, zLayer] = utils.stitch.stageCoordsToOrigins(stageXYZum, pixSize);

            testCase.verifyEqual(nomOrigin(:, 2), [1; 201; 1; 201], ...
                '100 µm at 0.5 µm/px must be 200 px apart in X');
            testCase.verifyEqual(nomOrigin(:, 1), [1; 1; 101; 101], ...
                '50 µm at 0.5 µm/px must be 100 px apart in Y');
            testCase.verifyEqual(zLayer(:)', [1 1 2 2], ...
                'two distinct Z levels must rank into layers 1 and 2');
        end

        function estimateOverlap_recoversTrueOverlapFromWrongGuess(testCase)
            % The user-entered overlap is often a guess; estimateOverlap must
            % recover the actual grid step from the images alone (full-tile
            % phase correlation + top-K NCC verification, median over pairs),
            % regardless of how wrong the claimed overlap is.
            original = uint8(testCase.texturedImage(560, 560, 33));
            trueOverlapPx = 48; tileH = 218; tileW = 218;
            stepY = tileH - trueOverlapPx; stepX = tileW - trueOverlapPx;
            trueOverlapPercent = trueOverlapPx / tileH * 100;   % 22.0%

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(9);
            trueOrigins = zeros(9, 3);
            wrongStepY = round(tileH * 0.90);   % layout claims 10% overlap
            wrongStepX = round(tileW * 0.90);
            rng(11, 'twister');
            k = 0;
            for r = 1:3
                for c = 1:3
                    k = k + 1;
                    oy = min(max(1 + (r - 1) * stepY + randi([-5 5]), 1), 560 - tileH + 1);
                    ox = min(max(1 + (c - 1) * stepX + randi([-5 5]), 1), 560 - tileW + 1);
                    trueOrigins(k, :) = [oy, ox, 1];
                    tileFilename = fullfile(tempDir, sprintf('tile_%02d.tif', k));
                    imwrite(original(oy:(oy + tileH - 1), ox:(ox + tileW - 1)), tileFilename);
                    layout(k).index      = k;
                    layout(k).filename   = tileFilename;
                    layout(k).gridRC     = [r c];
                    layout(k).nomOrigin  = [1 + (r - 1) * wrongStepY, 1 + (c - 1) * wrongStepX, 1];
                    layout(k).tileSize   = [tileH, tileW, 1, 1];
                    layout(k).dataClass  = 'uint8';
                end
            end

            estimate = utils.stitch.estimateOverlap(layout);

            testCase.verifyGreaterThan(estimate.numMeasuredX, 0);
            testCase.verifyGreaterThan(estimate.numMeasuredY, 0);
            testCase.verifyEqual(estimate.overlapX, trueOverlapPercent, 'AbsTol', 3.0, ...
                'estimated X overlap too far from truth');
            testCase.verifyEqual(estimate.overlapY, trueOverlapPercent, 'AbsTol', 3.0, ...
                'estimated Y overlap too far from truth');

            % Full chain with the ESTIMATED overlap must recover the positions
            % even though the claimed overlap (10%) was badly wrong.
            estStepY = tileH * (1 - estimate.overlapY / 100);
            estStepX = tileW * (1 - estimate.overlapX / 100);
            for k = 1:9
                r = layout(k).gridRC(1); c = layout(k).gridRC(2);
                layout(k).nomOrigin = [1 + (r - 1) * estStepY, 1 + (c - 1) * estStepX, 1];
            end
            pairs = utils.stitch.findNeighborPairs(layout);
            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3, 'subpixel', true));
            positions = utils.stitch.solveGlobalLeastSquares(layout, edges);
            residual = positions(:, 1:2) - trueOrigins(:, 1:2);
            residual = residual - mean(residual, 1);
            testCase.verifyLessThan(max(abs(residual(:))), 1.5, ...
                'full chain with estimated overlap did not recover tile origins');
        end

        function fullChain3D_recoversJittered3DLayerStack(testCase)
            % PHASE 2 milestone: a 2x2 XY grid over 3 Z-layers, every tile a small
            % Z-stack, cut from a textured 3D volume at JITTERED 3D positions while
            % the layout carries the clean nominal grid. Exercises the cross-layer
            % dz measurement (measureZShift), slice-unit nomOrigin(3), and the
            % z-aware planCanvas. Recovers all three axes to sub-1.5 px, and the
            % fused mosaic interior must match the ground-truth volume.
            volumeH = 300; volumeW = 300; volumeDepth = 60;
            volume = testCase.texturedVolume(volumeH, volumeW, volumeDepth, 77);

            tileH = 180; tileW = 180; tileDepth = 28;
            stepY = tileH - 60;   % 120, XY overlap 60 px
            stepX = tileW - 60;
            stepZ = tileDepth - 12;   % 16, Z overlap 12 slices

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(12);
            trueOrigins = zeros(12, 3);
            clampOrigin = @(origin, tileSize, volumeSize) min(max(origin, 1), volumeSize - tileSize + 1);
            rng(23, 'twister');
            % Z jitter is per-LAYER, not per-tile: a 2D layer of tiles is one focal
            % plane, so all tiles in a layer share the same z (within-layer dz == 0,
            % which the solver enforces). Only XY jitters per tile.
            layerOz = arrayfun(@(zl) clampOrigin(1 + (zl - 1) * stepZ + randi([-2 2]), ...
                tileDepth, volumeDepth), 1:3);
            k = 0;
            for zl = 1:3
                for r = 1:2
                    for c = 1:2
                        k = k + 1;
                        oy = clampOrigin(1 + (r - 1) * stepY + randi([-4 4]), tileH, volumeH);
                        ox = clampOrigin(1 + (c - 1) * stepX + randi([-4 4]), tileW, volumeW);
                        oz = layerOz(zl);
                        trueOrigins(k, :) = [oy, ox, oz];
                        tileVol = volume(oy:oy + tileH - 1, ox:ox + tileW - 1, oz:oz + tileDepth - 1);
                        tileFilename = fullfile(tempDir, sprintf('tile_%02d.tif', k));
                        testCase.writeStackTiff(uint8(tileVol), tileFilename);
                        layout(k).index      = k;
                        layout(k).filename   = tileFilename;
                        layout(k).zLayer     = zl;
                        layout(k).gridRC     = [r c];
                        layout(k).nomOrigin  = [1 + (r - 1) * stepY, 1 + (c - 1) * stepX, ...
                                                1 + (zl - 1) * stepZ];
                        layout(k).tileSize   = [tileH, tileW, tileDepth, 1];
                        layout(k).dataClass  = 'uint8';
                    end
                end
            end

            pairs = utils.stitch.findNeighborPairs(layout);
            testCase.assertNotEmpty(pairs, 'no neighbour pairs found for the 3D stack');
            testCase.assertTrue(any(strcmp({pairs.direction}, 'z')), ...
                'expected at least one cross-layer z pair');

            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3, 'subpixel', true));

            % Every valid measured edge (all three axes) matches ground truth.
            for e = edges([edges.valid])
                trueDelta = trueOrigins(e.j, :) - trueOrigins(e.i, :);
                testCase.verifyLessThan(max(abs(e.measured - trueDelta)), 1.5, ...
                    sprintf('edge (%d,%d,%s) measured %s but truth is %s', ...
                    e.i, e.j, e.direction, mat2str(round(e.measured, 1)), mat2str(trueDelta)));
            end

            positions = utils.stitch.solveGlobalLeastSquares(layout, edges);
            residual = positions - trueOrigins;
            residual = residual - mean(residual, 1);
            testCase.verifyLessThan(max(abs(residual(:))), 1.5, ...
                '3D measure+solve chain did not recover jittered origins in all axes');

            % z-aware canvas: 3 layers with Z overlap must be thinner than a naive
            % 3*tileDepth stack, and the fused interior must match the volume.
            canvas = utils.stitch.planCanvas(layout, positions);
            testCase.verifyLessThan(canvas.size(3), 3 * tileDepth, ...
                'canvas Z did not account for inter-layer overlap');
            imgOut = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', 'Feather', 'background', 0));

            % Compare an interior sub-volume against the ground-truth volume,
            % aligned by the solved gauge (min corner -> pixel 1).
            gauge = round(min(positions, [], 1));
            oy = trueOrigins(1, 1) - gauge(1) + 1;
            ox = trueOrigins(1, 2) - gauge(2) + 1;
            oz = trueOrigins(1, 3) - gauge(3) + 1;
            my = 30; mx = 30; mz = 4;
            aBlock = double(imgOut(oy + my:oy + tileH - my, ox + mx:ox + tileW - mx, ...
                oz + mz:oz + tileDepth - mz, 1, 1));
            bBlock = double(volume(trueOrigins(1,1) + my:trueOrigins(1,1) + tileH - my, ...
                trueOrigins(1,2) + mx:trueOrigins(1,2) + tileW - mx, ...
                trueOrigins(1,3) + mz:trueOrigins(1,3) + tileDepth - mz));
            rmse = sqrt(mean((aBlock(:) - bBlock(:)).^2));
            testCase.verifyLessThan(rmse, 6.0, ...
                sprintf('fused 3D interior RMSE too high: %.3f', rmse));
        end

        function solver_prunesCorruptedEdgeAndSpringHolds(testCase)
            [layout, truthOrigins] = testCase.makeGrid(2, 2, [100 100 1 1], 80);
            trueOrigins = truthOrigins;   % no jitter -> nominal == truth
            edges = testCase.perfectEdges(layout, trueOrigins);

            % Corrupt one edge (tile 3->4 say): wrong measured, low quality.
            corruptIdx = find([edges.i] == 3 & [edges.j] == 4, 1);
            if isempty(corruptIdx); corruptIdx = numel(edges); end
            edges(corruptIdx).measured = edges(corruptIdx).measured + [50 50 0];
            edges(corruptIdx).quality  = 0.02;
            edges(corruptIdx).valid    = false;

            [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, edges, ...
                struct('springWeight', 0.1, 'nominalSpringWeight', 0.01));

            testCase.verifyGreaterThanOrEqual(stats.nPruned, 1, ...
                'corrupted edge should count as pruned');
            % The tile touched only by the corrupted edge should stay near nominal
            % thanks to the spring, NOT jump by the 50 px corruption.
            errAll = positions - trueOrigins;
            testCase.verifyLessThan(max(abs(errAll(:))), 3.0, ...
                'spring failed to hold pruned tile near nominal');
        end

        function solver_disconnectedTileFallsBackToNominal(testCase)
            % 3 tiles; tile 3 has NO valid edges -> must land at its nominal.
            layout = testCase.makeLineLayout(3, [100 100 1 1], 80);
            nomOrigins = reshape([layout.nomOrigin], 3, 3)';
            % Only edge 1-2 valid; tile 3 isolated.
            edges(1) = testCase.oneEdge(1, 2, 'x', ...
                nomOrigins(2, :) - nomOrigins(1, :), [3 0 0], 1.0, true);
            [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, edges);
            testCase.verifyTrue(ismember(3, stats.disconnectedTiles));
            testCase.verifyEqual(positions(3, :), nomOrigins(3, :), 'AbsTol', 0.5, ...
                'isolated tile should fall back to nominal origin');
        end
    end

    % =================================================================
    % planCanvas + blendWeights
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function planCanvas_sizeAndPlacement(testCase)
            layout = testCase.makeLineLayout(2, [100 120 1 1], 80);
            % tile1 origin [1 1 1], tile2 origin [1 81 1] (80 spacing).
            positions = [1 1 1; 1 81 1];
            canvas = utils.stitch.planCanvas(layout, positions);
            % Width = max(placementX + W - 1) = max(1+120-1, 81+120-1) = 200.
            testCase.verifyEqual(canvas.size(2), 200);
            testCase.verifyEqual(canvas.size(1), 100);
            testCase.verifyEqual(canvas.tilePlacement(1, :), [1 1 1]);
            testCase.verifyEqual(canvas.tilePlacement(2, :), [1 81 1]);
        end

        function planCanvas_shiftsMinOriginToOne(testCase)
            layout = testCase.makeLineLayout(2, [50 50 1 1], 40);
            positions = [-5 -5 1; -5 35 1];   % negative origins
            canvas = utils.stitch.planCanvas(layout, positions);
            testCase.verifyEqual(min(canvas.tilePlacement(:, 1)), 1);
            testCase.verifyEqual(min(canvas.tilePlacement(:, 2)), 1);
        end

        function planCanvas_subpixelResidualCaptured(testCase)
            layout = testCase.makeLineLayout(1, [40 40 1 1], 0);
            positions = [1.3 1.7 1];
            canvas = utils.stitch.planCanvas(layout, positions);
            % After shifting min to 1, residual is the fractional part.
            testCase.verifyLessThanOrEqual(max(abs(canvas.subpixelResidual(:))), 0.5);
        end

        function planCanvas_zSliceFixesShiftMosaicAboveBoundary(testCase)
            % Inspector Fix Z: rows [z dy dx] in options.zSliceFixes shift every
            % output slice >= z of the WHOLE mosaic. Verifies the per-slice shift
            % table, the canvas growth, the fused placement on both sides of the
            % boundary, and the sidecar round-trip of the corrections.
            rng(11, 'twister');
            vol = uint8(255 * rand(60, 80, 6));
            layout = testCase.makeLineLayout(2, [60 40 6 1], 40);
            tiles = {vol(:, 1:40, :), vol(:, 41:80, :)};
            readerFcn = @(tileIdx) tiles{tileIdx};
            positions = [1 1 1; 1 41 1];

            canvas = utils.stitch.planCanvas(layout, positions, ...
                struct('zSliceFixes', [4 3 -2]));
            % Baseline canvas is 60 x 80 x 6; the shift range grows it by [3 2].
            testCase.verifyEqual(canvas.size(1:3), [63 82 6]);
            % Slices < 4 carry the baseline (x baseline = +2 from the -2 min),
            % slices >= 4 the correction on top of it.
            testCase.verifyEqual(canvas.zShifts(3, :), [0 2]);
            testCase.verifyEqual(canvas.zShifts(4, :), [3 0]);

            fuseOptions = struct('blendMode', 'Overwrite', 'background', 0);
            below = utils.stitch.fuseSliceComposite(layout, canvas, 3, 1, readerFcn, fuseOptions);
            above = utils.stitch.fuseSliceComposite(layout, canvas, 4, 1, readerFcn, fuseOptions);
            testCase.verifyEqual(below(1:60, 3:82), vol(:, :, 3));
            testCase.verifyEqual(above(4:63, 1:80), vol(:, :, 4));

            % Sidecar round-trip (a single row must come back as 1x3).
            sidecarPath = [tempname, '.mibstitch.json'];
            cleanupSidecar = onCleanup(@() delete(sidecarPath));
            utils.stitch.saveProject(sidecarPath, layout, [], positions, [], [], {}, [4 3 -2]);
            [~, ~, ~, ~, ~, ~, zSliceFixes] = utils.stitch.loadProject(sidecarPath);
            testCase.verifyEqual(zSliceFixes, [4 3 -2]);
        end

        function blendWeights_interiorOneEdgesRamp(testCase)
            w = utils.stitch.blendWeights([100 100], 10);
            testCase.verifyClass(w, 'single');
            testCase.verifyEqual(size(w), [100 100]);
            % Center is 1, corners are the smallest.
            testCase.verifyEqual(w(50, 50), single(1));
            testCase.verifyLessThan(w(1, 1), w(50, 50));
            testCase.verifyGreaterThan(w(1, 1), 0);   % never zero
        end
    end

    % =================================================================
    % Canvas background colour + autocrop
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function makeTileReader_subRegionReadDoesNotDecodeTheWholeTile(testCase)
            % The sub-region fast path built imread's PixelRegion as CELLS,
            % which imread rejects outright ("its type was cell"); the try/catch
            % swallowed it and every TIFF region read silently decoded the whole
            % file. On a 24000x24000 tile that is 10 s instead of 0.7 s, and
            % nothing anywhere said so.
            %
            % The tell is the cache: only the full-load fallback populates it,
            % so a genuine region read leaves the tile NOT resident. Asserting
            % the pixels alone would pass either way - which is exactly why the
            % bug survived.
            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));
            tileFile = fullfile(tempDir, 'tile_01.tif');
            fullImage = uint8(mod(reshape(0:(120 * 80 - 1), 120, 80), 251));
            imwrite(fullImage, tileFile);

            layout = testCase.emptyLayout(1);
            layout(1).index = 1;
            layout(1).filename = tileFile;
            layout(1).tileSize = [120 80 1 1];

            [readerFcn, isCachedFcn] = utils.stitch.makeTileReader(layout);
            region = [11, 40; 21, 60];                      % [yMin yMax; xMin xMax]
            crop = readerFcn(1, region);

            testCase.verifyEqual(squeeze(crop), fullImage(11:40, 21:60), ...
                'the sub-region read returned the wrong pixels');
            testCase.verifyFalse(isCachedFcn(1), ...
                'the sub-region read fell back to decoding (and caching) the whole tile');

            % A whole-tile read still caches, and later crops come from it.
            readerFcn(1);
            testCase.verifyTrue(isCachedFcn(1));
            testCase.verifyEqual(squeeze(readerFcn(1, region)), fullImage(11:40, 21:60));
        end

        function tileCacheBudget_growsToTheLayoutAndNeverShrinks(testCase)
            % A fixed 2 GB budget could not hold one PAIR of large tiles, so the
            % inspector re-decoded both on every revisit. The budget must scale
            % with the layout - and must never come out BELOW the old fixed
            % default, or small-tile jobs would regress.
            fixedDefault = 2 * 1024^3;

            small = testCase.emptyLayout(4);
            for k = 1:4
                small(k).index = k; small(k).tileSize = [512 512 1 1]; small(k).dataClass = 'uint8';
            end
            testCase.verifyEqual(utils.stitch.tileCacheBudget(small), fixedDefault, ...
                'a tiny layout must not shrink the budget below the old default');

            big = testCase.emptyLayout(4);
            for k = 1:4
                big(k).index = k; big(k).tileSize = [24000 24000 1 1]; big(k).dataClass = 'uint16';
            end
            bigBudget = utils.stitch.tileCacheBudget(big);
            testCase.verifyGreaterThanOrEqual(bigBudget, fixedDefault);
            % Never more than the layout actually needs (4 x 1.15 GB here).
            testCase.verifyLessThanOrEqual(bigBudget, 4 * 24000 * 24000 * 2);

            % Several concurrent readers share the machine, not multiply it.
            dividedBudget = utils.stitch.tileCacheBudget(big, struct('divisor', 8));
            testCase.verifyLessThanOrEqual(dividedBudget, bigBudget);

            testCase.verifyEqual(utils.stitch.tileCacheBudget(testCase.emptyLayout(0)), fixedDefault);
        end

        function scoreSeams_cancelledIsFalseWithoutAProgressDialog(testCase)
            % Pins the third output: scoring is Cancelable, but only through the
            % progress dialog, so every headless/batch caller must see false —
            % a caller that treated "no dialog" as cancelled would silently drop
            % the seam check on every batch run.
            layout = testCase.makeLineLayout(2, [40 40 1 1], 30);
            positions = [1 1 1; 1 31 1];
            edges = struct('i', 1, 'j', 2, 'direction', 'x', 'nominal', [0 30 0], ...
                'measured', [0 30 0], 'quality', 1, 'valid', true, 'tform', [], ...
                'source', 'auto', 'seamScore', []);
            % Both tiles cut from one texture at the solved offset, so the seam
            % genuinely scores high; the reader takes (tileIdx, bbox) like
            % makeTileReader's.
            texture = StitchCoreTest.texturedImage(40, 70, 5);
            tiles = {texture(:, 1:40), texture(:, 31:70)};
            readerFcn = @(tileIdx, bbox) tiles{tileIdx}(bbox(1,1):bbox(1,2), bbox(2,1):bbox(2,2));

            [scored, ranking, cancelled] = utils.stitch.scoreSeams(layout, edges, positions, ...
                struct('readerFcn', readerFcn));

            testCase.verifyFalse(cancelled);
            testCase.verifyEqual(ranking, 1);
            testCase.verifyGreaterThan(scored(1).seamScore, 0.99);
        end

        function canvasBackground_whiteIsTheClassCeiling(testCase)
            testCase.verifyEqual(utils.stitch.canvasBackground('uint8', 'black'), 0);
            testCase.verifyEqual(utils.stitch.canvasBackground('uint16', 'black'), 0);
            testCase.verifyEqual(utils.stitch.canvasBackground('uint8', 'white'), 255);
            testCase.verifyEqual(utils.stitch.canvasBackground('uint16', 'white'), 65535);
            testCase.verifyEqual(utils.stitch.canvasBackground('int16', 'white'), 32767);
            % Float data rides the normalised 0..1 scale; realmax would be the
            % literal ceiling and useless as a fill value.
            testCase.verifyEqual(utils.stitch.canvasBackground('single', 'white'), 1);
            testCase.verifyEqual(utils.stitch.canvasBackground('uint8'), 0);   % default black
            testCase.verifyError(@() utils.stitch.canvasBackground('uint8', 'grey'), ...
                'utils:stitch:canvasBackground:badColor');
        end

        function canvasBackground_fillsUncoveredPixelsInEveryBlendMode(testCase)
            % Two tiles side by side with a 5 px gap: the gap column must come out
            % as the requested background, whichever blend mode wrote the slice.
            layout = testCase.makeLineLayout(2, [20 30 1 1], 35);
            positions = [1 1 1; 1 36 1];             % 30-wide tiles, 5 px gap at 31:35
            canvas = utils.stitch.planCanvas(layout, positions);
            readerFcn = @(tileIdx) repmat(uint8(60 + 40 * tileIdx), 20, 30);

            whiteValue = utils.stitch.canvasBackground(canvas.dataClass, 'white');
            modes = {'Feather', 'Average', 'Max', 'Min', 'Overwrite'};
            for modeIdx = 1:numel(modes)
                img = utils.stitch.fuseInMemory(layout, canvas, struct( ...
                    'blendMode', modes{modeIdx}, 'background', whiteValue, ...
                    'readerFcn', readerFcn));
                testCase.verifyEqual(unique(img(:, 31:35)), uint8(255), ...
                    sprintf('gap not filled with white in %s mode', modes{modeIdx}));
                testCase.verifyEqual(unique(img(:, 1:30)), uint8(100), ...
                    sprintf('tile pixels disturbed in %s mode', modes{modeIdx}));
            end
        end

        function autocrop_matchesBruteForceOptimumAndLeavesNoBackground(testCase)
            % 2x2 mosaic with per-tile jitter, so the solved positions leave a
            % ragged frame on all four sides. The crop must (a) be fully covered,
            % (b) be the LARGEST such rectangle - checked against an exhaustive
            % search over the real coverage mask - and (c) fuse with no background
            % pixel anywhere.
            tileH = 100; tileW = 120;
            positions = [ 1   1  1;
                          4  96  1;
                         89  -3  1;
                         93 101  1];
            layout = testCase.emptyLayout(4);
            for k = 1:4
                layout(k).index = k;
                layout(k).nomOrigin = positions(k, :);
                layout(k).tileSize = [tileH tileW 1 1];
                layout(k).dataClass = 'uint16';
            end

            plain   = utils.stitch.planCanvas(layout, positions);
            cropped = utils.stitch.planCanvas(layout, positions, struct('autocrop', true));
            testCase.verifyFalse(isfield(plain, 'cropRect'));   % off unless asked for
            testCase.verifyLessThan(cropped.size(1), plain.size(1));
            testCase.verifyLessThan(cropped.size(2), plain.size(2));

            coverage = false(plain.size(1), plain.size(2));
            for k = 1:4
                r = plain.tilePlacement(k, 1); c = plain.tilePlacement(k, 2);
                coverage(r:r + tileH - 1, c:c + tileW - 1) = true;
            end
            rect = cropped.cropRect;
            kept = coverage(rect(1):rect(2), rect(3):rect(4));
            testCase.verifyTrue(all(kept, 'all'), 'cropped region is not fully covered');
            testCase.verifyEqual(numel(kept), StitchCoreTest.largestCoveredArea(coverage));
            testCase.verifyEqual(cropped.size(1:2), [rect(2) - rect(1) + 1, rect(4) - rect(3) + 1]);

            readerFcn = @(tileIdx) repmat(uint16(1000 + 100 * tileIdx), tileH, tileW);
            img = utils.stitch.fuseInMemory(layout, cropped, struct( ...
                'blendMode', 'Overwrite', 'background', 0, 'readerFcn', readerFcn));
            testCase.verifyGreaterThan(min(img(:)), 0, 'background survived the crop');
        end

        function autocrop_intersectsCoverageOverAllZLayers(testCase)
            % Two z-layers with DIFFERENT in-plane jitter: the kept rectangle must
            % be covered on both output slices, not just the first.
            tileH = 60; tileW = 70;
            layerA = [ 1  1  1;  1 51  1];
            layerB = [ 6 -4  2;  6 46  2];
            positions = [layerA; layerB];
            layout = testCase.emptyLayout(4);
            for k = 1:4
                layout(k).index = k;
                layout(k).zLayer = 1 + (k > 2);
                layout(k).nomOrigin = positions(k, :);
                layout(k).tileSize = [tileH tileW 1 1];
            end

            cropped = utils.stitch.planCanvas(layout, positions, struct('autocrop', true));
            testCase.verifyEqual(cropped.size(3), 2);   % Z is never cropped

            readerFcn = @(tileIdx) repmat(uint8(50 + 20 * tileIdx), tileH, tileW);
            img = utils.stitch.fuseInMemory(layout, cropped, struct( ...
                'blendMode', 'Overwrite', 'background', 0, 'readerFcn', readerFcn));
            testCase.verifyGreaterThan(min(img(:)), 0, 'background survived on one of the slices');
        end

        function autocrop_integerTranslationTformsCropLikeThePlainPlan(testCase)
            % The affine path uses a conservative inscribed footprint; a plan whose
            % transforms are whole-pixel translations must still crop EXACTLY like
            % the translation-only plan (same test fuseSliceComposite applies to
            % pick its resampling-free fast path).
            positions = [ 1   1  1;
                          4  96  1;
                         89  -3  1;
                         93 101  1];
            layout = testCase.emptyLayout(4);
            tforms = cell(4, 1);
            for k = 1:4
                layout(k).index = k;
                layout(k).nomOrigin = positions(k, :);
                layout(k).tileSize = [100 120 1 1];
                tforms{k} = [eye(2), positions(k, [2 1])'; 0 0 1];
            end
            withTforms = utils.stitch.planCanvas(layout, positions, ...
                struct('tforms', {tforms}, 'autocrop', true));
            plainPlan  = utils.stitch.planCanvas(layout, positions, struct('autocrop', true));
            testCase.verifyEqual(withTforms.cropRect, plainPlan.cropRect);
            testCase.verifyEqual(withTforms.size(1:2), plainPlan.size(1:2));
        end

        function autocrop_warpedTilesLeaveNoBackground(testCase)
            % Small per-tile rotations: the inscribed-parallelogram footprint must
            % stay INSIDE the warped tiles, including the pixel imwarp blends
            % against its zero fill.
            tileH = 100; tileW = 120;
            positions = [ 1   1  1;
                          4  96  1;
                         89  -3  1;
                         93 101  1];
            layout = testCase.emptyLayout(4);
            tforms = cell(4, 1);
            for k = 1:4
                layout(k).index = k;
                layout(k).nomOrigin = positions(k, :);
                layout(k).tileSize = [tileH tileW 1 1];
                angle = deg2rad(1.5 * (k - 2));
                rotation = [cos(angle), -sin(angle); sin(angle), cos(angle)];
                tforms{k} = [rotation, positions(k, [2 1])'; 0 0 1];
            end
            cropped = utils.stitch.planCanvas(layout, positions, ...
                struct('tforms', {tforms}, 'autocrop', true));

            readerFcn = @(tileIdx) repmat(uint8(40 + 30 * tileIdx), tileH, tileW);
            for blendMode = {'Overwrite', 'Feather'}
                img = utils.stitch.fuseInMemory(layout, cropped, struct( ...
                    'blendMode', blendMode{1}, 'background', 0, 'readerFcn', readerFcn));
                testCase.verifyGreaterThan(min(img(:)), 0, ...
                    sprintf('warped tile left background in %s mode', blendMode{1}));
            end
        end
    end

    % =================================================================
    % fuseInMemory — all blend modes vs original
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function fuseInMemory_allBlendModesReconstruct(testCase)
            modes = {'Feather', 'Average', 'Max', 'Min', 'Overwrite'};
            for m = 1:numel(modes)
                testCase.subFuseReconstruct(modes{m});
            end
        end

        function fuseInMemory_maxAndMinPickExtremeTileInOverlap(testCase)
            % Two constant-intensity tiles overlapping by 20 px on a non-zero
            % background: Max must keep the brighter tile in the overlap, Min the
            % darker one, and NEITHER may fold the background into the projection.
            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            tileH = 40; tileW = 40; overlapPx = 20;
            values = [200, 80];
            layout = testCase.emptyLayout(2);
            for k = 1:2
                filename = fullfile(tempDir, sprintf('flat_%02d.tif', k));
                imwrite(uint8(values(k)) + zeros(tileH, tileW, 'uint8'), filename);
                layout(k).index     = k;
                layout(k).filename  = filename;
                layout(k).nomOrigin = [1, 1 + (k - 1) * (tileW - overlapPx), 1];
                layout(k).tileSize  = [tileH tileW 1 1];
            end
            positions = reshape([layout.nomOrigin], 3, 2)';
            canvas = utils.stitch.planCanvas(layout, positions, ...
                struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)));

            overlapCols = (tileW - overlapPx + 1):tileW;
            % Each mode gets the background that would BREAK it if the fresh-pixel
            % mask were missing: brighter than both tiles for Max, darker for Min.
            maxOut = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', 'Max', 'background', 250));
            minOut = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', 'Min', 'background', 5));

            testCase.verifyEqual(unique(maxOut(:, overlapCols, 1, 1, 1)), uint8(max(values)), ...
                'Max blend must keep the brighter tile across the overlap');
            testCase.verifyEqual(unique(minOut(:, overlapCols, 1, 1, 1)), uint8(min(values)), ...
                'Min blend must keep the darker tile across the overlap');
            % Outside the overlap both modes reproduce the single covering tile.
            testCase.verifyEqual(unique(minOut(:, 1:(tileW - overlapPx), 1, 1, 1)), uint8(values(1)), ...
                'Min blend must not fold the background into singly-covered pixels');
            testCase.verifyEqual(unique(maxOut(:, (tileW + 1):end, 1, 1, 1)), uint8(values(2)), ...
                'Max blend must not fold the background into singly-covered pixels');
        end

        function stitchSliceProvider_matchesFuseInMemory(testCase)
            [layout, canvas, tempDir] = testCase.buildChoppedFusionCase(); %#ok<ASGLU>
            fuseOptions = struct('blendMode', 'Feather', 'background', 0);
            imgOut = utils.stitch.fuseInMemory(layout, canvas, fuseOptions);

            provider = io.savers.StitchSliceProvider(layout, canvas, fuseOptions);
            providerSlice = provider.getSlice(1, 1);           % [H W C]
            fuseSlice = reshape(imgOut(:, :, 1, :, 1), canvas.size(1), canvas.size(2), canvas.size(4));

            testCase.verifyEqual(providerSlice, fuseSlice, ...
                'StitchSliceProvider slice must equal fuseInMemory slice');
        end
    end

    % =================================================================
    % fuseStreaming — zarr round-trip (Integration)
    % =================================================================
    methods (Test, TestTags = {'Integration'})

        function fuseStreaming_zarrRoundTripMatchesInMemory(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            tempFixture = testCase.applyFixture(TemporaryFolderFixture);

            [layout, canvas] = testCase.buildChoppedFusionCase();
            fuseOptions = struct('blendMode', 'Feather', 'background', 0);
            imgOut = utils.stitch.fuseInMemory(layout, canvas, fuseOptions);

            outPath = fullfile(tempFixture.Folder, 'mosaic.zarr3');
            streamOptions = fuseOptions;
            streamOptions.pixSize = canvas.pixSize;
            streamOptions.showWaitbar = false;
            utils.stitch.fuseStreaming(layout, canvas, outPath, streamOptions);

            testCase.assertTrue(isfolder(outPath), 'zarr output was not created');

            % Reopen as BigData and compare a region (recipe from applyAlignmentBigData).
            loaderOpts = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOpts);
            [imgInfo, files] = loader.loadMetadata({outPath}, loaderOpts);
            [~, ~] = loader.loadImages(files, imgInfo, loaderOpts);

            % Level 0 array read-back — compare the whole level-0 volume.
            arr = io.zarr.Array(fullfile(outPath, '0'));
            zarrData = arr.read();     % [Y X Z (C)]
            H = canvas.size(1); W = canvas.size(2); Z = canvas.size(3); C = canvas.size(4);
            zarrData = reshape(zarrData, H, W, Z, C);
            fuseData = reshape(imgOut, H, W, Z, C);

            testCase.verifyEqual(zarrData, fuseData, ...
                'zarr round-trip differs from in-memory fuse');
        end

        function buildLayoutBioFormats_fullChainFromStageCoords(testCase)
            % End-to-end Bio-Formats layout source: write OME-TIFF tiles carrying
            % OME stage coordinates, build the layout from that metadata, then
            % measure + solve and check the origins are recovered. Needs the
            % Bio-Formats Java library; self-skips when it cannot be loaded.
            import matlab.unittest.fixtures.PathFixture
            import matlab.unittest.fixtures.TemporaryFolderFixture
            thisFile = mfilename('fullpath');
            mibFolder = fullfile(fileparts(fileparts(fileparts(thisFile))), 'mib');
            testCase.applyFixture(PathFixture(fullfile(mibFolder, 'external', 'bioformats')));
            try
                utils.ensureJavaLibraries({'bioformats'});
            catch loadErr
                testCase.assumeFail(['Bio-Formats unavailable: ' loadErr.message]);
            end

            tempFixture = testCase.applyFixture(TemporaryFolderFixture);
            tempDir = tempFixture.Folder;

            base = uint8(testCase.texturedImage(560, 560, 71));
            tileSz = 220; step = 170; pixUm = 0.5;
            rc = [1 1; 1 2; 2 1; 2 2];
            files = cell(1, 4);
            trueYX = zeros(4, 2);
            rng(23, 'twister');
            for k = 1:4
                oy = min(max(1 + (rc(k,1)-1)*step + randi([-4 4]), 1), 560 - tileSz + 1);
                ox = min(max(1 + (rc(k,2)-1)*step + randi([-4 4]), 1), 560 - tileSz + 1);
                trueYX(k, :) = [oy ox];
                tile = base(oy:oy+tileSz-1, ox:ox+tileSz-1);
                files{k} = fullfile(tempDir, sprintf('tile_%02d.ome.tiff', k));
                meta = createMinimalOMEXMLMetadata(tile);
                meta.setPlanePositionX(ome.units.quantity.Length(java.lang.Double((ox-1)*pixUm), ome.units.UNITS.MICROMETER), 0, 0);
                meta.setPlanePositionY(ome.units.quantity.Length(java.lang.Double((oy-1)*pixUm), ome.units.UNITS.MICROMETER), 0, 0);
                meta.setPixelsPhysicalSizeX(ome.units.quantity.Length(java.lang.Double(pixUm), ome.units.UNITS.MICROMETER), 0);
                meta.setPixelsPhysicalSizeY(ome.units.quantity.Length(java.lang.Double(pixUm), ome.units.UNITS.MICROMETER), 0);
                bfsave(tile, files{k}, 'metadata', meta);
            end

            layout = utils.stitch.buildLayoutBioFormats(strjoin(files, newline));
            testCase.assertEqual(numel(layout), 4, 'expected 4 tiles from stage metadata');
            % nomOrigin must reflect the stage grid (min-shifted to 1).
            nomYX = vertcat(layout.nomOrigin);
            testCase.verifyEqual(nomYX(:, 1:2) - nomYX(1, 1:2), ...
                trueYX - trueYX(1, :), 'AbsTol', 1.0, ...
                'stage-derived nominal origins do not match the true grid');

            pairs = utils.stitch.findNeighborPairs(layout, struct('minOverlapPx', 16));
            edges = utils.stitch.measureAllPairs(layout, pairs, struct('qualityThreshold', 0.3));
            positions = utils.stitch.solveGlobalLeastSquares(layout, edges, struct('springWeight', 0.1));
            solved = positions(:, 1:2) - positions(1, 1:2);
            truth  = trueYX - trueYX(1, :);
            err = sqrt(sum((solved - truth).^2, 2));
            testCase.verifyLessThan(max(err), 1.5, ...
                'Bio-Formats full chain did not recover the tile origins');
        end
    end

    % =================================================================
    % solveGlobalAffine + warped-footprint canvas + warp fusion
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function affineSolver_recoversExactTransforms(testCase)
            % Exact, mutually consistent affine edge measurements must be
            % recovered up to the tiny rank-guard spring bias (well below 0.05).
            [layout, G] = testCase.makeAffineTruthGrid(31);
            edges = testCase.affineEdgesFromTruth(layout, G);

            [tforms, positions, stats] = utils.stitch.solveGlobalAffine(layout, edges);

            maxErr = 0;
            for t = 1:numel(G)
                maxErr = max(maxErr, max(abs(tforms{t}(:) - G{t}(:))));
            end
            testCase.verifyLessThan(maxErr, 0.05, ...
                'affine solver did not recover the ground-truth transforms');
            testCase.verifyLessThan(stats.rmseTotal, 0.05);
            % positions collapse: pixel (1,1) position from each transform.
            for t = 1:numel(G)
                originXY = tforms{t}(1:2, 1:2) * [1; 1] + tforms{t}(1:2, 3);
                testCase.verifyEqual(positions(t, 1:2), [originXY(2), originXY(1)], ...
                    'AbsTol', 1e-9, 'positions must be the transform of pixel (1,1)');
            end
        end

        function affineSolver_translationEdgesCollapseToTranslationSolver(testCase)
            % With translation-only edges (no .tform) the affine solve must
            % reduce to the per-axis translation solver: identity linear parts
            % and matching positions. Guards the edge-synthesis sign convention.
            [layout, truthOrigins] = testCase.makeGrid(3, 3, [100 100 1 1], 80);
            rng(5);
            jitter = round(5 * randn(9, 3)); jitter(:, 3) = 0;
            trueOrigins = truthOrigins + jitter;
            trueOrigins(1, :) = truthOrigins(1, :);
            edges = testCase.perfectEdges(layout, trueOrigins);

            [tforms, positionsAffine] = utils.stitch.solveGlobalAffine(layout, edges);
            positionsRef = utils.stitch.solveGlobalLeastSquares(layout, edges);

            % The rank-guard springs bias L off identity by O(1e-4) on a jittered
            % grid; a real assembly/sign error shows up at O(1e-2) or worse.
            for t = 1:numel(tforms)
                testCase.verifyEqual(tforms{t}(1:2, 1:2), eye(2), 'AbsTol', 5e-4, ...
                    'translation edges must keep the linear parts at identity');
            end
            testCase.verifyEqual(positionsAffine, positionsRef, 'AbsTol', 0.05, ...
                'affine solve on translation edges must match the translation solver');
        end

        function planCanvas_integerTranslationTformsMatchPlainPlan(testCase)
            % Pure integer-translation transforms must produce the same canvas
            % size and tile placement as the plain (no-tforms) plan.
            layout = testCase.makeLineLayout(2, [100 120 1 1], 80);
            positions = [1 1 1; 1 81 1];
            plainCanvas = utils.stitch.planCanvas(layout, positions);

            % pos = L*[1;1] + p with L = I  =>  p = origin_xy - 1.
            tforms = {[eye(2), [0; 0]; 0 0 1]; [eye(2), [80; 0]; 0 0 1]};
            warpCanvas = utils.stitch.planCanvas(layout, positions, struct('tforms', {tforms}));

            testCase.verifyEqual(warpCanvas.size, plainCanvas.size, ...
                'integer-translation tforms changed the canvas size');
            testCase.verifyEqual(warpCanvas.tilePlacement, plainCanvas.tilePlacement, ...
                'integer-translation tforms changed the tile placement');
            testCase.verifyTrue(isfield(warpCanvas, 'tforms') && isfield(warpCanvas, 'tileBounds'));
        end

        function fuseWarp_reconstructsAffineChoppedImage(testCase)
            % Milestone (plan_transforms.md phase 1): chop a known image with an
            % affine warp per tile; planning + warp fusion with the GROUND-TRUTH
            % transforms must reproduce the source image.
            [layout, G, original] = testCase.buildAffineChoppedCase(43);
            nomOrigins = vertcat(layout.nomOrigin);

            canvas = utils.stitch.planCanvas(layout, nomOrigins, struct('tforms', {G}));
            mosaic = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', 'Feather', 'background', 0));

            meanAbsErr = testCase.mosaicVsOriginal(mosaic(:, :, 1, 1, 1), original, ...
                canvas.tforms{1}, G{1});
            testCase.verifyLessThan(meanAbsErr, 3.0, ...
                sprintf('warp fusion with ground-truth transforms off by %.2f grey levels', meanAbsErr));
        end

        function rigidSolver_recoversRotationsAndStaysOrthogonal(testCase)
            % Phase 2 milestone (plan_transforms.md): a rotated-tile set is
            % recovered with TransformType = Rigid, and every solved linear part
            % is exactly a proper rotation (R'R = I, det = 1 — the projection
            % guarantee, not a tolerance on the data).
            [layout, G] = testCase.makeRigidTruthGrid(17);
            edges = testCase.affineEdgesFromTruth(layout, G);

            [tforms, ~, stats] = utils.stitch.solveGlobalAffine(layout, edges, ...
                struct('transformType', 'Rigid', 'allowRotation', true));

            maxErr = 0;
            for t = 1:numel(G)
                maxErr = max(maxErr, max(abs(tforms{t}(:) - G{t}(:))));
                L = tforms{t}(1:2, 1:2);
                testCase.verifyEqual(L' * L, eye(2), 'AbsTol', 1e-12, ...
                    'rigid-projected linear parts must be orthogonal');
                testCase.verifyEqual(det(L), 1, 'AbsTol', 1e-12, ...
                    'rigid-projected linear parts must be proper rotations');
            end
            testCase.verifyLessThan(maxErr, 0.05, ...
                'rigid solve did not recover the ground-truth rotations');
            testCase.verifyLessThan(stats.rmseTotal, 0.05);
        end

        function rigidSolver_allowRotationOffForcesExactIdentity(testCase)
            % Phase 2 milestone: with AllowRotation off the SAME rotated set
            % solves with rotation residual EXACTLY zero (identity linear parts
            % by construction), i.e. it degenerates to a translation solve.
            [layout, G] = testCase.makeRigidTruthGrid(17);
            edges = testCase.affineEdgesFromTruth(layout, G);

            [tforms, positions] = utils.stitch.solveGlobalAffine(layout, edges, ...
                struct('transformType', 'Rigid', 'allowRotation', false));

            for t = 1:numel(tforms)
                testCase.verifyEqual(tforms{t}(1:2, 1:2), eye(2), ...
                    'AllowRotation=false must force exactly identity linear parts');
            end
            testCase.verifyTrue(all(isfinite(positions(:))));
            % Ground-truth rotations are small, so the rotation-locked positions
            % must stay close to the true origins (pixel (1,1) of each map).
            for t = 1:numel(G)
                trueOrigin = G{t}(1:2, 1:2) * [1; 1] + G{t}(1:2, 3);
                testCase.verifyEqual(positions(t, 1:2), [trueOrigin(2), trueOrigin(1)], ...
                    'AbsTol', 3.0, 'rotation-locked positions drifted from the true origins');
            end
        end

        function similaritySolver_recoversScaleAndRotation(testCase)
            % Similarity = s*R per tile: recover a scaled+rotated ground truth;
            % the solved linear parts must be exact scalar multiples of rotations.
            [layout, G] = testCase.makeRigidTruthGrid(29);
            rng(29, 'twister');
            for t = 2:numel(G)
                G{t}(1:2, 1:2) = (1 + (rand - 0.5) * 0.02) * G{t}(1:2, 1:2);
            end
            edges = testCase.affineEdgesFromTruth(layout, G);

            tforms = utils.stitch.solveGlobalAffine(layout, edges, ...
                struct('transformType', 'Similarity', 'allowRotation', true));

            maxErr = 0;
            for t = 1:numel(G)
                maxErr = max(maxErr, max(abs(tforms{t}(:) - G{t}(:))));
                L = tforms{t}(1:2, 1:2);
                s = sqrt(det(L));
                testCase.verifyEqual((L / s)' * (L / s), eye(2), 'AbsTol', 1e-10, ...
                    'similarity-projected linear parts must be s * rotation');
            end
            testCase.verifyLessThan(maxErr, 0.05, ...
                'similarity solve did not recover scale + rotation');
        end

        function featureShift_rotationLockProjectsFittedTransform(testCase)
            % With allowRotation = false a similarity fit on ROTATED content must
            % return a transform whose linear part carries no rotation (s * I).
            base = testCase.texturedImage(300, 300, 19);
            rotated = imrotate(base, 2, 'bilinear', 'crop');   % 2 degrees
            cropA = base(51:250, 51:250);
            cropB = rotated(51:250, 51:250);

            lockedOpts = struct('transformType', 'similarity', 'allowRotation', false);
            [~, quality, debugInfo] = utils.stitch.featureShift(cropA, cropB, lockedOpts);
            testCase.assumeGreaterThan(quality, 0, 'fit did not converge on this texture');
            M = debugInfo.tformA(1:2, 1:2);
            testCase.verifyEqual(M(1, 2), 0, 'AbsTol', 1e-12, ...
                'rotation-locked similarity fit must have zero off-diagonal terms');
            testCase.verifyEqual(M(2, 1), 0, 'AbsTol', 1e-12, ...
                'rotation-locked similarity fit must have zero off-diagonal terms');

            % Same content with rotation allowed: the fit must SEE the rotation.
            freeOpts = struct('transformType', 'similarity', 'allowRotation', true);
            [~, qualityFree, debugFree] = utils.stitch.featureShift(cropA, cropB, freeOpts);
            testCase.assumeGreaterThan(qualityFree, 0);
            recoveredDeg = atan2d(debugFree.tformA(2, 1), debugFree.tformA(1, 1));
            testCase.verifyEqual(abs(recoveredDeg), 2, 'AbsTol', 0.3, ...
                'unlocked similarity fit should recover the 2-degree rotation');
        end

        function fullChain_affineMeasureSolveFuse(testCase)
            % Full affine chain: feature measurement with transformType Affine ->
            % solveGlobalAffine -> warped canvas -> warp fusion. Solved per-tile
            % transforms must match the ground truth and the mosaic the source.
            [layout, G, original] = testCase.buildAffineChoppedCase(59);

            pairs = utils.stitch.findNeighborPairs(layout, struct('minOverlapPx', 16));
            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3, 'transformType', 'Affine'));

            testCase.assertGreaterThanOrEqual(sum([edges.valid]), 3, ...
                'affine feature measurement validated too few edges');
            for e = edges([edges.valid])
                testCase.assertFalse(isempty(e.tform), ...
                    'valid affine edges must carry the fitted pairwise transform');
            end

            [tforms, ~, stats] = utils.stitch.solveGlobalAffine(layout, edges);
            maxErr = 0;
            for t = 1:numel(G)
                maxErr = max(maxErr, max(abs(tforms{t}(:) - G{t}(:))));
            end
            testCase.verifyLessThan(maxErr, 0.5, ...
                sprintf('solved affine transforms off by %.3f from ground truth', maxErr));
            testCase.verifyLessThan(stats.rmseTotal, 1.0);

            nomOrigins = vertcat(layout.nomOrigin);
            canvas = utils.stitch.planCanvas(layout, nomOrigins, struct('tforms', {tforms}));
            mosaic = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', 'Feather', 'background', 0));
            meanAbsErr = testCase.mosaicVsOriginal(mosaic(:, :, 1, 1, 1), original, ...
                canvas.tforms{1}, G{1});
            testCase.verifyLessThan(meanAbsErr, 3.0, ...
                sprintf('measured affine chain mosaic off by %.2f grey levels', meanAbsErr));
        end

        function fullChain3DAffine_measureSolveFuseAcrossLayers(testCase)
            % Phase 3 milestone (plan_transforms.md): the 2D in-plane affine
            % model on depth>1 / multi-layer data. A 2x2 grid over 2 Z-layers of
            % Z-stack tiles, each tile cut with its OWN in-plane affine applied
            % to every slice, layer 2 jittered in Z. Measure (feature-based,
            % forced by the Affine model) -> solveGlobalAffine (z via the scalar
            % path) -> warped-footprint canvas -> per-slice warp fusion must
            % recover the transforms, the layer dz, and reproduce the volume.
            [layout, G, volume, trueLayerZ, tileDepth] = testCase.buildAffine3DChoppedCase(67);

            pairs = utils.stitch.findNeighborPairs(layout, struct('minOverlapPx', 16));
            testCase.assertTrue(any(strcmp({pairs.direction}, 'z')), ...
                'expected cross-layer z pairs in the 3D affine layout');

            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3, 'transformType', 'Affine'));

            % Within-layer edges must carry the fitted transform; z-edges stay
            % translation-only (empty .tform) — the 3D-affine scope.
            for e = edges([edges.valid])
                if strcmp(e.direction, 'z')
                    testCase.assertTrue(isempty(e.tform), ...
                        'cross-layer edges must be measured as translations');
                else
                    testCase.assertFalse(isempty(e.tform), ...
                        'valid within-layer affine edges must carry the fitted transform');
                end
            end
            testCase.assertGreaterThanOrEqual(sum([edges.valid]), 8, ...
                '3D affine measurement validated too few edges');

            [tforms, positions, stats] = utils.stitch.solveGlobalAffine(layout, edges);
            maxErr = 0;
            for t = 1:numel(G)
                maxErr = max(maxErr, max(abs(tforms{t}(:) - G{t}(:))));
            end
            testCase.verifyLessThan(maxErr, 0.5, ...
                sprintf('solved 3D affine transforms off by %.3f from ground truth', maxErr));
            testCase.verifyLessThan(stats.rmseTotal, 1.0);

            % Layer dz (z composes additively regardless of the in-plane model).
            trueDz = trueLayerZ(2) - trueLayerZ(1);
            for t = 5:8
                testCase.verifyEqual(positions(t, 3) - positions(t - 4, 3), trueDz, ...
                    'AbsTol', 1.0, 'solved layer dz drifted from the true Z jitter');
            end

            % Warp-fuse the full stack and compare one mid-layer slice per layer
            % against the matching volume slice (the canvas frame offset comes
            % from the anchor's canvas transform vs its ground-truth map).
            canvas = utils.stitch.planCanvas(layout, positions, struct('tforms', {tforms}));
            testCase.verifyLessThan(canvas.size(3), 2 * tileDepth, ...
                'canvas Z did not account for the inter-layer overlap');
            mosaic = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', 'Feather', 'background', 0));

            for probe = [1, 5]   % anchor tile of each layer
                zLocal = round(tileDepth / 2);
                zGlobal = canvas.tilePlacement(probe, 3) + zLocal - 1;
                volumeSlice = volume(:, :, trueLayerZ(1 + (probe > 4)) + zLocal - 1);
                meanAbsErr = testCase.mosaicVsOriginal(mosaic(:, :, zGlobal, 1, 1), ...
                    volumeSlice, canvas.tforms{1}, G{1});
                testCase.verifyLessThan(meanAbsErr, 4.0, ...
                    sprintf('layer %d mid-slice mosaic off by %.2f grey levels', ...
                    1 + (probe > 4), meanAbsErr));
            end
        end
    end

    % =================================================================
    % Local helpers
    % =================================================================
    methods (Access = private)

        function subFuseReconstruct(testCase, blendMode)
            [layout, canvas, ~, original] = testCase.buildChoppedFusionCase();
            imgOut = utils.stitch.fuseInMemory(layout, canvas, ...
                struct('blendMode', blendMode, 'background', 0));
            % Compare in the non-seam interior of the canvas against the original
            % (the chop uses zero jitter and integer placement, so interiors match).
            H = min(size(imgOut, 1), size(original, 1));
            W = min(size(imgOut, 2), size(original, 2));
            marginY = round(0.15 * H); marginX = round(0.15 * W);
            rows = (1 + marginY):(H - marginY);
            cols = (1 + marginX):(W - marginX);
            a = double(imgOut(rows, cols, 1, 1, 1));
            b = double(original(rows, cols));
            rmse = sqrt(mean((a(:) - b(:)).^2));
            testCase.verifyLessThan(rmse, 5.0, ...
                sprintf('%s blend RMSE too high in interior: %.3f', blendMode, rmse));
        end

        function [layout, canvas, tempDir, original] = buildChoppedFusionCase(testCase)
            % Chop a textured image into a 2x2 grid of overlapping tiles written to
            % disk, build an inline layout pointing at them, plan the canvas.
            original = uint8(testCase.texturedImage(220, 220, 21));
            overlapPx = 40;
            [tiles, origins] = testCase.chopIntoTiles(original, 2, 2, overlapPx, 0);

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            nTiles = numel(tiles);
            layout = testCase.emptyLayout(nTiles);
            for k = 1:nTiles
                fn = fullfile(tempDir, sprintf('tile_%02d.tif', k));
                imwrite(tiles{k}, fn);
                layout(k).index      = k;
                layout(k).filename   = fn;
                layout(k).sliceFiles = {};
                layout(k).zLayer     = 1;
                layout(k).gridRC     = [NaN NaN];
                layout(k).nomOrigin  = origins(k, :);
                layout(k).tileSize   = [size(tiles{k}, 1), size(tiles{k}, 2), 1, 1];
                layout(k).dataClass  = 'uint8';
            end
            % Positions = ground-truth origins shifted to 1-based min.
            positions = origins;
            canvas = utils.stitch.planCanvas(layout, positions, ...
                struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)));
        end

        function edges = perfectEdges(testCase, layout, trueOrigins)
            % Build edges for every direct 4-neighbour grid pair (tiles sharing a
            % full edge) with perfect measurements from the ground-truth origins.
            nomOrigins = reshape([layout.nomOrigin], 3, numel(layout))';
            tileSize = layout(1).tileSize;
            H = tileSize(1); W = tileSize(2);
            edges = testCase.emptyEdges(0);
            for i = 1:numel(layout)
                for j = (i + 1):numel(layout)
                    dy = nomOrigins(j, 1) - nomOrigins(i, 1);
                    dx = nomOrigins(j, 2) - nomOrigins(i, 2);
                    directX = (dy == 0) && (abs(dx) > 0) && (abs(dx) < W);
                    directY = (dx == 0) && (abs(dy) > 0) && (abs(dy) < H);
                    if ~(directX || directY); continue; end
                    if directX; direction = 'x'; else; direction = 'y'; end
                    nominal  = nomOrigins(j, :) - nomOrigins(i, :);
                    measured = trueOrigins(j, :) - trueOrigins(i, :);
                    edges(end+1) = testCase.oneEdge(i, j, direction, nominal, ...
                        measured - nominal, 1.0, true); %#ok<AGROW>
                end
            end
        end

        function e = oneEdge(~, i, j, direction, nominal, shift, quality, valid)
            e.i = i; e.j = j; e.direction = direction;
            e.nominal = nominal;
            e.measured = nominal + shift;
            e.quality = quality;
            e.valid = valid;
        end

        function edges = emptyEdges(~, n)
            edges = repmat(struct('i', 0, 'j', 0, 'direction', 'x', ...
                'nominal', [0 0 0], 'measured', [0 0 0], 'quality', 0, ...
                'valid', false), 1, n);
        end

        function layout = emptyLayout(~, n)
            layout = repmat(struct('index', 0, 'filename', '', 'sliceFiles', {{}}, ...
                'zLayer', 1, 'gridRC', [NaN NaN], 'nomOrigin', [1 1 1], ...
                'tileSize', [1 1 1 1], 'dataClass', 'uint8'), 1, n);
        end

        function layout = makeTwoTileLayout(testCase, origin1, origin2, tileSize)
            layout = testCase.emptyLayout(2);
            layout(1).index = 1; layout(1).nomOrigin = origin1; layout(1).tileSize = tileSize;
            layout(2).index = 2; layout(2).nomOrigin = origin2; layout(2).tileSize = tileSize;
        end

        function layout = makeLineLayout(testCase, n, tileSize, spacing)
            layout = testCase.emptyLayout(n);
            for k = 1:n
                layout(k).index = k;
                layout(k).nomOrigin = [1, 1 + (k - 1) * spacing, 1];
                layout(k).tileSize = tileSize;
            end
        end

        function [layout, G] = makeAffineTruthGrid(testCase, seed)
            % 2x2 layout with ground-truth per-tile affine maps: anchor identity
            % at nominal, others small rotation/scale/shear + XY jitter.
            [layout, origins] = testCase.makeGrid(2, 2, [200 200 1 1], 140);
            rng(seed, 'twister');
            G = cell(4, 1);
            G{1} = [eye(2), origins(1, [2 1])' - 1; 0 0 1];
            for t = 2:4
                ang = (rand - 0.5) * 2 * pi/180;          % +-1 degree
                sc  = 1 + (rand - 0.5) * 0.02;            % +-1% scale
                sh  = (rand - 0.5) * 0.01;                % small shear
                L = sc * [cos(ang), -sin(ang); sin(ang), cos(ang)] * [1 sh; 0 1];
                jitter = (rand(2, 1) - 0.5) * 8;
                G{t} = [L, origins(t, [2 1])' - 1 + jitter; 0 0 1];
            end
        end

        function [layout, G] = makeRigidTruthGrid(testCase, seed)
            % 2x2 layout with rotation-only ground truth (proper rotations +
            % XY jitter, no scale/shear) — the rigid-projection test bed.
            [layout, origins] = testCase.makeGrid(2, 2, [200 200 1 1], 140);
            rng(seed, 'twister');
            G = cell(4, 1);
            G{1} = [eye(2), origins(1, [2 1])' - 1; 0 0 1];
            for t = 2:4
                ang = (rand - 0.5) * 2 * pi/180;          % +-1 degree
                R = [cos(ang), -sin(ang); sin(ang), cos(ang)];
                jitter = (rand(2, 1) - 0.5) * 8;
                G{t} = [R, origins(t, [2 1])' - 1 + jitter; 0 0 1];
            end
        end

        function edges = affineEdgesFromTruth(testCase, layout, G)
            % Exact pairwise transforms for the four 2x2 grid adjacencies:
            % edge.tform is the tile-local map i->j, T = inv(G_j) * G_i.
            nomOrigins = reshape([layout.nomOrigin], 3, numel(layout))';
            pairsIJ = [1 2; 3 4; 1 3; 2 4];
            edges = testCase.emptyEdges(0);
            for k = 1:size(pairsIJ, 1)
                i = pairsIJ(k, 1); j = pairsIJ(k, 2);
                T = G{j} \ G{i};
                if k <= 2; direction = 'x'; else; direction = 'y'; end
                e = testCase.oneEdge(i, j, direction, ...
                    nomOrigins(j, :) - nomOrigins(i, :), [0 0 0], 1.0, true);
                e.measured = [-T(2, 3), -T(1, 3), 0];   % translation-part approximation
                e.tform = T;
                if isempty(edges); edges = e; else; edges(end+1) = e; end %#ok<AGROW>
            end
        end

        function [layout, G, original] = buildAffineChoppedCase(testCase, seed)
            % Chop a textured image into a 2x2 grid where each tile is CUT with
            % its own affine warp (tile(v) = original(G*v)) and written to disk —
            % the affine analogue of buildChoppedFusionCase. 240 px tiles at
            % 170 px pitch (70 px overlap, the proven feature-detection setup).
            original = uint8(testCase.texturedImage(620, 620, seed));
            tileH = 240; tileW = 240;
            nom = [1 1 1; 1 171 1; 171 1 1; 171 171 1];

            rng(seed, 'twister');
            G = cell(4, 1);
            G{1} = [eye(2), nom(1, [2 1])' - 1; 0 0 1];
            for t = 2:4
                ang = (rand - 0.5) * 2 * pi/180;
                sc  = 1 + (rand - 0.5) * 0.02;
                L = sc * [cos(ang), -sin(ang); sin(ang), cos(ang)];
                jitter = (rand(2, 1) - 0.5) * 8;
                G{t} = [L, nom(t, [2 1])' - 1 + jitter; 0 0 1];
            end

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(4);
            for t = 1:4
                tileImg = imwarp(original, affinetform2d(inv(G{t})), 'linear', ...
                    'OutputView', imref2d([tileH tileW]), 'FillValues', 0);
                fn = fullfile(tempDir, sprintf('tile_%02d.tif', t));
                imwrite(tileImg, fn);
                layout(t).index     = t;
                layout(t).filename  = fn;
                layout(t).gridRC    = [floor((t - 1) / 2) + 1, mod(t - 1, 2) + 1];
                layout(t).nomOrigin = nom(t, :);
                layout(t).tileSize  = [tileH, tileW, 1, 1];
                layout(t).dataClass = 'uint8';
            end
        end

        function [layout, G, volume, trueLayerZ, tileDepth] = buildAffine3DChoppedCase(testCase, seed)
            % The 3D analogue of buildAffineChoppedCase: a 2x2 XY grid over 2
            % Z-layers of Z-stack tiles (multi-page TIFFs), every tile cut with
            % its own IN-PLANE affine applied identically to all its slices
            % (tile(v, s) = volume(G*v, oz+s-1)) — the 3D-affine scope where z
            % stays translational. The volume shares one strong 2D texture
            % across slices (so the depth-flattened feature matching keeps the
            % full content) plus a z-varying component (so the dz NCC scan has
            % a sharp peak). Layer 1 sits at z = 1 (the solver's gauge); layer 2
            % is Z-jittered against its nominal.
            base = testCase.texturedImage(620, 620, seed);
            volumeDepth = 20;
            tileDepth = 12;
            stepZ = 7;   % nominal z overlap: tileDepth - stepZ = 5 slices
            rng(seed, 'twister');
            zNoise = imgaussfilt3(randn(620, 620, volumeDepth), 2.0);
            zNoise = zNoise / max(abs(zNoise(:)));
            volume = 0.75 * repmat(base, 1, 1, volumeDepth) + 0.25 * (100 * zNoise + 120);
            volume = uint8(min(max(volume, 0), 255));

            tileH = 240; tileW = 240;
            nomXY = [1 1; 1 171; 171 1; 171 171];
            trueLayerZ = [1, 1 + stepZ + randi([-1 1])];

            % The linear part is shared per grid SLOT across layers (lens/stage
            % distortion is per-position, not per-section) — which is also what
            % the solver assumes: cross-layer edges are translation-only, so a
            % layer's common linear factor is unobservable and the solver's
            % M = I z-rows pin each tile's L to its partner in the next layer.
            % Only the translation jitters independently per tile (observable
            % through the z-edge [dy dx] measurements).
            G = cell(8, 1);
            slotL = cell(4, 1);
            slotL{1} = eye(2);
            for gridSlot = 2:4
                ang = (rand - 0.5) * 2 * pi/180;
                sc  = 1 + (rand - 0.5) * 0.02;
                slotL{gridSlot} = sc * [cos(ang), -sin(ang); sin(ang), cos(ang)];
            end
            G{1} = [eye(2), nomXY(1, [2 1])' - 1; 0 0 1];
            for t = 2:8
                gridSlot = mod(t - 1, 4) + 1;
                jitter = (rand(2, 1) - 0.5) * 8;
                G{t} = [slotL{gridSlot}, nomXY(gridSlot, [2 1])' - 1 + jitter; 0 0 1];
            end

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(8);
            for t = 1:8
                gridSlot = mod(t - 1, 4) + 1;
                zLayer = 1 + (t > 4);
                oz = trueLayerZ(zLayer);
                tileVolume = zeros(tileH, tileW, tileDepth, 'uint8');
                for sliceIdx = 1:tileDepth
                    tileVolume(:, :, sliceIdx) = imwarp(volume(:, :, oz + sliceIdx - 1), ...
                        affinetform2d(inv(G{t})), 'linear', ...
                        'OutputView', imref2d([tileH tileW]), 'FillValues', 0);
                end
                fn = fullfile(tempDir, sprintf('tile_%02d.tif', t));
                testCase.writeStackTiff(tileVolume, fn);
                layout(t).index     = t;
                layout(t).filename  = fn;
                layout(t).zLayer    = zLayer;
                layout(t).gridRC    = [floor((gridSlot - 1) / 2) + 1, mod(gridSlot - 1, 2) + 1];
                layout(t).nomOrigin = [nomXY(gridSlot, :), 1 + (zLayer - 1) * stepZ];
                layout(t).tileSize  = [tileH, tileW, tileDepth, 1];
                layout(t).dataClass = 'uint8';
            end
        end

        function [layout, origins] = makeGrid(testCase, rows, cols, tileSize, spacing)
            n = rows * cols;
            layout = testCase.emptyLayout(n);
            origins = zeros(n, 3);
            k = 0;
            for r = 1:rows
                for c = 1:cols
                    k = k + 1;
                    oy = 1 + (r - 1) * spacing;
                    ox = 1 + (c - 1) * spacing;
                    layout(k).index = k;
                    layout(k).nomOrigin = [oy ox 1];
                    layout(k).tileSize = tileSize;
                    layout(k).gridRC = [r c];
                    origins(k, :) = [oy ox 1];
                end
            end
        end
    end

    methods (Static, Access = private)

        function bestArea = largestCoveredArea(coverage)
            % LARGESTCOVEREDAREA - Exhaustive maximum-area all-true rectangle in a
            % logical mask. Deliberately naive (O(H^2 W)) - it is the independent
            % ground truth utils.stitch.autocropCanvas's compressed-grid answer is
            % checked against, so it must share no logic with it.
            bestArea = 0;
            H = size(coverage, 1);
            for topRow = 1:H
                for bottomRow = topRow:H
                    columnOk = all(coverage(topRow:bottomRow, :), 1);
                    runEdges = diff([0, columnOk, 0]);
                    runLengths = find(runEdges == -1) - find(runEdges == 1);
                    if isempty(runLengths); continue; end
                    bestArea = max(bestArea, (bottomRow - topRow + 1) * max(runLengths));
                end
            end
        end

        function img = texturedImage(H, W, seed)
            % TEXTUREDIMAGE - Deterministic textured single image (filtered noise +
            % gradients) so phase correlation has real content to lock onto.
            rng(seed, 'twister');
            noise = randn(H, W);
            kernel = fspecial('gaussian', [9 9], 2.0);
            smooth = imfilter(noise, kernel, 'replicate');
            [xx, yy] = meshgrid(linspace(0, 1, W), linspace(0, 1, H));
            gradient = 0.4 * xx + 0.3 * yy + 0.2 * sin(6 * pi * xx) .* cos(5 * pi * yy);
            img = smooth / max(abs(smooth(:))) + gradient;
            img = img - min(img(:));
            img = 200 * img / max(img(:)) + 20;   % into a visible 20..220 range
            img = single(img);
        end

        function volume = texturedVolume(H, W, D, seed)
            % TEXTUREDVOLUME - Deterministic 3D textured volume (3D-filtered noise +
            % gradients) so phase correlation has real content in all three axes.
            rng(seed, 'twister');
            noise = randn(H, W, D);
            noise = imgaussfilt3(noise, 2.0);
            [xx, yy, zz] = meshgrid(linspace(0, 1, W), linspace(0, 1, H), linspace(0, 1, D));
            gradient = 0.35 * xx + 0.25 * yy + 0.25 * zz + ...
                0.15 * sin(5 * pi * xx) .* cos(4 * pi * yy) .* sin(3 * pi * zz);
            volume = noise / max(abs(noise(:))) + gradient;
            volume = volume - min(volume(:));
            volume = 200 * volume / max(volume(:)) + 20;
            volume = single(volume);
        end

        function writeStackTiff(volume, filename)
            % WRITESTACKTIFF - Write a [H W D] uint8 volume as a multi-page TIFF so
            % makeTileReader stacks the pages back into the depth dimension.
            imwrite(volume(:, :, 1), filename);
            for z = 2:size(volume, 3)
                imwrite(volume(:, :, z), filename, 'WriteMode', 'append');
            end
        end

        function meanAbsErr = mosaicVsOriginal(mosaic, original, canvasAnchorTform, trueAnchorTform)
            % MOSAICVSORIGINAL - Mean absolute grey-level difference between a
            % fused mosaic and its source image. The anchor's canvas transform vs
            % its ground-truth map gives the (fractional) source->canvas offset;
            % the source is sampled at the corresponding fractional coordinates.
            offsetXY = canvasAnchorTform(1:2, 3) - trueAnchorTform(1:2, 3);
            [H, W] = size(mosaic);
            margin = 8;   % skip mosaic borders (feather edge + zero fill)
            rows = (1 + margin):(H - margin);
            cols = (1 + margin):(W - margin);
            [colGrid, rowGrid] = meshgrid(cols, rows);
            srcX = colGrid - offsetXY(1);
            srcY = rowGrid - offsetXY(2);
            inside = srcX >= 2 & srcX <= size(original, 2) - 1 & ...
                     srcY >= 2 & srcY <= size(original, 1) - 1;
            srcVals = interp2(double(original), srcX(inside), srcY(inside), 'linear');
            mosaicRegion = double(mosaic(rows, cols));
            meanAbsErr = mean(abs(mosaicRegion(inside) - srcVals));
        end

        function [tiles, origins] = chopIntoTiles(img, rows, cols, overlapPx, jitterPx)
            % CHOPINTOTILES - Split a textured image into an overlapping tile grid.
            %
            % Returns the tile crops plus their ground-truth top-left origins
            % ([y x z], 1-based). jitterPx perturbs the reported origins to emulate
            % positioning error (0 for an exact reconstruction test).
            [H, W] = size(img);
            % tile step so that tiles cover the image with the requested overlap.
            tileH = floor((H + (rows - 1) * overlapPx) / rows);
            tileW = floor((W + (cols - 1) * overlapPx) / cols);
            stepY = tileH - overlapPx;
            stepX = tileW - overlapPx;

            tiles = {};
            origins = [];
            rng(999, 'twister');
            for r = 1:rows
                for c = 1:cols
                    oy = 1 + (r - 1) * stepY;
                    ox = 1 + (c - 1) * stepX;
                    oy = min(oy, H - tileH + 1);
                    ox = min(ox, W - tileW + 1);
                    crop = img(oy:(oy + tileH - 1), ox:(ox + tileW - 1));
                    tiles{end+1} = uint8(crop); %#ok<AGROW>
                    jy = round(jitterPx * (2 * rand - 1));
                    jx = round(jitterPx * (2 * rand - 1));
                    origins(end+1, :) = [oy + jy, ox + jx, 1]; %#ok<AGROW>
                end
            end
        end
    end
end
