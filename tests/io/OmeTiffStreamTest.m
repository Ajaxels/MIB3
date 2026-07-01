classdef OmeTiffStreamTest < matlab.unittest.TestCase
% OMETIFFSTREAMTEST - Round-trip tests for io.savers.OmeTiffSaver.saveStream.
%
% OmeTiffSaver.saveStream writes an OME-TIFF straight from a SliceProvider,
% pulling one Z-slice at a time so a large pyramid level is never gathered
% whole. These tests characterise the OUTPUT contract that streaming must
% preserve: the streamed file is pixel-exact and has the expected plane
% count, identical to a non-streaming save of the same data.
%
% The pixSize carries the long unit spelling 'micrometers' (as zarr/BigData
% datasets do) — exercising utils.normalizeUnits end-to-end through
% io.BioFormats.mibImage2ometiff, which previously errored on it.
%
% Tagged Integration: OME-TIFF writing needs the Bio-Formats Java library.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Static)
        function [data, meta] = makeData()
            % Distinct-valued grayscale volume [H W D C T] with several Z slices.
            H = 8; W = 6; D = 5;
            data = reshape(uint8(mod(0:H*W*D-1, 251) + 1), [H W D 1 1]);
            meta = struct();
            meta.filename   = 'synthetic.tif';
            meta.colorType  = 'grayscale';
            meta.lutColors  = [1 1 1];
            meta.dataClass  = 'uint8';
            meta.maxInt     = 255;
            meta.pixSize    = struct('x',0.5,'y',0.5,'z',0.7, ...
                'units','micrometers','t',1,'tunits','s');
            meta.imageDescription = '';
        end

        function vol = readOmeTiffPlanes(file)
            % Read all TIFF planes (pixels only) into [H W nPlanes].
            info = imfinfo(file);
            nP   = numel(info);
            vol  = zeros(info(1).Height, info(1).Width, nP, 'uint8');
            for k = 1:nP
                vol(:, :, k) = imread(file, k);
            end
        end
    end

    methods (Test, TestTags = {'Integration'})

        function saveStream_5d_pixelRoundtrip(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'stack.ome.tiff');
            [data, meta] = OmeTiffStreamTest.makeData();

            provider = io.savers.InMemorySliceProvider(data);
            saver    = io.savers.OmeTiffSaver(struct());
            opts = struct('Format','OME-TIFF 5D (*.ome.tiff)', ...
                'silent',true, 'showWaitbar',false, 'overwrite',true, 'layerType','image');

            fnOut = saver.saveStream(provider, meta, outFile, opts);

            testCase.verifyTrue(isfile(fnOut), 'saveStream must write the .ome.tiff file');
            back = OmeTiffStreamTest.readOmeTiffPlanes(fnOut);
            testCase.verifyEqual(size(back, 3), 5, 'plane count must equal the Z depth');
            testCase.verifyEqual(back, squeeze(data), ...
                'streamed OME-TIFF planes must be pixel-exact with the source volume');
        end

        function saveStream_5d_matchesNonStreaming(testCase)
            % The streaming override must produce the same pixels as the
            % full-array save() path on identical input.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [data, meta] = OmeTiffStreamTest.makeData();

            streamFile = fullfile(tmpDir.Folder, 'stream.ome.tiff');
            gatherFile = fullfile(tmpDir.Folder, 'gather.ome.tiff');
            opts = struct('Format','OME-TIFF 5D (*.ome.tiff)', ...
                'silent',true, 'showWaitbar',false, 'overwrite',true, 'layerType','image');

            saver = io.savers.OmeTiffSaver(struct());
            saver.saveStream(io.savers.InMemorySliceProvider(data), meta, streamFile, opts);
            saver.save(data, meta, gatherFile, opts);

            streamVol = OmeTiffStreamTest.readOmeTiffPlanes(streamFile);
            gatherVol = OmeTiffStreamTest.readOmeTiffPlanes(gatherFile);
            testCase.verifyEqual(streamVol, gatherVol, ...
                'streamed and gathered OME-TIFF output must be identical');
        end

        function saveStream_5d_multichannel_roundtrip(testCase)
            % C>1 exercises the XYCZT plane ordering and per-channel saveBytes path.
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'mc.ome.tiff');
            H = 8; W = 6; D = 3; C = 2;
            data = reshape(uint16(1:H*W*D*C), [H W D C 1]);
            meta = struct('filename','mc.tif','colorType','multichannel', ...
                'dataClass','uint16','maxInt',65535, 'lutColors',[1 0 0; 0 1 0], ...
                'imageDescription','', 'pixSize', ...
                struct('x',0.5,'y',0.5,'z',0.7,'units','micrometers','t',1,'tunits','s'));

            saver = io.savers.OmeTiffSaver(struct());
            opts = struct('Format','OME-TIFF 5D (*.ome.tiff)', ...
                'silent',true, 'showWaitbar',false, 'overwrite',true, 'layerType','image');
            fnOut = saver.saveStream(io.savers.InMemorySliceProvider(data), meta, outFile, opts);

            % read back through Bio-Formats, mapping each plane by its Z/C label
            planes = bfopen(fnOut); planes = planes{1};
            back = zeros(H, W, D, C, 'uint16');
            for k = 1:size(planes, 1)
                z = str2double(regexp(planes{k,2}, 'Z=(\d+)', 'tokens', 'once'));
                c = str2double(regexp(planes{k,2}, 'C=(\d+)', 'tokens', 'once'));
                back(:, :, z, c) = planes{k, 1};
            end
            testCase.verifyEqual(back, squeeze(data), ...
                'multichannel streamed OME-TIFF must reconstruct pixel-exact');
        end

        function saveStream_2dSequence_pixelRoundtrip(testCase)
            tmpDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'seq.ome.tiff');
            [data, meta] = OmeTiffStreamTest.makeData();   % [8 6 5 1 1]

            provider = io.savers.InMemorySliceProvider(data);
            saver    = io.savers.OmeTiffSaver(struct());
            opts = struct('Format','OME-TIFF 2D sequence (*.ome.tiff)', ...
                'silent',true, 'showWaitbar',false, 'overwrite',true, 'layerType','image', ...
                'FilenameGenerator','Use sequential filename');

            fnOut = saver.saveStream(provider, meta, outFile, opts);

            testCase.verifyClass(fnOut, 'cell');
            testCase.verifyNumElements(fnOut, 5, 'one file per Z slice');
            for z = 1:5
                testCase.verifyTrue(isfile(fnOut{z}), 'each slice file must exist');
                plane = imread(fnOut{z});
                testCase.verifyEqual(plane, squeeze(data(:,:,z)), ...
                    sprintf('slice %d must be pixel-exact', z));
            end
        end

    end
end
