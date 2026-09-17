classdef OmeZarrLevelRegistrationTest < matlab.unittest.TestCase
% OMEZARRLEVELREGISTRATIONTEST - Placing a label pyramid inside an image pyramid's scale space.
%
% Covers the two halves of the geometry a view-only label overlay needs, both of
% which fail silently rather than loudly:
%
%   1. **Registration.** A pyramid that numbers its levels from its own level 0
%      is right only while both pyramids start at the same resolution.
%      ``jrc_mus-kidney``'s ``nuc`` starts at 128 nm against the EM's 8 nm, so
%      calling its first level "scale 1" puts every label at one-sixteenth size.
%   2. **The read window.** Serving a full-resolution view from a level 16x
%      coarser is not a resize: the coarse block does not begin where the view
%      begins. A shape-only check passes while every label sits 14 pixels to the
%      left, so everything here is asserted on **values** - the gathered numbers
%      are the source voxel indices themselves, and the expected ones are worked
%      out from the image's own grid rather than from the code under test.
%
% The last test pins the coupling the rest of it rests on: that
% ``screenGridForRange`` really does predict how many pixels
% ``core.MibVirtualImage.getDataZarr`` returns. The two layers are composited by
% ``labeloverlay``, which needs them the same size exactly, so a drift there is
% an error rather than a misplacement.

    properties (Access = private)
        TempDir
        StorePath
        OriginalZarrLibrary
    end

    properties (Constant, Access = private)
        % jrc_mus-kidney, in micrometres: EM 12 levels from 8 nm, nuc 5 from
        % 128 nm, both covering the same volume.
        ImageVoxelSizesUm = 0.008 * 2 .^ (0:11)' * [1 1 1]
        LabelVoxelSizesUm = 0.128 * 2 .^ (0:4)'  * [1 1 1]
        % Edge-based outer extent, shared by both pyramids
        VolumeOuterBoxUm = [0 40.96 0 40.96 0 20.48]

        % The local store built for the getDataZarr coupling test - z, y, x, in
        % the store's own C-order.
        Level0Shape = [8, 64, 96]
        Level1Shape = [4, 32, 48]
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % ---- 1. registration ------------------------------------------------

        function anOffsetPyramidRegistersInTheImagesScaleSpace(testCase)
            registration = testCase.registerNuc();

            testCase.verifyTrue(registration.ok, registration.reason);
            testCase.verifyEqual(registration.scaleFactorsYXZ(:, 1)', [16 32 64 128 256], ...
                'nuc s0 is the EM s4, so its own level 0 is scale 16 - not 1');
            testCase.verifyEqual(registration.scaleFactorsYXZ, ...
                repmat([16 32 64 128 256]', 1, 3), ...
                'every axis registers, not only the one that gets looked at');
            testCase.verifyEqual(registration.referenceScaleFactorsYXZ(:, 1)', 2 .^ (0:11), ...
                'the image keeps its own magnification axis, 1 .. 2048');
            testCase.verifyTrue(registration.isIntegerScale);
        end

        function aRoundedDecimalScaleSnapsToAWholeNumber(testCase)
            % Stores write their scales as rounded decimals, and 127.99 / 8 is
            % not 16. Every ceil() downstream reads one voxel too far at exactly
            % the level boundaries if that is left as 15.99875.
            roundedSizes = 0.12799 * 2 .^ (0:4)' * [1 1 1];
            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                roundedSizes, testCase.VolumeOuterBoxUm, ...
                testCase.ImageVoxelSizesUm, testCase.VolumeOuterBoxUm);

            testCase.verifyTrue(registration.ok, registration.reason);
            testCase.verifyEqual(registration.scaleFactorsYXZ(:, 1)', [16 32 64 128 256]);
            testCase.verifyTrue(registration.isIntegerScale);
        end

        function aTrulyFractionalScaleRegistersButIsFlagged(testCase)
            % 1.5x is a real scale and reads correctly; it just cannot be served
            % without splitting a label across a voxel boundary, and the caller
            % has to be able to tell the two cases apart.
            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                [0.012 0.012 0.012], testCase.VolumeOuterBoxUm, ...
                testCase.ImageVoxelSizesUm, testCase.VolumeOuterBoxUm);

            testCase.verifyTrue(registration.ok, registration.reason);
            testCase.verifyEqual(registration.scaleFactorsYXZ, [1.5 1.5 1.5], 'AbsTol', 1e-12);
            testCase.verifyFalse(registration.isIntegerScale, ...
                'a fractional scale must be reported, not rounded away');
        end

        function aShapeRoundedUpIsStillTheSameVolume(testCase)
            % jrc_ctl-id8-1: nuc is the EM downsampled 16x, and 18500/16 rounds
            % up to 1157, so the labels claim 1157 * 64 = 74048 nm against the
            % EM's 18500 * 4 = 74000 nm. Half an image voxel rejects that
            % outright; the excess can never exceed one label voxel, so that is
            % the bound.
            imageBox = [0 74 0 74 0 10];
            labelBox = [0 74.048 0 74.048 0 10.048];
            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                [0.064 0.064 0.064], labelBox, [0.004 0.004 0.004], imageBox);

            testCase.verifyTrue(registration.ok, registration.reason);
            testCase.verifyEqual(registration.scaleFactorsYXZ, [16 16 16]);
        end

        function aSubVolumeIsRefusedRatherThanPlaced(testCase)
            % Nothing here carries an origin offset, so a pyramid covering part
            % of the image would be placed at the origin at the wrong extent.
            % That case is a crop, and crops are read into memory instead.
            halfVolume = testCase.VolumeOuterBoxUm .* [1 0.5 1 0.5 1 0.5];
            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                testCase.LabelVoxelSizesUm, halfVolume, ...
                testCase.ImageVoxelSizesUm, testCase.VolumeOuterBoxUm);

            testCase.verifyFalse(registration.ok);
            testCase.verifySubstring(registration.reason, 'same volume');
            testCase.verifySubstring(registration.reason, '20.48', ...
                'the refusal has to name the two extents that disagreed');
        end

        function aShiftedVolumeIsRefused(testCase)
            % Same size, wrong place - the failure a scale factor alone cannot
            % see, and the reason the extents are checked at all.
            shifted = testCase.VolumeOuterBoxUm + [10 10 0 0 0 0];
            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                testCase.LabelVoxelSizesUm, shifted, ...
                testCase.ImageVoxelSizesUm, testCase.VolumeOuterBoxUm);

            testCase.verifyFalse(registration.ok);
        end

        function anUnusableVoxelSizeIsRefusedNotDividedBy(testCase)
            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                [0.128 0.128 0.128], testCase.VolumeOuterBoxUm, ...
                [0 0 0], testCase.VolumeOuterBoxUm);
            testCase.verifyFalse(registration.ok);
            testCase.verifyNotEmpty(registration.reason);
        end

        % ---- 2. the screen grid --------------------------------------------

        function aLevelAtTheRequestedMagnificationIsShownVoxelForVoxel(testCase)
            grid = io.loaders.OmeZarrMetadataUtils.screenGridForRange([9 24], 4, 4);

            testCase.verifyEqual(grid.levelRange, [3 6]);
            testCase.verifyEqual(grid.size, 4, 'no resize happens when the level already fits');
            testCase.verifyEqual(grid.step, 4);
        end

        function theGridStartsWhereTheImageSnappedItNotWhereItWasAsked(testCase)
            % The image rounds the request outward onto its own level first, so
            % screen pixel 1 begins before the request does. Sampling a second
            % pyramid from the requested coordinate instead puts every label up
            % to one screen pixel off - invisible at a glance, wrong everywhere.
            grid = io.loaders.OmeZarrMetadataUtils.screenGridForRange([10 24], 4, 4);

            testCase.verifyEqual(grid.origin, 9, ...
                'level voxel 3 starts at full-resolution voxel 9, not at the requested 10');
            testCase.verifyEqual(grid.size, 4);
        end

        function aMagnifiedGridReportsTheStepItActuallyDelivers(testCase)
            % 32 level voxels shown at magFactor 3 from a level of scale 2:
            % round(32 / 1.5) = 21 pixels over 64 full-resolution voxels, so the
            % step is 64/21 and not the 3 that was asked for. Using magFactor
            % here would drift by a pixel and a half by the far edge.
            grid = io.loaders.OmeZarrMetadataUtils.screenGridForRange([1 64], 2, 3);

            testCase.verifyEqual(grid.levelRange, [1 32]);
            testCase.verifyEqual(grid.size, 21);
            testCase.verifyEqual(grid.step, 64/21, 'AbsTol', 1e-12);
            testCase.verifyEqual(grid.origin, 1);
        end

        % ---- 3. the read window, asserted on values -------------------------

        function aMatchingLevelIsReadStraightThrough(testCase)
            % The case that already worked - it must keep working, or the fix
            % for the offset pyramid has broken every store that lines up.
            grid   = io.loaders.OmeZarrMetadataUtils.screenGridForRange([3 34], 1, 1);
            window = io.loaders.OmeZarrMetadataUtils.levelReadWindow(grid, 1, 100);

            testCase.verifyEqual(window.levelRange, [3 34]);
            testCase.verifyEqual(window.sourceIndex, 1:32);
        end

        function aCoarseLevelIsGatheredNotStretchedFromItsOwnStart(testCase)
            % The worked example: at scale 16, columns 3-34 cover coarse voxels
            % 1-3. Resizing those three gives 48 columns starting at column 1 -
            % right-looking labels, 2 pixels left and half again too wide.
            grid   = io.loaders.OmeZarrMetadataUtils.screenGridForRange([3 34], 1, 1);
            window = io.loaders.OmeZarrMetadataUtils.levelReadWindow(grid, 16, 7);

            testCase.verifyEqual(window.levelRange, [1 3]);
            testCase.verifyEqual(numel(window.sourceIndex), 32, ...
                'the overlay is exactly as wide as the view, never as wide as the block');
            % full-resolution 3..16 is coarse voxel 1, 17..32 is 2, 33..34 is 3
            testCase.verifyEqual(window.sourceIndex, ...
                [ones(1, 14), 2 * ones(1, 16), 3 3]);
        end

        function everyScreenPixelShowsTheVoxelThatCoversIt(testCase)
            % The value test. The gathered numbers ARE the source voxel indices,
            % and the expected ones come from where the image put that pixel in
            % space - the image shows level voxel c, whose centre sits at
            % (c - 0.5) * imageScale, and the label voxel holding that position
            % follows from the label scale alone. Neither step re-uses the
            % arithmetic under test.
            labelScale = 16;
            labelSize  = 64;
            for imageScale = [1 2 8 16]
                for fullRange = {[1 64], [3 34], [17 48], [513 1024], [990 1024]}
                    requested = fullRange{1};
                    grid = io.loaders.OmeZarrMetadataUtils.screenGridForRange( ...
                        requested, imageScale, imageScale);
                    window = io.loaders.OmeZarrMetadataUtils.levelReadWindow( ...
                        grid, labelScale, labelSize);

                    % A block whose voxels encode their own coordinates.
                    labelBlock = window.levelRange(1):window.levelRange(2);
                    gathered   = labelBlock(window.sourceIndex);

                    screenPixels  = 1:grid.size;
                    imageVoxels   = grid.levelRange(1) + screenPixels - 1;
                    centresInFull = (imageVoxels - 0.5) * imageScale;
                    expected      = min(floor(centresInFull / labelScale) + 1, labelSize);

                    testCase.verifyEqual(gathered, expected, sprintf( ...
                        'image scale %g, range %d-%d', imageScale, requested(1), requested(2)));
                end
            end
        end

        function aPixelStraddlingABoundaryTakesTheVoxelItStartsIn(testCase)
            % A screen pixel wider than two label voxels has its centre exactly
            % on the boundary between them and covers equal parts of each, so
            % which one it shows is a choice rather than a result. It happens
            % whenever the view is zoomed out past the label pyramid's coarsest
            % level - the level picker then serves 256 nm labels at magFactor
            % 512 and every pixel is a tie. The lower voxel wins, matching the
            % ceil() convention the rest of the pyramid arithmetic uses.
            grid   = io.loaders.OmeZarrMetadataUtils.screenGridForRange([1 128], 32, 32);
            window = io.loaders.OmeZarrMetadataUtils.levelReadWindow(grid, 16, 8);

            testCase.verifyEqual(grid.size, 4);
            labelBlock = window.levelRange(1):window.levelRange(2);
            testCase.verifyEqual(labelBlock(window.sourceIndex), [1 3 5 7], ...
                'pixel 1 covers label voxels 1-2 and shows 1, never 2');
        end

        function aNonIntegerMagnificationStaysInsideItsOwnPixel(testCase)
            % round() decides the pixel count when the magnification falls
            % between levels, so the step is fractional and no closed form is
            % worth asserting. What must hold is the property: the voxel a pixel
            % is served from has to overlap the span that pixel covers.
            imageScale = 2;
            magFactor  = 3;
            labelScale = 16;
            grid   = io.loaders.OmeZarrMetadataUtils.screenGridForRange([1 64], imageScale, magFactor);
            window = io.loaders.OmeZarrMetadataUtils.levelReadWindow(grid, labelScale, 4);

            labelBlock = window.levelRange(1):window.levelRange(2);
            gathered   = labelBlock(window.sourceIndex);

            for screenPixel = 1:grid.size
                pixelStart = (grid.origin - 1) + (screenPixel - 1) * grid.step;
                pixelEnd   = (grid.origin - 1) + screenPixel * grid.step;
                voxelStart = (gathered(screenPixel) - 1) * labelScale;
                voxelEnd   = gathered(screenPixel) * labelScale;
                testCase.verifyLessThan(voxelStart, pixelEnd, ...
                    sprintf('pixel %d is served from a voxel that starts after it', screenPixel));
                testCase.verifyGreaterThan(voxelEnd, pixelStart, ...
                    sprintf('pixel %d is served from a voxel that ends before it', screenPixel));
            end
        end

        function theWindowNeverReadsPastTheEndOfTheLevel(testCase)
            % A level published with a floor-rounded shape is one voxel short of
            % the volume. Repeating its last voxel is a pixel of slop at the far
            % edge; reading voxel 7 of a 6-voxel array is an error out of the
            % zarr engine, several layers down from anything that could explain it.
            grid   = io.loaders.OmeZarrMetadataUtils.screenGridForRange([81 100], 1, 1);
            window = io.loaders.OmeZarrMetadataUtils.levelReadWindow(grid, 16, 6);

            testCase.verifyEqual(window.levelRange, [6 6]);
            testCase.verifyEqual(window.sourceIndex, ones(1, 20));
        end

        function aSliceAxisPicksOneLabelSliceWithNoResize(testCase)
            % z is never magnified: pass the image's own z scale as the step and
            % the same pair of calls gives one label slice per image slice.
            grid   = io.loaders.OmeZarrMetadataUtils.screenGridForRange([33 33], 1, 1);
            window = io.loaders.OmeZarrMetadataUtils.levelReadWindow(grid, 16, 5);

            testCase.verifyEqual(grid.size, 1);
            testCase.verifyEqual(window.levelRange, [3 3], ...
                'full-resolution slice 33 is the third slice of a 16x downsample');

            deepGrid   = io.loaders.OmeZarrMetadataUtils.screenGridForRange([32 32], 1, 1);
            deepWindow = io.loaders.OmeZarrMetadataUtils.levelReadWindow(deepGrid, 16, 5);
            testCase.verifyEqual(deepWindow.levelRange, [2 2], ...
                'and slice 32 is still the second - the boundary is between them');
        end

        function theTwoAxesCombineIntoOneIndexedRead(testCase)
            % How a caller actually applies the result. Both axes at once,
            % against a block whose voxels encode their own coordinates.
            gridY = io.loaders.OmeZarrMetadataUtils.screenGridForRange([3 34], 1, 1);
            gridX = io.loaders.OmeZarrMetadataUtils.screenGridForRange([17 48], 1, 1);
            windowY = io.loaders.OmeZarrMetadataUtils.levelReadWindow(gridY, 16, 7);
            windowX = io.loaders.OmeZarrMetadataUtils.levelReadWindow(gridX, 16, 7);

            [voxelY, voxelX] = ndgrid(windowY.levelRange(1):windowY.levelRange(2), ...
                windowX.levelRange(1):windowX.levelRange(2));
            block = uint16(voxelY * 100 + voxelX);

            slice = block(windowY.sourceIndex, windowX.sourceIndex);

            testCase.verifyEqual(size(slice), [gridY.size, gridX.size], ...
                'labeloverlay composites the two layers directly - the sizes must agree');
            testCase.verifyEqual(slice(1, 1), uint16(1 * 100 + 2), ...
                'the top left pixel is full-resolution (3,17), i.e. label voxel (1,2)');
            testCase.verifyEqual(slice(end, end), uint16(3 * 100 + 3), ...
                'and the bottom right is (34,48), i.e. label voxel (3,3)');
        end

        % ---- 4. the coupling to the image loader ---------------------------

        function theScreenGridPredictsWhatTheImageLoaderReturns(testCase)
            % Everything above assumes screenGridForRange reproduces
            % getDataZarr's own arithmetic. That is a copy of a formula living
            % in another file, so it is asserted against the real loader rather
            % than against itself - if getDataZarr ever rounds differently, the
            % overlay stops compositing and this is what says why.
            testCase.buildLocalStore();

            options = struct('datasetMode', 'Virtual', 'ParentFigure', []);
            loader  = io.loaders.Zarr2VirtualSetupLoader(options);
            [imginfo, files] = loader.loadMetadata({testCase.StorePath}, options);
            [~, imginfo] = loader.loadImages(files, imginfo, options);

            virtualImage = core.MibVirtualImage();
            virtualImage.initialize({testCase.StorePath}, imginfo);

            requestY = [5 60];
            requestX = [9 88];
            for magFactor = [1 2 3]
                slice = virtualImage.getDataZarr('image', 3, [], struct( ...
                    'magFactor', magFactor, 'y', requestY, 'x', requestX, 'z', [3 3]));

                levelScales = virtualImage.pyramid.levelScaleFactors;
                [~, levelIdx] = min(abs(levelScales(:, 1) - magFactor));
                gridY = io.loaders.OmeZarrMetadataUtils.screenGridForRange( ...
                    requestY, levelScales(levelIdx, 1), magFactor);
                gridX = io.loaders.OmeZarrMetadataUtils.screenGridForRange( ...
                    requestX, levelScales(levelIdx, 2), magFactor);

                testCase.verifyEqual(size(slice, 1), gridY.size, ...
                    sprintf('rows at magFactor %g', magFactor));
                testCase.verifyEqual(size(slice, 2), gridX.size, ...
                    sprintf('columns at magFactor %g', magFactor));
            end
        end
    end

    methods (TestMethodTeardown)
        function restore(testCase)
            if ~isempty(testCase.OriginalZarrLibrary)
                io.zarr.Config.setLibrary(testCase.OriginalZarrLibrary);
                testCase.OriginalZarrLibrary = [];
            end
            if ~isempty(testCase.TempDir) && isfolder(testCase.TempDir)
                rmdir(testCase.TempDir, 's');
                testCase.TempDir = '';
            end
        end
    end

    methods (Access = private)
        function registration = registerNuc(testCase)
            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                testCase.LabelVoxelSizesUm, testCase.VolumeOuterBoxUm, ...
                testCase.ImageVoxelSizesUm, testCase.VolumeOuterBoxUm);
        end

        function buildLocalStore(testCase)
            % A two-level OME-Zarr v2 pyramid, native engine only, so the
            % loader coupling can be checked offline and without python.
            testCase.OriginalZarrLibrary = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');

            testCase.TempDir = fullfile(tempdir, 'mib_level_registration_test');
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
            mkdir(testCase.TempDir);
            testCase.StorePath = fullfile(testCase.TempDir, 'volume.zarr2');

            group  = io.zarr.Group.create(testCase.StorePath, 'zarrFormat', 2);
            level0 = group.createArray('s0', testCase.Level0Shape, 'uint8', ...
                'chunkShape', [4 16 16], 'fillValue', 0);
            level1 = group.createArray('s1', testCase.Level1Shape, 'uint8', ...
                'chunkShape', [4 16 16], 'fillValue', 0);
            level0.write(ones(testCase.Level0Shape, 'uint8'));
            level1.write(ones(testCase.Level1Shape, 'uint8'));

            axesDefinition = {struct('name','z','type','space','unit','nanometer'), ...
                              struct('name','y','type','space','unit','nanometer'), ...
                              struct('name','x','type','space','unit','nanometer')};
            datasets = { ...
                struct('path','s0','coordinateTransformations', ...
                    {{struct('type','scale','scale',[2 2 2])}}), ...
                struct('path','s1','coordinateTransformations', ...
                    {{struct('type','scale','scale',[4 4 4])}})};
            group.setAttributes(struct('multiscales', {{struct('version','0.4', ...
                'axes', {axesDefinition}, 'datasets', {datasets})}}));
        end
    end
end
