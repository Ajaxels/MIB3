classdef ImageConverterNativeZarrTest < matlab.unittest.TestCase
% IMAGECONVERTERNATIVEZARRTEST - ImageConverter native (zarrMex) Zarr v3 conversion.
%
% When io.zarr.Config = native and the output is Zarr v3, ImageConverter routes a
% folder of image files through io.savers.Zarr3Saver.saveStream (shared in-app
% pyramid logic) instead of its legacy Python pipeline, then writes the bounding
% box + voxel size via Zarr3Saver.patchMetadata. This verifies the harmonized
% output: correct pixels, dimensions, voxel scale and mibBoundingBox, reopenable
% by MIB's own zarr reader.

    properties (Access = private)
        OrigZarrLib
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            % ImageConverter lives under mib/plugins (not on the default test path)
            here     = fileparts(mfilename('fullpath'));            % tests/io
            repoRoot = fileparts(fileparts(here));
            pluginDir = fullfile(repoRoot, 'mib', 'plugins', 'FileProcessing', 'ImageConverter');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(pluginDir));
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

    methods (Test, TestTags = {'Integration'})

        function nativeZarr3_pixelsVoxelAndBoundingBox(testCase)
            inDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            % synthetic grayscale stack: [H W D] = [16 12 8]
            vol = reshape(uint8(mod(0:16*12*8-1, 251) + 1), [16 12 8]);
            for z = 1:8
                imwrite(vol(:, :, z), fullfile(inDir.Folder, sprintf('s_%02d.tif', z)));
            end
            ds = imageDatastore(inDir.Folder, 'FileExtensions', '.tif');

            zarrPath = fullfile(outDir.Folder, 'out.zarr3');
            BatchOpt = struct();
            BatchOpt.OutputDirectory        = zarrPath;
            BatchOpt.ZarrImageType          = {'image'};
            BatchOpt.ZarrChunkSizes         = '8, 8, 4, 1, 1';   % x,y,z,c,t
            BatchOpt.ZarrUseSharding        = false;
            BatchOpt.ZarrShardXFactorsXYZ   = '2, 2, 1, 1, 1';
            BatchOpt.ZarrCompression        = {'blosc'};
            BatchOpt.ZarrVoxelSizeXYZ       = '0.01, 0.02, 0.03';   % x,y,z
            BatchOpt.ZarrUnits              = {'micrometers'};
            BatchOpt.ZarrBBShiftsXYZ        = '1, 2, 3';            % x,y,z shift
            BatchOpt.ZarrDownsampleLimitXYZ = '8, 8, 4';

            fnOut = ImageConverter.convertToZarr3Native(ds, BatchOpt, struct());

            testCase.verifyTrue(isfolder(fnOut), 'a zarr3 group must be written');

            % --- pixels + dims round-trip at level 0 (stored [Y X Z]) ---
            grp  = io.zarr.Group(fnOut);
            arr0 = grp.openArray('0');
            data0 = arr0.read();
            testCase.verifyEqual(size(data0, 1:3), [16 12 8], 'level-0 dims must match the stack');
            testCase.verifyEqual(data0, vol, 'level-0 pixels must be exact');

            % --- bounding box [xmin xmax ymin ymax zmin zmax] (shift + (dim-1)*voxel) ---
            attrs = grp.getAttributes();
            testCase.verifyTrue(isfield(attrs, 'mibBoundingBox'), 'mibBoundingBox must be written');
            expectedBB = [1, 1 + 11*0.01, 2, 2 + 15*0.02, 3, 3 + 7*0.03];
            testCase.verifyEqual(double(attrs.mibBoundingBox(:)'), expectedBB, 'AbsTol', 1e-6, ...
                'mibBoundingBox must encode the shift + physical extent');
        end

    end
end
