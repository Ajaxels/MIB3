classdef IsotropicLevelBigDataTest < matlab.unittest.TestCase
% ISOTROPICLEVELBIGDATATEST - a store with the isotropic level opens as BigData and carries a model.
%
% Step 7 of development/bigdata/isotropic_hr_level.md. A 5x5x13 nm store (XY factors 1, 2, 2.6,
% 5.2, 10.4; Z factors 1, 1, 1, 2, 4) is written by Zarr3Saver, opened through
% controllers.BigDataOptions.openStoreInBuffer, and a model store is created from its pyramid:
% the factors must survive the metadata round trip as 2.6 and not 2.5999999999999996, and the
% model needs a tile of whole pixels of every level (52 x 52 x 4 voxels).

    properties (Access = private)
        OrigZarrLib
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function forceNativeBackend(testCase)
            testCase.OrigZarrLib = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');
        end
    end

    methods (TestMethodTeardown)
        function restoreBackend(testCase)
            io.zarr.Config.setLibrary(testCase.OrigZarrLib);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function nonIntegerPyramidOpensAndCarriesAModel(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            volume = uint8(randi(255, 260, 260, 9));
            sourcePath = fullfile(folder, 'source.zarr3');
            metadata = struct('pixSize', struct('x', 0.005, 'y', 0.005, 'z', 0.013, 'units', 'um'));
            io.savers.Zarr3Saver(struct()).save(volume, metadata, sourcePath, struct('silent', true, ...
                'showWaitbar', false, 'ChunkSize', [64 64 1], 'MinLevelSize', 16, ...
                'DownsampleStrategy', 'Anisotropy-preserving + isotropic level'));

            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            controllers.BigDataOptions.openStoreInBuffer(mibModel, sourcePath, 1);
            dataset = mibModel.I{1};

            pyramid = dataset.image.pyramid;
            testCase.verifyEqual(pyramid.levelScaleFactors(:, 1)', [1 2 2.6 5.2 10.4]);
            testCase.verifyEqual(pyramid.levelScaleFactors(:, 3)', [1 1 1 2 4]);
            testCase.verifyEqual(pyramid.levelImageSizes(:, 1)', ceil(260 ./ [1 2 2.6 5.2 10.4]));

            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.createStore([dataset.image.height dataset.image.width dataset.image.depth], ...
                fullfile(folder, 'Labels_source.zarr3'), pyramid);
            testCase.addTeardown(@() labels.closeStore());
            testCase.verifyEqual(labels.tileSize, [52 52 4]);
            testCase.verifyEqual(size(labels.matLevel), [5 5 3 3]);
        end

    end
end
