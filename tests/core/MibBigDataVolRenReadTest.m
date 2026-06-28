classdef MibBigDataVolRenReadTest < matlab.unittest.TestCase
% MIBBIGDATAVOLRENREADTEST - Integration tests for the BigData read seam used by VolRenApp.
%
% Validates the two contracts that VolRenApp relies on when rendering BigData volumes:
%
%   1. core.MibBigDataImage.getData with options.pyramidLevel returns a spatial
%      array whose dimensions match pyramid.levelImageSizes(L, :) for every tested level L.
%   2. core.MibBigDataLabels.getData63 with options.pyramidLevel returns data whose
%      spatial dimensions also match pyramid.levelImageSizes(L, :).
%   3. pyramid.levelScaleFactors correctly describes coarser voxel spacing at higher
%      level indices, confirming the pixSize-scaling logic in VolRenApp.grabVolume.
%
% Requires CMU-1.ndpi at C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi.
% Tagged Integration — all tests skip automatically when the file is absent.
%
% Note: labels tests use a zero-initialised in-memory store (createStore).
% The store is built once per test method (TestMethodSetup) and cleaned up
% afterwards; the expensive image-reader object (io_) is built once per class
% in TestClassSetup because BioFormats loading takes several seconds.

    properties (Access = private)
        ImageObj        % core.MibBigDataImage — shared across test methods (read-only)
        LabelsObj       % core.MibBigDataLabels — fresh per test method
        LabelsStorePath % char — path of the temp zarr3 labels store (per method)
    end

    methods (TestClassSetup)
        function addPathsAndBuildImage(testCase)
            % Add mib/ and tests/ to path, then build the shared image reader.
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);

            ndpiFile = 'C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi';
            testCase.assumeTrue(isfile(ndpiFile), ...
                'CMU-1.ndpi not found at expected path — skipping BigData VolRen read tests');

            % Mirror the §7 shared MCP setup helper from bigdata_implementation_plan.md
            io.BioFormats.Config.setLibrary('mib');
            io.zarr.Config.setSmoothing(false);

            repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            mibPath  = fullfile(repoRoot, 'mib');

            loadOptions = struct('datasetMode', 'BigData', 'readerFamily', 'BioFormats', ...
                'silentMode', true, 'ParentFigure', [], 'mibPath', mibPath);
            loader = io.loaders.BioFormatsVirtualSetupLoader(loadOptions);
            [metadata, fileList] = loader.loadMetadata({ndpiFile}, loadOptions);
            [imageData, metadata] = loader.loadImages(fileList, metadata, loadOptions);
            testCase.ImageObj = core.MibBigDataImage(imageData, metadata);
        end
    end

    methods (TestMethodSetup)
        function buildLabelsStore(testCase)
            % Skip if image object was not created (file absent).
            testCase.assumeNotEmpty(testCase.ImageObj, ...
                'ImageObj is empty — image file was absent, skipping labels setup');

            storePath = [tempname '_volren_readtest.zarr3'];
            if isfolder(storePath); rmdir(storePath, 's'); end
            levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
            if isfile(levelMapPath); delete(levelMapPath); end

            imageObj = testCase.ImageObj;
            baseMeta = core.MibImage.initializeImgInfo( ...
                'Height', imageObj.height, ...
                'Width',  imageObj.width, ...
                'Depth',  imageObj.depth, ...
                'Time',   imageObj.time, ...
                'Colors', 1);
            labelsObj = core.MibBigDataLabels([], baseMeta);
            labelsObj.createStore([imageObj.height, imageObj.width, imageObj.depth], ...
                storePath, imageObj.pyramid);

            testCase.LabelsObj = labelsObj;
            testCase.LabelsStorePath = storePath;
        end
    end

    methods (TestMethodTeardown)
        function cleanupLabelsStore(testCase)
            if ~isempty(testCase.LabelsObj) && isvalid(testCase.LabelsObj)
                try testCase.LabelsObj.closeStore(); catch; end %#ok<CTCH>
            end
            storePath = testCase.LabelsStorePath;
            if ~isempty(storePath)
                if isfolder(storePath); rmdir(storePath, 's'); end
                levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
                if isfile(levelMapPath); delete(levelMapPath); end
            end
        end
    end

    methods (Test, TestTags = {'Integration'})

        function testImageReadDimsAtCoarseLevels(testCase)
            % VolRenApp calls getData3D with options.pyramidLevel for BigData images.
            % Verify that the returned spatial dims match levelImageSizes for coarse levels.
            % (Level 1 = full resolution is skipped to avoid out-of-memory on a WSI.)
            imageObj = testCase.ImageObj;
            levelSizes = imageObj.pyramid.levelImageSizes;   % [N x 3] [Y X Z]
            noLevels   = size(levelSizes, 1);

            % Choose 3 coarse levels to test (no level 1 to stay within memory bounds)
            testLevels = unique([ ...
                noLevels, ...
                max(2, floor((noLevels + 2) / 2)), ...
                max(2, noLevels - 1)], 'stable');

            for testIdx = 1:numel(testLevels)
                levelNumber = testLevels(testIdx);
                getOptions  = struct('pyramidLevel', levelNumber, 't', [1 1]);
                result      = imageObj.getData('image', 3, [], getOptions);

                expectedY = levelSizes(levelNumber, 1);
                expectedX = levelSizes(levelNumber, 2);
                expectedZ = levelSizes(levelNumber, 3);

                testCase.verifyEqual(size(result, 1), expectedY, ...
                    sprintf('Level %d: Y (height) mismatch — expected %d, got %d', ...
                    levelNumber, expectedY, size(result, 1)));
                testCase.verifyEqual(size(result, 2), expectedX, ...
                    sprintf('Level %d: X (width) mismatch — expected %d, got %d', ...
                    levelNumber, expectedX, size(result, 2)));
                testCase.verifyEqual(size(result, 3), expectedZ, ...
                    sprintf('Level %d: Z (depth) mismatch — expected %d, got %d', ...
                    levelNumber, expectedZ, size(result, 3)));
                testCase.verifyEqual(size(result, 4), imageObj.colors, ...
                    sprintf('Level %d: color channel count mismatch — expected %d, got %d', ...
                    levelNumber, imageObj.colors, size(result, 4)));
            end
        end

        function testPixSizeScalingIncreasesWithLevel(testCase)
            % VolRenApp.grabVolume scales pixSize by levelScaleFactors(L,:) for BigData.
            % Verify: level 1 has unit scale factors; every coarser level has scaled
            % voxel sizes >= the full-resolution base; the coarsest level is strictly coarser.
            %
            % Note: for BioFormats-backed BigData, io_.pixSize is [] — the physical voxel
            % sizes at full resolution are stored in pyramid.levelVoxelSizes (index 1 = Y,
            % 2 = X, 3 = Z).  VolRenApp reads pixSize from mibModel.I{id}.image.pixSize
            % (a struct set during MibDataset assembly), but the scale-factor logic being
            % tested here is dataset-type-independent and fully verified via levelVoxelSizes.
            imageObj          = testCase.ImageObj;
            levelScaleFactors = imageObj.pyramid.levelScaleFactors;   % [N x 3] [yScale xScale zScale]
            levelVoxelSizes   = imageObj.pyramid.levelVoxelSizes;     % [Ysize Xsize Zsize] at full res
            noLevels          = size(levelScaleFactors, 1);
            baseYVoxel        = levelVoxelSizes(1);
            baseXVoxel        = levelVoxelSizes(2);

            % Level 1 must be the full-resolution reference with unit scale factors
            testCase.verifyEqual(levelScaleFactors(1, 1), 1, 'AbsTol', 1e-9, ...
                'Level 1 yScale must be 1 (full resolution)');
            testCase.verifyEqual(levelScaleFactors(1, 2), 1, 'AbsTol', 1e-9, ...
                'Level 1 xScale must be 1 (full resolution)');

            % Every coarser level must produce a voxel size at least as large as full res
            for levelNumber = 2:noLevels
                scaleFactor    = levelScaleFactors(levelNumber, :);
                scaledYVoxel   = baseYVoxel * scaleFactor(1);
                scaledXVoxel   = baseXVoxel * scaleFactor(2);

                testCase.verifyGreaterThanOrEqual(scaledYVoxel, baseYVoxel, ...
                    sprintf('Level %d: scaled Y voxel size must be >= full-res Y voxel size', levelNumber));
                testCase.verifyGreaterThanOrEqual(scaledXVoxel, baseXVoxel, ...
                    sprintf('Level %d: scaled X voxel size must be >= full-res X voxel size', levelNumber));
            end

            % The coarsest level must be strictly coarser than the finest in X and Y
            coarsestScale = levelScaleFactors(noLevels, :);
            testCase.verifyGreaterThan(coarsestScale(1), 1, ...
                'Coarsest level yScale must be > 1');
            testCase.verifyGreaterThan(coarsestScale(2), 1, ...
                'Coarsest level xScale must be > 1');
        end

        function testLabelsReadDimsAtPyramidLevel(testCase)
            % VolRenApp.modelUpdateOverlay calls getData3D with options.pyramidLevel for labels.
            % For the disk-backed labels store, getData63 with the same option must return
            % data with spatial dimensions matching levelImageSizes for the chosen level.
            %
            % The store is zero-initialised — this is a pure dimension check.
            % Level 1 is skipped (WSI full-resolution is too large to allocate labels for).
            imageObj   = testCase.ImageObj;
            labelsObj  = testCase.LabelsObj;
            levelSizes = imageObj.pyramid.levelImageSizes;   % [N x 3] [Y X Z]
            noLevels   = size(levelSizes, 1);

            testLevels = unique([noLevels, max(2, noLevels - 1)], 'stable');

            for testIdx = 1:numel(testLevels)
                levelNumber = testLevels(testIdx);
                getOptions  = struct('pyramidLevel', levelNumber, 't', [1 1]);
                result      = labelsObj.getData63('labels', 3, [], getOptions);

                expectedY = levelSizes(levelNumber, 1);
                expectedX = levelSizes(levelNumber, 2);

                testCase.verifyEqual(size(result, 1), expectedY, ...
                    sprintf('Labels level %d: Y (height) mismatch — expected %d, got %d', ...
                    levelNumber, expectedY, size(result, 1)));
                testCase.verifyEqual(size(result, 2), expectedX, ...
                    sprintf('Labels level %d: X (width) mismatch — expected %d, got %d', ...
                    levelNumber, expectedX, size(result, 2)));
            end
        end

    end
end
