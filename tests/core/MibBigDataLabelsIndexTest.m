classdef MibBigDataLabelsIndexTest < matlab.unittest.TestCase
% MIBBIGDATALABELSINDEXTEST - A label pyramid served over an image it does not match.
%
% Builds a local OME-Zarr v2 label pyramid starting at 128 nm and attaches it to a
% notional 8 nm image, which is the ``jrc_mus-kidney`` shape: the labels' own level
% 0 is the image's ``s4``. Offline and native-backend only.
%
% Every voxel of the finest label level carries a value encoding its own
% coordinates, so the failures this class exists to prevent change the **values**
% rather than the dimensions:
%
%   * numbering the levels from the store's own level 0 puts the labels at
%     one-sixteenth size - a shape check sees nothing, since the shape is decided
%     by the view;
%   * resizing the covering block instead of gathering from it shifts them by up to
%     15 pixels at 128 nm.
%
% The store is uint16 with ids from 101 up, so the packed-byte failure
% (``MibLabels63`` turning 255 into material 63 with the mask and selection bits
% set) would also be visible in the values rather than silent.

    properties (Access = private)
        TempDir
        StorePath
        OriginalZarrLibrary
        RawLevel0            % the finest level as written, MIB [y x z] order
        RawLevel1            % the middle level, MIB [y x z] order
    end

    properties (Constant, Access = private)
        % z, y, x - the store's own C-order, matching its declared axes
        Level0Shape = [4, 16, 16]
        Level1Shape = [2, 8, 8]
        Level2Shape = [1, 4, 4]
        % nanometres, as the store declares them: 128 / 256 / 512
        LevelScalesNm = [128 256 512]

        % The image these labels attach to: 8 nm, six levels, same volume.
        ImageShapeYXZ = [256 256 64]
        % Outer extent in micrometres, edge-based: 256 voxels of 8 nm from a first
        % voxel centred on the origin.
        ImageOuterBoxUm = [-0.004 2.044 -0.004 2.044 -0.004 0.508]
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

            testCase.TempDir = fullfile(tempdir, 'mib_labels_index_test');
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
            mkdir(testCase.TempDir);
            testCase.StorePath = fullfile(testCase.TempDir, 'nuc.zarr2');

            group = io.zarr.Group.create(testCase.StorePath, 'zarrFormat', 2);
            level0 = group.createArray('s0', testCase.Level0Shape, 'uint16', ...
                'chunkShape', [2 8 8], 'fillValue', 0);
            level1 = group.createArray('s1', testCase.Level1Shape, 'uint16', ...
                'chunkShape', [2 8 8], 'fillValue', 0);
            level2 = group.createArray('s2', testCase.Level2Shape, 'uint16', ...
                'chunkShape', [1 4 4], 'fillValue', 0);

            % Each voxel is its own object, numbered by its coordinates: a shift in
            % any axis lands on an id that cannot be confused with a neighbour.
            % Every value is above 63, so the packed-byte ceiling would show.
            [zz, yy, xx] = ndgrid(0:testCase.Level0Shape(1)-1, ...
                0:testCase.Level0Shape(2)-1, 0:testCase.Level0Shape(3)-1);
            level0Data = uint16(zz*10000 + (yy+1)*100 + (xx+1));
            level0.write(level0Data);
            testCase.RawLevel0 = permute(level0Data, [2 3 1]);   % [z,y,x] -> [y,x,z]

            level1Data = uint16(500 + reshape(1:prod(testCase.Level1Shape), testCase.Level1Shape));
            level1.write(level1Data);
            testCase.RawLevel1 = permute(level1Data, [2 3 1]);   % [z,y,x] -> [y,x,z]
            level2.write(uint16(60000 * ones(testCase.Level2Shape)));

            axesDefinition = {struct('name','z','type','space','unit','nanometer'), ...
                              struct('name','y','type','space','unit','nanometer'), ...
                              struct('name','x','type','space','unit','nanometer')};
            datasets = cell(1, 3);
            for levelIndex = 1:3
                scale = repmat(testCase.LevelScalesNm(levelIndex), 1, 3);
                datasets{levelIndex} = struct('path', sprintf('s%d', levelIndex-1), ...
                    'coordinateTransformations', {{struct('type','scale','scale',scale)}});
            end
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

        % ---- 1. registration, the silent-16x guard --------------------------

        function theStoreRegistersInTheImagesScaleSpaceNotItsOwn(testCase)
            labels = testCase.attachLabels();

            testCase.verifyEqual(labels.modelScaleFactors(:, 1)', [16 32 64], ...
                'the 128 nm level is scale 16 over an 8 nm image, not scale 1');
            testCase.verifyEqual(labels.imageScaleFactors(:, 1)', 2 .^ (0:5), ...
                'and the image keeps its own magnification axis');
            testCase.verifyEqual([labels.height, labels.width, labels.depth], ...
                testCase.ImageShapeYXZ, ...
                'the dimensions are the image''s full resolution, not the store''s');
        end

        function aPyramidOverADifferentVolumeIsRefusedAtOpen(testCase)
            reference = testCase.imageReference();
            reference.outerBoxUm = reference.outerBoxUm * 4;

            labels = core.MibBigDataLabelsIndex();
            testCase.verifyError(@() labels.openStore(testCase.StorePath, reference), ...
                'core:MibBigDataLabelsIndex:openStore');
            testCase.verifyFalse(labels.exists, ...
                'a refused registration must not leave a half-attached store');
        end

        % ---- 2. reads, asserted on values -----------------------------------

        function aReadAtTheMatchingMagnificationIsTheRawArray(testCase)
            % magFactor 16 is where the image shows its s4 and the labels their own
            % level 0 - the one case where no resampling of any kind is involved, so
            % the result has to be the stored array itself.
            labels = testCase.attachLabels();
            slice = labels.getData('labels', 3, [], struct( ...
                'magFactor', 16, 'y', [1 256], 'x', [1 256], 'z', [17 17]));

            % full-resolution slice 17 sits in label slice ceil(17/16) = 2
            testCase.verifyEqual(slice, testCase.RawLevel0(:, :, 2), ...
                'a matching-level read must be byte-identical to the store');
        end

        function aFullResolutionReadUpsamplesInPlaceWithoutShifting(testCase)
            % The feature. At magFactor 1 the labels have no matching level, so the
            % finest one is stretched across the view - and it has to land where the
            % image put it. The expected voxels come from ceil(fullRes / 16), worked
            % out here rather than taken from the code under test.
            labels = testCase.attachLabels();
            requestY = 3:34;
            requestX = 17:48;
            slice = labels.getData('labels', 3, [], struct( ...
                'magFactor', 1, 'y', [requestY(1) requestY(end)], ...
                'x', [requestX(1) requestX(end)], 'z', [17 17]));

            expected = testCase.RawLevel0(ceil(requestY / 16), ceil(requestX / 16), ...
                ceil(17 / 16));

            testCase.verifySize(slice, [32 32], ...
                'the overlay is the size of the view, never the size of the block');
            testCase.verifyEqual(slice, expected, ...
                'an off-by-one here is 15 pixels of displacement at this scale');
        end

        function theOverlayIsTheSizeTheImageLayerReturns(testCase)
            % labeloverlay composites the two arrays directly, so a size that merely
            % looks reasonable is an error rather than a misplacement. Checked
            % against the same helper the image loader is pinned to.
            labels = testCase.attachLabels();
            for magFactor = [1 2 8 16 32]
                slice = labels.getData('labels', 3, [], struct( ...
                    'magFactor', magFactor, 'y', [5 200], 'x', [9 240], 'z', [17 17]));

                imageScale = labels.imageScaleForMagFactor(magFactor);
                gridY = io.loaders.OmeZarrMetadataUtils.screenGridForRange( ...
                    [5 200], imageScale(1), magFactor);
                gridX = io.loaders.OmeZarrMetadataUtils.screenGridForRange( ...
                    [9 240], imageScale(2), magFactor);

                testCase.verifySize(slice, [gridY.size, gridX.size], ...
                    sprintf('at magFactor %g', magFactor));
            end
        end

        function aWholeVolumeReadComesBackAtTheImageLevelsDimensions(testCase)
            % What the 3D renderer needs, and the read it gets wrong if it treats the
            % level picked from the IMAGE pyramid as an index into this one: the two
            % lists have different lengths (6 against 3 here), so image level 5 would
            % clamp to the labels' coarsest and arrive 4x too coarse. Asking by
            % magnification instead is level-list agnostic, and z is included because
            % a volume read is the only caller that magnifies all three axes.
            labels = testCase.attachLabels();
            for imageLevel = 1:size(labels.imageScaleFactors, 1)
                magFactor = labels.imageScaleFactors(imageLevel, 1);
                volume = labels.getData('labels', 3, [], struct('magFactor', magFactor));

                expectedSize = ceil(testCase.ImageShapeYXZ ./ ...
                    labels.imageScaleFactors(imageLevel, :));
                testCase.verifySize(volume, expectedSize, ...
                    sprintf('at image level %d (magFactor %g)', imageLevel, magFactor));
            end
        end

        function anXZSliceReadsTheSameVoxelsTransposed(testCase)
            % The orientation mapping is shared with getDataZarr and easy to get
            % subtly wrong - the slice axis becomes a physical axis that is NOT the
            % one the caller named.
            labels = testCase.attachLabels();
            slice = labels.getData('labels', 1, [], struct( ...
                'magFactor', 16, 'z', [17 17], 'y', [1 64], 'x', [1 256]));

            % orient 1 slices at physical y (label voxel 2) and lays out [z, x]:
            % options.x is the horizontal range (X), options.y the vertical one (Z)
            expected = squeeze(testCase.RawLevel0(2, :, :)).';
            testCase.verifyEqual(slice, expected);
        end

        function anExplicitLevelIsReturnedVoxelForVoxel(testCase)
            % Same meaning the field has in getData63: this resolution,
            % unresampled. It is also the read contract MibImageSliceProvider
            % needs, so the export path depends on it returning the STORED
            % voxels and not a view of them.
            labels = testCase.attachLabels();
            slice = labels.getData('labels', 3, [], struct('pyramidLevel', 2, ...
                'y', [1 256], 'x', [1 256], 'z', [1 1]));

            testCase.verifySize(slice, [8 8], 'level 2 of this store is 8 x 8 per slice');
            testCase.verifyEqual(slice, testCase.RawLevel1(:, :, 1), ...
                'and it is that level''s own array, not the image-resolution view of it');
        end

        % ---- 3. what the values mean ----------------------------------------

        function idsAboveSixtyThreeSurviveTheRead(testCase)
            labels = testCase.attachLabels();
            slice = labels.getData('labels', 3, [], struct( ...
                'magFactor', 16, 'y', [1 256], 'x', [1 256], 'z', [17 17]));

            testCase.verifyClass(slice, 'uint16');
            testCase.verifyEqual(labels.maxMaterials, 65535);
            % label voxel (16,16) of slice 2 - the highest id in that plane
            testCase.verifyEqual(slice(16, 16), uint16(1 * 10000 + 16 * 100 + 16));
            testCase.verifyGreaterThan(min(slice(:)), uint16(63), ...
                'every id in this store is above the packed-byte ceiling');
        end

        function theDefaultShowsEachObjectSeparately(testCase)
            % Per-object is the default: the object ids are what the store actually
            % carries, and merging them is the lossy view. Constructed here rather than
            % through attachLabels, which sets the field explicitly - the point of this
            % test is the value nobody set.
            labels = core.MibBigDataLabelsIndex();
            testCase.verifyTrue(labels.renderPerObject, ...
                'a freshly constructed overlay renders per object');

            labels.openStore(testCase.StorePath, testCase.imageReference());
            slice = labels.getData('labels', 3, [], struct( ...
                'magFactor', 16, 'y', [1 256], 'x', [1 256], 'z', [17 17]));

            testCase.verifyGreaterThan(numel(unique(slice(:))), 1, ...
                'the ids survive to the display without being asked to');
        end

        function collapsingToOneMaterialFusesEveryObject(testCase)
            % The opt-out: 864 unrelated objects read as one structure, which is what
            % is wanted when the question is "where are the nuclei" rather than "which
            % nucleus is this".
            labels = testCase.attachLabels();
            labels.renderPerObject = false;
            slice = labels.getData('labels', 3, [], struct( ...
                'magFactor', 16, 'y', [1 256], 'x', [1 256], 'z', [17 17]));

            testCase.verifyEqual(unique(slice(:))', uint16(1), ...
                'every voxel of this store is occupied, so all of it is material 1');
            testCase.verifyEqual(labels.countMaterials(), 1);
        end

        function aSingleObjectCanBeExtractedAsABinaryMap(testCase)
            labels = testCase.attachLabels();
            objectId = double(testCase.RawLevel0(5, 7, 2));
            slice = labels.getData('labels', 3, objectId, struct( ...
                'magFactor', 16, 'y', [1 256], 'x', [1 256], 'z', [17 17]));

            testCase.verifyClass(slice, 'uint8');
            testCase.verifyEqual(sum(slice(:)), 1, ...
                'exactly one voxel carries that id');
            testCase.verifyEqual(slice(5, 7), uint8(1));
        end

        function askingForOneObjectIgnoresTheSingleMaterialCollapse(testCase)
            % renderPerObject is a DISPLAY setting, so it must not decide what a
            % caller naming an object id gets back. Collapsing first makes id 1 match
            % every object in the volume and every other id match nothing - which is
            % what "Generate surface by index..." and a MaterialIndex export both ran
            % into: one merged surface over 2165 nuclei instead of one nucleus.
            labels = testCase.attachLabels();
            labels.renderPerObject = false;
            objectId = double(testCase.RawLevel0(5, 7, 2));
            readOptions = struct('magFactor', 16, 'y', [1 256], 'x', [1 256], 'z', [17 17]);

            slice = labels.getData('labels', 3, objectId, readOptions);
            testCase.verifyEqual(sum(slice(:)), 1, ...
                'still exactly one voxel, not the union of the whole store');
            testCase.verifyEqual(slice(5, 7), uint8(1));

            merged = labels.getData('labels', 3, 1, readOptions);
            testCase.verifyEqual(sum(merged(:)), 0, ...
                'id 1 belongs to no object here, so it must match nothing');

            testCase.verifyEqual(unique(labels.getData('labels', 3, [], readOptions))', ...
                uint16(1), 'and the display read still collapses');
        end

        function reportingOneMaterialDoesNotDestroyTheStoredCount(testCase)
            % countMaterials reports 1 while the objects are fused, but the fusing is
            % a display setting the user can switch off again. Writing the 1 into
            % materialsCount lost the store's own count for good - and the count is
            % what tells the user how many objects a merged surface would span.
            labels = testCase.attachLabels();
            highestId = double(max(testCase.RawLevel0(:)));
            labels.renderPerObject = false;

            testCase.verifyEqual(labels.countMaterials(), 1, ...
                'the fused layer reports a single material');
            testCase.verifyEqual(labels.materialsCount, highestId, ...
                'but the measured object count survives the report');

            labels.renderPerObject = true;
            testCase.verifyEqual(labels.countMaterials(), highestId, ...
                'so switching per-object back on recovers it');
        end

        function theObjectCountComesFromAProbeNotAVolumeScan(testCase)
            % core.MibLabels.countMaterials scans every voxel for maxMaterials >= 256,
            % which here is a remote volume. openStore reads a single small level
            % instead - the finest one inside its voxel budget, which for this
            % three-level store is s0.
            labels = testCase.attachLabels();
            highestId = double(max(testCase.RawLevel0(:)));

            testCase.verifyEqual(labels.materialsCount, highestId);
            testCase.verifyEqual(labels.countMaterials(), highestId);
        end

        function theCountIsNotTakenFromTheCoarsestLevel(testCase)
            % The regression this store is shaped to catch. Probing only the coarsest
            % level is what jrc_mus-kidney-2's nuc breaks: its bottom level is 3x3x3,
            % every nucleus has been downsampled out of existence by then, and the
            % count came back as 1. Here the coarsest level is filled with a single
            % id 60000 that appears nowhere else, so reading it instead of a finer
            % level is visible rather than merely inaccurate.
            labels = testCase.attachLabels();
            coarsest = labels.modelArrays{end}.read();

            testCase.verifyEqual(double(max(coarsest(:))), 60000, ...
                'the fixture still marks its coarsest level');
            testCase.verifyNotEqual(labels.materialsCount, 60000, ...
                'and the reported count does not come from there');
            testCase.verifyEqual(labels.materialsCount, double(max(testCase.RawLevel0(:))), ...
                'it comes from the finest level the budget allows');
        end

        % ---- 4. read-only, and nothing in memory ----------------------------

        function writingIsBlockedAndTheStoreIsNotTouched(testCase)
            labels = testCase.attachLabels();
            % The notice is a modal dialog shown once per session; flip its flag
            % first so the suite asserts the guard rather than opening a window.
            labels.readOnlyWarningShown = true;

            before = io.zarr.Array(fullfile(testCase.StorePath, 's0')).read();
            result = labels.setData(ones(16, 16, 'uint16'), 'labels', 3, [], struct());
            labels.setDataFast(ones(16, 16, 'uint16'), 1, 1, 1);
            after = io.zarr.Array(fullfile(testCase.StorePath, 's0')).read();

            testCase.verifyFalse(result, 'a blocked write must report that it failed');
            testCase.verifyEqual(after, before, 'the store on disk must be untouched');
            testCase.verifyEmpty(labels.data, ...
                'setDataFast writes into obj.data - here it must not allocate one');
        end

        % ---- 4b. exporting a chosen level ----------------------------------

        function aChosenLevelIsExportedToAModelFile(testCase)
            % Read-only is not the same as un-exportable. "Save model as..."
            % writes ONE pyramid level, and the level has to be chosen because
            % these labels have no full-resolution one to default to - writing
            % what the image is showing would upsample the whole volume to a
            % resolution the labels never had.
            labels  = testCase.attachLabels();
            outFile = fullfile(testCase.TempDir, 'Labels_nuc.model');

            fnOut = labels.save(outFile, testCase.saveOptions(1));

            testCase.verifyEqual(fnOut, outFile);
            saved = load(outFile, '-mat');
            testCase.verifyEqual(saved.mibModel, testCase.RawLevel0, ...
                'the exported volume must be the store''s own level, value for value');
            testCase.verifyEqual(saved.modelType, 65535);
            testCase.verifyEqual(saved.modelMaterialNames(:)', {'1', '2'}, ...
                'the >255-material convention carries the index in the name');
        end

        function exportingACoarserLevelWritesThatLevel(testCase)
            % The point of asking: a different answer has to give a different
            % file, at that level's own dimensions.
            labels  = testCase.attachLabels();
            outFile = fullfile(testCase.TempDir, 'Labels_nuc_s1.model');

            labels.save(outFile, testCase.saveOptions(2));

            saved = load(outFile, '-mat');
            testCase.verifyEqual(saved.mibModel, testCase.RawLevel1, ...
                'level 2 is 8 x 8 x 2 and is written as such');
        end

        function anExportHoldsNothingInMemory(testCase)
            % Streamed a slice at a time through MibImageSliceProvider, so the
            % file may be large but the process is not. A gather here would be a
            % whole remote volume - jrc_mus-liver-6's er segmentation is 510 GiB.
            labels  = testCase.attachLabels();
            outFile = fullfile(testCase.TempDir, 'Labels_stream.model');

            labels.save(outFile, testCase.saveOptions(1));

            testCase.verifyEmpty(labels.data, ...
                'the export must not materialise the volume in the layer');
        end

        function anOutOfRangeExportLevelIsClampedNotRefused(testCase)
            % A stale batch protocol naming level 9 of a 3-level pyramid gets the
            % coarsest, not an error out of the zarr engine four frames down.
            labels  = testCase.attachLabels();
            outFile = fullfile(testCase.TempDir, 'Labels_clamped.model');

            labels.save(outFile, testCase.saveOptions(9));

            saved = load(outFile, '-mat');
            testCase.verifySize(saved.mibModel, [4 4 1], ...
                'the coarsest level of this store is 4 x 4 x 1');
        end

        function aSingleObjectCanBeExportedOnItsOwn(testCase)
            % MaterialIndex reaches the provider, so one object can be written
            % out as a binary volume without gathering the rest.
            labels  = testCase.attachLabels();
            outFile = fullfile(testCase.TempDir, 'Labels_one.model');
            options = testCase.saveOptions(1);
            options.MaterialIndex = double(testCase.RawLevel0(5, 7, 2));

            labels.save(outFile, options);

            saved = load(outFile, '-mat');
            expected = uint8(testCase.RawLevel0 == uint16(options.MaterialIndex));
            testCase.verifyEqual(saved.mibModel, expected, ...
                'exactly the one object, as a binary volume');
        end

        function nothingIsHeldInMemory(testCase)
            labels = testCase.attachLabels();
            labels.getData('labels', 3, [], struct('magFactor', 1, ...
                'y', [1 256], 'x', [1 256], 'z', [17 17]));

            testCase.verifyEmpty(labels.data, ...
                'a browsing read must not materialise the volume');
        end

        function everythingIsRefusedRatherThanReturningLabels(testCase)
            % 'everything' means the packed byte with all three layers, which does not
            % exist outside the MibLabels63 family. Returning the labels instead would
            % be read by the caller as a mask and a selection that are always empty.
            labels = testCase.attachLabels();
            testCase.verifyError(@() labels.getData('everything', 3, [], struct()), ...
                'core:MibBigDataLabelsIndex:getData');
        end

        function maskAndSelectionComeBackEmptyAtTheRightSize(testCase)
            labels = testCase.attachLabels();
            readOptions = struct('magFactor', 1, 'y', [3 34], 'x', [17 48], 'z', [17 17]);

            labelSlice     = labels.getData('labels', 3, [], readOptions);
            maskSlice      = labels.getData('mask', 3, [], readOptions);
            selectionSlice = labels.getData('selection', 3, [], readOptions);

            testCase.verifySize(maskSlice, size(labelSlice));
            testCase.verifySize(selectionSlice, size(labelSlice));
            testCase.verifyEqual(max(maskSlice(:)), uint8(0));
            testCase.verifyEqual(max(selectionSlice(:)), uint8(0));
        end

        % ---- 5. describing the image to register against --------------------

        function theImageReferenceIsTakenFromTheLevelsTheImageItselfUses(testCase)
            % imageReference is shared with controllers.SelectFromUrl, so the
            % route the info panel promises and the one loadModel takes cannot
            % diverge. The voxel sizes come from levelScaleFactors - the table
            % getDataZarr picks levels with - rather than from levelVoxelSizes,
            % so the overlay's idea of the magnification axis is the image's own.
            image = core.MibImage();
            image.height = 256; image.width = 256; image.depth = 64;
            pixSize = image.pixSize;
            % Anisotropic on purpose: a [y x z] table read as [x y z] would swap
            % two equal numbers and pass unnoticed.
            pixSize.x = 8; pixSize.y = 8; pixSize.z = 40; pixSize.units = 'nm';
            image.pixSize = pixSize;
            image.boundingBox = [0 255*8 0 255*8 0 63*40];
            image.pyramid = struct('levelScaleFactors', 2 .^ (0:5)' * [1 1 1]);

            reference = core.MibBigDataLabelsIndex.imageReference(image);

            testCase.verifyTrue(reference.ok, reference.reason);
            testCase.verifyEqual(reference.shapeYXZ, [256 256 64]);
            testCase.verifyEqual(reference.voxelSizesXYZ(1, :), [0.008 0.008 0.040], ...
                'AbsTol', 1e-12, 'level 0 is the voxel size itself, in micrometres');
            testCase.verifyEqual(reference.voxelSizesXYZ(6, :), [0.256 0.256 1.280], ...
                'AbsTol', 1e-12, 'and every level scales from it');
            % half a voxel wider than the centre-based box at each end
            testCase.verifyEqual(reference.outerBoxUm, ...
                [-0.004 2.044 -0.004 2.044 -0.020 2.540], 'AbsTol', 1e-12);
        end

        function aSingleLevelImageIsStillAUsableReference(testCase)
            % core.MibImage.initialize:157 gives EVERY image a pyramid with
            % levelScaleFactors = [1 1 1], so "no pyramid" is not the state a
            % non-pyramidal dataset is in - it has one level, scale 1. That is a
            % perfectly good scale space to register coarse labels against, and
            % refusing it would rule out the case for no reason.
            image = core.MibImage();
            image.boundingBox = [0 1 0 1 0 1];

            reference = core.MibBigDataLabelsIndex.imageReference(image);

            testCase.verifyTrue(reference.ok, reference.reason);
            testCase.verifySize(reference.voxelSizesXYZ, [1 3], ...
                'one level, and the registration then has one scale to match');
        end

        function anImageWhosePyramidWasClearedIsReportedNotGuessed(testCase)
            image = core.MibImage();
            image.boundingBox = [0 1 0 1 0 1];
            image.pyramid = [];

            reference = core.MibBigDataLabelsIndex.imageReference(image);

            testCase.verifyFalse(reference.ok);
            testCase.verifySubstring(reference.reason, 'no pyramid');
        end

        function anImageWithNoBoundingBoxIsReportedNotGuessed(testCase)
            % Without a box the two volumes cannot be compared at all, and the
            % extent check is the only thing standing between a scale factor and
            % labels placed over a different volume.
            image = core.MibImage();
            image.boundingBox = [];

            reference = core.MibBigDataLabelsIndex.imageReference(image);

            testCase.verifyFalse(reference.ok);
            testCase.verifySubstring(reference.reason, 'bounding box');
        end

        function anUnattachedContainerReadsAsEmpty(testCase)
            labels = core.MibBigDataLabelsIndex();
            testCase.verifyFalse(labels.exists);
            testCase.verifyEqual(labels.type, 'labels', ...
                'MibImage maps class to type with a switch that has no branch here');
            testCase.verifyEmpty(labels.getData('labels', 3, [], struct()));
        end
    end

    methods (Access = private)
        function reference = imageReference(testCase)
            reference = struct( ...
                'shapeYXZ', testCase.ImageShapeYXZ, ...
                'voxelSizesXYZ', 0.008 * 2 .^ (0:5)' * [1 1 1], ...
                'outerBoxUm', testCase.ImageOuterBoxUm);
        end

        function options = saveOptions(testCase, pyramidLevel)
            % SAVEOPTIONS - What MibDataset.saveImage injects, for one level.
            % pixSize is the IMAGE's full-resolution voxel size; MibLabels.save
            % scales it by the chosen level's factors.
            options = struct( ...
                'Format', 'Matlab format (*.model)', ...
                'PyramidLevel', pyramidLevel, ...
                'silent', true, 'showWaitbar', false, 'overwrite', true, ...
                'pixSize', struct('x', 8, 'y', 8, 'z', 8, 't', 1, ...
                    'units', 'nm', 'tunits', 's'), ...
                'boundingBox', testCase.ImageOuterBoxUm * 1000);
        end

        function labels = attachLabels(testCase)
            labels = core.MibBigDataLabelsIndex();
            labels.openStore(testCase.StorePath, testCase.imageReference());
            % Stated rather than inherited: the value tests need the ids, and they
            % should keep passing if the default is ever reconsidered again.
            labels.renderPerObject = true;
        end
    end
end
