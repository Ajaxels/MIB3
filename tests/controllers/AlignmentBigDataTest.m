classdef AlignmentBigDataTest < matlab.unittest.TestCase
% ALIGNMENTBIGDATATEST - Integration tests for BigData alignment (controllers.Alignment).
%
% Exercises the full headless pipeline against a bare ``models.MibModel``:
% a synthetic pyramidal OME-Zarr v3 (BigData) dataset is written to a temporary
% folder, loaded, aligned via ``controllers.Alignment(model, [], BatchOpt)``, and
% the swapped-in aligned store is asserted. Covers drift correction (translation),
% feature-based v2 (affine), landmark modes, packed-63 label preservation,
% extended-vs-cropped canvas, metadata propagation, the no-model path, and the
% missing-output-path guard.
%
% All tests are headless and offline but write to disk and drive the controller +
% io savers/loaders, so they are tagged ``Integration``.
%
% See also: controllers.Alignment, io.savers.Zarr3Saver, core.MibBigDataLabels

    methods (TestClassSetup)
        function addPaths(testCase)
            % Ensure tests/ is on the path (so mibtest.* resolves) when this file
            % is run standalone; then apply the shared mib/ path fixture.
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function driftTranslationExtended(testCase)
            % Drift correction (extended) grows the canvas and swaps to BigData.
            [mibModel, ~, N, outPath] = testCase.buildBigData('shift');
            testCase.runAlign(mibModel, testCase.batch('Drift correction', 'extended', outPath));
            d = mibModel.I{1};
            testCase.verifyEqual(d.datasetType, 'BigData');
            testCase.verifyGreaterThan(d.image.height, N);
            testCase.verifyGreaterThan(d.image.width, N);
            testCase.verifyTrue(contains(d.image.filename, 'aligned'));
            testCase.verifyTrue(isfolder(outPath));
        end

        function driftCroppedKeepsCanvas(testCase)
            % Cropped mode keeps the original canvas dimensions.
            [mibModel, ~, N, outPath] = testCase.buildBigData('shift');
            testCase.runAlign(mibModel, testCase.batch('Drift correction', 'cropped', outPath));
            d = mibModel.I{1};
            testCase.verifyEqual(d.datasetType, 'BigData');
            testCase.verifyEqual([d.image.height, d.image.width], [N, N]);
        end

        function featureV2StraightensRotation(testCase)
            % Feature-based v2 (rigid) corrects an injected per-slice rotation.
            [mibModel, angles, N, outPath] = testCase.buildBigData('rotate'); %#ok<ASGLU>
            testCase.setSurfFriendlyOptions(mibModel);
            B = testCase.batch('Automatic feature-based v2', 'extended', outPath);
            B.TransformationType = {'rigid'};
            B.FeatureDetectorType = {'Blobs: Speeded-Up Robust Features (SURF) algorithm'};
            testCase.runAlign(mibModel, B);
            d = mibModel.I{1};
            testCase.verifyEqual(d.datasetType, 'BigData');
            testCase.verifyGreaterThan(d.image.height, N);
            residDeg = testCase.residualRotation(d, 1, d.image.depth);
            testCase.verifyLessThan(residDeg, 1.0);
        end

        function packed63BitsPreservedAcrossLevels(testCase)
            % Material + mask + selection survive the warp on every pyramid level.
            [mibModel, ~, N, outPath] = testCase.buildBigData('shift', 'withModel', true); %#ok<ASGLU>
            testCase.runAlign(mibModel, testCase.batch('Drift correction', 'extended', outPath));
            d = mibModel.I{1};
            testCase.verifyTrue(isa(d.labels, 'core.MibBigDataLabels') && d.labels.exists);
            testCase.verifyEqual(d.labels.height, d.image.height);
            testCase.verifyEqual(d.labels.width, d.image.width);
            nLevels = size(d.labels.modelLevelSizes, 1);
            paintSlice = 2;
            for L = 1:nLevels
                lbl = d.labels.getData63('labels', 3, [], struct('pyramidLevel', L, 'z', [paintSlice paintSlice]));
                msk = d.labels.getData63('mask', 3, [], struct('pyramidLevel', L, 'z', [paintSlice paintSlice]));
                sel = d.labels.getData63('selection', 3, [], struct('pyramidLevel', L, 'z', [paintSlice paintSlice]));
                testCase.verifyTrue(any(lbl(:) == 5), sprintf('material lost at level %d', L));
                testCase.verifyTrue(any(msk(:) == 1), sprintf('mask lost at level %d', L));
                testCase.verifyTrue(any(sel(:) == 1), sprintf('selection lost at level %d', L));
            end

            % Material names/colours must survive in-session AND on disk (the
            % aligned store is a NEW zarr3 — the mibMaterials attribute must be
            % written so reopening the file keeps names/colours, not just the
            % swapped in-memory object).
            testCase.verifyEqual(d.labels.materialNames(:), {'a';'b';'c';'d';'e'});
            [pdir, stem, ext] = fileparts(outPath);
            labStore = fullfile(pdir, ['Labels_' stem ext]);
            reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            reopened.openStore(labStore);
            testCase.verifyEqual(reopened.materialNames(:), {'a';'b';'c';'d';'e'}, ...
                'material names not persisted to the aligned labels store');
            testCase.verifyEqual(reopened.materialColors, lines(5), 'AbsTol', 1e-6, ...
                'material colours not persisted to the aligned labels store');
            reopened.closeStore();
        end

        function pyramidSettingsMatchSource(testCase)
            % The aligned store reproduces the SOURCE pyramid (level count + chunk
            % shape), not a hardcoded default.
            import matlab.unittest.fixtures.TemporaryFolderFixture
            tf = testCase.applyFixture(TemporaryFolderFixture);
            scratch = tf.Folder;
            N = 320; Z = 4;
            rng(9); base = uint8(255 * mat2gray(conv2(randn(N+40), ones(6), 'same')));
            dx = [0 8 16 5]; dy = [0 -6 4 10];
            vol = zeros(N, N, Z, 'uint8');
            for z = 1:Z; vol(:,:,z) = imtranslate(base(21:20+N, 21:20+N), [dx(z) dy(z)]); end
            srcImg = fullfile(scratch, 'src.zarr3');
            meta = struct('pixSize', struct('x', 0.02, 'y', 0.02, 'z', 0.05, 'units', 'um'));
            % distinctive pyramid: chunk [64 64 2], exactly 3 levels, XY-only
            io.savers.Zarr3Saver(struct()).save(reshape(vol, N, N, Z, 1, 1), meta, srcImg, ...
                struct('silent', true, 'showWaitbar', false, ...
                       'ChunkSize', [64 64 2], 'Levels', 3, 'DownsampleStrategy', 'XY only'));

            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder);
            lo = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(lo);
            [imgInfo, files] = loader.loadMetadata({srcImg}, lo);
            [imgRaw, imgInfo] = loader.loadImages(files, imgInfo, lo);
            mibModel.I{1}.initialize(imgRaw, imgInfo, 'BigData');
            mibModel.I{1}.enableSelection = true;
            srcLevels = size(mibModel.I{1}.image.pyramid.levelImageSizes, 1);
            srcChunk  = mibModel.I{1}.image.pyramid.chunkSizes{1};

            outPath = fullfile(scratch, 'aligned.zarr3');
            testCase.runAlign(mibModel, testCase.batch('Drift correction', 'extended', outPath));
            op = mibModel.I{1}.image.pyramid;
            testCase.verifyEqual(size(op.levelImageSizes, 1), srcLevels, ...
                'aligned store level count must match the source');
            testCase.verifyEqual(op.chunkSizes{1}, srcChunk, ...
                'aligned store chunk shape must match the source');
        end

        function boundingBoxAndPixSizePropagate(testCase)
            % pixSize survives; the new store has a bounding box set.
            [mibModel, ~, ~, outPath] = testCase.buildBigData('shift');
            srcPix = mibModel.I{1}.image.pixSize;
            testCase.runAlign(mibModel, testCase.batch('Drift correction', 'extended', outPath));
            d = mibModel.I{1};
            testCase.verifyEqual(d.image.pixSize.x, srcPix.x, 'RelTol', 1e-6);
            testCase.verifyEqual(d.image.pixSize.y, srcPix.y, 'RelTol', 1e-6);
            testCase.verifyNumElements(d.image.boundingBox, 6);
            testCase.verifyGreaterThanOrEqual(d.image.boundingBox(2), d.image.boundingBox(1));
        end

        function noModelPathImageOnly(testCase)
            % A dataset with no model aligns image-only (no labels store created).
            [mibModel, ~, N, outPath] = testCase.buildBigData('shift', 'withModel', false); %#ok<ASGLU>
            testCase.runAlign(mibModel, testCase.batch('Drift correction', 'extended', outPath));
            d = mibModel.I{1};
            testCase.verifyEqual(d.datasetType, 'BigData');
            testCase.verifyFalse(d.modelExist);
            [pdir, stem, ext] = fileparts(outPath);
            testCase.verifyFalse(isfolder(fullfile(pdir, ['Labels_' stem ext])));
        end

        function landmarkSingleTranslation(testCase)
            % Single-landmark (annotation) translation aligns a tracked model blob.
            [mibModel, info, N, outPath] = testCase.buildBigData('shift', 'withModel', true, 'annotateSingle', true); %#ok<ASGLU>
            testCase.runAlign(mibModel, testCase.batch('Single landmark point', 'extended', outPath));
            d = mibModel.I{1};
            testCase.verifyEqual(d.datasetType, 'BigData');
            cents = zeros(d.image.depth, 2);
            for z = 1:d.image.depth
                lbl = d.labels.getData63('labels', 3, [], struct('pyramidLevel', 1, 'z', [z z]));
                st = regionprops(lbl == 5, 'Centroid');
                testCase.assertNotEmpty(st, sprintf('blob missing on slice %d', z));
                cents(z, :) = st(1).Centroid;
            end
            testCase.verifyLessThan(max(std(cents, 0, 1)), 2.0);
            % extended mode grows the canvas to fit the shifted slices
            testCase.verifyGreaterThan(d.image.width, N);
        end

        function landmarkSingleCroppedKeepsCanvas(testCase)
            % Single-landmark honours TransformationMode: cropped keeps the original
            % canvas (extended grows it — see landmarkSingleTranslation).
            [mibModel, ~, N, outPath] = testCase.buildBigData('shift', 'annotateSingle', true);
            testCase.runAlign(mibModel, testCase.batch('Single landmark point', 'cropped', outPath));
            d = mibModel.I{1};
            testCase.verifyEqual(d.datasetType, 'BigData');
            testCase.verifyEqual([d.image.height, d.image.width], [N, N]);
        end

        function landmarkMultiAffine(testCase)
            % Multi-point (annotation) affine straightens an injected rotation.
            [mibModel, ~, N, outPath] = testCase.buildBigData('rotate', 'annotateMulti', true); %#ok<ASGLU>
            B = testCase.batch('Landmarks, multi points', 'extended', outPath);
            B.TransformationType = {'affine'};
            testCase.runAlign(mibModel, B);
            d = mibModel.I{1};
            testCase.verifyEqual(d.datasetType, 'BigData');
            residDeg = testCase.residualRotation(d, 1, d.image.depth);
            testCase.verifyLessThan(residDeg, 1.0);
        end

        function driftSaveShiftsWritesLevel0File(testCase)
            % SaveShiftsToFile writes a .coefXY of LEVEL-0 shifts. The saved shifts
            % must directly predict the (level-0) grown canvas — if they were the
            % raw level-L analysis shifts, or double-scaled on the applied side, the
            % predicted canvas would not match. This locks save/load as level-0 so a
            % file saved here replays correctly on another dataset via loadShiftsCheck.
            [mibModel, ~, N, outPath] = testCase.buildBigData('shift');
            B = testCase.batch('Drift correction', 'extended', outPath);
            B.SaveShiftsToFile = true;
            testCase.runAlign(mibModel, B);
            d = mibModel.I{1};

            coefFile = fullfile(fileparts(outPath), 'src_align.coefXY');
            testCase.verifyTrue(isfile(coefFile), 'SaveShiftsToFile did not write a .coefXY file');
            S = load(coefFile, '-mat');
            testCase.verifyTrue(isfield(S, 'shiftsX') && isfield(S, 'shiftsY'), ...
                'saved file lacks shiftsX / shiftsY');
            sx = round(S.shiftsX(:));   sy = round(S.shiftsY(:));
            testCase.verifyEqual(numel(sx), d.image.depth, 'one shift per slice expected');
            % extended canvas growth from the LEVEL-0 shift extremes
            testCase.verifyEqual(d.image.width,  N + (abs(min(sx)) + max(sx)));
            testCase.verifyEqual(d.image.height, N + (abs(min(sy)) + max(sy)));
        end

        function featureV2SaveShiftsWritesStruct(testCase)
            % Feature-based v2 SaveShiftsToFile writes the level-0 alignment struct
            % (cumulativeTforms + decomposed params) so it can be replayed via
            % loadShiftsCheck. Previously the v2 BigData path never saved anything.
            [mibModel, ~, ~, outPath] = testCase.buildBigData('rotate');
            testCase.setSurfFriendlyOptions(mibModel);
            B = testCase.batch('Automatic feature-based v2', 'extended', outPath);
            B.TransformationType = {'rigid'};
            B.FeatureDetectorType = {'Blobs: Speeded-Up Robust Features (SURF) algorithm'};
            B.SaveShiftsToFile = true;
            testCase.runAlign(mibModel, B);

            coefFile = fullfile(fileparts(outPath), 'src_align.coefXY');
            testCase.verifyTrue(isfile(coefFile), 'v2 SaveShiftsToFile did not write a file');
            S = load(coefFile, '-mat');
            testCase.verifyTrue(isfield(S, 'cumulativeTforms'), 'v2 saved file lacks cumulativeTforms');
            testCase.verifyEqual(numel(S.cumulativeTforms), mibModel.I{1}.image.depth);
            testCase.verifyClass(S.cumulativeTforms{1}, 'affinetform2d');
        end

        function missingOutputPathAborts(testCase)
            % Empty BigData_OutputPath aborts without swapping the buffer.
            [mibModel, ~, N, ~] = testCase.buildBigData('shift');
            B = testCase.batch('Drift correction', 'extended', '');   % empty output path
            testCase.runAlign(mibModel, B);
            d = mibModel.I{1};
            % Unchanged: still original canvas, still pointing at the source store.
            testCase.verifyEqual([d.image.height, d.image.width], [N, N]);
            testCase.verifyFalse(contains(d.image.filename, 'aligned'));
        end

    end

    % =====================================================================
    methods (Access = private)

        function [mibModel, info, N, outPath] = buildBigData(testCase, mode, opts)
            % Build a fresh headless MibModel with a synthetic BigData dataset.
            arguments
                testCase
                mode (1,:) char                    % 'shift' | 'rotate'
                opts.withModel (1,1) logical = false
                opts.annotateSingle (1,1) logical = false
                opts.annotateMulti (1,1) logical = false
            end
            import matlab.unittest.fixtures.TemporaryFolderFixture
            tf = testCase.applyFixture(TemporaryFolderFixture);
            scratch = tf.Folder;
            srcImg  = fullfile(scratch, 'src.zarr3');
            srcLab  = fullfile(scratch, 'Labels_src.zarr3');
            outPath = fullfile(scratch, 'src_aligned.zarr3');

            N = 300; Z = 4;
            base = testCase.surfFriendlyBase(N);
            info = struct();
            vol = zeros(N, N, Z, 'uint8');
            if strcmp(mode, 'rotate')
                angles = [0 3 6 9];
                for z = 1:Z; vol(:,:,z) = imrotate(base, angles(z), 'bicubic', 'crop'); end
                info.angles = angles;
            else
                dx = [0 6 11 5]; dy = [0 -5 -9 -4];
                for z = 1:Z; vol(:,:,z) = circshift(base, [dy(z) dx(z)]); end
                info.dx = dx; info.dy = dy; info.fx = 150; info.fy = 150;
            end

            meta = struct('pixSize', struct('x', 0.02, 'y', 0.02, 'z', 0.05, 'units', 'um'));
            io.savers.Zarr3Saver(struct()).save(reshape(vol, N, N, Z, 1, 1), meta, srcImg, ...
                struct('silent', true, 'showWaitbar', false));

            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder);
            lo = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(lo);
            [imgInfo, files] = loader.loadMetadata({srcImg}, lo);
            [imgRaw, imgInfo] = loader.loadImages(files, imgInfo, lo);
            mibModel.I{1}.initialize(imgRaw, imgInfo, 'BigData');
            mibModel.I{1}.enableSelection = true;

            if opts.withModel
                lb = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
                lb.createStore([N N Z], srcLab, mibModel.I{1}.image.pyramid);
                for z = 1:Z
                    packed = zeros(N, N, 'uint8');
                    if strcmp(mode, 'rotate')
                        cx = 150; cy = 150;
                    else
                        cx = info.fx + info.dx(z); cy = info.fy + info.dy(z);
                    end
                    rr = max(1,cy-9):min(N,cy+9); cc = max(1,cx-9):min(N,cx+9);
                    packed(rr, cc) = 5;                                 % material 5
                    packed(rr, cc) = bitset(packed(rr, cc), 7);         % mask
                    packed(rr, cc) = bitset(packed(rr, cc), 8);         % selection
                    lb.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1, 'z', [z z]));
                end
                lb.materializeAll(); lb.filename = srcLab;
                lb.materialNames = {'a';'b';'c';'d';'e'}; lb.materialColors = lines(5); lb.materialsCount = 5;
                mibModel.I{1}.labels = lb; mibModel.I{1}.modelExist = true;
            end

            if opts.annotateSingle
                aText = arrayfun(@(z) 'p1', (1:Z)', 'UniformOutput', false);
                aPos = [(1:Z)', (info.fx + info.dx(:)), (info.fy + info.dy(:)), ones(Z,1)];
                mibModel.I{1}.annotations.replaceLabels(aText, aPos, ones(Z,1));
            end
            if opts.annotateMulti
                cen = [N/2 N/2]; P = [100 110; 220 120; 150 230]; labs = {'q1';'q2';'q3'};
                aText = {}; aPos = [];
                for z = 1:Z
                    th = deg2rad(-info.angles(z)); R = [cos(th) -sin(th); sin(th) cos(th)];
                    Pk = (R*(P - cen)')' + cen;
                    for i = 1:3
                        aText{end+1,1} = labs{i}; %#ok<AGROW>
                        aPos(end+1,:) = [z, Pk(i,1), Pk(i,2), 1]; %#ok<AGROW>
                    end
                end
                mibModel.I{1}.annotations.replaceLabels(aText, aPos, ones(size(aPos,1),1));
            end
        end

        function base = surfFriendlyBase(~, N)
            % Textured base with sharp squares -> reliable SURF/blob features.
            rng(17); [xx,yy] = meshgrid(1:N,1:N); base = zeros(N,N);
            for k = 1:35; cx=randi(N); cy=randi(N); s=10+randi(18); base=base+0.6*exp(-((xx-cx).^2+(yy-cy).^2)/(2*s^2)); end
            for k = 1:110; s=3+randi(6); r=randi(N-s); c=randi(N-s); base(r:r+s,c:c+s)=0.4+0.6*rand; end
            base = uint8(255*mat2gray(base));
        end

        function runAlign(~, mibModel, BatchOpt)
            controllers.Alignment(mibModel, [], BatchOpt);
        end

        function B = batch(~, algorithm, mode, outPath)
            B = struct();
            B.Algorithm            = {algorithm};
            B.TransformationMode   = {mode};
            B.BigData_PyramidLevel = {'<auto>'};
            B.BigData_OutputPath   = outPath;
            B.showWaitbar          = false;
            B.SaveShiftsToFile     = false;
        end

        function setSurfFriendlyOptions(~, mibModel)
            % Force full-res, rotation-invariant analysis for reliable matching.
            o = struct();
            o.imgWidthForAnalysis = 80;
            o.imgDownsamplingFactorForAnalysis = 1;
            o.rotationInvariance = false;
            o.detectSURFFeatures = struct('MetricThreshold', 200, 'NumOctaves', 3, 'NumScaleLevels', 4);
            o.detectSIFTFeatures = struct('ContrastThreshold', 0.0133, 'EdgeThreshold', 10, 'NumLayersInOctave', 3, 'Sigma', 1.6);
            o.detectMSERFeatures = struct('ThresholdDelta', 2, 'RegionAreaRange', [30 14000], 'MaxAreaVariation', 0.25);
            o.detectHarrisFeatures = struct('MinQuality', 0.01, 'FilterSize', 5);
            o.detectBRISKFeatures = struct('MinContrast', 0.2, 'MinQuality', 0.1, 'NumOctaves', 4);
            o.detectFASTFeatures = struct('MinQuality', 0.1, 'MinContrast', 0.2);
            o.detectMinEigenFeatures = struct('MinQuality', 0.01, 'FilterSize', 5);
            o.detectORBFeatures = struct('ScaleFactor', 1.2, 'NumLevels', 8);
            o.amst = struct('PyramidLevels', 1, 'MaximumIterations', 100, 'GradientMagnitudeTolerance', 0.0001, 'MinimumStepLength', 0.0001, 'MaximumStepLength', 0.0625, 'RelaxationFactor', 0.5);
            o.estGeomTransform = struct('MaxNumTrials', 1000, 'Confidence', 99, 'MaxDistance', 1.5);
            mibModel.sessionSettings.automaticAlignmentOptions = o;
        end

        function residDeg = residualRotation(~, d, s1, s2)
            % Residual rotation (deg) between two aligned slices via SURF matching.
            J1 = squeeze(d.image.getData('image', 3, 1, struct('pyramidLevel', 1, 'z', [s1 s1])));
            J2 = squeeze(d.image.getData('image', 3, 1, struct('pyramidLevel', 1, 'z', [s2 s2])));
            p1 = detectSURFFeatures(J1); p2 = detectSURFFeatures(J2);
            [f1, v1] = extractFeatures(J1, p1); [f2, v2] = extractFeatures(J2, p2);
            ip = matchFeatures(f1, f2);
            residDeg = NaN;
            if size(ip, 1) >= 3
                tf = estgeotform2d(v2(ip(:,2)), v1(ip(:,1)), 'rigid', 'MaxDistance', 2);
                residDeg = abs(atan2d(tf.A(2,1), tf.A(1,1)));
            end
        end
    end
end
