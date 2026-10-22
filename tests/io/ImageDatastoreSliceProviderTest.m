classdef ImageDatastoreSliceProviderTest < matlab.unittest.TestCase
% IMAGEDATASTORESLICEPROVIDERTEST - Unit tests for io.savers.ImageDatastoreSliceProvider.
%
% Wraps an imageDatastore (one Z-slice per file, or volumes) so a streaming saver
% can pull slices on demand. Used by ImageConverter to feed Zarr3Saver.saveStream when the
% native (zarrMex) backend writes a Zarr v3 pyramid.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Static)
        function ds = writeStack(folder, vol)
            % Write each Z-slice of vol [H W D] or [H W C D] as a numbered file.
            if ndims(vol) == 3
                D = size(vol, 3);
                for z = 1:D
                    imwrite(vol(:, :, z), fullfile(folder, sprintf('s_%02d.tif', z)));
                end
            else
                D = size(vol, 4);
                for z = 1:D
                    imwrite(vol(:, :, :, z), fullfile(folder, sprintf('s_%02d.tif', z)));
                end
            end
            ds = imageDatastore(folder, 'FileExtensions', '.tif');
        end

        function ds = writeVolumes(folder, volumes)
            % Write each [H W C Z] array of the cell volumes as a numbered .mat file,
            % read back whole as ImageConverter.readWithLoader returns a volume.
            for fileIndex = 1:numel(volumes)
                volume = volumes{fileIndex};
                save(fullfile(folder, sprintf('v_%02d.mat', fileIndex)), 'volume');
            end
            ds = imageDatastore(folder, 'FileExtensions', '.mat', ...
                'ReadFcn', @(filename) getfield(load(filename), 'volume'));
        end

        function depth = matFileDepth(filename)
            % Slices of a file written by writeVolumes, from its variable size.
            details = whos('-file', filename, 'volume');
            depth = 1;
            if numel(details.size) >= 4; depth = details.size(4); end
        end
    end

    methods (Test, TestTags = {'Unit'})

        function grayscale_sizeAndSlices(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            vol = reshape(uint8(mod(0:5*6*4-1, 251) + 1), [5 6 4]);   % [H W D]
            ds  = ImageDatastoreSliceProviderTest.writeStack(tmp.Folder, vol);

            provider = io.savers.ImageDatastoreSliceProvider(ds);

            testCase.verifyEqual(provider.OutputSize, [5 6 4 1 1]);
            testCase.verifyEqual(provider.DataClass, 'uint8');
            testCase.verifyEqual(provider.NumSlices, 4);
            testCase.verifyEqual(provider.NumChannels, 1);

            slice = provider.getSlice(2, 1);
            testCase.verifyEqual(size(slice), [5 6]);
            testCase.verifyEqual(slice, vol(:, :, 2), 'slice 2 must equal source file 2');
        end

        function rgb_channelsExposed(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            vol = reshape(uint8(mod(0:4*4*3*3-1, 251) + 1), [4 4 3 3]);   % [H W C D]
            ds  = ImageDatastoreSliceProviderTest.writeStack(tmp.Folder, vol);

            provider = io.savers.ImageDatastoreSliceProvider(ds);

            testCase.verifyEqual(provider.OutputSize, [4 4 3 3 1]);
            testCase.verifyEqual(provider.NumChannels, 3);
            slice = provider.getSlice(1, 1);
            testCase.verifyEqual(size(slice), [4 4 3]);
            testCase.verifyEqual(slice, vol(:, :, :, 1));
        end

        function oneVolume_slicesAlongZ(testCase)
            % a single volume file is Z, not channels (it was written as C = depth)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = reshape(uint8(mod(0:5*6*1*7-1, 251)), [5 6 1 7]);   % [H W C Z]
            ds = ImageDatastoreSliceProviderTest.writeVolumes(tmp.Folder, {volume});

            provider = io.savers.ImageDatastoreSliceProvider(ds);

            testCase.verifyEqual(provider.OutputSize, [5 6 7 1 1]);
            testCase.verifyEqual(provider.LargestFileDepth, 7);
            testCase.verifyFalse(provider.SupportsRowReads);
            for z = [1 4 7 2]   % out of order too: a released volume is read again
                testCase.verifyEqual(provider.getSlice(z, 1), volume(:, :, :, z), sprintf('slice %d', z));
            end
        end

        function folderOfVolumes_concatenatedInFileOrder(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            first  = reshape(uint16(1:4*3*2*3), [4 3 2 3]);          % 3 slices, 2 channels
            second = reshape(uint16(1000 + (1:4*3*2*5)), [4 3 2 5]); % 5 slices
            ds = ImageDatastoreSliceProviderTest.writeVolumes(tmp.Folder, {first, second});
            expected = cat(4, first, second);

            withCount = io.savers.ImageDatastoreSliceProvider(ds, @ImageDatastoreSliceProviderTest.matFileDepth);
            byReading = io.savers.ImageDatastoreSliceProvider(ds);

            for provider = {withCount, byReading}
                testCase.verifyEqual(provider{1}.OutputSize, [4 3 8 2 1]);
                testCase.verifyEqual(provider{1}.LargestFileDepth, 5);
                for z = 1:8
                    testCase.verifyEqual(provider{1}.getSlice(z, 1), expected(:, :, :, z), sprintf('slice %d', z));
                end
            end
        end

        function volumeAfterSingleImages_errors(testCase)
            % the first file sets single images: a later volume must not be cut to its first slice
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            ds = ImageDatastoreSliceProviderTest.writeVolumes(tmp.Folder, ...
                {zeros(4, 4, 'uint8'), zeros(4, 4, 1, 3, 'uint8')});

            provider = io.savers.ImageDatastoreSliceProvider(ds);

            testCase.verifyEqual(provider.NumSlices, 2);
            testCase.verifyError(@() provider.getSlice(2, 1), 'io:ImageDatastoreSliceProvider:depthMismatch');
        end

        function timeSeries_refused(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            ds = ImageDatastoreSliceProviderTest.writeVolumes(tmp.Folder, {zeros(4, 4, 1, 3, 2, 'uint8')});

            testCase.verifyError(@() io.savers.ImageDatastoreSliceProvider(ds), ...
                'io:ImageDatastoreSliceProvider:timeSeries');
        end

    end
end
