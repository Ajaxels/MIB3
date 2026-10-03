classdef StitchInspectorTest < matlab.unittest.TestCase
% STITCHINSPECTORTEST - Unit tests for the seam-inspector headless core (Phase A).
%
% Covers (see development/stitching/plan_inspector.md):
%   utils.stitch.scoreSeams       - pixel NCC at solved positions + worst-first ranking
%   utils.stitch.localCorrelate   - click-seeded ROI registration + confidence gate
%   solver user-edge support      - userEdgeWeight dominance, never-pruned rule
%   utils.stitch.measureAllPairs  - user edges survive a re-measure (preserveEdges)
%   saveProject / loadProject     - sidecar v2 (source/seamScore) + v1 back-compat

    methods (TestClassSetup)
        function addPaths(testCase)
            thisFile = mfilename('fullpath');
            testsFolder = fileparts(fileparts(thisFile));          % tests/
            repoRoot = fileparts(testsFolder);
            mibFolder = fullfile(repoRoot, 'mib');
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture({testsFolder, mibFolder}));
        end
    end

    % =================================================================
    % scoreSeams
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function scoreSeams_correctHighMisplacedLow(testCase)
            % Correct placement scores high everywhere; misplacing one tile
            % tanks exactly its edges' scores - the metric that catches
            % confidently-wrong edges the solver residuals cannot see.
            [layout, truth] = testCase.buildChoppedCase(21);
            edges = testCase.edgesFromPairs(layout);

            edges = utils.stitch.scoreSeams(layout, edges, truth);
            goodScores = [edges.seamScore];
            testCase.verifyGreaterThan(min(goodScores), 0.7, ...
                'seams at the true placement must score high');

            % Misplace tile 4 by [25 18]: only its edges must drop.
            corrupted = truth;
            corrupted(4, 1:2) = corrupted(4, 1:2) + [25 18];
            edges = utils.stitch.scoreSeams(layout, edges, corrupted);
            badScores = [edges.seamScore];
            touchesTile4 = [edges.i] == 4 | [edges.j] == 4;
            testCase.verifyLessThan(max(badScores(touchesTile4)), ...
                min(badScores(~touchesTile4)) - 0.2, ...
                'edges of the misplaced tile must score clearly below the rest');

            % Worst-first ranking starts with a tile-4 edge.
            [~, ranking] = utils.stitch.scoreSeams(layout, edges, corrupted);
            testCase.verifyTrue(touchesTile4(ranking(1)), ...
                'ranking must lead with an edge of the misplaced tile');
        end

        function scoreSeams_prunedEdgesRankFirst(testCase)
            % A pruned (valid = false) edge leads the review order even when
            % its pixels agree perfectly at the solved positions.
            [layout, truth] = testCase.buildChoppedCase(33);
            edges = testCase.edgesFromPairs(layout);
            edges(2).valid = false;

            [edges, ranking] = utils.stitch.scoreSeams(layout, edges, truth);
            testCase.verifyEqual(ranking(1), 2, ...
                'the pruned edge must rank first regardless of its seam score');
            testCase.verifyGreaterThan(edges(2).seamScore, 0.7, ...
                'the pruned edge still gets a real score for the table');
        end

        function scoreSeams_noOverlapScoresNaN(testCase)
            % Tiles pushed apart at the solved positions: no pixels to compare.
            [layout, truth] = testCase.buildChoppedCase(43);
            apart = truth;
            apart(2, 2) = apart(2, 2) + 500;   % tile 2 far right
            edges = testCase.edgesFromPairs(layout);

            [edges, ranking] = utils.stitch.scoreSeams(layout, edges, apart);
            edge12 = find([edges.i] == 1 & [edges.j] == 2, 1);
            testCase.verifyTrue(isnan(edges(edge12).seamScore), ...
                'non-overlapping placement must score NaN');
            testCase.verifyEqual(ranking(1), edge12, ...
                'the NaN-scored edge must lead the ranking');
        end

        function scoreSeams3D_dzErrorLoweredAndHinted(testCase)
            % 3D check: strips are depth-aligned by the solved dz and scored
            % slice-by-slice. At the true dz the z-pair scores ~1 with no
            % hint; corrupting the solved dz by +2 tanks the score AND the
            % dz-scan points back (dzHint = -2), which also round-trips
            % through the project sidecar.
            dzTrue = 3;
            [layout, truth, edges] = testCase.buildZPairCase(55, dzTrue);

            scored = utils.stitch.scoreSeams(layout, edges, truth);
            testCase.verifyGreaterThan(scored(1).seamScore, 0.9, ...
                'z-pair at the true dz must score high');
            testCase.verifyEqual(scored(1).dzHint, 0, ...
                'no dz hint when the solved dz is the optimum');

            corrupted = truth;
            corrupted(2, 3) = corrupted(2, 3) + 2;   % solved dz off by +2
            misScored = utils.stitch.scoreSeams(layout, edges, corrupted);
            testCase.verifyLessThan(misScored(1).seamScore, ...
                scored(1).seamScore - 0.2, ...
                'a dz error must clearly lower the per-slice slab score');
            testCase.verifyEqual(misScored(1).dzHint, -2, ...
                'the dz-scan must point back to the true offset');

            projectDir = tempname; mkdir(projectDir);
            testCase.addTeardown(@() rmdir(projectDir, 's'));
            projectFile = fullfile(projectDir, 'zpair.mibstitch.json');
            utils.stitch.saveProject(projectFile, layout, misScored, corrupted, [], []);
            [~, loadedEdges] = utils.stitch.loadProject(projectFile);
            testCase.verifyEqual(loadedEdges(1).dzHint, -2, ...
                'dzHint must round-trip through the project sidecar');
        end

        function zBoundaryFix_shiftsAllLayersAbove(testCase)
            % The microscopy requirement behind Fix-Z: correcting a Z-boundary
            % seam must shift the WHOLE upper stack and EVERY layer above it
            % (the stacks hang off each other through the cross-layer edges),
            % while the layers below stay put. Pure solver behaviour - no
            % pixel data needed.
            depth = 8; dzTrue = 6;
            layout = testCase.emptyLayout(3);
            for k = 1:3
                layout(k).index = k;
                layout(k).zLayer = k;
                layout(k).nomOrigin = [1, 1, 1 + (k - 1) * dzTrue];
                layout(k).tileSize = [96, 96, depth, 1];
            end
            edgeTemplate = struct('i', 1, 'j', 2, 'direction', 'z', ...
                'nominal', [0 0 dzTrue], 'measured', [0 0 dzTrue], ...
                'quality', 1, 'valid', true, 'source', 'auto');
            edges = [edgeTemplate, edgeTemplate];
            edges(2).i = 2; edges(2).j = 3;

            solverOptions = struct('springWeight', 0.05);
            positionsBefore = utils.stitch.solveGlobalLeastSquares(layout, edges, solverOptions);

            % User fixes the 1-2 boundary: layer 2 is [5 7] px off in-plane.
            edges(1).measured = [5 7 dzTrue];
            edges(1).source = 'user';
            positionsAfter = utils.stitch.solveGlobalLeastSquares(layout, edges, solverOptions);

            shiftLayer2 = positionsAfter(2, 1:2) - positionsBefore(2, 1:2);
            shiftLayer3 = positionsAfter(3, 1:2) - positionsBefore(3, 1:2);
            testCase.verifyEqual(positionsAfter(1, :), positionsBefore(1, :), 'AbsTol', 0.25, ...
                'the layer BELOW the fixed boundary must stay put');
            testCase.verifyEqual(shiftLayer2, [5 7], 'AbsTol', 1.0, ...
                'the corrected layer must shift by the fixed in-plane offset');
            testCase.verifyEqual(shiftLayer3, shiftLayer2, 'AbsTol', 1.0, ...
                'every layer above must follow the corrected one as a block');
        end
    end

    % =================================================================
    % localCorrelate
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function localCorrelate_recoversOffsetFromClick(testCase)
            % Two overlapping cuts of a textured image; start from an offset
            % that is 20-ish px wrong (within the search radius) and click a
            % spot in the overlap: the NCC snap must recover the true offset.
            base = testCase.texturedImage(400, 400, 7);
            tileA = base(1:260, 1:260);
            trueOffsetYX = [40, 130];                       % tile B origin - tile A origin
            tileB = base(41:300, 131:390);
            wrongOffsetYX = trueOffsetYX + [17, -12];

            % Click inside the overlap (A-local): overlap cols 131..260, rows 41..260.
            clickXY = [200, 150];                           % [x y]
            [newOffsetYX, score, confident, debugInfo] = utils.stitch.localCorrelate( ...
                tileA, tileB, clickXY, wrongOffsetYX);

            testCase.verifyTrue(confident, sprintf('expected a confident match (reason: %s)', debugInfo.reason));
            testCase.verifyGreaterThan(score, 0.8);
            testCase.verifyEqual(newOffsetYX, trueOffsetYX, 'AbsTol', 0.5, ...
                'click-to-correlate did not recover the true offset');
        end

        function localCorrelate_rawFirstBlurredFallback(testCase)
            % Clean content matches on the raw crops (no blur used); with
            % pixel noise the raw NCC falls under minPeak and the blurred
            % fallback must snap to the true offset instead.
            stream = RandStream('twister', 'Seed', 1);
            base = imgaussfilt(rand(stream, 400, 400, 'single'), 2);
            base = (base - min(base(:))) / (max(base(:)) - min(base(:)));
            trueOffsetYX = [40, 130];
            wrongOffsetYX = trueOffsetYX + [6, -5];
            clickXY = [200, 150];

            [~, ~, confident, debugInfo] = utils.stitch.localCorrelate( ...
                base(1:260, 1:260), base(41:300, 131:390), clickXY, wrongOffsetYX);
            testCase.verifyTrue(confident);
            testCase.verifyEqual(debugInfo.smoothSigma, 0, ...
                'clean content must match on the raw crops');

            noisyA = base + 0.15 * randn(stream, 400, 400, 'single');
            noisyB = base + 0.15 * randn(stream, 400, 400, 'single');
            tileA = noisyA(1:260, 1:260);
            tileB = noisyB(41:300, 131:390);
            [~, ~, rawConfident] = utils.stitch.localCorrelate( ...
                tileA, tileB, clickXY, wrongOffsetYX, struct('smoothSigma', 0));
            testCase.assertFalse(rawConfident, 'the noise level must defeat the raw match');
            [newOffsetYX, ~, confident, debugInfo] = utils.stitch.localCorrelate( ...
                tileA, tileB, clickXY, wrongOffsetYX);
            testCase.verifyTrue(confident, sprintf('the blurred fallback must snap (reason: %s)', debugInfo.reason));
            testCase.verifyEqual(debugInfo.smoothSigma, 1);
            testCase.verifyEqual(newOffsetYX, trueOffsetYX, 'AbsTol', 0.5);
        end

        function localCorrelate_flatTextureNotConfident(testCase)
            % Featureless ROI: never a confident (silent) move.
            flat = 100 * ones(300, 300, 'single');
            currentOffsetYX = [0, 150];
            [newOffsetYX, ~, confident, debugInfo] = utils.stitch.localCorrelate( ...
                flat, flat, [200, 150], currentOffsetYX);
            testCase.verifyFalse(confident);
            testCase.verifyEqual(debugInfo.reason, 'flat-template');
            testCase.verifyEqual(newOffsetYX, currentOffsetYX, ...
                'a non-confident result must leave the offset unchanged');
        end

        function localCorrelate_repetitivePatternNotConfident(testCase)
            % Pure periodic stripes: the second NCC peak ties the first, so the
            % prominence gate must refuse - this is the failure mode the
            % inspector exists to fix, it must not reproduce it.
            [cols, ~] = meshgrid(1:300, 1:300);
            stripes = single(127 + 100 * sin(2 * pi * cols / 24));
            [~, ~, confident, debugInfo] = utils.stitch.localCorrelate( ...
                stripes, stripes, [150, 150], [0, 0]);
            testCase.verifyFalse(confident, ...
                sprintf('periodic content must not pass the prominence gate (reason: %s)', debugInfo.reason));
        end
    end

    % =================================================================
    % Solver user-edge support
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function solver_userEdgeDominatesConflictingAutoEdge(testCase)
            layout = testCase.twoTileLayout();
            autoEdge = testCase.makeEdge(1, 2, [5 95 0], 1.0, true, 'auto');
            userEdge = testCase.makeEdge(1, 2, [0 80 0], 1.0, true, 'user');
            edges = [autoEdge, userEdge];

            positions = utils.stitch.solveGlobalLeastSquares(layout, edges);
            delta = positions(2, :) - positions(1, :);
            testCase.verifyEqual(delta(1:2), [0 80], 'AbsTol', 3.0, ...
                'the user fix (weight 5) must dominate the conflicting auto edge');
            errUser = norm(delta(1:2) - [0 80]);
            errAuto = norm(delta(1:2) - [5 95]);
            testCase.verifyLessThan(errUser, errAuto);

            % Same behaviour through the affine solver.
            [~, positionsAffine] = utils.stitch.solveGlobalAffine(layout, edges);
            deltaAffine = positionsAffine(2, 1:2) - positionsAffine(1, 1:2);
            testCase.verifyEqual(deltaAffine, [0 80], 'AbsTol', 3.0, ...
                'the affine solver must weight user edges identically');
        end

        function solver_userEdgeNeverPruned(testCase)
            % quality = 0 / valid = false would normally demote the edge to a
            % nominal spring; source='user' must keep it as a real constraint.
            layout = testCase.twoTileLayout();
            userEdge = testCase.makeEdge(1, 2, [6 90 0], 0, false, 'user');

            [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, userEdge);
            delta = positions(2, :) - positions(1, :);
            testCase.verifyEqual(delta(1:2), [6 90], 'AbsTol', 0.1, ...
                'a user edge must never be pruned by the quality threshold');
            testCase.verifyEqual(stats.nPruned, 0);
        end
    end

    % =================================================================
    % Phase B milestone: the sabotaged-chain review loop
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function sabotagedChain_caughtRankedAndRecovered(testCase)
            % The seam inspector's reason to exist, end to end (headless): a
            % confidently-wrong edge on a CHAIN satisfies the solver exactly
            % (residual-blind), the pixel seam score ranks it first, and
            % exclude + re-solve recovers the layout via the nominal springs.
            [layout, truth] = testCase.buildChainCase(77);
            pairs = utils.stitch.findNeighborPairs(layout);
            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3));

            % Corrupt the 2-3 edge: one "period" off, high quality.
            edge23 = find([edges.i] == 2 & [edges.j] == 3, 1);
            testCase.assertNotEmpty(edge23);
            edges(edge23).measured = edges(edge23).measured + [0 18 0];
            edges(edge23).quality  = 0.95;
            edges(edge23).valid    = true;

            [positions, stats] = utils.stitch.solveGlobalLeastSquares(layout, edges);
            testCase.verifyLessThan(stats.rmseTotal, 0.5, ...
                'a chain has no loop: the corrupted edge must be residual-invisible');
            testCase.verifyEqual(positions(3, 2) - truth(3, 2), 18, 'AbsTol', 1.5, ...
                'the corruption must displace tile 3 by the injected offset');

            [edges, ranking] = utils.stitch.scoreSeams(layout, edges, positions);
            testCase.verifyEqual(ranking(1), edge23, ...
                'the pixel seam score must rank the corrupted edge first');
            edge12 = find([edges.i] == 1 & [edges.j] == 2, 1);
            testCase.verifyLessThan(edges(edge23).seamScore, ...
                edges(edge12).seamScore - 0.3);

            % Inspector action: exclude + re-solve; the chop has zero jitter,
            % so the nominal springs recover the truth exactly.
            edges(edge23).valid = false;
            edges(edge23).source = 'auto';
            recovered = utils.stitch.solveGlobalLeastSquares(layout, edges);
            testCase.verifyEqual(recovered(:, 1:2), truth(:, 1:2), 'AbsTol', 1.0, ...
                'exclude + re-solve must recover the zero-jitter chain');

            edges = utils.stitch.scoreSeams(layout, edges, recovered);
            testCase.verifyGreaterThan(edges(edge23).seamScore, 0.8, ...
                'the recovered seam must score high again');
        end
    end

    % =================================================================
    % Phase C milestone: click-fix
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function clickFix_recoversSabotagedChainWithinOnePixel(testCase)
            % Phase C milestone: the corrupted edge is FIXED (not excluded)
            % via one click near a landmark - localCorrelate snaps the pair
            % from the wrong SOLVED offset, the resulting user edge steers
            % the solve, and every tile lands within 1 px of ground truth.
            [layout, truth] = testCase.buildChainCase(91);
            pairs = utils.stitch.findNeighborPairs(layout);
            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3));

            edge23 = find([edges.i] == 2 & [edges.j] == 3, 1);
            testCase.assertNotEmpty(edge23);
            edges(edge23).measured = edges(edge23).measured + [0 18 0];
            edges(edge23).quality  = 0.95;
            edges(edge23).valid    = true;
            positions = utils.stitch.solveGlobalLeastSquares(layout, edges);

            % The inspector's click-to-correlate: click a spot inside the
            % 40-px overlap of tiles 2/3, seeded with the WRONG solved
            % offset. ROI kept smaller than the overlap strip (as the GUI
            % spinner allows) so the template content actually exists in B.
            readerFcn = utils.stitch.makeTileReader(layout);
            tileA = readerFcn(2);
            tileB = readerFcn(3);
            wrongOffsetYX = positions(3, 1:2) - positions(2, 1:2);
            clickXY = [150, 80];                       % [x y], tile-2 local
            [newOffsetYX, score, confident, debugInfo] = utils.stitch.localCorrelate( ...
                tileA, tileB, clickXY, wrongOffsetYX, struct('roiSize', 48));
            testCase.assertTrue(confident, ...
                sprintf('the click must produce a confident snap (reason: %s)', debugInfo.reason));
            testCase.verifyGreaterThan(score, 0.8);

            % applyUserFix semantics: user edge, quality 1, never pruned.
            edges(edge23).measured = [newOffsetYX, 0];
            edges(edge23).quality  = 1;
            edges(edge23).valid    = true;
            edges(edge23).source   = 'user';
            fixedPositions = utils.stitch.solveGlobalLeastSquares(layout, edges);
            testCase.verifyEqual(fixedPositions(:, 1:2), truth(:, 1:2), 'AbsTol', 1.0, ...
                'click-fix milestone: all tiles within 1 px of ground truth');

            edges = utils.stitch.scoreSeams(layout, edges, fixedPositions);
            testCase.verifyGreaterThan(edges(edge23).seamScore, 0.8, ...
                'the fixed seam must score high at the re-solved placement');
        end

    end

    % =================================================================
    % measureAllPairs preservation + sidecar v2
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function measureAllPairs_preservesUserEdges(testCase)
            [layout, ~, ~] = testCase.buildChoppedCase(55);
            pairs = utils.stitch.findNeighborPairs(layout);
            edges = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3));
            testCase.assertNotEmpty(edges);
            testCase.verifyTrue(all(strcmp({edges.source}, 'auto')), ...
                'fresh measurements must be tagged auto');

            % A QC session fixed edge 1 by hand …
            fixed = edges;
            fixed(1).measured = [3 33 0];
            fixed(1).quality  = 1;
            fixed(1).valid    = true;
            fixed(1).source   = 'user';

            % … and a re-measure must keep exactly that fix.
            remeasured = utils.stitch.measureAllPairs(layout, pairs, ...
                struct('qualityThreshold', 0.3, 'preserveEdges', fixed));
            match = find([remeasured.i] == fixed(1).i & [remeasured.j] == fixed(1).j, 1);
            testCase.verifyEqual(remeasured(match).measured, [3 33 0], ...
                'the user-fixed offset must survive a re-measure');
            testCase.verifyEqual(remeasured(match).source, 'user');
            otherSources = {remeasured([remeasured.i] ~= fixed(1).i | [remeasured.j] ~= fixed(1).j).source};
            testCase.verifyTrue(all(strcmp(otherSources, 'auto')), ...
                'non-fixed edges must take the fresh automatic measurement');
        end

        function saveLoadProject_v2RoundTripAndV1BackCompat(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            tempFixture = testCase.applyFixture(TemporaryFolderFixture);

            layout = testCase.twoTileLayout();
            layout(1).filename = fullfile(tempFixture.Folder, 'a.tif');
            layout(2).filename = fullfile(tempFixture.Folder, 'b.tif');

            % v2 round-trip: source + seamScore survive.
            edges = [testCase.makeEdge(1, 2, [0 80 0], 0.9, true, 'user'), ...
                     testCase.makeEdge(1, 2, [1 81 0], 0.8, true, 'confirmed')];
            edges(1).seamScore = 0.42;
            projectFile = fullfile(tempFixture.Folder, 'v2.mibstitch.json');
            utils.stitch.saveProject(projectFile, layout, edges, [], [], []);
            [~, loadedEdges] = utils.stitch.loadProject(projectFile);
            testCase.verifyEqual(loadedEdges(1).source, 'user');
            testCase.verifyEqual(loadedEdges(1).seamScore, 0.42, 'AbsTol', 1e-9);
            testCase.verifyEqual(loadedEdges(2).source, 'confirmed');
            testCase.verifyEmpty(loadedEdges(2).seamScore);

            % v1 back-compat: edges saved WITHOUT the new fields load with
            % defaults ('auto', unscored).
            v1Edges = rmfield(edges, {'source', 'seamScore'});
            v1File = fullfile(tempFixture.Folder, 'v1.mibstitch.json');
            utils.stitch.saveProject(v1File, layout, v1Edges, [], [], []);
            [~, loadedV1] = utils.stitch.loadProject(v1File);
            testCase.verifyEqual(loadedV1(1).source, 'auto', ...
                'v1 edges must default to auto provenance');
            testCase.verifyEmpty(loadedV1(1).seamScore);
        end
    end

    % =================================================================
    % Local helpers
    % =================================================================
    methods (Access = private)

        function [layout, truth, original] = buildChoppedCase(testCase, seed)
            % 2x2 chop of a textured image written to disk; layout carries the
            % TRUE origins as nominal (zero jitter), truth = those origins.
            original = uint8(testCase.texturedImage(220, 220, seed));
            overlapPx = 40;
            tileH = floor((220 + overlapPx) / 2);
            tileW = tileH;
            stepY = tileH - overlapPx;
            stepX = tileW - overlapPx;

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(4);
            truth = zeros(4, 3);
            k = 0;
            for r = 1:2
                for c = 1:2
                    k = k + 1;
                    oy = min(1 + (r - 1) * stepY, 220 - tileH + 1);
                    ox = min(1 + (c - 1) * stepX, 220 - tileW + 1);
                    truth(k, :) = [oy, ox, 1];
                    fn = fullfile(tempDir, sprintf('tile_%02d.tif', k));
                    imwrite(original(oy:oy + tileH - 1, ox:ox + tileW - 1), fn);
                    layout(k).index = k;
                    layout(k).filename = fn;
                    layout(k).gridRC = [r c];
                    layout(k).nomOrigin = truth(k, :);
                    layout(k).tileSize = [tileH, tileW, 1, 1];
                    layout(k).dataClass = 'uint8';
                end
            end
        end

        function [layout, truth] = buildChainCase(testCase, seed)
            % 1x3 chain (no loop) chopped with ZERO jitter - nominal == truth,
            % so nominal-spring recovery after an exclusion is exact.
            original = uint8(testCase.texturedImage(180, 460, seed));
            tileH = 160; tileW = 160; step = 120;   % 40 px overlap

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(3);
            truth = zeros(3, 3);
            for k = 1:3
                oy = 1;
                ox = 1 + (k - 1) * step;
                truth(k, :) = [oy, ox, 1];
                fn = fullfile(tempDir, sprintf('tile_%02d.tif', k));
                imwrite(original(oy:oy + tileH - 1, ox:ox + tileW - 1), fn);
                layout(k).index = k;
                layout(k).filename = fn;
                layout(k).gridRC = [1 k];
                layout(k).nomOrigin = truth(k, :);
                layout(k).tileSize = [tileH, tileW, 1, 1];
                layout(k).dataClass = 'uint8';
            end
        end

        function [layout, truth, edges] = buildZPairCase(testCase, seed, dzTrue)
            % Two z-stack tiles (multi-page TIFFs) cut from one volume at a
            % dzTrue slice offset: a cross-layer ('z') pair sharing the full
            % XY footprint and depth - dzTrue slices. The volume is smoothed
            % in XY but only lightly in Z, so per-slice correlation is
            % strongly peaked at the true dz.
            rng(seed, 'twister');
            tileH = 96; tileW = 96; depth = 8;
            volume = rand(tileH, tileW, depth + dzTrue);
            volume = smooth3(volume, 'box', [9 9 3]);
            volume = uint8(255 * (volume - min(volume(:))) / ...
                (max(volume(:)) - min(volume(:))));

            tempDir = tempname; mkdir(tempDir);
            testCase.addTeardown(@() rmdir(tempDir, 's'));

            layout = testCase.emptyLayout(2);
            truth = [1 1 1; 1 1 1 + dzTrue];
            for k = 1:2
                zRange = truth(k, 3):truth(k, 3) + depth - 1;
                fn = fullfile(tempDir, sprintf('ztile_%02d.tif', k));
                imwrite(volume(:, :, zRange(1)), fn);
                for z = zRange(2:end)
                    imwrite(volume(:, :, z), fn, 'WriteMode', 'append');
                end
                layout(k).index = k;
                layout(k).filename = fn;
                layout(k).zLayer = k;
                layout(k).nomOrigin = truth(k, :);
                layout(k).tileSize = [tileH, tileW, depth, 1];
            end

            edges = struct('i', 1, 'j', 2, 'direction', 'z', ...
                'nominal', [0 0 dzTrue], 'measured', [0 0 dzTrue], ...
                'quality', 1, 'valid', true, 'source', 'auto', 'seamScore', []);
        end

        function edges = edgesFromPairs(~, layout)
            % Valid edges for all neighbour pairs, measured == nominal (truth).
            pairs = utils.stitch.findNeighborPairs(layout);
            edges = pairs;
            for k = 1:numel(edges)
                edges(k).measured  = edges(k).nominal;
                edges(k).quality   = 1;
                edges(k).valid     = true;
                edges(k).source    = 'auto';
                edges(k).seamScore = [];
            end
        end

        function layout = twoTileLayout(testCase)
            layout = testCase.emptyLayout(2);
            layout(1).index = 1; layout(1).nomOrigin = [1 1 1];
            layout(2).index = 2; layout(2).nomOrigin = [1 81 1];
            layout(1).tileSize = [100 100 1 1];
            layout(2).tileSize = [100 100 1 1];
        end

        function edge = makeEdge(~, i, j, measured, quality, valid, source)
            edge.i = i; edge.j = j; edge.direction = 'x';
            edge.nominal = [0 80 0];
            edge.measured = measured;
            edge.quality = quality;
            edge.valid = valid;
            edge.tform = [];
            edge.source = source;
            edge.seamScore = [];
        end

        function layout = emptyLayout(~, n)
            layout = repmat(struct('index', 0, 'filename', '', 'sliceFiles', {{}}, ...
                'zLayer', 1, 'gridRC', [NaN NaN], 'nomOrigin', [1 1 1], ...
                'tileSize', [1 1 1 1], 'dataClass', 'uint8'), 1, n);
        end
    end

    methods (Static, Access = private)

        function img = texturedImage(H, W, seed)
            % Deterministic textured image (filtered noise + gradients) - same
            % recipe as StitchCoreTest so correlation has real content.
            rng(seed, 'twister');
            noise = randn(H, W);
            kernel = fspecial('gaussian', [9 9], 2.0);
            smooth = imfilter(noise, kernel, 'replicate');
            [xx, yy] = meshgrid(linspace(0, 1, W), linspace(0, 1, H));
            gradient = 0.4 * xx + 0.3 * yy + 0.2 * sin(6 * pi * xx) .* cos(5 * pi * yy);
            img = smooth / max(abs(smooth(:))) + gradient;
            img = img - min(img(:));
            img = 200 * img / max(img(:)) + 20;
            img = single(img);
        end
    end
end
