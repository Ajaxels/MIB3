classdef CropToBigDataParallelTest < matlab.unittest.TestCase
% CROPTOBIGDATAPARALLELTEST - core.MibDataset.cropToBigData on the workers of a process pool.
%
% The image bands of a crop are read and written by the workers
% (``options.Pool``); the store must equal the one written on the client. Uses
% the open pool or starts one of 2 workers (closed again at the end), so it is
% slow; tagged Integration.
%
% See also: core.MibDataset.cropToBigData, utils.bigdata.startProcessPool

    properties
        Pool
        CreatedPool = false
    end

    methods (TestClassSetup)
        function addPathsAndPool(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            testCase.Pool = gcp('nocreate');
            if isempty(testCase.Pool)
                testCase.Pool = parpool('Processes', 2);
                testCase.CreatedPool = true;
            end
            wait(parfevalOnAll(testCase.Pool, @io.zarr.pinNativeLibrary, 0));
        end
    end

    methods (TestClassTeardown)
        function deletePool(testCase)
            if testCase.CreatedPool; delete(testCase.Pool); end
        end
    end

    methods (Test, TestTags = {'Integration'})
        function workersWriteTheClientCrop(testCase)
            folderFixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            scratch = folderFixture.Folder;
            rng(5);
            volume = uint8(randi(255, 400, 360, 6));
            sourcePath = fullfile(scratch, 'src.zarr3');
            meta = struct('pixSize', struct('x', 0.01, 'y', 0.01, 'z', 0.03, 'units', 'um'));
            io.savers.Zarr3Saver(struct()).save(volume, meta, sourcePath, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 2], 'Levels', 3, ...
                'DownsampleStrategy', 'XY only'));
            dataset = testCase.openDataset(sourcePath);

            cropF = [21 11 300 350 2 4];
            bandBytes = 8 * 300 * 64;     % several bands per slice
            result = dataset.cropToBigData(cropF, struct('outputPath', fullfile(scratch, 'workers.zarr3'), ...
                'showWaitbar', false, 'Pool', testCase.Pool, 'BandBytes', bandBytes));
            testCase.verifyEqual(result, 1);
            result = dataset.cropToBigData(cropF, struct('outputPath', fullfile(scratch, 'client.zarr3'), ...
                'showWaitbar', false, 'BandBytes', bandBytes));
            testCase.verifyEqual(result, 1);

            onWorkers = testCase.openDataset(fullfile(scratch, 'workers.zarr3')).image;
            onClient = testCase.openDataset(fullfile(scratch, 'client.zarr3')).image;
            for level = 1:size(onClient.pyramid.levelImageSizes, 1)
                testCase.verifyEqual(onWorkers.getData('image', 3, [], struct('pyramidLevel', level)), ...
                    onClient.getData('image', 3, [], struct('pyramidLevel', level)), sprintf('level %d', level));
            end
            level0 = onWorkers.getData('image', 3, [], struct('pyramidLevel', 1));
            testCase.verifyEqual(reshape(level0, 350, 300, 4), volume(11:360, 21:320, 2:5));
        end
    end

    methods (Access = private)
        function dataset = openDataset(~, storePath)
            % The store as the BigData dataset of a fresh headless MibModel
            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({storePath}, loaderOptions);
            [imageRaw, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            mibModel.I{1}.initialize(imageRaw, imageInfo, 'BigData');
            dataset = mibModel.I{1};
        end
    end
end
