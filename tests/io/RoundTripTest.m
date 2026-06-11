classdef RoundTripTest < matlab.unittest.TestCase
% ROUNDTRIPTEST - Save → load round-trip correctness for MIB3 IO formats.
%
% Each test method:
%  1. Creates a small synthetic dataset
%  2. Saves it to a TemporaryFolderFixture directory via SaverFactory
%  3. Loads it back via LoaderFactory / loadImagesWrapper
%  4. Asserts the round-tripped array is identical to the original
%
% All tests are tagged Unit (fast, offline, headless).
%
% Notes on format coverage:
%   AmiraMesh — full round-trip via loadImagesWrapper (AmiraMeshLoader is headless-safe).
%   HDF5      — write verified via h5read; HDF5NoHeaderLoader requires interactive
%               dataset selection (SelectHDFSeries dialog) and cannot be used headlessly.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    % =====================================================================
    % Image round-trips
    % =====================================================================
    methods (Test, TestTags = {'Unit'})

        function amiraMeshImageRoundtrip(testCase)
            tempFolder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'image.am');

            rng(5, 'twister');
            data = uint8(randi(255, [32 32 6 1 1]));

            saver = io.SaverFactory.create('Amira Mesh binary (*.am)');
            opts  = RoundTripTest.amiraMeshSaveOpts('image');
            meta  = RoundTripTest.makeImageMeta(data);
            saver.save(data, meta, outFile, opts);

            loaded = io.loadImagesWrapper(outFile);
            testCase.verifyEqual(squeeze(loaded), squeeze(data));
        end

        function hdf5ImageRoundtrip(testCase)
            % HDF5NoHeaderLoader requires interactive dataset selection via SelectHDFSeries,
            % so we verify the write side with h5read directly (dataset path = /image from baseName).
            tempFolder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'image.h5');

            rng(6, 'twister');
            data = uint8(randi(255, [8 8 4 1 1]));

            saver = io.SaverFactory.create('Hierarchical Data Format (*.h5)');
            opts  = RoundTripTest.hdf5SaveOpts();
            meta  = RoundTripTest.makeImageMeta(data);
            saver.save(data, meta, outFile, opts);

            loaded = h5read(outFile, '/image');   % dataset path = '/' + baseName
            testCase.verifyEqual(squeeze(loaded), squeeze(data));
        end

        function tifImageRoundtrip(testCase)
            tempFolder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'image.tif');

            rng(0, 'twister');
            data = uint8(randi(255, [32 32 6 1 1]));

            saver = io.SaverFactory.create('TIF format uncompressed (*.tif)');
            opts  = RoundTripTest.imageSaveOpts('TIF format uncompressed (*.tif)');
            saver.save(data, RoundTripTest.makeImageMeta(data), outFile, opts);

            loaded = io.loadImagesWrapper(outFile);
            testCase.verifyEqual(loaded, data);
        end

        function tifImageLzwRoundtrip(testCase)
            tempFolder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'image_lzw.tif');

            rng(1, 'twister');
            data = uint8(randi(255, [32 32 6 1 1]));

            saver = io.SaverFactory.create('TIF format LZW compression (*.tif)');
            opts  = RoundTripTest.imageSaveOpts('TIF format LZW compression (*.tif)');
            opts.Compression = 'lzw';
            saver.save(data, RoundTripTest.makeImageMeta(data), outFile, opts);

            loaded = io.loadImagesWrapper(outFile);
            testCase.verifyEqual(loaded, data);
        end

        function nrrdImageRoundtrip(testCase)
            tempFolder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'image.nrrd');

            rng(2, 'twister');
            data = uint8(randi(255, [32 32 6 1 1]));

            saver = io.SaverFactory.create('NRRD Data Format (*.nrrd)');
            opts  = RoundTripTest.nrrdSaveOpts('image');
            meta  = RoundTripTest.makeImageMeta(data);
            saver.save(data, meta, outFile, opts);

            loaded = io.loadImagesWrapper(outFile);
            testCase.verifyEqual(squeeze(loaded), squeeze(data));
        end

    end

    % =====================================================================
    % Labels (segmentation model) round-trips
    % =====================================================================
    methods (Test, TestTags = {'Unit'})

        function matlabModelRoundtrip(testCase)
            tempFolder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'Labels_test.model');

            rng(3, 'twister');
            labels = uint8(randi([0 3], [32 32 6 1 1]));

            saver = io.SaverFactory.create('Matlab format (*.model)');
            opts  = RoundTripTest.modelSaveOpts('Matlab format (*.model)');
            meta  = RoundTripTest.makeModelMeta(labels, 3);
            saver.save(labels, meta, outFile, opts);

            loader = io.loaders.MatModelLoader();
            [~, files] = loader.loadMetadata({outFile});
            loaded = files(1).data;   % raw array cached in loadMetadata

            testCase.verifyEqual(squeeze(loaded), squeeze(labels));
        end

        function matlabMaskRoundtrip(testCase)
            tempFolder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tempFolder.Folder, 'mask.mask');

            rng(4, 'twister');
            mask = uint8(rand([32 32 6 1 1]) > 0.5);

            saver = io.SaverFactory.create('Matlab format (*.mask)');
            opts.Format      = 'Matlab format (*.mask)';
            opts.showWaitbar = false;
            opts.silent      = true;
            opts.overwrite   = true;
            meta = RoundTripTest.makeImageMeta(mask);
            saver.save(mask, meta, outFile, opts);

            loaded = load(outFile, '-mat', 'maskImg');   % -mat: force MAT-file despite .mask ext
            testCase.verifyEqual(uint8(loaded.maskImg), squeeze(mask));
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function meta = makeImageMeta(data)
            meta.filename  = 'synthetic.tif';
            meta.colorType = 'grayscale';
            meta.lutColors = [1 1 1];
            meta.dataClass = class(data);
            meta.maxInt    = double(intmax(class(data)));
            meta.sliceName = {};
            meta.pixSize   = struct('x',1,'y',1,'z',1,'units','um','t',1,'tunits','s');
            meta.boundingBox = zeros(1,6);
            meta.imageDescription = '';
        end

        function meta = makeModelMeta(labels, numMaterials)
            colors = lines(numMaterials);
            names  = arrayfun(@(k) sprintf('Material%d', k), 1:numMaterials, ...
                'UniformOutput', false);
            meta.filename       = 'synthetic.tif';
            meta.materialNames  = names(:);
            meta.materialColors = colors;
            meta.labelsVariable = 'mibModel';
            meta.modelType      = 255;
            meta.dataClass      = class(labels);
            meta.pixSize        = struct('x',1,'y',1,'z',1,'units','um','t',1,'tunits','s');
            meta.boundingBox    = zeros(1,6);
        end

        function opts = imageSaveOpts(formatStr)
            opts.Format            = formatStr;
            opts.Saving3DPolicy    = '3D stack';
            opts.Compression       = 'none';
            opts.showWaitbar       = false;
            opts.silent            = true;
            opts.overwrite         = true;
            opts.FilenameGenerator = 'Use sequential filename';
        end

        function opts = amiraMeshSaveOpts(layerType)
            opts.Format      = 'Amira Mesh binary (*.am)';
            opts.layerType   = layerType;
            opts.showWaitbar = false;
            opts.silent      = true;
            opts.overwrite   = true;
        end

        function opts = hdf5SaveOpts()
            opts.Format      = 'Hierarchical Data Format (*.h5)';
            opts.layerType   = 'image';
            opts.showWaitbar = false;
            opts.silent      = true;
            opts.overwrite   = true;
        end

        function opts = nrrdSaveOpts(layerType)
            opts.Format            = 'NRRD Data Format (*.nrrd)';
            opts.layerType         = layerType;
            opts.showWaitbar       = false;
            opts.silent            = true;
            opts.overwrite         = true;
            opts.FilenameGenerator = 'Use sequential filename';
        end

        function opts = modelSaveOpts(formatStr)
            opts.Format      = formatStr;
            opts.showWaitbar = false;
            opts.silent      = true;
            opts.overwrite   = true;
        end

    end
end
