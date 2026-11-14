classdef Zarr3SaverIsotropicPlanTest < matlab.unittest.TestCase
% ZARR3SAVERISOTROPICPLANTEST - the level plan of the 'Anisotropy-preserving + isotropic level' strategy.
%
% Covers ``io.savers.Zarr3Saver.computeLevelPlan`` only (step 2 of
% development/bigdata/isotropic_hr_level.md): which levels exist, which level each is built from,
% their sizes, and the invariant the BigData level map relies on (every XY factor divides the
% coarsest one). The savers that write these levels are covered by the Zarr3Saver tests.

    properties (Constant, Access = private)
        IsoStrategy = 'Anisotropy-preserving + isotropic level'
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})
        function testFiveFiveThirty(testCase)
            plan = testCase.planFor(4096, 4096, 100, [5 5 30], 'iso');
            testCase.verifyEqual([plan.cumXYFactor], [1 2 4 6 12]);
            testCase.verifyEqual([plan.cumZFactor], [1 1 1 1 2]);
            % 5, 10, 20, 30, 60 nm in XY; Z 30, 30, 30, 30, 60 nm
            testCase.verifyEqual([plan.physScaleX], 5 * [1 2 4 6 12]);
            testCase.verifyEqual([plan.physScaleZ], 30 * [1 1 1 1 2]);
        end

        function testFiveFiveThirtyFive(testCase)
            % 4 does not divide 14, so 28 is appended: the coarsest factor must be a multiple of all
            plan = testCase.planFor(4096, 4096, 100, [5 5 35], 'iso');
            testCase.verifyEqual([plan.cumXYFactor], [1 2 4 7 14 28]);
            testCase.verifyEqual([plan.cumZFactor], [1 1 1 1 2 4]);
            testCase.verifyEqual(plan(4).physScaleX, 35);
            testCase.verifyEqual(plan(4).physScaleZ, 35);
        end

        function testEveryLevelFromTheIsotropicOneIsIsotropic(testCase)
            plan = testCase.planFor(4096, 4096, 100, [5 5 35], 'iso');
            for levelId = 4:numel(plan)
                testCase.verifyEqual(plan(levelId).physScaleX, plan(levelId).physScaleZ, 'AbsTol', 1e-12);
                testCase.verifyEqual(plan(levelId).physScaleY, plan(levelId).physScaleZ, 'AbsTol', 1e-12);
            end
        end

        function testIsotropicLevelIsBuiltFromTheCoarsestDividingLevel(testCase)
            % 30 nm from the 10 nm level (3x), the 60 nm level from the 30 nm one
            plan = testCase.planFor(4096, 4096, 100, [5 5 30], 'iso');
            testCase.verifyEqual([plan.sourceLevel], [0 1 2 2 4]);
            testCase.verifyEqual([plan.relXY], [1 2 2 3 2]);
            % F = 12: levels 1, 2, 4, 8, then 12 (the 5th); the 20 nm level (factor 4, level 3) divides it
            plan = testCase.planFor(8192, 8192, 100, [5 5 60], 'iso');
            testCase.verifyEqual([plan(1:5).cumXYFactor], [1 2 4 8 12]);
            testCase.verifyEqual([plan(5).sourceLevel, plan(5).relXY], [3 3]);
            % F = 7 and 5: only level 0 divides it
            plan = testCase.planFor(4096, 4096, 100, [5 5 35], 'iso');
            testCase.verifyEqual([plan(4).sourceLevel, plan(4).relXY], [1 7]);
            plan = testCase.planFor(4096, 4096, 100, [5 5 25], 'iso');
            testCase.verifyEqual([plan(4).cumXYFactor, plan(4).sourceLevel, plan(4).relXY], [5 1 5]);
        end

        function testSizesAreCeilOfLevelZero(testCase)
            plan = testCase.planFor(1001, 1503, 41, [5 5 30], 'iso', struct('MinLevelSize', 16));
            for levelId = 1:numel(plan)
                testCase.verifyEqual(plan(levelId).Yl, ceil(1001 / plan(levelId).cumXYFactor));
                testCase.verifyEqual(plan(levelId).Xl, ceil(1503 / plan(levelId).cumXYFactor));
                testCase.verifyEqual(plan(levelId).Zl, ceil(41 / plan(levelId).cumZFactor));
            end
            testCase.verifyEqual(plan(4).Yl, 167);   % ceil(1001 / 6), not round
        end

        function testIsotropicLevelIsMandatoryForExplicitLevels(testCase)
            % 3 levels requested, the isotropic one is the 4th, and 4 does not divide 6 -> 12 appended
            plan = testCase.planFor(4096, 4096, 100, [5 5 30], 'iso', struct('Levels', 3));
            testCase.verifyEqual([plan.cumXYFactor], [1 2 4 6 12]);
        end

        function testMaxLevelsDoesNotRemoveIsotropicLevel(testCase)
            plan = testCase.planFor(4096, 4096, 100, [5 5 30], 'iso', struct('MaxLevels', 2));
            testCase.verifyTrue(ismember(6, [plan.cumXYFactor]));
        end

        function testPowerOfTwoRatioEqualsAnisotropyPreserving(testCase)
            isoPlan = testCase.planFor(4096, 4096, 100, [5 5 20], 'iso');
            anisoPlan = testCase.planFor(4096, 4096, 100, [5 5 20], 'aniso');
            testCase.verifyEqual(isoPlan, anisoPlan);
        end

        function testIsotropicDataGetsNoExtraLevel(testCase)
            isoPlan = testCase.planFor(4096, 4096, 100, [5 5 5], 'iso');
            anisoPlan = testCase.planFor(4096, 4096, 100, [5 5 5], 'aniso');
            testCase.verifyEqual(isoPlan, anisoPlan);
        end

        function testAutoStrategyFollowsTheVoxelRatio(testCase)
            resolve = @io.savers.Zarr3Saver.resolveDownsampleStrategy;
            testCase.verifyEqual(resolve('Auto', struct('x', 5, 'y', 5, 'z', 30)), 'Anisotropy-preserving');
            testCase.verifyEqual(resolve('Auto', struct('x', 5, 'y', 5, 'z', 7.5)), 'Anisotropy-preserving');
            testCase.verifyEqual(resolve('Auto', struct('x', 5, 'y', 5, 'z', 7.4)), 'XY only');
            testCase.verifyEqual(resolve('Auto', struct('x', 5, 'y', 5, 'z', 5)), 'XY only');
            testCase.verifyEqual(resolve('Auto', []), 'XY only', 'an unknown voxel size gives XY only');
            for name = {'XY only', 'Anisotropy-preserving', 'Anisotropy-preserving + isotropic level'}
                testCase.verifyEqual(resolve(name{1}, struct('x', 5, 'y', 5, 'z', 30)), name{1}, 'explicit strategies pass through');
            end
        end

        function testPyramidCutAtThePredictedLevelKeepsTheIsotropicLevel(testCase)
            % DeepMIB mirrors the levels from the predicted level down (startPredictionBlockedImage):
            % the saver, given the options of the cut pyramid and the voxel size of the cut level,
            % must give the same relative levels. 5x5x30 nm: XY factors 1 2 4 6 12, Z 1 1 1 1 2
            % The strategy alone fails for a cut at 20 nm (Z/XY = 1.5): DeepMIB passes LevelFactors
            full = io.savers.Zarr3Saver.computeLevelPlan(4096, 4096, 512, struct('x', 5, 'y', 5, 'z', 30), ...
                struct('DownsampleStrategy', 'Anisotropy-preserving + isotropic level'));
            levelSizes = [[full.Yl]', [full.Xl]', [full.Zl]'];
            factors = [[full.cumXYFactor]', [full.cumXYFactor]', [full.cumZFactor]'];
            for cutLevel = 1:4
                kept = cutLevel:size(levelSizes, 1);
                cutPyramid = struct('axisOrder', 'yxz', 'levelImageSizes', levelSizes(kept, :), ...
                    'levelScaleFactors', factors(kept, :), 'chunkSizes', {repmat({[256 256 16]}, 1, numel(kept))});
                saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(cutPyramid);
                voxelXY = 5 * factors(cutLevel, 1);
                plan = io.savers.Zarr3Saver.computeLevelPlan(levelSizes(cutLevel, 1), levelSizes(cutLevel, 2), ...
                    levelSizes(cutLevel, 3), struct('x', voxelXY, 'y', voxelXY, 'z', 30), ...
                    struct('DownsampleStrategy', saverOptions.DownsampleStrategy, 'Levels', saverOptions.Levels, ...
                    'LevelFactors', factors(kept, :) ./ factors(cutLevel, :)));
                testCase.verifyEqual([plan.cumXYFactor], factors(kept, 1)' / factors(cutLevel, 1), ...
                    sprintf('XY factors, cut at level %d', cutLevel), 'AbsTol', 1e-9);
                testCase.verifyEqual([plan.cumZFactor], factors(kept, 3)' / factors(cutLevel, 3), ...
                    sprintf('Z factors, cut at level %d', cutLevel), 'AbsTol', 1e-9);
            end
        end

        function testRatioOfNoSimpleFractionWarnsAndFallsBack(testCase)
            % 13.37 / 5 = 2.674 = 1337 / 500: no tile of whole pixels of small size fits it
            anisoPlan = testCase.planFor(4096, 4096, 100, [5 5 13.37], 'aniso');
            testCase.verifyWarning(@() testCase.planFor(4096, 4096, 100, [5 5 13.37], 'iso'), ...
                'Zarr3Saver:isotropicLevelNonInteger');
            plan = testCase.planFor(4096, 4096, 100, [5 5 13.37], 'iso', struct(), true);
            testCase.verifyEqual(plan, anisoPlan);
        end

        function testNonIntegerIsotropicLevelIsExact(testCase)
            % 5x5x13 nm: F = 13 / 5 = 2.6. XY 5, 10, 13, 26, 52 nm; the 13 nm level is built from
            % level 0 in one 2.6 step, every later level halves XY and Z
            plan = testCase.planFor(4096, 4096, 100, [5 5 13], 'iso');
            testCase.verifyEqual([plan.cumXYFactor], [1 2 2.6 5.2 10.4], 'AbsTol', 1e-12);
            testCase.verifyEqual([plan.cumZFactor], [1 1 1 2 4]);
            testCase.verifyEqual([plan.sourceLevel], [0 1 1 3 4]);
            testCase.verifyEqual([plan.relXY], [1 2 2.6 2 2], 'AbsTol', 1e-12);
            testCase.verifyEqual([plan.Yl], ceil(4096 ./ [1 2 2.6 5.2 10.4]));
            testCase.verifyEqual([plan(3).physScaleX, plan(3).physScaleY, plan(3).physScaleZ], [13 13 13], 'AbsTol', 1e-9);
        end

        function testSmallImageWarnsAndFallsBack(testCase)
            % 300 px / 6 = 50 px, below MinLevelSize 256
            anisoPlan = testCase.planFor(300, 300, 100, [5 5 30], 'aniso');
            testCase.verifyWarning(@() testCase.planFor(300, 300, 100, [5 5 30], 'iso'), ...
                'Zarr3Saver:isotropicLevelTooSmall');
            plan = testCase.planFor(300, 300, 100, [5 5 30], 'iso', struct(), true);
            testCase.verifyEqual(plan, anisoPlan);
        end

        function testOldStrategiesKeepTheirLevelsAndGainSourceFields(testCase)
            for strategy = {'xy', 'aniso'}
                plan = testCase.planFor(4096, 4096, 100, [5 5 30], strategy{1});
                testCase.verifyEqual([plan.sourceLevel], 0:numel(plan) - 1);
                testCase.verifyEqual([plan.relXY], [1 2 * ones(1, numel(plan) - 1)]);
            end
            plan = testCase.planFor(4096, 4096, 100, [5 5 30], 'aniso');
            testCase.verifyEqual([plan.cumXYFactor], [1 2 4 8 16]);
            testCase.verifyEqual([plan.cumZFactor], [1 1 1 2 4]);
        end

        function testCoarsestFactorIsAMultipleOfEveryOther(testCase)
            % the level-map invariant, over many ratios and sizes
            for ratio = [3 5 6 7 9 10 11 12 13 15 21 35]
                for edge = [2000 4096 20000]
                    plan = testCase.planFor(edge, edge, 200, [4 4 4 * ratio], 'iso', struct(), true);
                    factors = [plan.cumXYFactor];
                    zFactors = [plan.cumZFactor];
                    testCase.verifyTrue(all(mod(factors(end), factors) == 0), ...
                        sprintf('ratio %d, edge %d: %s', ratio, edge, mat2str(factors)));
                    testCase.verifyTrue(all(mod(zFactors(end), zFactors) == 0));
                    testCase.verifyTrue(all(diff(factors) > 0));
                    testCase.verifyTrue(ismember(ratio, factors) || all(factors == 2.^(0:numel(factors) - 1)));
                end
            end
        end
    end

    methods (Test, TestTags = {'Unit'})
        function testSourcesFromFactorsAgreeWithThePlan(testCase)
            % a writer that rebuilds levels of a stored pyramid (BigDataOptions overwrite) must find
            % the source the planner chose, from the stored scale factors alone
            for strategy = {'xy', 'aniso', 'iso'}
                for voxelNm = {[5 5 30], [5 5 35], [5 5 20], [5 5 60], [5 5 25], [4 4 12]}
                    plan = testCase.planFor(8192, 8192, 100, voxelNm{1}, strategy{1}, struct('MinLevelSize', 16), true);
                    [sourceLevels, relXY, relZ] = io.savers.Zarr3Saver.levelSourcesFromFactors( ...
                        [plan.cumXYFactor], [plan.cumZFactor]);
                    message = sprintf('%s %s', strategy{1}, mat2str(voxelNm{1}));
                    testCase.verifyEqual(sourceLevels, [plan.sourceLevel], message);
                    testCase.verifyEqual(relXY, [plan.relXY], message);
                    testCase.verifyEqual(relZ, [plan.cumZFactor] ./ [plan(max(1, sourceLevels)).cumZFactor], message);
                end
            end
        end

        function testSourcesOfAStoreThatDoesNotFollowTheRule(testCase)
            % Level 0 divides every XY factor, so only a Z ratio can break the rule: a Z factor of 1.5
            % divides by no finer level. Full resolution is returned with the actual Z step, for the
            % caller (BigDataOptions) to reject.
            [sourceLevels, relXY, relZ] = io.savers.Zarr3Saver.levelSourcesFromFactors([1 2 4], [1 1 1.5]);
            testCase.verifyEqual(sourceLevels, [0 1 1]);
            testCase.verifyEqual(relXY, [1 2 4]);
            testCase.verifyEqual(relZ, [1 1 1.5]);
            % the isotropic level of a non-integer F: built from level 0 with the step F
            [sourceLevels, relXY] = io.savers.Zarr3Saver.levelSourcesFromFactors([1 2 2.6 5.2 10.4], [1 1 1 2 4]);
            testCase.verifyEqual(sourceLevels, [0 1 1 3 4]);
            testCase.verifyEqual(relXY, [1 2 2.6 2 2], 'AbsTol', 1e-12);
        end

        function testOptionsFromPyramidDetectsTheStrategy(testCase)
            cases = {[1 2 4 8 16], [1 1 1 1 1], 'XY only'; ...
                     [1 2 4 8 16], [1 1 1 2 4], 'Anisotropy-preserving'; ...
                     [1 2 4 6 12], [1 1 1 1 2], 'Anisotropy-preserving + isotropic level'; ...
                     [1 2 4 7 14 28], [1 1 1 1 2 4], 'Anisotropy-preserving + isotropic level'; ...
                     [1 3 6 12], [1 1 1 1], 'XY only'};   % factors off the grid of 2, but Z is never halved
            for caseId = 1:size(cases, 1)
                factors = cases{caseId, 1};
                pyramid = struct('levelImageSizes', repmat([4096 4096 100], numel(factors), 1), ...
                    'levelScaleFactors', [factors(:), factors(:), cases{caseId, 2}(:)]);
                saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(pyramid);
                testCase.verifyEqual(saverOptions.DownsampleStrategy, cases{caseId, 3}, mat2str(factors));
            end
        end

        function testAPyramidOfTheIsotropicStrategyIsReproduced(testCase)
            % crop / alignment: plan -> pyramid -> optionsFromPyramid -> plan gives the same levels
            for voxelNm = {[5 5 30], [5 5 35], [5 5 25]}
                original = testCase.planFor(6000, 5000, 120, voxelNm{1}, 'iso', struct('MinLevelSize', 16));
                pyramid = io.savers.Zarr3Saver.pyramidFromPlan(original, [64 64 4], 'yxz');
                saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(pyramid);
                testCase.assertEqual(saverOptions.DownsampleStrategy, 'Anisotropy-preserving + isotropic level');
                pixSize = struct('x', voxelNm{1}(1), 'y', voxelNm{1}(2), 'z', voxelNm{1}(3));
                again = io.savers.Zarr3Saver.computeLevelPlan(6000, 5000, 120, pixSize, saverOptions);
                testCase.verifyEqual(again, original, mat2str(voxelNm{1}));
            end
        end
    end

    methods (Access = private)
        function plan = planFor(testCase, Y, X, Z, voxelNm, strategyName, extraOptions, silenceWarnings)
            % PLANFOR - computeLevelPlan with strategy 'xy' | 'aniso' | 'iso'
            if nargin < 7; extraOptions = struct(); end
            if nargin < 8; silenceWarnings = false; end
            strategies = struct('xy', 'XY only', 'aniso', 'Anisotropy-preserving', 'iso', testCase.IsoStrategy);
            options = extraOptions;
            options.DownsampleStrategy = strategies.(strategyName);
            pixSize = struct('x', voxelNm(1), 'y', voxelNm(2), 'z', voxelNm(3));
            if silenceWarnings
                previous = warning('off', 'all');
                cleanup = onCleanup(@() warning(previous));
            end
            plan = io.savers.Zarr3Saver.computeLevelPlan(Y, X, Z, pixSize, options);
        end
    end
end
