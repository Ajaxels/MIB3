classdef StitchingControllerTest < matlab.unittest.TestCase
% STITCHINGCONTROLLERTEST - Unit tests for the Stitching controller (controllers.Stitching).
%
% The controller layer BETWEEN the GUI and the ``utils.stitch`` core: BatchOpt
% defaults, layout building from BatchOpt, the measure/optimize workflow
% methods, the project-settings flatten/restore pair, and the alignment-quality
% chip. ``utils.stitch`` itself is covered by ``tests/utils/Stitch*Test.m`` —
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
            % Every dropdown's default must be one of its own items — a typo
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
            % layout — including solverInfo (the quality chip reads it) and the
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
    end

    % =================================================================
    % Alignment-quality chip
    % =================================================================
    methods (Test, TestTags = {'Unit'})

        function qualityChipIsNeutralBeforeASolve(testCase)
            controller = testCase.newController();
            rmseLabel = testCase.attachChipLabel(controller);
            controller.refreshQualityChip();
            testCase.verifyEqual(rmseLabel.Text, 'Alignment: —');
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

            % Exclude it — no re-solve, no new pixels read, same positions.
            positionsBefore = controller.positions;
            controller.edges(badEdge).valid = false;
            controller.refreshQualityChip();

            testCase.verifyEqual(controller.positions, positionsBefore);
            testCase.verifySubstring(rmseLabel.Text, 'Excellent alignment');
            testCase.verifyEqual(rmseLabel.BackgroundColor, [0.20 0.60 0.30]);
        end

        function qualityChipReportsAPendingReSolve(testCase)
            % While the inspector owes a re-solve, the cached RMSE no longer
            % describes the current edge set — say so instead of quoting it.
            [controller, ~] = testCase.solvedSabotagedChain(32);
            rmseLabel = testCase.attachChipLabel(controller);
            controller.inspector = controllers.StitchingInspector( ...
                controller.mibModel, controller, struct('createView', false));
            controller.inspector.resolvePending = true;

            controller.refreshQualityChip();
            testCase.verifySubstring(rmseLabel.Text, 'Re-solve needed');
            testCase.verifyEqual(rmseLabel.BackgroundColor, [0.85 0.50 0.05]);
        end
    end

    % =================================================================
    % Local helpers
    % =================================================================
    methods (Access = private)

        function controller = newController(testCase)
            % Headless controller: the "return BatchOpt" constructor path
            % builds the full default state without a view.
            repoRoot  = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            mibModel  = models.MibModel(1, fullfile(repoRoot, 'mib'));
            mibModel.preferences.System.DeveloperMode = false;   % keep test output clean
            controller = controllers.Stitching(mibModel, [], NaN);
            testCase.assertEmpty(controller.view, 'the NaN path must not build a view');
            controller.BatchOpt.showWaitbar = false;
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
            % seam WELL inside the chip's red band (< 0.4) — 18 px off on this
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
