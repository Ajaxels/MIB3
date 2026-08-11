classdef OmeZarrWorldGeometryTest < matlab.unittest.TestCase
% OMEZARRWORLDGEOMETRYTEST - World coordinates and region arithmetic for OME-Zarr.
%
% Covers the geometry that lets MIB open a sub-volume of a remote store: where a
% group sits in its container's coordinate space, and which voxels of a pyramid
% a physical region covers.
%
% **Why these assert exact numbers rather than approximate ones.** Every failure
% mode here is a fraction of a voxel. A centre/edge confusion, a right-alignment
% mistake on a 5-axis store, or a floating-point ``floor`` at 597.9999999 all
% produce a result of the correct shape and type, holding real pixels, shifted
% by one voxel against the image it is supposed to line up with. Nothing about
% it looks wrong afterwards, so the arithmetic is pinned to the digit.
%
% The reference numbers come from the live OpenOrganelle ``jrc_hela-2`` store
% and are embedded here so the checks run offline.

    properties (Constant, Access = private)
        % Real coordinateTransformations from jrc_hela-2, axes z,y,x in nm.
        CropScale       = [2.62, 2, 2]
        CropTranslation = [3132.21, 899, 25863]
        CropShape       = [200, 1000, 1000]      % z, y, x
        EmScale         = [5.24, 4, 4]
        EmShape         = [6368, 1600, 12000]
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % ---- translations -------------------------------------------------

        function translationIsZeroWhenAbsent(testCase)
            % Every store MIB read before this existed declares no translation
            % and must keep landing at the origin. A default of ones - the value
            % the scale sibling of this function uses - would move all of them.
            transforms = {struct('type', 'scale', 'scale', [2 2 2])};
            translation = io.loaders.OmeZarrMetadataUtils.extractTranslationFromCT(transforms, 3);
            testCase.verifyEqual(translation, [0 0 0]);
        end

        function translationRightAlignsOnFiveAxes(testCase)
            % OME puts t and c before the spatial axes, so a 3-value transform
            % on a 5-axis store describes z,y,x and belongs at the END.
            transforms = {struct('type', 'translation', 'translation', [5 1 2])};
            translation = io.loaders.OmeZarrMetadataUtils.extractTranslationFromCT(transforms, 5);
            testCase.verifyEqual(translation, [0 0 5 1 2]);
        end

        function translationIgnoresAScaleOnlyTransform(testCase)
            transforms = struct('type', 'scale', 'scale', [1 1 1]);
            testCase.verifyEqual( ...
                io.loaders.OmeZarrMetadataUtils.extractTranslationFromCT(transforms, 3), [0 0 0]);
        end

        % ---- world bounding boxes -----------------------------------------

        function worldBoxMatchesTheLiveCropMetadata(testCase)
            multiscale = testCase.buildMultiscale(testCase.CropScale, testCase.CropTranslation);
            box = io.loaders.OmeZarrMetadataUtils.worldBoundingBox( ...
                multiscale, 1, testCase.CropShape);

            % Centre of the first voxel to the centre of the last: (n-1)*scale.
            testCase.verifyEqual(box, ...
                [25863, 25863 + 999*2, 899, 899 + 999*2, 3132.21, 3132.21 + 199*2.62], ...
                'AbsTol', 1e-9);
        end

        function worldBoxIsTheOriginWithoutTransforms(testCase)
            multiscale = struct('axes', testCase.spatialAxes(), ...
                'datasets', struct('path', '0'));
            box = io.loaders.OmeZarrMetadataUtils.worldBoundingBox(multiscale, 1, [10 20 30]);
            testCase.verifyEqual(box, [0 29 0 19 0 9], ...
                'no coordinateTransformations must mean scale 1 at the origin');
        end

        function worldBoxHandlesFiveAxes(testCase)
            axes5 = struct('name', {'t','c','z','y','x'}, ...
                'type', {'time','channel','space','space','space'}, ...
                'unit', {'','','micrometer','micrometer','micrometer'});
            dataset = struct('path', '0', 'coordinateTransformations', ...
                {{struct('type','scale','scale',[1 1 2 0.1 0.1]), ...
                  struct('type','translation','translation',[0 0 5 1 2])}});
            multiscale = struct('axes', axes5, 'datasets', dataset);

            box = io.loaders.OmeZarrMetadataUtils.worldBoundingBox(multiscale, 1, [3 2 10 100 200]);
            testCase.verifyEqual(box, [2, 2+199*0.1, 1, 1+99*0.1, 5, 5+9*2], 'AbsTol', 1e-9);
        end

        function worldBoxRefusesAnOutOfRangeLevel(testCase)
            multiscale = testCase.buildMultiscale(testCase.CropScale, testCase.CropTranslation);
            testCase.verifyEmpty( ...
                io.loaders.OmeZarrMetadataUtils.worldBoundingBox(multiscale, 7, testCase.CropShape), ...
                'an unusable level must give [] so the caller leaves the box alone');
        end

        % ---- centre space vs edge space -----------------------------------

        function outerBoxGrowsByHalfAVoxel(testCase)
            outer = io.loaders.OmeZarrMetadataUtils.outerBoundingBox([10 20 10 20 10 20], [2 4 6]);
            testCase.verifyEqual(outer, [9 21 8 22 7 23]);
        end

        function cropAndEmGridsAlignOnlyInEdgeSpace(testCase)
            % The whole reason outerBoundingBox exists. In centre space the crop
            % starts at 25863 nm on a 4 nm grid, which is 6465.75 voxels - a
            % misaligned store, if that were the right space to ask in. In edge
            % space it is exactly 6466.
            cropMultiscale = testCase.buildMultiscale(testCase.CropScale, testCase.CropTranslation);
            cropCentreBox  = io.loaders.OmeZarrMetadataUtils.worldBoundingBox( ...
                cropMultiscale, 1, testCase.CropShape);

            centreSpaceIndex = cropCentreBox(1) / testCase.EmScale(3);
            testCase.verifyNotEqual(centreSpaceIndex, round(centreSpaceIndex), ...
                'centre space must NOT come out integral - that is the trap');

            cropOuterBox = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
                cropCentreBox, testCase.CropScale([3 2 1]));
            emEdgeOrigin = -testCase.EmScale(3) / 2;
            edgeSpaceIndex = (cropOuterBox(1) - emEdgeOrigin) / testCase.EmScale(3);
            testCase.verifyEqual(edgeSpaceIndex, 6466, 'AbsTol', 1e-9);
        end

        % ---- region to voxel range ----------------------------------------

        function regionReproducesThePublishedCropBounds(testCase)
            % The bounds recorded for jrc_hela-2 crop1, to the voxel.
            [cropOuterBox, emCentreBox] = testCase.cropAndEmBoxes();

            voxelRange = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
                cropOuterBox, emCentreBox, testCase.EmScale([3 2 1]), testCase.EmShape([3 2 1]));

            % rows x, y, z; 1-based inclusive
            testCase.verifyEqual(voxelRange, [6467 6966; 226 725; 599 698]);
        end

        function regionRoundsOutwardAndReportsTheResidual(testCase)
            % Grid alignment is a property of a store, not a promise of OME-NGFF.
            % A region that does not divide evenly must grow, never shift.
            [cropOuterBox, emCentreBox] = testCase.cropAndEmBoxes();
            offGridBox = cropOuterBox + [1 -1 1 -1 1 -1];   % nm, inside the grid lines

            [voxelRange, residual] = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
                offGridBox, emCentreBox, testCase.EmScale([3 2 1]), testCase.EmShape([3 2 1]));

            testCase.verifyEqual(voxelRange, [6467 6966; 226 725; 599 698], ...
                'shrinking the request by less than a voxel must not lose one');
            testCase.verifyGreaterThan(max(abs(residual(:))), 0, ...
                'an inexact fit has to be reported, not silently accepted');
        end

        function regionIsClampedToTheLevel(testCase)
            centreBox = [0 99 0 99 0 99];
            hugeRegion = [-1000 1000 -1000 1000 -1000 1000];
            voxelRange = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
                hugeRegion, centreBox, [1 1 1], [100 100 100]);
            testCase.verifyEqual(voxelRange, [1 100; 1 100; 1 100]);
        end

        function regionMissingTheLevelReportsAnEmptyRange(testCase)
            voxelRange = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
                [500 600 500 600 500 600], [0 99 0 99 0 99], [1 1 1], [100 100 100]);
            testCase.verifyEqual(voxelRange, [1 0; 1 0; 1 0], ...
                'a miss must read as an empty range, not as a negative count');
        end

        function toleranceSurvivesFloatingPointDivision(testCase)
            % 3133.52 / 5.24 is 598 in exact arithmetic and 597.99999... in
            % binary. Without the grid tolerance, floor() loses a voxel here.
            centreBox = [0 0 0 0 0 (700-1)*5.24];
            % The crop's own z edges: centre 3133.52 back half a coarse voxel,
            % out to centre 3653.59 forward half a fine voxel.
            outerRegion = [0 0 0 0, 3133.52 - 2.62, 3654.90];
            voxelRange = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
                outerRegion, centreBox, [1 1 5.24], [1 1 700]);
            testCase.verifyEqual(voxelRange(3, :), [599 698]);
        end

        % ---- applyRequestedRegion: the no-op contract ----------------------

        function anAbsentRegionChangesNothing(testCase)
            % The property that matters most in this file. Region touches the
            % read path of every zarr dataset MIB opens; almost none ask for one.
            levelSizes  = [100 200 50; 50 100 25];
            levelVoxels = [1 1 2; 2 2 4];
            levelBoxes  = [0 99 0 199 0 98; 0 98 0 198 0 96];

            for options = {struct(), struct('Region', []), struct('Region', [1 2 3])}
                region = io.loaders.OmeZarrMetadataUtils.resolveRegionOption(options{1}, struct());
                [sizes, origins, boxes, report] = ...
                    io.loaders.OmeZarrMetadataUtils.applyRequestedRegion( ...
                        region, levelSizes, levelVoxels, levelBoxes, 'um');

                testCase.verifyEqual(sizes, levelSizes);
                testCase.verifyEqual(boxes, levelBoxes);
                testCase.verifyEqual(origins, ones(2, 3), ...
                    'origin [1 1 1] is what every read path treats as "no offset"');
                testCase.verifyFalse(report.requested);
            end
        end

        function regionOptionFallsBackToTheLoaderOptions(testCase)
            % A region can arrive with the call or be baked into the loader at
            % construction, which is the route core.MibDataset.loadModel takes.
            region = [0 1 0 1 0 1];
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.resolveRegionOption( ...
                struct(), struct('Region', region)), region);
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.resolveRegionOption( ...
                struct('Region', region), struct('Region', [9 9 9 9 9 9])), region, ...
                'the call must win over the loader default');
        end

        function regionIsConvertedFromMicrometresToStoreUnits(testCase)
            % Region is in um because it is compared across pyramids that may
            % declare different units; the level tables are in the store's unit.
            levelSizes  = [100 100 100];
            levelVoxels = [4 4 4];                 % nm
            levelBoxes  = [0 396 0 396 0 396];     % nm

            % 6..26 nm, which falls on this grid's voxel edges (-2, 2, 6, ...),
            % so the conversion is the only thing being measured here.
            region = [0.006 0.026 0.006 0.026 0.006 0.026];   % um
            [sizes, origins, ~, report] = io.loaders.OmeZarrMetadataUtils.applyRequestedRegion( ...
                region, levelSizes, levelVoxels, levelBoxes, 'nm');

            testCase.verifyTrue(report.requested);
            testCase.verifyTrue(report.isExact);
            testCase.verifyEqual(sizes, [5 5 5]);
            testCase.verifyEqual(origins, [3 3 3]);
        end

        function eachLevelIsIntersectedOnItsOwnGrid(testCase)
            % Levels need not be exact multiples of one another, so dividing
            % level 0's answer by a scale factor is not the same computation -
            % and this case shows the difference. The region lands exactly on
            % level 0's 2 um grid but half a voxel inside level 1's 4 um grid,
            % so level 1 rounds outward to SIX voxels where naive halving of
            % level 0's ten would have said five.
            levelSizes  = [100 100 100; 50 50 50];
            levelVoxels = [2 2 2; 4 4 4];
            levelBoxes  = [0 198 0 198 0 198; 1 197 1 197 1 197];

            region = [9 29 9 29 9 29];
            [sizes, origins, boxes, report] = io.loaders.OmeZarrMetadataUtils.applyRequestedRegion( ...
                region, levelSizes, levelVoxels, levelBoxes, 'um');

            testCase.verifyTrue(report.requested);
            testCase.verifyEqual(sizes(1, :), [10 10 10]);
            testCase.verifyEqual(origins(1, :), [6 6 6]);
            testCase.verifyEqual(sizes(2, :), [6 6 6]);
            testCase.verifyEqual(origins(2, :), [3 3 3]);
            testCase.verifyEqual(boxes(1, [1 3 5]), [10 10 10], 'AbsTol', 1e-9, ...
                'the cropped box addresses the centre of the first kept voxel');
        end

        function aRegionOutsideTheGroupIsReportedAndIgnored(testCase)
            [sizes, origins, ~, report] = io.loaders.OmeZarrMetadataUtils.applyRequestedRegion( ...
                [500 600 500 600 500 600], [100 100 100], [1 1 1], [0 99 0 99 0 99], 'um');

            testCase.verifyEqual(sizes, [100 100 100], ...
                'a non-overlapping region must keep the full extent, not give a 0-sized dataset');
            testCase.verifyEqual(origins, [1 1 1]);
            testCase.verifySubstring(report.message, 'does not overlap');
        end

        % ---- unit conversion ----------------------------------------------

        function unitFactorsMatchMibImage(testCase)
            % Same table core.MibImage.updateBoundingBox uses; a mismatch would
            % scale a region by 1000 without anything else looking wrong.
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor('nm'), 1e-3);
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor('um'), 1);
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor('mm'), 1e3);
            testCase.verifyEqual(io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor('parsec'), 1, ...
                'an unknown unit falls back to "already micrometres", as MibImage does');
        end

        % ---- bbox construction --------------------------------------------

        function levelRegionBboxPlacesRangesInStoreAxisOrder(testCase)
            bbox = io.loaders.OmeZarrMetadataUtils.levelRegionBbox('zyx', [5 11 3], [20 20 10], 1, 1);
            % rows are z, y, x; each [start_1based, end_exclusive]
            testCase.verifyEqual(bbox, [3 13; 5 25; 11 31]);
        end

        function levelRegionBboxGivesAbsentAxesASingleton(testCase)
            bbox = io.loaders.OmeZarrMetadataUtils.levelRegionBbox('tczyx', [1 1 1], [4 5 6], 2, 3);
            testCase.verifyEqual(bbox, [1 4; 1 3; 1 7; 1 5; 1 6]);
        end
    end

    methods (Access = private)
        function axesDef = spatialAxes(~)
            axesDef = struct('name', {'z','y','x'}, 'type', {'space','space','space'}, ...
                'unit', {'nanometer','nanometer','nanometer'});
        end

        function multiscale = buildMultiscale(testCase, scale, translation)
            dataset = struct('path', 's0', 'coordinateTransformations', ...
                {{struct('type', 'scale', 'scale', scale), ...
                  struct('type', 'translation', 'translation', translation)}});
            multiscale = struct('axes', testCase.spatialAxes(), 'datasets', dataset);
        end

        function [cropOuterBox, emCentreBox] = cropAndEmBoxes(testCase)
            % The crop's outer extent and the EM level-0 box, both in nm and in
            % [xmin xmax ymin ymax zmin zmax] order.
            cropMultiscale = testCase.buildMultiscale(testCase.CropScale, testCase.CropTranslation);
            cropCentreBox  = io.loaders.OmeZarrMetadataUtils.worldBoundingBox( ...
                cropMultiscale, 1, testCase.CropShape);
            cropOuterBox = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
                cropCentreBox, testCase.CropScale([3 2 1]));

            emMultiscale = testCase.buildMultiscale(testCase.EmScale, [0 0 0]);
            emCentreBox  = io.loaders.OmeZarrMetadataUtils.worldBoundingBox( ...
                emMultiscale, 1, testCase.EmShape);
        end
    end
end
