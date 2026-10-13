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

        function tileOrderMovesEditTheParentsDrawingOrder(testCase)
            % The pair view's tile-order menu edits the parent's tileStack - what
            % Stitch fuses with and the project saves - starting from the order
            % in force.
            [inspector, stitching] = testCase.openGrid2x2Inspector(3);
            testCase.assertEmpty(stitching.tileStack);
            testCase.verifyEqual(inspector.currentTileStack(), 1:4, ...
                'no correction and no user order: the highest index is on top');

            positionsBefore = stitching.positions;
            inspector.tileOrder_Callback(4, 'down');
            testCase.verifyEqual(stitching.tileStack, [1 2 4 3], ...
                'tile 4 steps below its nearest overlapping neighbour underneath');
            inspector.tileOrder_Callback(1, 'top');
            testCase.verifyEqual(inspector.currentTileStack(), [2 4 3 1]);
            testCase.verifyEqual(stitching.tileStack, [2 4 3 1]);
            testCase.verifyEqual(stitching.positions, positionsBefore, ...
                'reordering must not move any tile');

            stitching.buildLayoutFromBatchOpt();
            testCase.verifyEmpty(stitching.tileStack, ...
                'a rebuilt layout must drop the order chosen for the old one');
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

        function fixZTableListsSliceBoundariesWhenAllStacksShareOneLayer(testCase)
            % Z-stack tiles on ONE layer (e.g. one folder of serial sections per
            % tile) have no cross-layer seam, so Fix Z used to show an empty
            % table although its per-slice fixes work. It now lists the slice
            % boundaries: a row selects the boundary view, Up/Down step it, and
            % the Shift column reports the correction stored at each boundary.
            [inspector, stitching] = testCase.openStackChainInspector(57, 6);
            seamTable = mibtest.helpers.FakeWidget();
            inspector.view = struct('handles', struct( ...
                'fixModeDropdown', struct('Value', 'Fix Z (match slices)'), ...
                'seamTable', seamTable), 'gui', []);

            testCase.assertEmpty(inspector.visibleRanking(), 'one layer: no cross-layer seam');
            testCase.verifyTrue(inspector.listsSliceBoundaries());
            inspector.updateWidgets();
            testCase.verifySize(seamTable.Data, [5 3], 'one row per boundary of a 6-slice stack');
            testCase.verifyEqual(seamTable.Data(:, 1)', {'Z 1-2', 'Z 2-3', 'Z 3-4', 'Z 4-5', 'Z 5-6'});

            inspector.seamTableSelection_Callback(struct('Selection', 3));
            testCase.verifyTrue(inspector.boundaryModeActive(), 'a row must open the boundary view');
            testCase.verifyEqual([inspector.viewSlice.sliceA, inspector.viewSlice.sliceB], [3 4], ...
                'row 3 is the boundary between slices 3 and 4');

            inspector.applyZBoundaryFix([2 -1], 'test');
            testCase.verifyEqual(stitching.zSliceFixes, [4 2 -1], 'AbsTol', 1e-9);
            inspector.updateWidgets();
            testCase.verifyEqual(seamTable.Data(3, :), {'Z 3-4', '2.0 -1.0', 'fixed'});
            testCase.verifyEqual(seamTable.Selection, 3, 'the boundary on screen stays highlighted');

            inspector.keyPress_Callback(struct('Key', 'downarrow', 'Modifier', {{}}));
            testCase.verifyEqual(inspector.viewSlice.sliceB, 5, 'Down steps to the next boundary row');
            inspector.keyPress_Callback(struct('Key', 'uparrow', 'Modifier', {{}}));
            inspector.keyPress_Callback(struct('Key', 'uparrow', 'Modifier', {{}}));
            testCase.verifyEqual(inspector.viewSlice.sliceB, 3, 'Up steps back');
            testCase.verifyEqual(stitching.zSliceFixes, [4 2 -1], 'AbsTol', 1e-9, ...
                'browsing must never change a correction');

            inspector.view.handles.fixModeDropdown.Value = 'Fix XY (move tile)';
            testCase.verifyFalse(inspector.listsSliceBoundaries(), 'Fix XY lists seams');
        end

        function fixZViewIsTheStitchedMosaicAroundTheChosenPoint(testCase)
            % Fix Z treats the tiles as stitched: the view is a crop of the
            % FUSED mosaic at slices z-1 / z around the mini-map point - the
            % pixels Stitch would write there - and drag / click-correlate work
            % on exactly that crop. Stored corrections do not change what is
            % compared (the boundary's own is applied as the offset of z).
            [inspector, stitching] = testCase.openStackChainInspector(58, 6);
            inspector.view = struct('handles', struct( ...
                'fixModeDropdown', struct('Value', 'Fix Z (match slices)'), ...
                'seamTable', mibtest.helpers.FakeWidget()), 'gui', []);
            inspector.seamTableSelection_Callback(struct('Selection', 2));   % boundary 2|3
            testCase.verifyTrue(inspector.boundaryModeActive());
            testCase.verifyEqual(inspector.viewSlice.sliceB, 3);

            point = [stitching.positions(3, 2) + 100, stitching.positions(3, 1) + 70];   % [x y]
            inspector.fixZSelectPoint(point);
            testCase.verifyEqual(inspector.zMosaicCenter, [point(2), point(1)]);
            crops = inspector.buildZMosaicCrops(3);

            viewCanvas = utils.stitch.planCanvas(stitching.layout, stitching.positions);
            mosaic = utils.stitch.fuseInMemory(stitching.layout, viewCanvas, ...
                struct('blendMode', stitching.BatchOpt.BlendMode{1}, 'background', 0));
            rows = crops.region(1, 1):crops.region(1, 2);
            cols = crops.region(2, 1):crops.region(2, 2);
            testCase.verifyEqual(crops.sliceA, single(mosaic(rows, cols, 2, 1)), 'slice z-1 is the stitched mosaic');
            testCase.verifyEqual(crops.sliceB, single(mosaic(rows, cols, 3, 1)), 'slice z is the stitched mosaic');
            testCase.verifyTrue(point(2) >= crops.regionPositions(1, 1) && point(2) <= crops.regionPositions(1, 2) && ...
                point(1) >= crops.regionPositions(2, 1) && point(1) <= crops.regionPositions(2, 2), ...
                'the crop contains the chosen point');

            inspector.applyZBoundaryFix([2 -3], 'test');
            testCase.verifyEqual(inspector.buildZMosaicCrops(3).sliceB, crops.sliceB, ...
                'the correction is shown as the offset of slice z, not baked into the crop');
            testCase.verifyEqual(inspector.boundaryDelta(3), [2 -3], 'AbsTol', 1e-9);
        end

        function fixZCorrectionReratesItsBoundaryOnTheCorrectedMosaic(testCase)
            % A boundary moved off by hand must be rated on the pixels the
            % mosaic now shows: its links are re-scored at the corrected
            % placement (and ONLY its links), its row climbs to the top of
            % the worst-first table and shows the correction; removing the
            % correction gives the original scores back.
            numSections = 4;
            [inspector, stitching] = testCase.openSectionInspector(numSections, 68);
            seamTable = mibtest.helpers.FakeWidget();
            inspector.view = struct('handles', struct( ...
                'fixModeDropdown', struct('Value', 'Fix Z (match slices)'), ...
                'seamTable', seamTable), 'gui', []);
            inspector.updateWidgets();
            rows = inspector.visibleRanking();
            lastRowEdge = rows(end);   % the best-rated boundary
            inspector.selectSeam(lastRowEdge);
            viewCanvas = inspector.zViewCanvas();
            zBoundary = inspector.zBoundaryOfEdge(lastRowEdge, viewCanvas);
            inspector.viewSlice = struct('edgeIdx', lastRowEdge, 'sliceA', zBoundary - 1, 'sliceB', zBoundary, ...
                'depthA', numSections, 'depthB', numSections, 'mosaic', true);
            isLink = strcmp({stitching.edges.direction}, 'z') & ...
                arrayfun(@(k) isequal(inspector.zBoundaryOfEdge(k, viewCanvas), zBoundary), 1:numel(stitching.edges));
            scoresBefore = [stitching.edges.seamScore];

            inspector.applyZBoundaryFix([9 -9], 'test');
            scoresAfter = [stitching.edges.seamScore];
            testCase.verifyLessThan(max(scoresAfter(isLink)), min(scoresBefore(isLink)) - 0.2, ...
                'the boundary''s links are rated on the corrected (now misaligned) mosaic');
            testCase.verifyEqual(scoresAfter(~isLink), scoresBefore(~isLink), ...
                'no other seam is re-read or changes');
            testCase.verifyEqual(inspector.rowOfEdge(inspector.currentEdgeIdx), 1, ...
                'the moved boundary is now the worst row');
            testCase.verifyEqual(seamTable.Data{1, 3}, '9.0 -9.0', 'the row shows its correction');
            testCase.verifyEqual(seamTable.Selection, 1, 'and stays the selected row');

            inspector.undoFix_Callback();
            testCase.verifyEqual([stitching.edges.seamScore], scoresBefore, 'AbsTol', 1e-12, ...
                'removing the correction restores the original rating');
        end

        function ctrlShiftClickCorrelatesEveryZBoundaryOfTheStack(testCase)
            % Ctrl+Shift+click in Fix Z: one click measures EVERY boundary at
            % that spot. A stack whose content jumps at slices 4 and 6 gets
            % exactly the two corrections that undo the jumps; a stale
            % correction on an aligned boundary is measured away; nothing
            % else is stored.
            jumps = zeros(6, 2);           % content offset of each slice
            jumps(4:5, :) = repmat([4 -6], 2, 1);
            jumps(6, :) = [1 -1];
            [inspector, stitching] = testCase.openJumpingStackInspector(jumps);
            inspector.view = struct('handles', struct( ...
                'fixModeDropdown', struct('Value', 'Fix Z (match slices)'), ...
                'seamTable', mibtest.helpers.FakeWidget()), 'gui', []);
            stitching.zSliceFixes = [2 5 5];   % stale: boundary 2 is aligned
            inspector.viewSlice = struct('edgeIdx', inspector.currentEdgeIdx, 'sliceA', 3, ...
                'sliceB', 4, 'depthA', 6, 'depthB', 6, 'mosaic', true);
            crops = inspector.buildZMosaicCrops(4);

            inspector.ctrlDown = true; inspector.shiftDown = true;   % what the key handlers record
            inspector.correlateStackAtPoint(fliplr(round(size(crops.sliceA) / 2)));

            fixes = stitching.zSliceFixes;
            testCase.verifyEqual(fixes(:, 1)', [4 6], 'only the two jumping boundaries carry a correction');
            testCase.verifyEqual(fixes(1, 2:3), -(jumps(4, :) - jumps(3, :)), 'AbsTol', 0.5);
            testCase.verifyEqual(fixes(2, 2:3), -(jumps(6, :) - jumps(5, :)), 'AbsTol', 0.5);

            % Ctrl+Z undoes the whole run in one step; nothing earlier was an action.
            ctrlZ = struct('Key', 'z', 'Modifier', {{'control'}});
            inspector.keyPress_Callback(ctrlZ);
            testCase.verifyEqual(stitching.zSliceFixes, [2 5 5], 'every boundary back as before the run');
            inspector.keyPress_Callback(ctrlZ);
            testCase.verifyEqual(stitching.zSliceFixes, [2 5 5], 'one run, one undo');

            % Run, then a single fix: Ctrl+Z steps back through them in order.
            inspector.correlateStackAtPoint(fliplr(round(size(crops.sliceA) / 2)));
            fixesAfterRun = stitching.zSliceFixes;
            inspector.viewSlice = struct('edgeIdx', inspector.currentEdgeIdx, 'sliceA', 2, ...
                'sliceB', 3, 'depthA', 6, 'depthB', 6, 'mosaic', true);
            inspector.applyZBoundaryFix([1 1], 'manual after the run');
            inspector.keyPress_Callback(ctrlZ);
            testCase.verifyEqual(stitching.zSliceFixes, fixesAfterRun, ...
                'the first Ctrl+Z takes back only the single fix');
            inspector.keyPress_Callback(ctrlZ);
            testCase.verifyEqual(stitching.zSliceFixes, [2 5 5], 'the second one the whole run');
        end

        function ctrlZReturnsABoundaryToItsPreviousCorrection(testCase)
            % After a drag / Shift+click, Ctrl+Z gives the boundary its
            % PREVIOUS correction back - not none; after Z (remove), it
            % brings the removed correction back. Other boundaries untouched.
            [inspector, stitching] = testCase.openInspector(57);
            testCase.attachFixModeDropdown(inspector, 'Fix Z (match slices)');
            ctrlZ = struct('Key', 'z', 'Modifier', {{'control'}});
            testCase.enterBoundaryView(inspector, 8);
            inspector.applyZBoundaryFix([1 1], 'other boundary');
            testCase.enterBoundaryView(inspector, 5);
            inspector.applyZBoundaryFix([3 -2], 'first');
            inspector.applyZBoundaryFix([6 4], 'second');

            inspector.keyPress_Callback(ctrlZ);
            testCase.verifyEqual(inspector.boundaryDelta(5), [3 -2], 'AbsTol', 1e-9, 'back to the previous value');
            testCase.verifyEqual(inspector.boundaryDelta(8), [1 1], 'AbsTol', 1e-9);

            inspector.keyPress_Callback(struct('Key', 'z', 'Modifier', {{}}));   % Z: remove
            testCase.verifyEqual(inspector.boundaryDelta(5), [0 0]);
            inspector.keyPress_Callback(ctrlZ);
            testCase.verifyEqual(inspector.boundaryDelta(5), [3 -2], 'AbsTol', 1e-9, 'Ctrl+Z undoes the removal');

            inspector.keyPress_Callback(ctrlZ);
            testCase.verifyEqual(inspector.boundaryDelta(5), [0 0], 'and the first fix');
            testCase.verifyEqual(stitching.zSliceFixes, [8 1 1], 'AbsTol', 1e-9);
        end

        function fixZBrowsingSectionsKeepsTheBoundaryRowInStep(testCase)
            % Serial sections: Fix Z rows are section boundaries; browsing the
            % boundary with Q/W moves the current row with it, and a mini-map
            % point changes where the view looks, not which boundary.
            numSections = 4;
            [inspector, stitching] = testCase.openSectionInspector(numSections, 67);
            seamTable = mibtest.helpers.FakeWidget();
            inspector.view = struct('handles', struct( ...
                'fixModeDropdown', struct('Value', 'Fix Z (match slices)'), ...
                'seamTable', seamTable), 'gui', []);
            viewCanvas = inspector.zViewCanvas();
            testCase.assertEqual(viewCanvas.size(3), numSections);
            ranking = inspector.visibleRanking();
            startEdge = ranking(1);
            inspector.selectSeam(startEdge);
            zStart = inspector.zBoundaryOfEdge(startEdge, viewCanvas);
            inspector.viewSlice = struct('edgeIdx', startEdge, 'sliceA', zStart - 1, 'sliceB', zStart, ...
                'depthA', numSections, 'depthB', numSections, 'mosaic', true);   % as renderPairView leaves it

            inspector.fixZSelectPoint([100, 100]);
            testCase.verifyEqual(inspector.viewSlice.sliceB, zStart, 'a mini-map point keeps the boundary');

            step = 1 - 2 * (zStart == numSections);   % stay inside 2..numSections
            if step > 0; key = 'w'; else; key = 'q'; end
            inspector.keyPress_Callback(struct('Key', key, 'Modifier', {{}}));
            testCase.verifyEqual(inspector.viewSlice.sliceB, zStart + step);
            testCase.verifyEqual(inspector.zBoundaryOfEdge(inspector.currentEdgeIdx, viewCanvas), zStart + step, ...
                'the current row follows the browsed boundary');
            testCase.verifyEqual(seamTable.Selection, inspector.rowOfEdge(inspector.currentEdgeIdx));
            testCase.verifyEqual(stitching.edges(inspector.currentEdgeIdx).direction, 'z');
        end

        function sectionLayoutTablesNameFoldersAndGroupBoundaries(testCase)
            % Serial sections (RegisterSlices): Fix XY lists every in-plane seam
            % with its section, tiles named by FOLDER; Fix Z collapses the 4
            % tile links of each section boundary into one row, landing on
            % that boundary's worst link.
            numSections = 4;
            [inspector, stitching] = testCase.openSectionInspector(numSections, 63);
            seamTable = mibtest.helpers.FakeWidget();
            inspector.view = struct('handles', struct( ...
                'fixModeDropdown', struct('Value', 'Fix XY (move tile)'), ...
                'seamTable', seamTable), 'gui', []);

            inspector.updateWidgets();
            testCase.verifySize(seamTable.Data, [4 * numSections, 7], ...
                '4 in-plane seams of a 2x2 grid in every section');
            testCase.verifyEqual(seamTable.ColumnName{2}, 'Section');
            testCase.verifyEqual(unique(seamTable.Data(:, 1)), {'X (1-2)'; 'X (3-4)'; 'Y (1-3)'; 'Y (2-4)'}, ...
                'tiles are named by their folder, the same in every section');

            inspector.view.handles.fixModeDropdown.Value = 'Fix Z (match slices)';
            testCase.verifyFalse(inspector.listsSliceBoundaries(), ...
                'a section layout has real section-to-section seams to list');
            ranking = inspector.visibleRanking();
            testCase.verifyNumElements(ranking, numSections - 1, 'one row per section boundary');
            inspector.updateWidgets();
            testCase.verifySize(seamTable.Data, [numSections - 1, 6]);
            testCase.verifyEqual(sort(seamTable.Data(:, 1)), {'Z 1-2'; 'Z 2-3'; 'Z 3-4'});
            testCase.verifyEqual(cell2mat(seamTable.Data(:, 5))', repmat(4, 1, numSections - 1), ...
                'each boundary row covers the 4 tile links');
            for rowIdx = 1:numel(ranking)
                rowEdge = stitching.edges(ranking(rowIdx));
                section = stitching.layout(rowEdge.i).zLayer;
                boundaryEdges = stitching.edges(strcmp({stitching.edges.direction}, 'z') & ...
                    arrayfun(@(edge) stitching.layout(edge.i).zLayer == section, stitching.edges));
                testCase.verifyEqual(rowEdge.seamScore, min([boundaryEdges.seamScore]), 'AbsTol', 1e-12, ...
                    'the row lands on the boundary''s worst tile link');
            end
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
            mibModel = models.MibModel(1, fullfile(repoRoot, 'mib'), Verbose = false, Preferences = 'defaults');
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

        function [inspector, stitching] = openSectionInspector(testCase, numSections, seed)
            % Measured + solved 2x2 serial-section montage (RegisterSlices on,
            % mibtest.helpers.writeSerialSectionFolders) in a headless inspector.
            [tileFolders, ~, parentFolder] = mibtest.helpers.writeSerialSectionFolders(numSections, seed);
            testCase.addTeardown(@() rmdir(parentFolder, 's'));
            repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            mibModel = models.MibModel(1, fullfile(repoRoot, 'mib'), Verbose = false, Preferences = 'defaults');
            mibModel.preferences.System.DeveloperMode = false;
            stitching = controllers.Stitching(mibModel, [], NaN);
            stitching.BatchOpt.showWaitbar     = false;
            stitching.BatchOpt.LayoutSource{1} = 'Grid';
            stitching.BatchOpt.InputPath       = strjoin(tileFolders, newline);
            stitching.BatchOpt.SubfolderMode   = true;
            stitching.BatchOpt.RegisterSlices  = true;
            stitching.BatchOpt.SectionAlignment{1} = 'Follow image content';
            stitching.BatchOpt.GridRows{1}     = 2;
            stitching.BatchOpt.GridCols{1}     = 2;
            stitching.BatchOpt.OverlapX{1}     = 25;
            stitching.BatchOpt.OverlapY{1}     = 25;
            stitching.BatchOpt.EstimateOverlap = false;
            stitching.buildLayoutFromBatchOpt();
            stitching.measureOverlaps_Callback();
            stitching.optimizePositions_Callback();

            inspector = controllers.StitchingInspector(stitching.mibModel, stitching, ...
                struct('createView', false));
            stitching.inspector = inspector;
            testCase.addTeardown(@() delete(inspector));
        end

        function [inspector, stitching] = openJumpingStackInspector(testCase, jumps)
            % Solved 1x3 chain of Z-stack tiles (Prealigned) cut from one
            % texture, where slice s of EVERY tile shows the content moved by
            % jumps(s, :) = [dy dx] - a mosaic whose slices are mutually
            % misaligned while every seam within a slice is exact.
            stitching = testCase.chainController(59);
            original = mibtest.helpers.stitchTextureImage(200, 480, 59);
            tileDir = stitching.BatchOpt.InputPath;
            for k = 1:3
                x0 = 1 + (k - 1) * 120 + 10; y0 = 11;
                tileFilename = fullfile(tileDir, sprintf('tile_%02d.tif', k));
                for slice = 1:size(jumps, 1)
                    d = jumps(slice, :);
                    sliceImage = original(y0 - d(1):y0 - d(1) + 159, x0 - d(2):x0 - d(2) + 159);
                    if slice == 1
                        imwrite(sliceImage, tileFilename);
                    else
                        imwrite(sliceImage, tileFilename, 'WriteMode', 'append');
                    end
                end
            end
            stitching.buildLayoutFromBatchOpt();
            stitching.measureOverlaps_Callback();
            stitching.optimizePositions_Callback();
            inspector = controllers.StitchingInspector(stitching.mibModel, stitching, ...
                struct('createView', false));
            stitching.inspector = inspector;
            testCase.addTeardown(@() delete(inspector));
        end

        function [inspector, stitching] = openStackChainInspector(testCase, seed, depth)
            % Solved 1x3 chain whose tiles are multi-page TIFF Z-stacks of
            % `depth` slices, all on one layer - opened in a headless inspector.
            stitching = testCase.chainController(seed);
            original = mibtest.helpers.stitchTextureImage(180, 460, seed);
            tileDir = stitching.BatchOpt.InputPath;
            for k = 1:3
                originX = 1 + (k - 1) * 120;
                tileFilename = fullfile(tileDir, sprintf('tile_%02d.tif', k));
                imwrite(original(1:160, originX:originX + 159), tileFilename);
                for slice = 2:depth
                    imwrite(original(1:160, originX:originX + 159), tileFilename, 'WriteMode', 'append');
                end
            end
            stitching.buildLayoutFromBatchOpt();
            testCase.assertEqual(stitching.layout(1).tileSize(3), depth);
            stitching.measureOverlaps_Callback();
            stitching.optimizePositions_Callback();

            inspector = controllers.StitchingInspector(stitching.mibModel, stitching, ...
                struct('createView', false));
            stitching.inspector = inspector;
            testCase.addTeardown(@() delete(inspector));
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
            mibModel = models.MibModel(1, fullfile(repoRoot, 'mib'), Verbose = false, Preferences = 'defaults');
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
            % renderPairView establishes in Fix Z mode: the mosaic shown at
            % slices z-1 (cyan) vs z (magenta).
            inspector.viewSlice = struct('edgeIdx', inspector.currentEdgeIdx, ...
                'sliceA', zBoundary - 1, 'sliceB', zBoundary, ...
                'depthA', 12, 'depthB', 12, 'mosaic', true);
        end
    end
end
