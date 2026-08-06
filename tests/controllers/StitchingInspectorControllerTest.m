classdef StitchingInspectorControllerTest < matlab.unittest.TestCase
% STITCHINGINSPECTORCONTROLLERTEST - Unit tests for the seam inspector controller.
%
% The review/fix logic of ``controllers.StitchingInspector``: ranking, the
% single write path for user fixes (``applyUserFix``), undo, exclude/confirm,
% navigation, the re-solve handshake with the parent Stitching window, and the
% Fix-Z per-slice mosaic corrections. The scoring and solving primitives
% underneath are covered by ``tests/utils/StitchInspectorTest.m``; these tests
% drive the CONTROLLER, which owns the state transitions between them.
%
% Headless throughout: ``controllers.StitchingInspector(mibModel, stitching,
% struct('createView', false))`` builds the inspector without its window, and
% every widget access in the class is guarded by
% :meth:`controllers.StitchingInspector.hasWidget`, so the same code paths run.
% Where a test needs a specific widget (the Fix-mode dropdown) it injects a
% stub ``view`` holding only that one.
%
% The fixture is a 1x3 chain with one confidently-wrong seam - a chain has no
% loop, so the solver residual cannot see the error and only the pixel seam
% score can, which is the inspector's reason to exist.
%
% See also: controllers.StitchingInspector, controllers.Stitching, utils.stitch.scoreSeams

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    % =================================================================
    % Construction, scoring and ranking
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function headlessConstructionScoresRanksAndSelectsTheWorstSeam(testCase)
            [inspector, stitching, badEdge] = testCase.openInspector(44);

            testCase.verifyEmpty(inspector.view, 'createView=false must not build a window');
            testCase.verifyEqual(numel(inspector.ranking), numel(stitching.edges));
            testCase.verifyEqual(inspector.ranking(1), badEdge, ...
                'the sabotaged seam must rank first (worst pixel match)');
            testCase.verifyEqual(inspector.currentEdgeIdx, badEdge, ...
                'the inspector must open on the worst seam');
            testCase.verifyFalse(inspector.resolvePending);
            % Scores are written back onto the PARENT's edges (single source of
            % truth). How far a misplaced seam falls depends on the texture, so
            % assert the SEPARATION that drives the ranking, not an absolute value.
            goodEdge = setdiff(1:numel(stitching.edges), badEdge);
            testCase.verifyGreaterThan(stitching.edges(goodEdge).seamScore, 0.8);
            testCase.verifyLessThan(stitching.edges(badEdge).seamScore, ...
                stitching.edges(goodEdge).seamScore - 0.3);
        end

        function constructionBeforeASolveIsRefused(testCase)
            % The inspector reviews seams at the SOLVED placement; without
            % positions there is nothing to review. With a window this is an
            % error dialog + CloseEvent, headless it must raise.
            controller = testCase.chainController(42);
            controller.buildLayoutFromBatchOpt();
            controller.measureOverlaps_Callback();      % edges but no positions
            testCase.verifyError(@() controllers.StitchingInspector( ...
                controller.mibModel, controller, struct('createView', false)), ...
                'StitchingInspector:noSeams');
        end

        function dataValidTurnsFalseWhenTheParentRebuildsTheLayout(testCase)
            % A layout rebuild in the Stitching window invalidates the review
            % session; every entry point checks dataValid first, so the stale
            % inspector must degrade to no-ops rather than error.
            [inspector, stitching] = testCase.openInspector(43);
            testCase.assertTrue(inspector.dataValid());

            stitching.buildLayoutFromBatchOpt();     % drops edges + positions
            testCase.verifyFalse(inspector.dataValid());
            testCase.verifyWarningFree(@() inspector.updateWidgets());
            testCase.verifyWarningFree(@() inspector.confirmSeam_Callback());
            testCase.verifyWarningFree(@() inspector.excludeSeam_Callback());
            testCase.verifyWarningFree(@() inspector.applyUserFix([0 120], 'ignored'));
            testCase.verifyEmpty(stitching.edges, 'a stale inspector must not resurrect edges');
        end
    end

    % =================================================================
    % applyUserFix - the single write path for every fixing tool
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function applyUserFixWritesAUserEdgeAndReSolves(testCase)
            % Drag / click-to-correlate / two-click all funnel through here:
            % the measurement becomes the user's offset, provenance 'user',
            % quality 1 (the solver weights user edges high and never prunes
            % them), any fitted transform dropped, and the global solve re-run.
            [inspector, stitching, badEdge] = testCase.openInspector(44);
            truthOffset = [0 120];   % tiles 2 and 3 are 120 px apart

            inspector.applyUserFix(truthOffset, 'test fix');

            edge = stitching.edges(badEdge);
            testCase.verifyEqual(edge.source, 'user');
            testCase.verifyEqual(edge.quality, 1);
            testCase.verifyTrue(edge.valid);
            testCase.verifyEmpty(edge.tform, 'a user fix is pure translation');
            testCase.verifyEqual(edge.measured(1:2), truthOffset, 'AbsTol', 1e-9);
            testCase.verifyFalse(inspector.resolvePending, 'auto re-solve is on by default');
            testCase.verifyEqual(stitching.positions, [1 1 1; 1 121 1; 1 241 1], 'AbsTol', 1.0, ...
                'the fixed edge must steer the solve back to the truth');
        end

        function deferredFixLeavesPositionsStaleAndFlagsAReSolve(testCase)
            % deferResolve (and auto-re-solve off) is what makes Stitch check
            % resolvePending before fusing - otherwise the mosaic would come
            % from positions that predate the fix.
            [inspector, stitching, badEdge] = testCase.openInspector(45);
            positionsBefore = stitching.positions;
            seamsUpdated = 0;
            listener = addlistener(inspector, 'SeamsUpdated', @(~, ~) countUpdate()); %#ok<NASGU>

            inspector.applyUserFix([0 120], 'deferred fix', true);

            testCase.verifyTrue(inspector.resolvePending);
            testCase.verifyEqual(stitching.positions, positionsBefore, ...
                'a deferred fix must not move any tile yet');
            testCase.verifyEqual(stitching.edges(badEdge).source, 'user');
            testCase.verifyEqual(seamsUpdated, 1, 'the parent must be told the edges changed');

            inspector.resolveBtn_Callback();
            testCase.verifyFalse(inspector.resolvePending);
            testCase.verifyEqual(stitching.positions, [1 1 1; 1 121 1; 1 241 1], 'AbsTol', 1.0);
            testCase.verifyGreaterThan(min([stitching.edges.seamScore]), 0.8, ...
                'a re-solve must re-score the seams at the new placement');

            function countUpdate()
                seamsUpdated = seamsUpdated + 1;
            end
        end

        function undoRestoresTheOriginalAutomaticEdgeAfterRepeatedFixes(testCase)
            % One backup per edge = the ORIGINAL automatic measurement, so a
            % sequence of nudges undoes to where the automatics left it, not to
            % the previous nudge.
            [inspector, stitching, badEdge] = testCase.openInspector(46);
            automaticEdge = stitching.edges(badEdge);

            inspector.applyUserFix([0 100], 'first');
            inspector.applyUserFix([0 120], 'second');
            testCase.assertEqual(stitching.edges(badEdge).measured(1:2), [0 120], 'AbsTol', 1e-9);

            inspector.undoFix_Callback();

            restored = stitching.edges(badEdge);
            testCase.verifyEqual(restored.measured, automaticEdge.measured, 'AbsTol', 1e-9);
            testCase.verifyEqual(restored.source, automaticEdge.source);
            testCase.verifyEqual(restored.quality, automaticEdge.quality);
            testCase.verifyTrue(restored.valid);
        end

        function undoWithoutAFixIsANoOp(testCase)
            [inspector, stitching, badEdge] = testCase.openInspector(47);
            before = stitching.edges(badEdge);
            inspector.undoFix_Callback();
            testCase.verifyEqual(stitching.edges(badEdge).measured, before.measured);
            testCase.verifyEqual(stitching.edges(badEdge).source, before.source);
        end
    end

    % =================================================================
    % Review bookkeeping: exclude / confirm / navigate
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function excludeTogglesValidityAndWithdrawsUserProvenance(testCase)
            % Excluding a user fix withdraws it - user edges are otherwise
            % never pruned, so leaving the provenance would re-assert the fix
            % on the next re-solve. The EDGE is the single source of truth, so
            % the second press must re-include.
            [inspector, stitching, badEdge] = testCase.openInspector(48);
            inspector.applyUserFix([0 120], 'a fix to be withdrawn');
            testCase.assertEqual(stitching.edges(badEdge).source, 'user');

            inspector.excludeSeam_Callback();
            testCase.verifyFalse(stitching.edges(badEdge).valid);
            testCase.verifyEqual(stitching.edges(badEdge).source, 'auto');
            testCase.verifyTrue(inspector.resolvePending, ...
                'positions are stale until the next Re-solve');

            inspector.excludeSeam_Callback();
            testCase.verifyTrue(stitching.edges(badEdge).valid);
        end

        function excludeAndReSolveRecoversTheChainFromTheNominalSprings(testCase)
            % The other half of the inspector's job: when a seam cannot be
            % fixed it is dropped, and the nominal springs hold the pair.
            [inspector, stitching] = testCase.openInspector(49);
            inspector.excludeSeam_Callback();
            inspector.resolveBtn_Callback();
            testCase.verifyEqual(stitching.positions, [1 1 1; 1 121 1; 1 241 1], 'AbsTol', 1.5);
        end

        function confirmMarksReviewedAndAdvancesToTheNextUnreviewedSeam(testCase)
            [inspector, stitching, badEdge] = testCase.openInspector(50);
            otherEdge = setdiff(1:numel(stitching.edges), badEdge);

            inspector.confirmSeam_Callback();
            testCase.verifyEqual(stitching.edges(badEdge).source, 'confirmed');
            testCase.verifyEqual(inspector.currentEdgeIdx, otherEdge, ...
                'confirm must advance to the next unreviewed seam');

            % Everything reviewed now: advancing stays put rather than looping.
            inspector.confirmSeam_Callback();
            testCase.verifyEqual(stitching.edges(otherEdge).source, 'confirmed');
            currentAfterAll = inspector.currentEdgeIdx;
            inspector.advanceToNextUnreviewed();
            testCase.verifyEqual(inspector.currentEdgeIdx, currentAfterAll);
        end

        function confirmKeepsUserProvenance(testCase)
            % A fixed seam stays 'user' - confirmation is bookkeeping only and
            % must not downgrade an edge the solver treats specially.
            [inspector, stitching, badEdge] = testCase.openInspector(51);
            inspector.applyUserFix([0 120], 'fix');
            inspector.selectSeam(badEdge);
            inspector.confirmSeam_Callback();
            testCase.verifyEqual(stitching.edges(badEdge).source, 'user');
        end

        function jumpToTileSelectsTheWorstIncidentSeam(testCase)
            % Mini-map click: tile 3 touches only the sabotaged seam, tile 1
            % only the good one.
            [inspector, stitching, badEdge] = testCase.openInspector(52);
            goodEdge = setdiff(1:numel(stitching.edges), badEdge);

            inspector.jumpToTile(3);
            testCase.verifyEqual(inspector.currentEdgeIdx, badEdge);
            inspector.jumpToTile(1);
            testCase.verifyEqual(inspector.currentEdgeIdx, goodEdge);
        end

        function edgeAtMiniMapPointResolvesAClickInTheOverlapStripToTheRightSeam(testCase)
            % Tiles overlap by design (160 px tiles, ~120 px stride -> a
            % ~40 px overlap strip between tiles 1 and 2, itself the location
            % of seam 1-2). A click well inside that strip, off to tile 1's
            % side, must resolve to seam 1-2 by proximity to the SEAM's own
            % location, regardless of which patch a real mouse click would
            % have hit (edgeAtMiniMapPoint never looks at that).
            [inspector, stitching] = testCase.openInspector(61);
            tile12Edge = find([stitching.edges.i] == 1 & [stitching.edges.j] == 2, 1);
            testCase.assertNotEmpty(tile12Edge);

            pos1 = stitching.positions(1, 1:2);   % [y x]
            pos2 = stitching.positions(2, 1:2);
            tileWidth  = stitching.layout(1).tileSize(2);
            tileHeight = stitching.layout(1).tileSize(1);
            overlapLeft  = pos2(2);
            overlapRight = pos1(2) + tileWidth;
            testCase.assertGreaterThan(overlapRight, overlapLeft, ...
                'tiles 1 and 2 must actually overlap for this test to mean anything');
            % 15% into the strip from tile 1's side: solidly nearer seam 1-2's
            % own location (the strip's midpoint) than seam 2-3's, ~120 px away.
            clickX = overlapLeft + 0.15 * (overlapRight - overlapLeft);
            clickY = pos1(1) + tileHeight / 2;

            k = inspector.edgeAtMiniMapPoint([clickX, clickY]);
            testCase.verifyEqual(k, tile12Edge, ...
                'a click inside the 1-2 overlap strip must resolve to seam 1-2');
        end

        function edgeAtMiniMapPointResolvesEachSideOfATileToItsOwnSeam(testCase)
            % The bug this exists for: a tile with neighbours on TWO different
            % sides (a 2x2 grid - tile 1 top-left, seams X(1-2) right and
            % Y(1-3) below) could only ever be jumped to its single WORST
            % incident seam via jumpToTile, no matter where on the tile you
            % clicked. A click near tile 1's right edge (seam 1-2's location)
            % and a click near its bottom edge (seam 1-3's location) must
            % resolve to their respective, DIFFERENT seams.
            [inspector, stitching] = testCase.openGrid2x2Inspector(71);
            edge12 = find([stitching.edges.i] == 1 & [stitching.edges.j] == 2, 1);
            edge13 = find([stitching.edges.i] == 1 & [stitching.edges.j] == 3, 1);
            testCase.assertNotEmpty(edge12);
            testCase.assertNotEmpty(edge13);

            pos1 = stitching.positions(1, 1:2);   % [y x]
            tileWidth  = stitching.layout(1).tileSize(2);
            tileHeight = stitching.layout(1).tileSize(1);

            % Near tile 1's right edge (seam 1-2's neighbourhood): inside the
            % tile, past its horizontal midline, well away from the bottom edge.
            k = inspector.edgeAtMiniMapPoint([pos1(2) + tileWidth - 5, pos1(1) + tileHeight / 2]);
            testCase.verifyEqual(k, edge12, ...
                'a click near tile 1''s right edge must select seam 1-2');

            % Near tile 1's bottom edge (seam 1-3's neighbourhood).
            k = inspector.edgeAtMiniMapPoint([pos1(2) + tileWidth / 2, pos1(1) + tileHeight - 5]);
            testCase.verifyEqual(k, edge13, ...
                'a click near tile 1''s bottom edge must select seam 1-3, not the same seam as above');
        end

        function currentOffsetShowsTheUserValueBeforeTheNextSolve(testCase)
            % A user-fixed edge displays what the user set (so the fix is
            % visible immediately); everything else displays the solved
            % position difference.
            [inspector, stitching, badEdge] = testCase.openInspector(53);
            goodEdge = setdiff(1:numel(stitching.edges), badEdge);

            solvedDelta = stitching.positions(stitching.edges(goodEdge).j, 1:2) - ...
                stitching.positions(stitching.edges(goodEdge).i, 1:2);
            testCase.verifyEqual(inspector.currentOffsetYX(goodEdge), solvedDelta, 'AbsTol', 1e-9);

            inspector.applyUserFix([0 120], 'fix', true);   % deferred: positions untouched
            testCase.verifyEqual(inspector.currentOffsetYX(badEdge), [0 120], 'AbsTol', 1e-9);
            testCase.verifyEqual(inspector.currentDz(badEdge), 0);
        end
    end

    % =================================================================
    % Fix mode: in-plane vs cross-layer, and per-slice mosaic corrections
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function visibleRankingSplitsInPlaneFromCrossLayerSeams(testCase)
            % The seam table never mixes the two - they read on different axes.
            [inspector, stitching, badEdge] = testCase.openInspector(54);
            crossLayerEdge = setdiff(1:numel(stitching.edges), badEdge);
            stitching.edges(crossLayerEdge).direction = 'z';

            testCase.verifyEqual(inspector.fixMode(), 'xy', 'no dropdown => Fix XY');
            testCase.verifyEqual(inspector.visibleRanking(), badEdge);

            testCase.attachFixModeDropdown(inspector, 'Fix Z (match slices)');
            testCase.verifyEqual(inspector.fixMode(), 'z');
            testCase.verifyEqual(inspector.visibleRanking(), crossLayerEdge);
        end

        function zBoundaryFixRecordsAndRemovesAPerSliceMosaicCorrection(testCase)
            % Fix Z edits the MOSAIC, not a seam: every output slice >= z
            % shifts in-plane, slices below stay put. Tile positions and the
            % solver are untouched, and the canvas is invalidated so the next
            % fuse re-plans with the correction.
            [inspector, stitching] = testCase.openInspector(55);
            testCase.attachFixModeDropdown(inspector, 'Fix Z (match slices)');
            testCase.enterBoundaryView(inspector, 5);
            positionsBefore = stitching.positions;
            stitching.canvas = struct('size', [1 1 1 1 1]);

            inspector.applyZBoundaryFix([3 -2], 'test');

            testCase.verifyEqual(stitching.zSliceFixes, [5 3 -2], 'AbsTol', 1e-9);
            testCase.verifyEqual(stitching.positions, positionsBefore, ...
                'a Z-boundary fix must not move any tile');
            testCase.verifyEmpty(stitching.canvas, 'the canvas must be re-planned after a Z fix');
            testCase.verifyEqual(inspector.boundaryDelta(5), [3 -2], 'AbsTol', 1e-9);

            % Re-fixing the same boundary replaces the row rather than adding one.
            inspector.applyZBoundaryFix([4 0], 'test again');
            testCase.verifyEqual(stitching.zSliceFixes, [5 4 0], 'AbsTol', 1e-9);

            % Dragged back to (sub-pixel) zero = removal, not a fix of zero.
            inspector.applyZBoundaryFix([0.1 -0.1], 'back to zero');
            testCase.verifyEmpty(stitching.zSliceFixes);
            testCase.verifyEqual(inspector.boundaryDelta(5), [0 0]);
        end

        function undoInBoundaryViewRemovesThatBoundarysCorrectionOnly(testCase)
            [inspector, stitching] = testCase.openInspector(56);
            testCase.attachFixModeDropdown(inspector, 'Fix Z (match slices)');

            testCase.enterBoundaryView(inspector, 4);
            inspector.applyZBoundaryFix([2 2], 'boundary 4');
            testCase.enterBoundaryView(inspector, 7);
            inspector.applyZBoundaryFix([5 5], 'boundary 7');
            testCase.assertEqual(size(stitching.zSliceFixes), [2 3]);

            inspector.undoFix_Callback();   % still viewing boundary 7

            testCase.verifyEqual(stitching.zSliceFixes, [4 2 2], 'AbsTol', 1e-9, ...
                'undo must remove only the boundary on screen');
        end
    end

    % =================================================================
    % Local helpers
    % =================================================================
    methods (Access = private)

        function [inspector, stitching, badEdge] = openInspector(testCase, seed)
            % Solved 1x3 chain with one confidently-wrong seam, opened in a
            % headless inspector - the fixture every review test starts from.
            stitching = testCase.chainController(seed);
            stitching.buildLayoutFromBatchOpt();
            stitching.measureOverlaps_Callback();
            badEdge = find([stitching.edges.i] == 2 & [stitching.edges.j] == 3, 1);
            testCase.assertNotEmpty(badEdge);
            stitching.edges(badEdge).measured = stitching.edges(badEdge).measured + [0 18 0];
            stitching.edges(badEdge).quality  = 0.95;
            stitching.optimizePositions_Callback();
            testCase.assertLessThan(stitching.solverInfo.rmseTotal, 0.5, ...
                'a chain has no loop: the corrupted edge must be residual-invisible');

            inspector = controllers.StitchingInspector(stitching.mibModel, stitching, ...
                struct('createView', false));
            stitching.inspector = inspector;
            testCase.addTeardown(@() delete(inspector));
        end

        function controller = chainController(testCase, seed)
            % Headless Stitching controller over a 1x3 chain of 160x160 tiles
            % (40 px overlap, zero jitter -> truth [1 1] / [1 121] / [1 241]).
            repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            mibModel = models.MibModel(1, fullfile(repoRoot, 'mib'));
            mibModel.preferences.System.DeveloperMode = false;
            controller = controllers.Stitching(mibModel, [], NaN);
            controller.BatchOpt.showWaitbar     = false;
            controller.BatchOpt.LayoutSource{1} = 'Grid';
            controller.BatchOpt.InputPath       = testCase.chopChain(seed);
            controller.BatchOpt.GridRows{1}     = 1;
            controller.BatchOpt.GridCols{1}     = 3;
            controller.BatchOpt.OverlapX{1}     = 25;
            controller.BatchOpt.OverlapY{1}     = 0;
            controller.BatchOpt.EstimateOverlap = false;
        end

        function tileDir = chopChain(testCase, seed)
            original = mibtest.helpers.stitchTextureImage(180, 460, seed);
            tileDir = tempname; mkdir(tileDir);
            testCase.addTeardown(@() rmdir(tileDir, 's'));
            for k = 1:3
                originX = 1 + (k - 1) * 120;
                imwrite(original(1:160, originX:originX + 159), ...
                    fullfile(tileDir, sprintf('tile_%02d.tif', k)));
            end
        end

        function [inspector, stitching] = openGrid2x2Inspector(testCase, seed)
            % Solved 2x2 grid (no sabotage) opened in a headless inspector -
            % the fixture for tests where a tile needs neighbours on TWO
            % different sides (a 1xN chain only ever gives a tile one).
            % Tile numbering (default 'Horizontal' order): 1=top-left,
            % 2=top-right, 3=bottom-left, 4=bottom-right -> seams X(1-2),
            % X(3-4), Y(1-3), Y(2-4).
            repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            mibModel = models.MibModel(1, fullfile(repoRoot, 'mib'));
            mibModel.preferences.System.DeveloperMode = false;
            stitching = controllers.Stitching(mibModel, [], NaN);
            stitching.BatchOpt.showWaitbar     = false;
            stitching.BatchOpt.LayoutSource{1} = 'Grid';
            stitching.BatchOpt.InputPath       = testCase.chopGrid2x2(seed);
            stitching.BatchOpt.GridRows{1}     = 2;
            stitching.BatchOpt.GridCols{1}     = 2;
            stitching.BatchOpt.OverlapX{1}     = 25;
            stitching.BatchOpt.OverlapY{1}     = 25;
            stitching.BatchOpt.EstimateOverlap = false;

            stitching.buildLayoutFromBatchOpt();
            stitching.measureOverlaps_Callback();
            stitching.optimizePositions_Callback();
            testCase.assertLessThan(stitching.solverInfo.rmseTotal, 0.5);

            inspector = controllers.StitchingInspector(stitching.mibModel, stitching, ...
                struct('createView', false));
            stitching.inspector = inspector;
            testCase.addTeardown(@() delete(inspector));
        end

        function tileDir = chopGrid2x2(testCase, seed)
            % 160x160 tiles, 40 px overlap both directions (120 px stride)
            % -> zero-jitter truth [1 1] / [1 121] / [121 1] / [121 121].
            original = mibtest.helpers.stitchTextureImage(280, 280, seed);
            tileDir = tempname; mkdir(tileDir);
            testCase.addTeardown(@() rmdir(tileDir, 's'));
            tileNum = 1;
            for row = 1:2
                for col = 1:2
                    originY = 1 + (row - 1) * 120;
                    originX = 1 + (col - 1) * 120;
                    imwrite(original(originY:originY + 159, originX:originX + 159), ...
                        fullfile(tileDir, sprintf('tile_%02d.tif', tileNum)));
                    tileNum = tileNum + 1;
                end
            end
        end

        function attachFixModeDropdown(~, inspector, value)
            % Inject the ONE widget the fix-mode logic reads. Everything else
            % stays absent, so hasWidget keeps the rendering paths switched off.
            inspector.view = struct('handles', ...
                struct('fixModeDropdown', struct('Value', value)), 'gui', []);
        end

        function enterBoundaryView(~, inspector, zBoundary)
            % Put the pair view into the mosaic Z-BOUNDARY state that
            % renderPairView establishes in Fix Z mode: one tile shown at
            % slices z-1 (cyan) vs z (magenta).
            inspector.viewSlice = struct('edgeIdx', inspector.currentEdgeIdx, ...
                'sliceA', zBoundary - 1, 'sliceB', zBoundary, ...
                'depthA', 12, 'depthB', 12, 'boundaryTile', 1);
        end
    end
end
