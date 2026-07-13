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
                fullfile(mibFolder, 'external', 'Zarr3Matlab')}));
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
    % fuseInMemory — all four blend modes vs original
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function fuseInMemory_allBlendModesReconstruct(testCase)
            modes = {'Feather', 'Average', 'Max', 'Overwrite'};
            for m = 1:numel(modes)
                testCase.subFuseReconstruct(modes{m});
            end
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
