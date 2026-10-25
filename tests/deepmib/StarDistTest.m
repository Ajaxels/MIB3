classdef StarDistTest < matlab.unittest.TestCase
    % STARDISTTEST - deepmib.stardist package: targets, normalisation, polygons, NMS, network, loss.
    %
    % Synthetic and self-contained: every expected value is derived analytically in the test
    % (ray lengths of a rectangle, percentiles of 1..100, the area of a diamond), so no reference
    % data from the Python StarDist is needed.
    %
    % Tests that compare the MEX (mib/external/stardist/stardistMex) with the MATLAB fallbacks
    % self-skip when the MEX is not built for this platform.

    methods (TestClassSetup)
        function addMibToPath(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            % the MEX sits next to its source in mib/external/stardist, which mib3.m adds
            mibFolder = fileparts(fileparts(fileparts(which('deepmib.stardist.nms'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(mibFolder, 'external', 'stardist')));
        end
    end

    methods (Test, TestTags = {'Unit'})
        %% configuration
        function defaultConfigKeepsGivenFields(testCase)
            config = deepmib.stardist.defaultConfig(struct('nRays', 16, 'grid', [2; 2]));
            testCase.verifyEqual(config.nRays, 16);
            testCase.verifyEqual(config.grid, [2 2], 'grid is returned as a row');
            testCase.verifyEqual(config.unetDepth, 3, 'missing fields take the StarDist defaults');
            testCase.verifyEqual(config.normalizePercentiles, [1 99.8]);
        end

        %% targets
        function rayDistancesOfRectangle(testCase)
            % rectangle rows 11-31, cols 11-51 (1-based); from pixel (21, 31) a ray leaves the
            % object after n unit steps and is corrected by half a step: n - 1 + 0.5
            labelMap = zeros(64, 64, 'uint16');
            labelMap(11:31, 11:51) = 1;
            config = deepmib.stardist.defaultConfig(struct('nRays', 32, 'grid', [1 1]));
            for method = ["matlab", testCase.mexMethodIfBuilt("mex")]
                targets = deepmib.stardist.computeTargets(labelMap, config, char(method));
                rays = squeeze(targets(21, 31, 2:end));
                testCase.verifyEqual(double(rays([1 9 17 25])), [20.5; 10.5; 20.5; 10.5], 'AbsTol', 1e-4, ...
                    sprintf('rays along +col, +row, -col, -row (%s)', method));
                testCase.verifyEqual(targets(1, 1, :), zeros(1, 1, 33, 'single'), 'background gets zeros');
            end
        end

        function probabilityIsNormalisedDistanceTransform(testCase)
            % the EDT inside the rectangle peaks at 11 on its middle row; normalised per object
            labelMap = zeros(64, 64, 'uint16');
            labelMap(11:31, 11:51) = 1;
            labelMap(41:50, 5:14) = 2;      % a second object with its own maximum
            targets = deepmib.stardist.computeTargets(labelMap, deepmib.stardist.defaultConfig(struct('grid', [1 1])));
            testCase.verifyEqual(targets(21, 31, 1), single(1), 'AbsTol', 1e-6);
            testCase.verifyEqual(targets(12, 31, 1), single(2/11), 'AbsTol', 1e-6);
            testCase.verifyEqual(max(max(targets(41:50, 5:14, 1))), single(1), 'AbsTol', 1e-6);
        end

        function gridSubsamplesFromPixelZero(testCase)
            labelMap = zeros(64, 64, 'uint16');
            labelMap(11:31, 11:51) = 1;
            fullTargets = deepmib.stardist.computeTargets(labelMap, deepmib.stardist.defaultConfig(struct('grid', [1 1])));
            gridTargets = deepmib.stardist.computeTargets(labelMap, deepmib.stardist.defaultConfig(struct('grid', [2 2])));
            testCase.verifySize(gridTargets, [32 32 33]);
            testCase.verifyEqual(gridTargets(:, :, 2:end), fullTargets(1:2:end, 1:2:end, 2:end), ...
                'distances are taken at every 2nd pixel starting at the first');
        end

        function targetsMexEqualsMatlab(testCase)
            testCase.assumeNotEmpty(testCase.mexMethodIfBuilt("mex"), 'stardistMex is not built');
            labelMap = StarDistTest.randomLabelMap(96, 80, 7);
            config = deepmib.stardist.defaultConfig(struct('grid', [2 2], 'nRays', 16));
            testCase.verifyEqual(deepmib.stardist.computeTargets(labelMap, config, 'mex'), ...
                deepmib.stardist.computeTargets(labelMap, config, 'matlab'), 'AbsTol', single(1e-5));
        end

        function labelIdsAboveUint16Work(testCase)
            labelMap = zeros(32, 32, 'uint32');
            labelMap(5:20, 5:20) = 70000;
            targets = deepmib.stardist.computeTargets(labelMap, deepmib.stardist.defaultConfig(struct('grid', [1 1])));
            testCase.verifyGreaterThan(targets(12, 12, 2), single(0));
        end

        %% normalisation
        function normalisationUsesNumpyPercentiles(testCase)
            % numpy 'linear': position (n-1)*p/100 in 1..100 -> p1 = 1.99, p99.8 = 99.802
            for imageClass = ["uint8", "double"]
                image = cast(reshape(1:100, 10, 10), imageClass);
                [normalized, low, high] = deepmib.stardist.normalizeImage(image, [1 99.8]);
                testCase.verifyEqual(double(low), 1.99, 'AbsTol', 1e-5, char(imageClass));
                testCase.verifyEqual(double(high), 99.802, 'AbsTol', 1e-4, char(imageClass));
                testCase.verifyEqual(normalized(1), single((1 - 1.99) / (99.802 - 1.99)), 'AbsTol', 1e-6);
                testCase.verifyClass(normalized, 'single');
            end
        end

        %% polygons
        function diamondHasExpectedArea(testCase)
            % 4 rays of 5.5 px: a diamond |r| + |c| <= 5.5 holds the 61 pixel centres with |r| + |c| <= 5;
            % the half pixel keeps every centre off the edges, where rounding would decide
            inside = deepmib.stardist.starPolygonMask([0 0], [5.5 5.5 5.5 5.5], -6:6, -6:6);
            testCase.verifyEqual(nnz(inside), 61);
        end

        function maskHasTheWindowShape(testCase)
            % regression: a one-column window came back as a square (vector indexing kept the
            % orientation of the vertex row vector)
            rays = zeros(1, 32);
            rays([9 25]) = 5;       % a vertical line, one pixel wide
            windows = {{5:15, 10}, {10, 5:15}, {10, 10}, {5:15, 5:15}};
            for windowId = 1:numel(windows)
                [rowRange, colRange] = windows{windowId}{:};
                inside = deepmib.stardist.starPolygonMask([10 10], rays, rowRange, colRange);
                testCase.verifySize(inside, [numel(rowRange) numel(colRange)]);
            end
            labels = deepmib.stardist.polygonsToLabel([10 10], rays, 1, [30 30]);
            testCase.verifyEqual(nnz(labels), 11);
        end

        function higherScoreWinsOnOverlap(testCase)
            % label 1 = highest score, drawn last
            points = [10 10; 10 14];
            rays = repmat([5 5 5 5], 2, 1);
            labels = deepmib.stardist.polygonsToLabel(points, rays, [0.5; 0.9], [30 30]);
            testCase.verifyEqual(labels(11, 13), uint32(1), 'the overlap goes to the higher score');
            testCase.verifyEqual(labels(11, 9), uint32(2));
            testCase.verifyEqual(labels(11, 19), uint32(1));
        end

        %% NMS
        function nmsSuppressesOverlapAndKeepsDistant(testCase)
            prob = zeros(40, 40, 'single');
            prob(11, 11) = 0.9;     % kept
            prob(11, 12) = 0.8;     % nearly the same polygon: suppressed
            prob(31, 31) = 0.7;     % far away: kept
            dist = 5 * ones(40, 40, 32, 'single');
            for method = ["raster", testCase.mexMethodIfBuilt("mex")]
                [points, scores] = deepmib.stardist.nms(prob, dist, [1 1], 0.5, 0.4, struct('method', char(method)));
                testCase.verifyEqual(points, [10 10; 30 30], char(method));
                testCase.verifyEqual(scores, single([0.9; 0.7]), char(method));
            end
        end

        function nmsIgnoresTheBorderAndAppliesTheGrid(testCase)
            prob = zeros(20, 20, 'single');
            prob(2, 10) = 0.9;      % inside the 2-cell border: never a candidate
            prob(8, 6) = 0.8;
            dist = 3 * ones(20, 20, 32, 'single');
            points = deepmib.stardist.nms(prob, dist, [2 2], 0.5, 0.4, struct('method', 'raster'));
            testCase.verifyEqual(points, [14 10], 'centre = (index - 1) * grid, no offset');
        end

        function nmsMexAgreesWithRaster(testCase)
            testCase.assumeNotEmpty(testCase.mexMethodIfBuilt("mex"), 'stardistMex is not built');
            randomStream = RandStream('mt19937ar', 'Seed', 3);
            prob = single(rand(randomStream, 48, 48) .^ 4);
            dist = single(2 + 6 * rand(randomStream, 48, 48, 16));
            pointsMex = deepmib.stardist.nms(prob, dist, [1 1], 0.6, 0.3, struct('method', 'mex'));
            pointsRaster = deepmib.stardist.nms(prob, dist, [1 1], 0.6, 0.3, struct('method', 'raster'));
            common = size(intersect(pointsMex, pointsRaster, 'rows'), 1);
            % the raster counts the intersection on pixel centres, the C++ clips integer polygons;
            % they may differ on candidates whose overlap lies on the threshold
            testCase.verifyGreaterThanOrEqual(common / max(size(pointsMex, 1), 1), 0.9);
        end

        %% network
        function networkOutputSize(testCase)
            cases = {struct('grid', [2 2], 'nRays', 32, 'patchSize', [64 64]), [32 32 33]; ...
                struct('grid', [1 1], 'nRays', 16, 'patchSize', [48 40]), [48 40 17]};
            for caseId = 1:size(cases, 1)
                net = deepmib.stardist.createNetwork(cases{caseId, 1});
                output = predict(net, dlarray(zeros([cases{caseId, 1}.patchSize 1], 'single'), 'SSCB'));
                testCase.verifySize(extractdata(output), cases{caseId, 2});
            end
            testCase.verifyError(@() deepmib.stardist.createNetwork(struct('grid', [2 2], 'patchSize', [40 40])), ...
                'stardist:createNetwork:patchSize');
        end

        function weightsLoadByLayerName(testCase)
            config = deepmib.stardist.defaultConfig(struct('grid', [2 2], 'nRays', 8, 'patchSize', [32 32], ...
                'unetFilterBase', 8, 'netConvAfterUnet', 16));
            source = deepmib.stardist.createNetwork(config);
            weights = struct();
            for rowId = 1:height(source.Learnables)
                parameter = lower(source.Learnables.Parameter{rowId});
                if strcmp(parameter, 'weights'); parameter = 'kernel'; end
                weights.(source.Learnables.Layer{rowId}).(parameter) = extractdata(source.Learnables.Value{rowId});
            end
            copy = deepmib.stardist.createNetwork(config, weights);
            input = dlarray(rand(32, 32, 1, 'single'), 'SSCB');
            testCase.verifyEqual(extractdata(predict(copy, input)), extractdata(predict(source, input)), 'AbsTol', 1e-6);
        end

        function tiledMapsEqualUntiled(testCase)
            config = deepmib.stardist.defaultConfig(struct('grid', [2 2], 'nRays', 8, 'patchSize', [32 32], ...
                'unetFilterBase', 8, 'netConvAfterUnet', 16));
            net = deepmib.stardist.createNetwork(config);
            image = rand(100, 130, 'single');
            [probWhole, distWhole] = deepmib.stardist.predictMaps(net, image, config, ...
                struct('tileSize', [Inf Inf], 'executionEnvironment', 'cpu'));
            [probTiled, distTiled] = deepmib.stardist.predictMaps(net, image, config, ...
                struct('tileSize', [32 48], 'executionEnvironment', 'cpu'));
            testCase.verifySize(probWhole, [50 65], 'output is ceil(size / grid)');
            testCase.verifyEqual(probTiled, probWhole, 'AbsTol', 1e-5);
            testCase.verifyEqual(distTiled, distWhole, 'AbsTol', 1e-4);
            testCase.verifyGreaterThanOrEqual(min(distWhole, [], 'all'), single(1e-3), 'distances are clamped');
        end

        function predictMapsCancels(testCase)
            config = deepmib.stardist.defaultConfig(struct('grid', [2 2], 'nRays', 8, 'patchSize', [32 32], ...
                'unetFilterBase', 8, 'netConvAfterUnet', 16));
            net = deepmib.stardist.createNetwork(config);
            [prob, dist, cancelled] = deepmib.stardist.predictMaps(net, rand(64, 64, 'single'), config, ...
                struct('executionEnvironment', 'cpu', 'progressDlg', mibtest.helpers.FakeProgressDialog(0)));
            testCase.verifyTrue(cancelled);
            testCase.verifyEmpty(prob);
            testCase.verifyEmpty(dist);
        end

        %% loss and metric
        function lossOfExactPredictionIsEntropyPlusRegulariser(testCase)
            % predicting the targets exactly leaves no distance error, only (a) the cross-entropy
            % of the soft probability target with itself (Keras: prediction clipped to
            % [1e-7, 1-1e-7], +1e-7 in the logs) and (b) the regulariser, which weighs the predicted
            % distances by 1 - probability target and so is small but non-zero inside objects
            labelMap = zeros(32, 32, 'uint16');
            labelMap(5:20, 6:25) = 1;
            config = deepmib.stardist.defaultConfig(struct('grid', [1 1], 'nRays', 8));
            targets = deepmib.stardist.computeTargets(labelMap, config);
            loss = deepmib.stardist.lossFunction(dlarray(targets, 'SSCB'), targets, config);
            probTarget = double(targets(:, :, 1));
            clipped = min(max(probTarget, 1e-7), 1 - 1e-7);
            entropy = -mean(probTarget .* log(clipped + 1e-7) + (1 - probTarget) .* log(1 - clipped + 1e-7), 'all');
            regulariser = config.trainBackgroundReg * mean((1 - probTarget) .* mean(double(targets(:, :, 2:end)), 3), 'all');
            expected = config.trainLossWeights(1) * entropy + config.trainLossWeights(2) * regulariser;
            testCase.verifyEqual(double(extractdata(loss)), expected, 'RelTol', 1e-5);
        end

        function coreIoUMetric(testCase)
            metric = deepmib.stardist.trainingMetrics();
            metric = metric{1};
            target = zeros(8, 8, 3, 'single');
            target(1:4, :, 1) = 0.8;        % 32 core cells
            prediction = target;
            testCase.verifyEqual(metric(dlarray(prediction, 'SSCB'), target), 100);
            prediction(1:2, :, 1) = 0.2;     % half of the core lost
            testCase.verifyEqual(metric(dlarray(prediction, 'SSCB'), target), 50);
            testCase.verifyEqual(metric(dlarray(zeros(8, 8, 3, 'single'), 'SSCB'), zeros(8, 8, 3, 'single')), 100, ...
                'no core on either side is a perfect match');
        end

        %% matching
        function matchingAtSeveralThresholds(testCase)
            labelsTrue = zeros(40, 40, 'uint16');
            labelsTrue(1:10, 1:10) = 1;
            labelsTrue(21:30, 21:30) = 2;
            labelsPred = zeros(40, 40, 'uint16');
            labelsPred(1:10, 1:10) = 7;     % identical object, another id
            labelsPred(21:30, 23:32) = 3;   % shifted by 2 columns: IoU 80 / 120
            stats = deepmib.stardist.matchInstances(labelsTrue, labelsPred, [0 0.5 0.7]);
            testCase.verifyEqual(stats.truePositives, [2 2 1]);
            testCase.verifyEqual(stats.sumMatchedIoU(1), 1 + 80/120, 'AbsTol', 1e-12);
            testCase.verifyEqual([stats.nTrue stats.nPred], [2 2]);
        end

        %% training data
        function labelMapPatchAndAugmentation(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            image = uint8(randi([0 255], 80, 90));
            imwrite(image, fullfile(folder, 'image.tif'));
            imageFilename = 'image.tif';
            instanceLabelMap = zeros(80, 90, 'uint16');
            instanceLabelMap(10:30, 10:40) = 4;
            instanceLabelMap(50:70, 50:80) = 9;
            save(fullfile(folder, 'labels.mat'), 'imageFilename', 'instanceLabelMap');

            options = struct('imageDir', folder, 'patchSize', [32 32], 'objectFraction', 1, 'minObjectArea', 0, ...
                'getImageOptions', struct('mibBioformatsCheck', false, 'BioFormatsIndices', 1, 'Workflow', '2D Instance'), ...
                'outputFormat', 'labelMap', 'normalizePercentiles', [1 99.8], 'patchSeed', 5);
            patch = deepmib.readInstancePatch(fullfile(folder, 'labels.mat'), options);
            [~, low, high] = deepmib.stardist.normalizeImage(image, [1 99.8]);
            testCase.verifySize(patch, [1 3]);
            testCase.verifySize(patch{1}, [32 32], 'native single channel, no RGB expansion');
            testCase.verifyClass(patch{2}, 'uint16');
            testCase.verifyEqual(patch{3}, [low; high], 'whole-image percentiles');

            augOpt.AugOpt2D = struct('Fraction', 1, 'FillValue', 0, 'RandRotation', struct('Min', 10, 'Max', 10));
            augOpt.Aug2DFuncNames = {'RandXReflection', 'Rotation90', 'RandRotation'};
            augOpt.Aug2DFuncProbability = [1 1 1];
            augmented = deepmib.augmentInstanceData2D(patch, augOpt);
            idsBefore = unique(patch{2}(patch{2} > 0));
            idsAfter = unique(augmented{2}(augmented{2} > 0));
            testCase.verifyTrue(all(ismember(idsAfter, idsBefore)), 'nearest interpolation keeps the ids');
            testCase.verifyEqual(augmented{3}, patch{3});
        end

        function unknownPretrainedModelIsRefused(testCase)
            testCase.verifyError(@() deepmib.stardist.loadPretrained('2D_versatile_he', tempdir), ...
                'stardist:loadPretrained:unknownModel');
        end
    end

    methods (Access = private)
        function method = mexMethodIfBuilt(~, name)
            % the method name when stardistMex is on the path, otherwise empty (skipped in loops)
            if exist('stardistMex', 'file') == 3
                method = name;
            else
                method = string.empty;
            end
        end
    end

    methods (Static, Access = private)
        function labelMap = randomLabelMap(height, width, seed)
            % touching blobs: a coarse random id grid enlarged with nearest interpolation
            randomStream = RandStream('mt19937ar', 'Seed', seed);
            coarse = uint16(randi(randomStream, [0 12], ceil(height / 12), ceil(width / 12)));
            labelMap = imresize(coarse, [height width], 'nearest');
        end
    end
end
