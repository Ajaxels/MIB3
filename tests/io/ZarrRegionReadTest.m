classdef ZarrRegionReadTest < matlab.unittest.TestCase
% ZARRREGIONREADTEST - Opening a world sub-volume of a zarr store, end to end.
%
% Builds a small local OME-Zarr v2 pyramid that declares a **non-zero
% translation** - the thing no store MIB read before this could - and drives the
% real loaders over it. Offline and native-backend only, so it also guards that
% none of this needs python or a network.
%
% Two properties are pinned, and the first matters more:
%
%   1. **No region is a literal no-op.** ``BatchOpt.Region`` reaches the read
%      path of every zarr dataset MIB opens, local and remote, v2 and v3, and
%      almost none will ever ask for one. An uncropped open must come back
%      byte-identical to what it was before the feature existed.
%   2. **A region returns the right voxels, not merely the right shape.** The
%      synthetic volume encodes each voxel's own coordinates, so an origin that
%      is off by one - the natural failure of edge/centre confusion - changes
%      the values rather than the dimensions, which a shape check cannot see.

    properties (Access = private)
        TempDir
        StorePath
        OriginalZarrLibrary
        Level0Data
    end

    properties (Constant, Access = private)
        % z, y, x - the store's C-order, matching its declared axes
        Level0Shape = [40, 60, 80]
        Level1Shape = [20, 30, 40]
        % Voxel centres start here, on a 2 nm grid; level 1 starts half a coarse
        % voxel further in, exactly as a real OME pyramid declares it.
        Level0Scale       = [2 2 2]
        Level0Translation = [100 200 300]
        Level1Scale       = [4 4 4]
        Level1Translation = [101 201 301]
        % Chosen to land exactly on BOTH grids: level 0 voxels x 10..29,
        % y 4..23, z 2..11 (0-based). Edge-based, in micrometres.
        ExactRegionUm = [0.319 0.359 0.207 0.247 0.103 0.123]
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function buildStore(testCase)
            testCase.OriginalZarrLibrary = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');

            testCase.TempDir = fullfile(tempdir, 'mib_zarr_region_test');
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
            mkdir(testCase.TempDir);
            testCase.StorePath = fullfile(testCase.TempDir, 'crop.zarr2');

            group = io.zarr.Group.create(testCase.StorePath, 'zarrFormat', 2);
            level0 = group.createArray('s0', testCase.Level0Shape, 'uint16', ...
                'chunkShape', [8 16 16], 'fillValue', 0);
            level1 = group.createArray('s1', testCase.Level1Shape, 'uint16', ...
                'chunkShape', [8 16 16], 'fillValue', 0);

            % Every voxel encodes its own coordinates - the primes keep
            % neighbouring values far apart, so a one-voxel shift in any axis is
            % unmistakable rather than merely improbable.
            [zz, yy, xx] = ndgrid(0:testCase.Level0Shape(1)-1, ...
                0:testCase.Level0Shape(2)-1, 0:testCase.Level0Shape(3)-1);
            testCase.Level0Data = uint16(mod(zz*7919 + yy*104729 + xx*1299709, 65521));
            level0.write(testCase.Level0Data);

            [zz1, yy1, xx1] = ndgrid(0:testCase.Level1Shape(1)-1, ...
                0:testCase.Level1Shape(2)-1, 0:testCase.Level1Shape(3)-1);
            level1.write(uint16(mod(zz1*104729 + yy1*1299709 + xx1*7919, 65521)));

            axesDefinition = {struct('name','z','type','space','unit','nanometer'), ...
                              struct('name','y','type','space','unit','nanometer'), ...
                              struct('name','x','type','space','unit','nanometer')};
            datasets = { ...
                struct('path','s0','coordinateTransformations', ...
                    {{struct('type','scale','scale',testCase.Level0Scale), ...
                      struct('type','translation','translation',testCase.Level0Translation)}}), ...
                struct('path','s1','coordinateTransformations', ...
                    {{struct('type','scale','scale',testCase.Level1Scale), ...
                      struct('type','translation','translation',testCase.Level1Translation)}})};
            group.setAttributes(struct('multiscales', {{struct('version','0.4', ...
                'axes', {axesDefinition}, 'datasets', {datasets})}}));
        end
    end

    methods (TestMethodTeardown)
        function restore(testCase)
            io.zarr.Config.setLibrary(testCase.OriginalZarrLibrary);
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
        end
    end

    methods (Test, TestTags = {'Unit'})

        % ---- 1. the no-op contract ----------------------------------------

        function withoutARegionNothingChanges(testCase)
            [imginfo, files] = testCase.loadMetadata(struct());

            testCase.verifyFalse(files.regionReport.requested);
            testCase.verifyEqual(files.levelRegionOrigins, ones(2, 3), ...
                'every read path reads [1 1 1] as "no offset"');
            testCase.verifyEqual([imginfo{"Height"}, imginfo{"Width"}, imginfo{"Depth"}], ...
                [60 80 40]);
            testCase.verifyEqual(files.levelImageSizes, [60 80 40; 30 40 20]);
        end

        function withoutARegionStandardModeReadsTheWholeLevel(testCase)
            options = struct('datasetMode', 'Standard', 'ParentFigure', [], 'ZarrLevel', 1);
            [imginfo, files] = testCase.loadMetadata(options);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            image = loader.loadImages(files, imginfo, options);

            expected = permute(testCase.Level0Data, [2 3 1]);   % [z,y,x] -> [y,x,z]
            testCase.verifyEqual(squeeze(image), expected, ...
                'an uncropped Standard open must return the array untouched');
        end

        % ---- 2. the derived world bounding box -----------------------------

        function theBoundingBoxComesFromTheTranslation(testCase)
            imginfo = testCase.loadMetadata(struct());
            % centre of first voxel to centre of last, in the store's own unit
            testCase.verifyEqual(imginfo{"BoundingBox"}, ...
                [300, 300+79*2, 200, 200+59*2, 100, 100+39*2], 'AbsTol', 1e-9);
        end

        function mibBoundingBoxStillWins(testCase)
            % A store MIB wrote carries its own box, and that must keep
            % overriding anything derived from the OME transforms.
            % setAttributes overwrites, so the multiscales have to be carried
            % across or the group stops being a pyramid at all.
            group = io.zarr.Group(testCase.StorePath);
            attributes = group.getAttributes();
            attributes.mibBoundingBox = [1 2 3 4 5 6];
            group.setAttributes(attributes);

            imginfo = testCase.loadMetadata(struct());
            testCase.verifyEqual(imginfo{"BoundingBox"}, [1 2 3 4 5 6]);
        end

        % ---- 3. cropping ---------------------------------------------------

        function aRegionCropsEveryLevelOnItsOwnGrid(testCase)
            [imginfo, files] = testCase.loadMetadata( ...
                struct('Region', testCase.ExactRegionUm));

            testCase.verifyTrue(files.regionReport.requested);
            testCase.verifyTrue(files.regionReport.isExact);
            testCase.verifyEqual([imginfo{"Height"}, imginfo{"Width"}, imginfo{"Depth"}], ...
                [20 20 10]);
            testCase.verifyEqual(files.levelImageSizes, [20 20 10; 10 10 5]);
            testCase.verifyEqual(files.levelRegionOrigins, [5 11 3; 3 6 2], ...
                '1-based first voxel of the crop within each level''s own array');
            testCase.verifyEqual(imginfo{"BoundingBox"}, ...
                [320 358 208 246 104 122], 'AbsTol', 1e-9, ...
                'the box must describe the crop, not the store it came from');
        end

        function aCroppedStandardOpenReturnsTheRightVoxels(testCase)
            options = struct('datasetMode', 'Standard', 'ParentFigure', [], ...
                'ZarrLevel', 1, 'Region', testCase.ExactRegionUm);
            [imginfo, files] = testCase.loadMetadata(options);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            image = loader.loadImages(files, imginfo, options);

            % level 0 voxels z 2..11, y 4..23, x 10..29 (0-based) = the region
            expected = permute(testCase.Level0Data(3:12, 5:24, 11:30), [2 3 1]);
            testCase.verifyEqual(squeeze(image), expected, ...
                'an origin off by one changes these values, not the shape');
        end

        function aCroppedVirtualReadIsOffsetByTheCropOrigin(testCase)
            % getDataZarr works in crop coordinates and adds the origin just
            % before the read; this is the assertion that the two agree.
            options = struct('datasetMode', 'Virtual', 'ParentFigure', [], ...
                'Region', testCase.ExactRegionUm);
            [imginfo, files] = testCase.loadMetadata(options);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            [~, imginfo] = loader.loadImages(files, imginfo, options);

            virtualImage = core.MibVirtualImage();
            virtualImage.initialize({testCase.StorePath}, imginfo);

            testCase.verifyEqual([virtualImage.height, virtualImage.width, virtualImage.depth], ...
                [20 20 10]);

            slice = virtualImage.getDataZarr('image', 3, [], ...
                struct('pyramidLevel', 1, 'z', [4 4]));
            expected = permute(testCase.Level0Data(6, 5:24, 11:30), [2 3 1]);
            testCase.verifyEqual(squeeze(slice), squeeze(expected), ...
                'slice 4 of the crop is slice 6 of the store');
        end

        function anOffGridRegionRoundsOutwardAndSaysSo(testCase)
            % Nothing in OME-NGFF promises a store's grid divides a region
            % evenly. Growing the region is recoverable; shifting it is not.
            insetRegion = testCase.ExactRegionUm + [0.0005 -0.0005 0 0 0 0];
            [~, files] = testCase.loadMetadata(struct('Region', insetRegion));

            testCase.verifyEqual(files.levelImageSizes(1, :), [20 20 10], ...
                'a request inside the grid lines must still cover them');
            testCase.verifyFalse(files.regionReport.isExact);
            testCase.verifySubstring(files.regionReport.message, 'rounded outward');
        end

        function aRegionMissingTheStoreKeepsTheFullExtent(testCase)
            [imginfo, files] = testCase.loadMetadata(struct('Region', [50 60 50 60 50 60]));

            testCase.verifyEqual([imginfo{"Height"}, imginfo{"Width"}, imginfo{"Depth"}], ...
                [60 80 40], 'a non-overlapping region must not give a zero-sized dataset');
            testCase.verifySubstring(files.regionReport.message, 'does not overlap');
        end

        function aMalformedRegionIsIgnored(testCase)
            [~, files] = testCase.loadMetadata(struct('Region', [1 2 3]));
            testCase.verifyFalse(files.regionReport.requested);
        end

        % ---- 4. explicit pyramid level -------------------------------------

        function anExplicitLevelSkipsThePickerAndReadsThatLevel(testCase)
            options = struct('datasetMode', 'Standard', 'ParentFigure', [], 'ZarrLevel', 2);
            [imginfo, files] = testCase.loadMetadata(options);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            image = loader.loadImages(files, imginfo, options);

            % level 1 is 30 x 40 x 20 in [y x z]; reaching it without a dialog is
            % the point - the store has two levels, so the picker would otherwise
            % open and block.
            testCase.verifyEqual(size(squeeze(image)), [30 40 20]);
        end

        function anOutOfRangeLevelIsIgnoredRatherThanClamped(testCase)
            % A stale batch protocol must fall back to asking, not silently open
            % a different resolution than it names.
            resolve = @(value) io.loaders.OmeZarrMetadataUtils.resolveLevelOption( ...
                struct('ZarrLevel', value), struct(), 2);
            testCase.verifyEmpty(resolve(9));
            testCase.verifyEmpty(resolve(0));
            testCase.verifyEmpty(resolve(1.5));
            testCase.verifyEqual(resolve(2), 2);
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.resolveLevelOption( ...
                struct(), struct('ZarrLevel', 2), 2), 2, ...
                'a level baked into the loader at construction must be honoured too');
        end
    end

    methods (Access = private)
        function [imginfo, files] = loadMetadata(testCase, options)
            if ~isfield(options, 'datasetMode'); options.datasetMode = 'Virtual'; end
            if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            [imginfo, files] = loader.loadMetadata({testCase.StorePath}, options);
        end
    end
end
