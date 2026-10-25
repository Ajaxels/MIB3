classdef ZarrPinNativeLibraryTest < matlab.unittest.TestCase
    % ZARRPINNATIVELIBRARYTEST - io.zarr.pinNativeLibrary keeps zarrMex loaded and usable.
    %
    % The crash it prevents happens only when MATLAB exits, so it cannot be asserted here; this
    % checks that the pin succeeds where utils.pinModule is compiled, and that zarrMex keeps
    % working after "clear zarrMex" once pinned (MATLAB rebinds to the same, still mapped module).

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            mibFolder = fileparts(fileparts(fileparts(which('io.zarr.pinNativeLibrary'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(mibFolder, 'external', 'zarr-matlab')));
            testCase.assumeTrue(isfile(fullfile(mibFolder, '+utils', ['pinModule.' mexext])), ...
                'utils.pinModule is not compiled for this platform');
        end
    end

    methods (Test, TestTags = {'Unit'})
        function zarrMexIsPinned(testCase)
            testCase.verifyTrue(io.zarr.pinNativeLibrary());
        end

        function zarrMexWorksAfterClear(testCase)
            testCase.assertTrue(io.zarr.pinNativeLibrary());
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            store = fullfile(folder, 'pinned.zarr');
            data = uint16(reshape(1:64*64*4, 64, 64, 4));
            ZarrArray.createFromData(store, data, 'chunkShape', [32 32 4], 'compressors', 'zstd');
            clear zarrMex
            testCase.verifyEqual(ZarrArray(store).read(), data);
        end
    end
end
