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

        function nativeZarr2_writesV2WithIdenticalPixels(testCase)
            % The output folder carries no .zarr2/.zarr3 extension, so the format
            % comes from BatchOpt.ZarrVersion rather than from the path. Assert
            % both that v2 metadata was written AND that the pixels survived: the
            % two formats express MATLAB's column-major layout differently, so a
            % mix-up transposes data while leaving every dimension intact.
            inDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            vol = reshape(uint8(mod(0:16*12*8-1, 251) + 1), [16 12 8]);
            for z = 1:8
                imwrite(vol(:, :, z), fullfile(inDir.Folder, sprintf('s_%02d.tif', z)));
            end
            ds = imageDatastore(inDir.Folder, 'FileExtensions', '.tif');

            zarrPath = fullfile(outDir.Folder, 'out_v2');
            BatchOpt = struct();
            BatchOpt.OutputDirectory        = zarrPath;
            BatchOpt.ZarrVersion            = {'Zarr v2'};
            BatchOpt.ZarrImageType          = {'image'};
            BatchOpt.ZarrChunkSizes         = '8, 8, 4, 1, 1';   % x,y,z,c,t
            BatchOpt.ZarrUseSharding        = false;
            BatchOpt.ZarrShardXFactorsXYZ   = '2, 2, 1, 1, 1';
            BatchOpt.ZarrCompression        = {'blosc'};
            BatchOpt.ZarrVoxelSizeXYZ       = '0.01, 0.02, 0.03';   % x,y,z
            BatchOpt.ZarrUnits              = {'micrometers'};
            BatchOpt.ZarrBBShiftsXYZ        = '0, 0, 0';
            BatchOpt.ZarrDownsampleLimitXYZ = '8, 8, 4';

            fnOut = ImageConverter.convertToZarr3Native(ds, BatchOpt, struct());

            group = io.zarr.Group(fnOut);
            testCase.verifyEqual(group.zarrFormat(), 2, ...
                'ZarrVersion must select the format when the path has no extension');
            testCase.verifyTrue(isfile(fullfile(fnOut, '.zgroup')));
            testCase.verifyFalse(isfile(fullfile(fnOut, 'zarr.json')));

            testCase.verifyEqual(group.openArray('0').read(), vol, ...
                'level-0 pixels must survive the v2 write unchanged');
        end

        function nativeZarr2_shardingIsRefused(testCase)
            % The dialog clears the sharding checkbox when v2 is picked, so this
            % combination can only arrive through batch mode - where it must fail
            % loudly rather than write a differently chunked store than requested.
            inDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            imwrite(uint8(zeros(16, 12)), fullfile(inDir.Folder, 's_01.tif'));
            ds = imageDatastore(inDir.Folder, 'FileExtensions', '.tif');

            BatchOpt = struct();
            BatchOpt.OutputDirectory        = fullfile(outDir.Folder, 'out_shard');
            BatchOpt.ZarrVersion            = {'Zarr v2'};
            BatchOpt.ZarrImageType          = {'image'};
            BatchOpt.ZarrChunkSizes         = '8, 8, 4, 1, 1';
            BatchOpt.ZarrUseSharding        = true;
            BatchOpt.ZarrShardXFactorsXYZ   = '2, 2, 1, 1, 1';
            BatchOpt.ZarrCompression        = {'blosc'};
            BatchOpt.ZarrVoxelSizeXYZ       = '0.01, 0.02, 0.03';
            BatchOpt.ZarrUnits              = {'micrometers'};
            BatchOpt.ZarrBBShiftsXYZ        = '0, 0, 0';
            BatchOpt.ZarrDownsampleLimitXYZ = '8, 8, 4';

            testCase.verifyError(@() ImageConverter.convertToZarr3Native(ds, BatchOpt, struct()), ...
                'io:Zarr3Saver:shardingUnsupportedV2');
        end

        function nativeZarr3_oddSliceCount_anisotropicStream_doesNotCrash(testCase)
            % Regression: an odd number of source slices combined with an
            % anisotropic voxel size (forcing a Z-downsampled pyramid level)
            % previously crashed with a zarrMex out-of-bounds write, because
            % computeLevelPlan floor-divided a Z-downsampled level's size while
            % saveStream's flush always writes the trailing partial group
            % (ceil-division worth of output slices). See Zarr3SaverTest for
            % the isolated level-plan math.
            inDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            D = 9;   % odd depth
            vol = reshape(uint8(mod(0:16*12*D-1, 251) + 1), [16 12 D]);
            for z = 1:D
                imwrite(vol(:, :, z), fullfile(inDir.Folder, sprintf('s_%02d.tif', z)));
            end
            ds = imageDatastore(inDir.Folder, 'FileExtensions', '.tif');

            zarrPath = fullfile(outDir.Folder, 'out.zarr3');
            BatchOpt = struct();
            BatchOpt.OutputDirectory        = zarrPath;
            BatchOpt.ZarrImageType          = {'image'};
            BatchOpt.ZarrChunkSizes         = '4, 4, 2, 1, 1';   % x,y,z,c,t
            BatchOpt.ZarrUseSharding        = false;
            BatchOpt.ZarrShardXFactorsXYZ   = '2, 2, 1, 1, 1';
            BatchOpt.ZarrCompression        = {'blosc'};
            BatchOpt.ZarrVoxelSizeXYZ       = '0.013, 0.013, 0.030';   % x,y,z anisotropic
            BatchOpt.ZarrUnits              = {'micrometers'};
            BatchOpt.ZarrBBShiftsXYZ        = '0, 0, 0';
            BatchOpt.ZarrDownsampleLimitXYZ = '4, 4, 4';   % forces multiple pyramid levels

            fnOut = ImageConverter.convertToZarr3Native(ds, BatchOpt, struct());

            testCase.verifyTrue(isfolder(fnOut), 'a zarr3 group must be written despite the odd slice count');

            grp  = io.zarr.Group(fnOut);
            arr0 = grp.openArray('0');
            testCase.verifyEqual(size(arr0.read(), 1:3), [16 12 D], 'level-0 dims must match the odd-depth stack');
        end

        function nativeZarr3_labels_materialNamesPopulatedFromData(testCase)
            % Regression: converting a folder of label slices wrote no
            % ``mibMaterials`` attribute at all (ImageConverter has no external
            % material-name source), so MIB's Materials table came up empty on
            % reopen even though the label data had real values. convertToZarr3Native
            % must derive "Material 1".."Material N" from the highest label value
            % actually present and write it via metadata.materialNames.
            inDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outDir = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            D = 5;
            vol = zeros(10, 12, D, 'uint8');
            for z = 1:D
                vol(:, :, z) = uint8(mod(z - 1, 4));   % label values 0..3 -> 3 materials
                imwrite(vol(:, :, z), fullfile(inDir.Folder, sprintf('s_%02d.tif', z)));
            end
            ds = imageDatastore(inDir.Folder, 'FileExtensions', '.tif');

            zarrPath = fullfile(outDir.Folder, 'out.zarr3');
            BatchOpt = struct();
            BatchOpt.OutputDirectory        = zarrPath;
            BatchOpt.ZarrImageType          = {'labels'};
            BatchOpt.ZarrChunkSizes         = '8, 8, 4, 1';
            BatchOpt.ZarrUseSharding        = false;
            BatchOpt.ZarrShardXFactorsXYZ   = '2, 2, 1, 1, 1';
            BatchOpt.ZarrCompression        = {'blosc'};
            BatchOpt.ZarrVoxelSizeXYZ       = '0.01, 0.01, 0.03';
            BatchOpt.ZarrUnits              = {'micrometers'};
            BatchOpt.ZarrBBShiftsXYZ        = '0, 0, 0';
            BatchOpt.ZarrDownsampleLimitXYZ = '4, 4, 4';

            fnOut = ImageConverter.convertToZarr3Native(ds, BatchOpt, struct());

            grp   = io.zarr.Group(fnOut);
            attrs = grp.getAttributes();
            testCase.verifyTrue(isfield(attrs, 'mibMaterials'), 'mibMaterials attribute must be written for labels');
            testCase.verifyEqual(attrs.mibMaterials.materialNames, {'Material 1'; 'Material 2'; 'Material 3'});

            % and it must actually round-trip through MIB's own BigData labels loader
            labels = core.MibBigDataLabels([], struct());
            labels.openStore(fnOut);
            testCase.verifyEqual(labels.materialsCount, 3);
            testCase.verifyEqual(labels.materialNames, {'Material 1'; 'Material 2'; 'Material 3'});
        end

    end
end
