classdef ImageDatastoreSliceProviderTest < matlab.unittest.TestCase
% IMAGEDATASTORESLICEPROVIDERTEST - Unit tests for io.savers.ImageDatastoreSliceProvider.
%
% Wraps an imageDatastore (one Z-slice per file) so a streaming saver can pull
% slices on demand. Used by ImageConverter to feed Zarr3Saver.saveStream when the
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

    end
end
