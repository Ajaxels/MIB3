classdef StitchingControllerTest < matlab.unittest.TestCase
% STITCHINGCONTROLLERTEST - Unit tests for the Stitching controller (controllers.Stitching).
%
% The controller layer BETWEEN the GUI and the ``utils.stitch`` core: BatchOpt
% defaults, layout building from BatchOpt, the measure/optimize workflow
% methods, the project-settings flatten/restore pair, and the alignment-quality
% chip. ``utils.stitch`` itself is covered by ``tests/utils/Stitch*Test.m`` -
% these tests exercise the wiring around it.
%
% All tests are headless: ``controllers.Stitching(mibModel, [], NaN)`` builds a
% controller with no view (the batch/"return BatchOpt" path), and every
% workflow method routes its dialogs and progress bars through
% :meth:`controllers.Stitching.guiFigure`, which yields ``[]`` without a
% window. Tiles are written to a temporary folder, so no network and no GUI.
%
% See also: controllers.Stitching, controllers.StitchingInspector, utils.stitch

    methods (TestClassSetup)
        function addPaths(testCase)
            % tests/ first (so mibtest.* resolves standalone), then mib/.
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    % =================================================================
    % BatchOpt contract
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function batchOptDropdownDefaultsAreOfferedItems(testCase)
            % Every dropdown's default must be one of its own items - a typo
            % here only shows up as a widget that refuses to display.
            controller = testCase.newController();
            fieldList = fieldnames(controller.BatchOpt);
            checked = 0;
            for fieldIdx = 1:numel(fieldList)
                value = controller.BatchOpt.(fieldList{fieldIdx});
                if ~iscell(value) || numel(value) < 2 || ~iscell(value{2}); continue; end
                checked = checked + 1;
                testCase.verifyTrue(ismember(value{1}, value{2}), ...
                    sprintf('BatchOpt.%s default "%s" is not in its item list', ...
                    fieldList{fieldIdx}, value{1}));
            end
            testCase.verifyGreaterThan(checked, 5, 'expected several dropdown fields');
        end

        function projectSettingFieldsExistAndExcludeBatchPlumbing(testCase)
            % The persisted list is shared by collect/apply, so a field renamed
            % in BatchOpt but not here would silently stop being saved.
            controller = testCase.newController();
            persistedFields = controllers.Stitching.projectSettingFields();
            for fieldIdx = 1:numel(persistedFields)
                testCase.verifyTrue(isfield(controller.BatchOpt, persistedFields{fieldIdx}), ...
                    sprintf('projectSettingFields lists "%s", which BatchOpt does not have', ...
                    persistedFields{fieldIdx}));
            end
            % Batch plumbing is deliberately NOT user settings.
            for excluded = {'showWaitbar', 'mibBatchSectionName', 'mibBatchActionName', 'id'}
                testCase.verifyFalse(ismember(excluded{1}, persistedFields), ...
                    sprintf('"%s" is batch plumbing and must not be persisted', excluded{1}));
            end
        end

        function returnBatchOptFiresSyncBatchWithTheSettings(testCase)
            % How mibBatchController collects the tool's parameters.
            controller = testCase.newController();
            captured = {};
            listener = addlistener(controller.mibModel, 'SyncBatch', ...
                @(~, evnt) assignInto(evnt)); %#ok<NASGU>
            controller.BatchOpt.OverlapX{1} = 42;
            controller.returnBatchOpt();
            testCase.assertNotEmpty(captured, 'returnBatchOpt must notify SyncBatch');
            testCase.verifyEqual(captured{1}.OverlapX{1}, 42);
            testCase.verifyEqual(captured{1}.mibBatchSectionName, 'Ribbon -> Dataset');

            function assignInto(evnt)
                captured{end+1} = evnt.Parameters;
            end
        end

        function buildFeatureOptionsDerivesRotationInvarianceFromAllowRotation(testCase)
            % The two rotation settings were collapsed into one checkbox: the
            % stored rotationInvariance is a placeholder, AllowRotation decides.
            % Upright descriptors cannot MATCH rotated content, so a stale
            % stored value must never be able to veto a rotating solve.
            controller = testCase.newController();

            controller.BatchOpt.AllowRotation = false;
            controller.automaticOptions.rotationInvariance = false;   % poisoned
            featureOptions = controller.buildFeatureOptions();
            testCase.verifyTrue(featureOptions.rotationInvariance, ...
                'no rotation allowed => upright descriptors, whatever is stored');

            controller.BatchOpt.AllowRotation = true;
            controller.automaticOptions.rotationInvariance = true;    % poisoned
            featureOptions = controller.buildFeatureOptions();
            testCase.verifyFalse(featureOptions.rotationInvariance, ...
                'rotation allowed => rotation-invariant descriptors, whatever is stored');

            % The rest of the detector settings ride along unchanged.
            controller.BatchOpt.FeatureDetectorType{1} = 'Corners: Harris-Stephens algorithm';
            controller.automaticOptions.imgDownsamplingFactorForAnalysis = 3;
            featureOptions = controller.buildFeatureOptions();
            testCase.verifyEqual(featureOptions.featureDetector, 'Corners: Harris-Stephens algorithm');
            testCase.verifyEqual(featureOptions.downsampleFactor, 3);
            testCase.verifyEqual(featureOptions.detectSURFFeatures.MetricThreshold, 500);
        end
    end

    % =================================================================
    % Layout building
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function buildLayoutGridResetsDownstreamStateAndProjectFlag(testCase)
            % A deliberate rebuild must drop everything derived from the old
            % layout - including solverInfo (the quality chip reads it) and the
            % layoutFromProject flag, whose whole job is to stand down once the
            % layout describes BatchOpt again.
            controller = testCase.chainController(11);
            controller.positions  = [1 2 3];
            controller.edges      = struct('i', 1, 'j', 2);
            controller.canvas     = struct('size', [1 1 1 1 1]);
            controller.solverInfo = struct('rmseTotal', 9);
            controller.zSliceFixes    = [4 1 1];
            controller.layoutFromProject = true;

            controller.buildLayoutFromBatchOpt();

            testCase.verifyEqual(numel(controller.layout), 3);
            testCase.verifyEqual(controller.layout(3).gridRC, [1 3]);
            testCase.verifyEqual(controller.layout(1).tileSize(1:2), [160 160]);
            testCase.verifyEmpty(controller.edges);
            testCase.verifyEmpty(controller.positions);
            testCase.verifyEmpty(controller.canvas);
            testCase.verifyEmpty(controller.zSliceFixes);
            testCase.verifyEmpty(fieldnames(controller.solverInfo));
            testCase.verifyFalse(controller.layoutFromProject);
        end

        function buildLayoutFromPositionFile(testCase)
            % The 'Position file' branch: filename X Y [Z] per tile.
            [controller, tileDir] = testCase.chainController(12);
            positionFile = fullfile(tileDir, 'positions.txt');
            fileId = fopen(positionFile, 'w');
            for k = 1:3
                fprintf(fileId, '%s %d %d\n', fullfile(tileDir, sprintf('tile_%02d.tif', k)), ...
                    (k - 1) * 120, 0);
            end
            fclose(fileId);

            controller.BatchOpt.LayoutSource{1} = 'Position file';
            controller.BatchOpt.InputPath = positionFile;
            controller.buildLayoutFromBatchOpt();

            testCase.verifyEqual(numel(controller.layout), 3);
            testCase.verifyEqual(controller.layout(2).nomOrigin, [1 121 1], 'AbsTol', 0.01);
        end

        function buildLayoutWithoutInputPathErrors(testCase)
            controller = testCase.newController();
            controller.BatchOpt.InputPath = '';
            testCase.verifyError(@() controller.buildLayoutFromBatchOpt(), ...
                'Stitching:noInputPath');
        end
    end

    % =================================================================
    % Workflow: measure -> optimize
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function measureThenOptimizeRecoversTheChain(testCase)
            % The two workflow buttons, headless, on a zero-jitter 1x3 chain:
            % every pair measured, positions solved back to the truth, canvas
            % planned, and the pixel seam check run (the scores the quality
            % chip and the inspector both read).
            controller = testCase.chainController(21);
            controller.buildLayoutFromBatchOpt();

            controller.measureOverlaps_Callback();
            testCase.assertEqual(numel(controller.edges), 2, ...
                'a 1x3 chain has exactly two overlapping pairs');
            testCase.verifyTrue(all([controller.edges.valid]));
            testCase.verifyGreaterThan(min([controller.edges.quality]), 0.5);

            controller.optimizePositions_Callback();
            expected = [1 1 1; 1 121 1; 1 241 1];
            testCase.verifyEqual(controller.positions, expected, 'AbsTol', 1.0);
            testCase.verifyLessThan(controller.solverInfo.rmseTotal, 0.5);
            testCase.verifyEmpty(controller.tforms, 'Translation solves carry no tforms');
            testCase.verifyEqual(controller.canvas.size(1:2), [160 400], 'AbsTol', 1);
            testCase.verifyGreaterThan(min([controller.edges.seamScore]), 0.8, ...
                'optimize must score the seams by re-reading the pixels');
        end

        function optimizeWithoutMeasurementsRaisesPrecondition(testCase)
            % With a window this is a message box and a return; headless there
            % is nobody to read it, so the same condition is an error rather
            % than a silent no-op reported as success.
            controller = testCase.chainController(22);
            controller.buildLayoutFromBatchOpt();
            testCase.verifyError(@() controller.optimizePositions_Callback(), ...
                'Stitching:precondition');
        end

        function measureWithoutLayoutRaisesPrecondition(testCase)
            controller = testCase.newController();
            testCase.verifyError(@() controller.measureOverlaps_Callback(), ...
                'Stitching:precondition');
        end
    end

    % =================================================================
    % Project settings (sidecar schema v3)
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function projectSettingsRoundTripIntoAFreshController(testCase)
            % collect -> apply must reproduce every persisted field, including
            % the nested feature-detector options.
            source = testCase.newController();
            source.BatchOpt.LayoutSource{1}       = 'Filename pattern';
            source.BatchOpt.InputPath             = 'C:\tiles';
            source.BatchOpt.SubfolderMode         = true;
            source.BatchOpt.GridRows{1}           = 4;
            source.BatchOpt.GridCols{1}           = 5;
            source.BatchOpt.TileOrder{1}          = 'Vertical snake';
            source.BatchOpt.OverlapX{1}           = 27;
            source.BatchOpt.OverlapY{1}           = 13;
            source.BatchOpt.EstimateOverlap       = false;
            source.BatchOpt.TransformType{1}      = 'Affine';
            source.BatchOpt.AllowRotation         = true;
            source.BatchOpt.RegistrationMethod{1} = 'Feature-based';
            source.BatchOpt.FeatureDetectorType{1} = 'Corners: Harris-Stephens algorithm';
            source.BatchOpt.QualityThreshold{1}   = 0.55;
            source.BatchOpt.NominalPositionWeight{1} = 0.25;
            source.BatchOpt.SubpixelPlacement     = true;
            source.BatchOpt.OutputMode{1}         = 'OME-Zarr3 (BigData)';
            source.BatchOpt.OutputPath            = 'C:\out\mosaic.zarr';
            source.BatchOpt.BlendMode{1}          = 'Min';
            source.BatchOpt.SaveProject           = false;
            source.automaticOptions.detectHarrisFeatures.MinQuality = 0.077;
            source.automaticOptions.imgDownsamplingFactorForAnalysis = 2;

            settings = source.collectProjectSettings();
            % Dropdowns/spinners are flattened to their {1} entry in the file.
            testCase.verifyEqual(settings.TileOrder, 'Vertical snake');
            testCase.verifyEqual(settings.OverlapX, 27);

            target = testCase.newController();
            appliedFields = target.applyProjectSettings(settings);

            persistedFields = controllers.Stitching.projectSettingFields();
            for fieldIdx = 1:numel(persistedFields)
                fieldName = persistedFields{fieldIdx};
                testCase.verifyEqual(target.BatchOpt.(fieldName), source.BatchOpt.(fieldName), ...
                    sprintf('BatchOpt.%s did not survive the round trip', fieldName));
            end
            testCase.verifyTrue(ismember('FeatureOptions', appliedFields));
            testCase.verifyEqual(target.automaticOptions.detectHarrisFeatures.MinQuality, 0.077);
            testCase.verifyEqual(target.automaticOptions.imgDownsamplingFactorForAnalysis, 2);
        end

        function applyProjectSettingsIgnoresUnknownRetiredAndMistypedValues(testCase)
            % An old project must load into a newer dialog: anything that does
            % not fit the CURRENT shape is skipped, never raised.
            controller = testCase.newController();
            defaults = controller.BatchOpt;

            settings = struct();
            settings.ThisFieldWasRemovedInMib2030 = 7;          % unknown field
            settings.BlendMode    = 'Kaleidoscope';             % retired dropdown item
            settings.TileOrder    = 42;                         % wrong type for a dropdown
            settings.SubfolderMode = 'yes';                     % wrong type for a logical
            settings.OverlapX     = 'twelve';                   % wrong type for a spinner
            settings.OutputPath   = 17;                         % wrong type for a char field
            settings.QualityThreshold = 0.44;                   % the one valid entry

            appliedFields = controller.applyProjectSettings(settings);

            testCase.verifyEqual(appliedFields, {'QualityThreshold'});
            testCase.verifyEqual(controller.BatchOpt.QualityThreshold{1}, 0.44);
            testCase.verifyEqual(controller.BatchOpt.BlendMode{1}, defaults.BlendMode{1});
            testCase.verifyEqual(controller.BatchOpt.TileOrder{1}, defaults.TileOrder{1});
            testCase.verifyEqual(controller.BatchOpt.SubfolderMode, defaults.SubfolderMode);
            testCase.verifyEqual(controller.BatchOpt.OverlapX{1}, defaults.OverlapX{1});
            testCase.verifyEqual(controller.BatchOpt.OutputPath, defaults.OutputPath);
        end

        function applyProjectSettingsClampsNumericsToTheCurrentLimits(testCase)
            controller = testCase.newController();
            controller.applyProjectSettings(struct('QualityThreshold', 5, 'OverlapY', -30));
            testCase.verifyEqual(controller.BatchOpt.QualityThreshold{1}, 1);   % limits [0 1]
            testCase.verifyEqual(controller.BatchOpt.OverlapY{1}, 0);           % limits [0 90]
        end

        function applyProjectSettingsRestoresRowVectorsFromJsonColumns(testCase)
            % jsondecode returns arrays as COLUMNS; detectMSERFeatures wants a
            % 1x2 RegionAreaRange and would otherwise get a 2x1.
            controller = testCase.newController();
            featureOptions = struct('detectMSERFeatures', struct('RegionAreaRange', [30; 14000]));
            controller.applyProjectSettings(struct('FeatureOptions', featureOptions));
            testCase.verifyEqual(size(controller.automaticOptions.detectMSERFeatures.RegionAreaRange), ...
                [1 2]);
            testCase.verifyEqual(controller.automaticOptions.detectMSERFeatures.RegionAreaRange, ...
                [30 14000]);
        end

        function applyProjectSettingsSkipFieldsKeepsTheCurrentPaths(testCase)
            % "Settings only" load: reuse a project's parameters on the tiles
            % selected right now, so the paths must NOT be overwritten.
            controller = testCase.newController();
            controller.BatchOpt.InputPath  = 'C:\current\tiles';
            controller.BatchOpt.OutputPath = 'C:\current\out.zarr';

            settings = struct('InputPath', 'C:\saved\tiles', 'OutputPath', 'C:\saved\out.zarr', ...
                'BlendMode', 'Max');
            appliedFields = controller.applyProjectSettings(settings, {'InputPath', 'OutputPath'});

            testCase.verifyEqual(controller.BatchOpt.InputPath, 'C:\current\tiles');
            testCase.verifyEqual(controller.BatchOpt.OutputPath, 'C:\current\out.zarr');
            testCase.verifyEqual(controller.BatchOpt.BlendMode{1}, 'Max');
            testCase.verifyEqual(appliedFields, {'BlendMode'});
        end

        % ---- session settings: what the next open starts from ---------------

        function closingTheDialogSnapshotsItsSettingsIntoTheSession(testCase)
            % Closing the window records the parameters under
            % sessionSettings.stitching; the constructor's GUI path reads that
            % key back, so the next open starts where this one left off.
            controller = testCase.newController();
            controller.view = struct('gui', gobjects(1), 'handles', struct());
            controller.BatchOpt.LayoutSource{1} = 'Filename pattern';
            controller.BatchOpt.BlendMode{1}    = 'Feather';
            controller.BatchOpt.InputPath       = 'C:\tiles\job1';

            controller.closeWindow();

            testCase.assertTrue(isfield(controller.mibModel.sessionSettings, 'stitching'));
            snapshot = controller.mibModel.sessionSettings.stitching;
            testCase.verifyEqual(snapshot.LayoutSource, 'Filename pattern');
            testCase.verifyEqual(snapshot.BlendMode, 'Feather');
            % The snapshot is the project-settings struct verbatim; the paths are
            % dropped when it is read back, not when it is written, so a future
            % reader can still see where the last job pointed.
            testCase.verifyEqual(snapshot.InputPath, 'C:\tiles\job1');
        end

        function closingWithoutAWindowLeavesTheSessionAlone(testCase)
            % A batch protocol states its parameters in full and has no business
            % changing what the dialog opens with.
            controller = testCase.newController();
            controller.mibModel.sessionSettings.stitching = struct('LayoutSource', 'Grid');
            controller.BatchOpt.LayoutSource{1} = 'Bio-Formats metadata';

            controller.closeWindow();

            testCase.verifyEqual( ...
                controller.mibModel.sessionSettings.stitching.LayoutSource, 'Grid');
        end
    end

    % =================================================================
    % Alignment-quality chip
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function qualityChipIsNeutralBeforeASolve(testCase)
            controller = testCase.newController();
            rmseLabel = testCase.attachChipLabel(controller);
            controller.refreshQualityChip();
            % Plain hyphen, not an em dash - see the dash rule in CLAUDE.md.
            testCase.verifyEqual(rmseLabel.Text, 'Alignment: -');
            testCase.verifyEqual(rmseLabel.BackgroundColor, 'none');
        end

        function qualityChipFollowsTheEdgeSetWithoutReSolving(testCase)
            % The regression this chip block exists for: the verdict folds in
            % the WORST seam score over the VALID edges, so excluding a bad
            % seam changes it without moving a single tile. Before the chip was
            % moved out of optimizePositions_Callback, only a re-solve could
            % repaint it and the stale verdict stayed on screen.
            [controller, badEdge] = testCase.solvedSabotagedChain(44);
            rmseLabel = testCase.attachChipLabel(controller);

            controller.refreshQualityChip();
            testCase.assertLessThan(controller.edges(badEdge).seamScore, 0.4, ...
                'the sabotaged seam must score badly at the solved placement');
            testCase.verifySubstring(rmseLabel.Text, 'Seams disagree');
            testCase.verifyEqual(rmseLabel.BackgroundColor, [0.75 0.20 0.20]);

            % Exclude it - no re-solve, no new pixels read, same positions.
            positionsBefore = controller.positions;
            controller.edges(badEdge).valid = false;
            controller.refreshQualityChip();

            testCase.verifyEqual(controller.positions, positionsBefore);
            testCase.verifySubstring(rmseLabel.Text, 'Excellent alignment');
            testCase.verifyEqual(rmseLabel.BackgroundColor, [0.20 0.60 0.30]);
        end

        function qualityChipSaysSoWhenTheSeamsWereNeverChecked(testCase)
            % Cancelling "Scoring seams..." clears the partial result, so the
            % chip is left with a solver residual and no pixel evidence. It must
            % SAY that rather than print "Seam match: NaN" - on a chain-like
            % graph the residual alone is exactly the number that cannot be
            % trusted, so the reader has to know the second check is missing.
            [controller, ~] = testCase.solvedSabotagedChain(44);
            rmseLabel = testCase.attachChipLabel(controller);
            [controller.edges.seamScore] = deal([]);   % what a cancelled pass leaves

            controller.refreshQualityChip();

            testCase.verifySubstring(rmseLabel.Text, 'Seam match: not checked');
            testCase.verifySubstring(rmseLabel.Tooltip, 'Seam match: not checked');
            testCase.verifyEmpty(strfind(rmseLabel.Text, 'NaN')); %#ok<STREMP>
        end

        function qualityChipReportsAPendingReSolve(testCase)
            % While a re-solve is owed, the cached RMSE no longer describes the
            % current edge set - say so instead of quoting it. The wording must
            % also NOT order the user to press Re-solve: Stitch settles the debt
            % itself, so the button is a shortcut, not a requirement.
            [controller, ~] = testCase.solvedSabotagedChain(32);
            rmseLabel = testCase.attachChipLabel(controller);
            controller.inspector = controllers.StitchingInspector( ...
                controller.mibModel, controller, struct('createView', false));
            controller.inspector.resolvePending = true;

            controller.refreshQualityChip();
            testCase.verifySubstring(rmseLabel.Text, 'Seams edited');
            testCase.verifySubstring(rmseLabel.Text, 'or just Stitch');
            testCase.verifySubstring(rmseLabel.Tooltip, 'never fuses stale positions');
            testCase.verifyEqual(rmseLabel.BackgroundColor, [0.85 0.50 0.05]);
        end

        function pendingReSolveOutlivesTheInspectorWindow(testCase)
            % The flag used to live on the inspector, so closing that window
            % dropped it: the chip went quiet and Stitch fused the PRE-FIX
            % positions with nothing said. It belongs to the mosaic, not to the
            % window that happened to edit it.
            [controller, badEdge] = testCase.solvedSabotagedChain(44);
            rmseLabel = testCase.attachChipLabel(controller);
            inspector = controllers.StitchingInspector(controller.mibModel, controller, ...
                struct('createView', false));

            inspector.selectSeam(badEdge);
            inspector.excludeSeam_Callback();          % an edit that never auto-resolves
            testCase.assertTrue(controller.resolvePending);

            delete(inspector);
            controller.inspector = [];                 % what onInspectorClosed does
            testCase.verifyTrue(controller.resolvePending, ...
                'closing the inspector must not discard the pending re-solve');
            controller.refreshQualityChip();
            testCase.verifySubstring(rmseLabel.Text, 'Seams edited');

            % ...and Stitch still settles it, with no inspector to delegate to.
            % Back to fully headless: attachChipLabel left a view stub holding
            % only rmseLabel, and the fuse path runs the real updateWidgets.
            controller.view = [];
            controller.BatchOpt.OutputMode{1} = 'In memory';
            controller.BatchOpt.SaveProject   = false;
            controller.stitchBtn_Callback(true);
            testCase.verifyFalse(controller.resolvePending, ...
                'Stitch must re-solve before fusing, inspector or no inspector');
        end
    end

    % =================================================================
    % Fibics Atlas layout source
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function atlasImportModesFillTheMatchingState(testCase)
            % BatchOpt.LayoutImport decides how much of an Atlas mosaic's own
            % stitch buildLayoutFromBatchOpt adopts - and the import must survive
            % the downstream reset that same method performs.
            [controller, mosaic] = testCase.atlasController();

            controller.BatchOpt.LayoutImport{1} = 'Nominal grid only';
            controller.buildLayoutFromBatchOpt();
            testCase.verifyNumElements(controller.layout, 4);
            testCase.verifyEmpty(controller.edges);
            testCase.verifyEmpty(controller.positions);

            controller.BatchOpt.LayoutImport{1} = 'Vendor seam measurements';
            controller.buildLayoutFromBatchOpt();
            testCase.verifyNumElements(controller.edges, 4);
            testCase.verifyEmpty(controller.positions, ...
                'seam-only import must leave the global solve to MIB');

            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();
            testCase.verifyNumElements(controller.edges, 4);
            testCase.verifySize(controller.positions, [4 3]);
            testCase.verifyEqual(mosaic.veMifPath, controller.BatchOpt.InputPath);
        end

        function atlasImportedPlacementReportsAnAlignmentRating(testCase)
            % An imported stitch arrives without a solve, so the chip would sit
            % blank - and the user would have no way to tell a good Atlas result
            % from the bad one this whole layout source exists to rescue.
            [controller, ~] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();

            testCase.verifyTrue(isfield(controller.solverInfo, 'rmseTotal'));
            testCase.verifyLessThan(controller.solverInfo.rmseTotal, 1);
            testCase.verifyEmpty(controller.solverInfo.disconnectedTiles);

            % The rating is not taken on trust from the file: the overlap pixels
            % are re-read at the imported placement, which is the only check that
            % catches an Atlas stitch that came out wrong. The mosaic's tiles are
            % cut from one texture at exactly these offsets, so the seams match.
            testCase.verifyGreaterThan(min([controller.edges.seamScore]), 0.7);

            rmseLabel = testCase.attachChipLabel(controller);
            controller.refreshQualityChip();
            testCase.verifySubstring(rmseLabel.Text, 'Excellent alignment');
        end

        function atlasNominalGridIsOnlyAStartingGuess(testCase)
            % The stage grid Atlas records is off by the per-seam correction (4 px
            % in X, 6 px in Y here) - the reason this source cannot simply trust
            % it. MIB's own measurement from that grid must recover the truth.
            [controller, mosaic] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Nominal grid only';
            controller.BatchOpt.EstimateOverlap = false;
            controller.buildLayoutFromBatchOpt();

            origins = reshape([controller.layout.nomOrigin], 3, []).';
            testCase.verifyEqual(origins(2, 2) - origins(1, 2), mosaic.stepPx, 'AbsTol', 1e-6);
            testCase.verifyNotEqual(mosaic.stepPx, mosaic.measuredStepXpx);

            controller.measureOverlaps_Callback();
            controller.optimizePositions_Callback();

            relative = controller.positions - controller.positions(1, :);
            testCase.verifyEqual(relative(2, 2), mosaic.measuredStepXpx, 'AbsTol', 1.5);
            testCase.verifyEqual(relative(3, 1), mosaic.measuredStepYpx, 'AbsTol', 1.5);
        end

        function atlasImportedPlacementSkipsMeasureOnStitch(testCase)
            % The point of importing a placement is that Stitch fuses it as it
            % stands. Nothing may re-measure or re-solve on the way.
            [controller, ~] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();

            importedPositions = controller.positions;
            importedEdges     = controller.edges;

            controller.BatchOpt.OutputMode{1} = 'In memory';
            controller.stitchBtn_Callback(true);

            testCase.verifyEqual(controller.positions, importedPositions, 'AbsTol', 1e-9);
            testCase.verifyNumElements(controller.edges, numel(importedEdges));
            testCase.verifyNotEmpty(controller.canvas);
        end

        function importedSeamScoresAreNotRecomputedByTheInspector(testCase)
            % Importing a vendor stitch scores the seams, and the inspector
            % scored them again on the way in - two full passes over every
            % overlap, which on a real mosaic is minutes each. The scores are a
            % function of the placement, and nothing moved in between.
            [controller, ~] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();

            testCase.assertNotEmpty(controller.edges);
            testCase.assertTrue(controller.seamScoresAreCurrent(), ...
                'the import must record what its seam scores were computed for');

            % A value no correlation produces: if the inspector re-scored, the
            % real scores would be back and this would fail.
            sentinel = -0.5;
            [controller.edges.seamScore] = deal(sentinel);

            inspector = controllers.StitchingInspector(controller.mibModel, controller, ...
                struct('createView', false));
            testCase.addTeardown(@() delete(inspector));

            testCase.verifyEqual([controller.edges.seamScore], ...
                repmat(sentinel, 1, numel(controller.edges)), ...
                'the inspector re-read every overlap instead of reusing the scores');
            % The ranking is still derived, since it costs no pixels.
            testCase.verifyNumElements(inspector.ranking, numel(controller.edges));
        end

        function seamScoresGoStaleWhenThePlacementOrTheCorrectionChanges(testCase)
            % The other half of the cache: skipping a rescore that IS needed
            % would rate the mosaic on pixels it no longer shows.
            [controller, ~] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();
            testCase.assertTrue(controller.seamScoresAreCurrent());

            % (a) the tiles moved - the strips are cut at the solved origins
            movedPositions = controller.positions;
            movedPositions(2, 1) = movedPositions(2, 1) + 3;
            controller.positions = movedPositions;
            testCase.verifyFalse(controller.seamScoresAreCurrent(), ...
                'a changed placement must force a rescore');

            % (b) different pixels: the scores correlate CORRECTED tiles
            controller.buildLayoutFromBatchOpt();
            testCase.assertTrue(controller.seamScoresAreCurrent());
            controller.BatchOpt.IntensityCorrection{1} = 'Flat-field (shared)';
            testCase.verifyFalse(controller.seamScoresAreCurrent(), ...
                'a changed intensity correction must force a rescore');

            % (c) a partial set is not a set (what a cancelled pass leaves)
            controller.BatchOpt.IntensityCorrection{1} = 'None';
            testCase.assertTrue(controller.seamScoresAreCurrent());
            controller.edges(1).seamScore = [];
            testCase.verifyFalse(controller.seamScoresAreCurrent(), ...
                'an unscored edge must force a rescore');
        end

        function atlasSourceIgnoresGridAndOverlapSettings(testCase)
            % Rows/Cols/Overlap belong to the grid-style sources; the Atlas layout
            % comes from the recorded stage positions, and the overlap estimator
            % must stand down rather than rebuild the layout from a percentage.
            [controller, ~] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Nominal grid only';
            controller.BatchOpt.EstimateOverlap = true;
            controller.buildLayoutFromBatchOpt();
            originsBefore = reshape([controller.layout.nomOrigin], 3, []).';

            cancelled = controller.runOverlapEstimation();

            testCase.verifyFalse(cancelled);
            originsAfter = reshape([controller.layout.nomOrigin], 3, []).';
            testCase.verifyEqual(originsAfter, originsBefore, 'AbsTol', 1e-9);
        end

        function positionFileSourceTellsTextFilesFromAtlasMosaics(testCase)
            % Both file kinds live under ONE layout source, told apart by
            % extension - the same controller must handle either without the user
            % switching anything, and a text file must not pick up Atlas state.
            [controller, mosaic] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();
            testCase.verifyNumElements(controller.layout, 4);
            testCase.verifySize(controller.positions, [4 3]);

            % Same controller, same layout source, now a plain position file.
            tileFolder = testCase.chopChain(41);
            tileFiles = dir(fullfile(tileFolder, '*.tif'));
            positionFile = fullfile(mosaic.folder, 'positions.txt');
            fileId = fopen(positionFile, 'w');
            for tileIdx = 1:numel(tileFiles)
                fprintf(fileId, '%s %d 0\n', ...
                    fullfile(tileFiles(tileIdx).folder, tileFiles(tileIdx).name), ...
                    (tileIdx - 1) * 120);
            end
            fclose(fileId);

            controller.BatchOpt.InputPath = positionFile;
            controller.buildLayoutFromBatchOpt();

            testCase.verifyNumElements(controller.layout, numel(tileFiles));
            testCase.verifyEmpty(controller.edges, ...
                'a text position file carries no seams - Atlas state must not leak in');
            testCase.verifyEmpty(controller.positions);
        end

        function atlasSidecarPickResolvesToTheMosaicRecord(testCase)
            % Picking a .ve-tie / .ve-updates names the same mosaic; the layout
            % must build from its .ve-mif rather than failing on the wrong file.
            [controller, mosaic] = testCase.atlasController();
            [mosaicFolder, mosaicBase] = fileparts(mosaic.veMifPath);
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';

            controller.BatchOpt.InputPath = mosaic.veMifPath;
            controller.buildLayoutFromBatchOpt();
            expectedPositions = controller.positions;

            for extension = {'.ve-tie', '.ve-updates'}
                controller.BatchOpt.InputPath = fullfile(mosaicFolder, [mosaicBase, extension{1}]);
                controller.buildLayoutFromBatchOpt();
                testCase.verifyEqual(controller.positions, expectedPositions, 'AbsTol', 1e-9, ...
                    sprintf('%s must resolve to the same mosaic', extension{1}));
            end
        end

        function atlasMissingMosaicFileRaises(testCase)
            % Headless callers must see an error where the GUI shows a dialog.
            controller = testCase.newController();
            controller.BatchOpt.LayoutSource{1} = 'Position file';
            controller.BatchOpt.InputPath = fullfile(tempdir, 'no_such_mosaic.ve-mif');
            testCase.verifyError(@() controller.buildLayoutFromBatchOpt(), ...
                'Stitching:badInputPath');
        end
    end

    % =================================================================
    % Local helpers
    % =================================================================
    % =================================================================
    % SerialEM montage layout source
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function mdocImportModesFillTheMatchingState(testCase)
            % The same three modes as Atlas, reached through the same field -
            % which is why the field is vendor-neutral.
            [controller, montage] = testCase.mdocController();

            controller.BatchOpt.LayoutImport{1} = 'Nominal grid only';
            controller.buildLayoutFromBatchOpt();
            testCase.verifyNumElements(controller.layout, montage.numTiles);
            testCase.verifyEmpty(controller.edges);
            testCase.verifyEmpty(controller.positions);

            controller.BatchOpt.LayoutImport{1} = 'Vendor seam measurements';
            controller.buildLayoutFromBatchOpt();
            testCase.verifyNumElements(controller.edges, 4);
            testCase.verifyEmpty(controller.positions, ...
                'seam-only import must leave the global solve to MIB');

            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();
            testCase.verifyNumElements(controller.edges, 4);
            testCase.verifySize(controller.positions, [montage.numTiles 3]);
            testCase.verifyEqual(controller.positions(:, 1:2), montage.expectedOriginRC, ...
                'AbsTol', 1e-9);
        end

        function mdocMontageResolvesFromTheMrcToo(testCase)
            % A user may pick either half of the pair; both must build the same
            % montage, since the .mdoc names the image and the image names the
            % .mdoc.
            [controllerFromMdoc, montage] = testCase.mdocController();
            controllerFromMdoc.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controllerFromMdoc.buildLayoutFromBatchOpt();

            controllerFromMrc = testCase.newController();
            controllerFromMrc.BatchOpt.LayoutSource{1} = 'Position file';
            controllerFromMrc.BatchOpt.InputPath = montage.imagePath;
            controllerFromMrc.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controllerFromMrc.buildLayoutFromBatchOpt();

            testCase.verifyEqual(controllerFromMrc.layout, controllerFromMdoc.layout);
            testCase.verifyEqual(controllerFromMrc.positions, controllerFromMdoc.positions);
        end

        function mdocImportedPlacementReportsAnAlignmentRating(testCase)
            % An imported stitch arrives without a solve, so the chip would sit
            % blank unless the residuals are synthesised for it.
            [controller, ~] = testCase.mdocController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();

            testCase.verifyTrue(isfield(controller.solverInfo, 'rmseTotal'));
            testCase.verifyLessThan(controller.solverInfo.rmseTotal, 0.5, ...
                'the imported edges are exact at the imported positions');
            testCase.verifyEmpty(controller.solverInfo.disconnectedTiles);
            % The pixel check must have run too, so a bad vendor stitch is caught.
            testCase.verifyNotEmpty([controller.edges.seamScore]);
        end

        function mdocTextPositionFileStillWorksUnderTheSameSource(testCase)
            % The Position file source now covers three file kinds; adding the
            % SerialEM branch must not shadow MIB's own text format.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tileFile = fullfile(tmpDir.Folder, 'tile.png');
            imwrite(mibtest.helpers.stitchTextureImage(32, 32, 5), tileFile);
            positionFile = fullfile(tmpDir.Folder, 'positions.txt');
            fileId = fopen(positionFile, 'w');
            fprintf(fileId, 'tile.png 0 0 0\ntile.png 24 0 0\n');
            fclose(fileId);

            controller = testCase.newController();
            controller.BatchOpt.LayoutSource{1} = 'Position file';
            controller.BatchOpt.InputPath = positionFile;
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.buildLayoutFromBatchOpt();

            testCase.verifyNumElements(controller.layout, 2);
            testCase.verifyEmpty(controller.edges, ...
                'a text position file carries no vendor stitch to import');
        end

        function legacyAtlasImportFieldIsAccepted(testCase)
            % Projects and batch protocols written before the rename must still
            % load: AtlasImport -> LayoutImport, with the values mapped too.
            renamed = controllers.Stitching.renameLegacyFields( ...
                struct('AtlasImport', 'Atlas seams + solved positions', 'GridRows', 3));
            testCase.verifyFalse(isfield(renamed, 'AtlasImport'));
            testCase.verifyEqual(renamed.LayoutImport, 'Vendor seams + solved positions');
            testCase.verifyEqual(renamed.GridRows, 3);

            % The cell (BatchOpt dropdown) form is accepted as well.
            fromCell = controllers.Stitching.renameLegacyFields( ...
                struct('AtlasImport', {{'Atlas seam measurements', {'a', 'b'}}}));
            testCase.verifyEqual(fromCell.LayoutImport, 'Vendor seam measurements');

            % A file carrying both keeps the current name untouched.
            bothNames = controllers.Stitching.renameLegacyFields(struct( ...
                'AtlasImport', 'Atlas seam measurements', ...
                'LayoutImport', 'Nominal grid only'));
            testCase.verifyEqual(bothNames.LayoutImport, 'Nominal grid only');

            % And it must survive a real project round-trip into BatchOpt.
            controller = testCase.newController();
            controller.applyProjectSettings(struct('AtlasImport', 'Atlas seam measurements'));
            testCase.verifyEqual(controller.BatchOpt.LayoutImport{1}, 'Vendor seam measurements');
        end

    end

    % =================================================================
    % Intensity correction correction
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function intensityCorrectionIsLazyAndDroppedWithTheLayout(testCase)
            % Estimating reads every tile, so it must not happen until a stage
            % actually needs pixels - and it must never outlive the tiles it was
            % estimated from.
            [controller, ~] = testCase.mdocController();
            controller.BatchOpt.LayoutImport{1}   = 'Nominal grid only';   % no scoring on build
            controller.BatchOpt.IntensityCorrection{1} = 'Flat-field (shared)';
            controller.buildLayoutFromBatchOpt();

            testCase.verifyEmpty(controller.intensityCorrection, ...
                'building a layout must not trigger an estimate');

            first = controller.ensureIntensityCorrection();
            testCase.verifyEqual(first.method, 'Flat-field (shared)');
            testCase.verifyNotEmpty(controller.intensityCorrection);
            testCase.verifyEqual(controller.ensureIntensityCorrection(), first, ...
                'a second call must reuse the cached estimate');

            controller.buildLayoutFromBatchOpt();
            testCase.verifyEmpty(controller.intensityCorrection, ...
                'a rebuilt layout must drop the estimate made from the old tiles');
        end

        function intensityCorrectionReEstimatesWhenTheMethodChanges(testCase)
            % The GUI drops the cache on the dropdown callback, but batch runs and
            % scripts change BatchOpt directly - so the accessor must notice too,
            % or a run would silently use the previous method's correction.
            [controller, ~] = testCase.mdocController();
            controller.BatchOpt.LayoutImport{1}   = 'Nominal grid only';
            controller.BatchOpt.IntensityCorrection{1} = 'Flat-field (shared)';
            controller.buildLayoutFromBatchOpt();
            withField = controller.ensureIntensityCorrection();
            testCase.verifyNotEmpty(withField.field);

            controller.BatchOpt.IntensityCorrection{1} = 'Match tile means';
            switched = controller.ensureIntensityCorrection();
            testCase.verifyEqual(switched.method, 'Match tile means');
            testCase.verifyEmpty(switched.field, ...
                'mean matching is per-tile scalars, not a field');
        end

        function intensityCorrectionNoneCostsNothingAndChangesNoPixels(testCase)
            % The default must be free: no tile reads, and pixels identical to a
            % reader built with no correction at all.
            [controller, ~] = testCase.mdocController();
            controller.BatchOpt.LayoutImport{1}   = 'Nominal grid only';
            controller.BatchOpt.IntensityCorrection{1} = 'None';
            controller.buildLayoutFromBatchOpt();

            neutral = controller.ensureIntensityCorrection();
            testCase.verifyEqual(neutral.method, 'None');
            testCase.verifyEmpty(neutral.field);
            testCase.verifyTrue(all(neutral.gain == 1));

            plainReader   = utils.stitch.makeTileReader(controller.layout);
            neutralReader = utils.stitch.makeTileReader(controller.layout, ...
                struct('correction', neutral));
            testCase.verifyEqual(neutralReader(1), plainReader(1));
        end

        function intensityCorrectionMethodRoundTripsThroughProjectSettings(testCase)
            % The METHOD is persisted; the estimate itself is not (it is a
            % deterministic function of the tiles, and an [H W] float has no
            % business in the sidecar JSON).
            controller = testCase.newController();
            controller.BatchOpt.IntensityCorrection{1} = 'Flat-field (shared)';
            settings = controller.collectProjectSettings();
            testCase.verifyEqual(settings.IntensityCorrection, 'Flat-field (shared)');

            reloaded = testCase.newController();
            reloaded.applyProjectSettings(settings);
            testCase.verifyEqual(reloaded.BatchOpt.IntensityCorrection{1}, 'Flat-field (shared)');
            testCase.verifyEmpty(reloaded.intensityCorrection, ...
                'loading settings must not carry an estimate with them');
        end

    end

    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function stitchedDatasetIsNamedAfterItsSource(testCase)
            % A fused mosaic has no file of its own, and a dataset with no
            % filename makes "Save as" open on MATLAB's working folder - somewhere
            % unrelated to the data. Name it after what it was built from, beside
            % the source.
            [controller, montage] = testCase.mdocController();
            controller.buildLayoutFromBatchOpt();

            stitchedName = controller.stitchedFilename();

            testCase.verifyEqual(fileparts(stitchedName), fileparts(montage.mdocPath), ...
                'the suggested name must sit beside the tiles it came from');
            [~, baseName, extension] = fileparts(stitchedName);
            testCase.verifyEqual(extension, '.tif', ...
                'a mosaic is a plain image, never its vendor acquisition container');
            % "Cell1.mrc.mdoc" reads as "Cell1" to a user, so both extensions go.
            [~, montageBase] = fileparts(montage.mdocPath);
            [~, montageBase] = fileparts(montageBase);
            testCase.verifyEqual(baseName, [montageBase '_stitch']);
        end

        function canvasColourFillsExactlyTheUncoveredPixels(testCase)
            % Jittered tiles never fill the canvas rectangle, so a frame is left
            % around the mosaic. Fusing the SAME plan black and white differs on
            % exactly the uncovered pixels - which is what makes this an exact
            % check rather than a guess at which corner happens to be empty.
            controller = testCase.jitteredPlacementController();

            controller.BatchOpt.CanvasColor{1} = 'black';
            controller.stitchBtn_Callback(true);
            blackMosaic = testCase.fusedData(controller);

            controller.BatchOpt.CanvasColor{1} = 'white';
            controller.stitchBtn_Callback(true);
            whiteMosaic = testCase.fusedData(controller);

            uncovered = blackMosaic ~= whiteMosaic;
            testCase.assertTrue(any(uncovered, 'all'), ...
                'the jittered mosaic should leave an uncovered frame to colour');
            testCase.verifyEqual(unique(whiteMosaic(uncovered)), intmax(class(whiteMosaic)));
            testCase.verifyEqual(unique(blackMosaic(uncovered)), zeros(1, 1, class(blackMosaic)));
            testCase.verifyEqual(blackMosaic(~uncovered), whiteMosaic(~uncovered), ...
                'the fill must not touch a pixel a tile covers');
        end

        function autocropRemovesTheFrameFromTheFusedMosaic(testCase)
            % With Autocrop on there is nothing left for CanvasColor to colour:
            % the black and white fuses come out bit-identical. That equality is
            % the real assertion - a smaller output alone would not prove the
            % frame is gone.
            controller = testCase.jitteredPlacementController();

            controller.stitchBtn_Callback(true);
            uncroppedSize = size(testCase.fusedData(controller));

            controller.BatchOpt.Autocrop = true;
            controller.canvas = [];              % what the widget callback does
            controller.BatchOpt.CanvasColor{1} = 'black';
            controller.stitchBtn_Callback(true);
            croppedBlack = testCase.fusedData(controller);

            controller.canvas = [];
            controller.BatchOpt.CanvasColor{1} = 'white';
            controller.stitchBtn_Callback(true);
            croppedWhite = testCase.fusedData(controller);

            testCase.verifyEqual(croppedBlack, croppedWhite, ...
                'a cropped mosaic must have no uncovered pixel left');
            testCase.verifyLessThan(size(croppedBlack, 1), uncroppedSize(1));
            testCase.verifyLessThan(size(croppedBlack, 2), uncroppedSize(2));
            testCase.verifyEqual(controller.canvas.size(1:2), ...
                [size(croppedBlack, 1), size(croppedBlack, 2)]);
            testCase.verifyTrue(isfield(controller.canvas, 'cropRect'));
        end

        function imageFileFormatsAllNameASaverThatExists(testCase)
            % The label the picker offers and the format string the fuse passes
            % to io.SaverFactory are DIFFERENT strings, joined only by this
            % table - a typo in it is a dialog entry that errors on Stitch.
            formats = controllers.Stitching.imageFileFormats();
            imageSaverFormats = io.SaverFactory.getFormats('image');
            testCase.assertNotEmpty(formats);
            for entry = formats
                testCase.verifyTrue(ismember(entry.saverFormat, imageSaverFormats), ...
                    sprintf('"%s" maps to "%s", which io.SaverFactory does not offer', ...
                    entry.label, entry.saverFormat));
                testCase.verifySubstring(entry.label, ['(*' entry.extension ')'], ...
                    'the label must advertise the extension the fuse will write');
                testCase.verifyTrue(ismember(entry.policy, {'2D sequence', '3D stack'}));
            end

            % The BatchOpt item list IS the table, so a format added to one
            % cannot go missing from the other.
            controller = testCase.newController();
            testCase.verifyEqual(controller.BatchOpt.OutputFormat{2}, {formats.label});
            testCase.verifyTrue(ismember('Image files', controller.BatchOpt.OutputMode{2}));

            % An unknown label (a newer MIB's project) falls back rather than
            % erroring - the export is still the point of pressing Stitch.
            testCase.verifyEqual(controllers.Stitching.imageFileFormat('no such format'), ...
                formats(1));
            testCase.verifyEqual( ...
                controllers.Stitching.imageFileFormat(formats(end).label).saverFormat, ...
                formats(end).saverFormat);
        end

        function imageFilesModeWritesTheFilesAndLeavesTheDatasetAlone(testCase)
            % 'Image files' is an EXPORT: the mosaic goes to disk carrying the
            % acquisition's voxel size, and the buffer the user was looking at is
            % not replaced the way 'In memory' and the zarr reopen replace it.
            [controller, montage] = testCase.mdocController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.BatchOpt.OutputMode{1}   = 'Image files';
            controller.BatchOpt.OutputFormat{1} = 'TIF format uncompressed, 2D sequence (*.tif)';
            controller.BatchOpt.OutputPath      = fullfile(montage.folder, 'export.tif');
            controller.BatchOpt.SaveProject     = false;

            activeId = controller.mibModel.getActiveId();
            datasetBefore = controller.mibModel.I{activeId};

            controller.stitchBtn_Callback(true);

            testCase.verifySameHandle(controller.mibModel.I{activeId}, datasetBefore, ...
                'an export must not swap the active buffer');

            % One section => one output slice => no numeric suffix.
            writtenFile = fullfile(montage.folder, 'export.tif');
            testCase.assertTrue(isfile(writtenFile), 'the mosaic was not written');
            testCase.verifyEqual(size(imread(writtenFile)), controller.canvas.size(1:2));

            % The SerialEM montage states 18.38 A/px, so a 1 um fallback would
            % show up here immediately.
            expectedResolution = utils.calculateResolution(controller.canvas.pixSize);
            % TIFF stores the resolution as a rational, so it comes back rounded
            % - the assertion is that the acquisition scale arrived, not that a
            % double survived the tag bit for bit.
            writtenInfo = imfinfo(writtenFile);
            testCase.verifyEqual(writtenInfo.XResolution, expectedResolution(1), 'RelTol', 1e-6);
            testCase.verifyLessThan(controller.canvas.pixSize.x, 0.01, ...
                'the mdoc pixel size must have reached the canvas for this to mean anything');
        end

        function imageFilesModeWithNoPathStopsInsteadOfGuessing(testCase)
            % Headless there is nobody to ask, and picking a destination on the
            % user's behalf writes files somewhere they did not choose.
            [controller, montage] = testCase.mdocController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.BatchOpt.OutputMode{1}   = 'Image files';
            controller.BatchOpt.OutputPath      = '';
            controller.BatchOpt.SaveProject     = false;

            stopped = false;
            listener = addlistener(controller.mibModel, 'StopProtocol', ...
                @(~, ~) assignStopped()); %#ok<NASGU>
            filesBefore = numel(dir(fullfile(montage.folder, '*.tif')));

            controller.stitchBtn_Callback(true);

            testCase.verifyTrue(stopped, 'a batch run with no destination must stop the protocol');
            testCase.verifyEqual(numel(dir(fullfile(montage.folder, '*.tif'))), filesBefore, ...
                'nothing may be written when the destination is unknown');

            function assignStopped()
                stopped = true;
            end
        end

        function stitchedNameFallsBackToTheFirstTile(testCase)
            % No position file to name it after: a Grid layout is named by its
            % first tile instead, so the rule still produces something beside the
            % data rather than an empty filename.
            [controller, tileDir] = testCase.chainController(7);
            controller.buildLayoutFromBatchOpt();

            stitchedName = controller.stitchedFilename();

            testCase.verifyEqual(fileparts(stitchedName), tileDir);
            testCase.verifySubstring(stitchedName, '_stitch.tif');
        end

    end

    methods (Access = private)

        function controller = jitteredPlacementController(testCase)
            % Controller with a solved 2x2 placement that is deliberately RAGGED:
            % the synthetic Atlas mosaic's imported placement is pixel-perfect (by
            % construction - the tiles were cut from one texture at those offsets),
            % so it tiles the canvas exactly and leaves no frame to colour or crop.
            % Perturbing the positions is what a real solve produces.
            [controller, ~] = testCase.atlasController();
            controller.BatchOpt.LayoutImport{1} = 'Vendor seams + solved positions';
            controller.BatchOpt.OutputMode{1}   = 'In memory';
            controller.BatchOpt.SaveProject     = false;
            controller.buildLayoutFromBatchOpt();
            testCase.assertNumElements(controller.layout, 4);
            controller.positions = controller.positions + ...
                [0 0 0; 3 -2 0; -4 5 0; 2 3 0];
            controller.canvas = [];
        end

        function pixelData = fusedData(~, controller)
            % FUSEDDATA - Pixels of the dataset stitchBtn_Callback just created
            % (In memory output mode replaces the active buffer).
            pixelData = controller.mibModel.I{controller.mibModel.getActiveId()}.image.data;
        end

        function [controller, montage] = mdocController(testCase)
            % Controller pointed at a synthetic SerialEM montage (2x2 in one MRC
            % stack, edges + aligned coords present) - see
            % mibtest.helpers.makeMdocMontage for the geometry and the format
            % traps it reproduces.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            montage = mibtest.helpers.makeMdocMontage(tmpDir.Folder);
            controller = testCase.newController();
            controller.BatchOpt.LayoutSource{1} = 'Position file';
            controller.BatchOpt.InputPath = montage.mdocPath;
        end

        function controller = newController(testCase)
            % Headless controller: the "return BatchOpt" constructor path
            % builds the full default state without a view.
            repoRoot  = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            mibModel  = models.MibModel(1, fullfile(repoRoot, 'mib'), Verbose = false, Preferences = 'defaults');
            mibModel.preferences.System.DeveloperMode = false;   % keep test output clean
            controller = controllers.Stitching(mibModel, [], NaN);
            testCase.assertEmpty(controller.view, 'the NaN path must not build a view');
            controller.BatchOpt.showWaitbar = false;
        end

        function [controller, mosaic] = atlasController(testCase)
            % Controller pointed at a synthetic Fibics Atlas mosaic (2x2, with
            % both sidecars present) - see mibtest.helpers.makeAtlasMosaic for
            % the geometry and the format traps it reproduces.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            mosaic = mibtest.helpers.makeAtlasMosaic(tmpDir.Folder);
            controller = testCase.newController();
            controller.BatchOpt.LayoutSource{1} = 'Position file';
            controller.BatchOpt.InputPath       = mosaic.veMifPath;
        end

        function [controller, tileDir] = chainController(testCase, seed)
            % Controller pointed at a 1x3 chain of 160x160 tiles cut from one
            % textured image with 40 px overlap and ZERO jitter, so the true
            % origins are [1 1], [1 121], [1 241].
            tileDir = testCase.chopChain(seed);
            controller = testCase.newController();
            controller.BatchOpt.LayoutSource{1} = 'Grid';
            controller.BatchOpt.InputPath       = tileDir;
            controller.BatchOpt.GridRows{1}     = 1;
            controller.BatchOpt.GridCols{1}     = 3;
            controller.BatchOpt.OverlapX{1}     = 25;
            controller.BatchOpt.OverlapY{1}     = 0;
            controller.BatchOpt.EstimateOverlap = false;
        end

        function [controller, badEdge] = solvedSabotagedChain(testCase, seed)
            % Measured + solved chain with one confidently-wrong edge: the
            % solver residual stays ~0 (a chain has no loop to contradict it)
            % while the seam pixels disagree.
            %
            % How far the seam score falls depends on the texture, so the seeds
            % used with this helper are ones measured to land the sabotaged
            % seam WELL inside the chip's red band (< 0.4) - 18 px off on this
            % 40 px overlap.
            controller = testCase.chainController(seed);
            controller.buildLayoutFromBatchOpt();
            controller.measureOverlaps_Callback();
            badEdge = find([controller.edges.i] == 2 & [controller.edges.j] == 3, 1);
            testCase.assertNotEmpty(badEdge);
            controller.edges(badEdge).measured = controller.edges(badEdge).measured + [0 18 0];
            controller.edges(badEdge).quality  = 0.95;
            controller.optimizePositions_Callback();
            testCase.assertLessThan(controller.solverInfo.rmseTotal, 0.5, ...
                'the corrupted edge must stay invisible to the solver residual');
        end

        function rmseLabel = attachChipLabel(~, controller)
            % Give the controller just the one widget the chip writes to.
            rmseLabel = mibtest.helpers.FakeWidget();
            controller.view = struct('handles', struct('rmseLabel', rmseLabel), 'gui', []);
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
    end
end
