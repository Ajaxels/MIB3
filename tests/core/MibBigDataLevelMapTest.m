classdef MibBigDataLevelMapTest < matlab.unittest.TestCase
% MIBBIGDATALEVELMAPTEST - Unit tests for the BigData level-map manager
% (core.MibBigDataLabels: matLevel write/read/recompute, materializeAll, side-file).
%
% A small synthetic 4-level packed pyramid is built on disk per test (no WSI data,
% offline, headless). The level map records, per coarsest-grid tile, the finest
% materialized level; edits write the working level + coarser and mark the tile,
% reads recompute finer-than-materialized tiles from their source and cache them.
%
% Bit scheme (labels63): material = bitand(x,63), mask = bitand(x,64)/64,
% selection = bitand(x,128)/128.

    properties (Access = private)
        Lb           % core.MibBigDataLabels under test
        StorePath    % char path of the temp .zarr3 store
        H            % full-resolution height
        W            % full-resolution width
    end

    properties (TestParameter)
        coarseLayer = {'selection', 'mask'};
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function buildStore(testCase)
            testCase.H = 256; testCase.W = 256;
            pyramid = struct();
            pyramid.axisOrder        = 'yxz';
            pyramid.levelImageSizes  = [256 256 1; 128 128 1; 64 64 1; 32 32 1];
            pyramid.levelScaleFactors = [1 1 1; 2 2 1; 4 4 1; 8 8 1];
            pyramid.chunkSizes       = {[64 64 1], [64 64 1], [64 64 1], [32 32 1]};
            bm = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            sp = [tempname '_levelmap.zarr3'];
            lmp = core.MibBigDataLabels.levelMapPathFor(sp);
            if isfile(lmp); delete(lmp); end
            lb = core.MibBigDataLabels([], bm);
            lb.createStore([256 256 1], sp, pyramid);
            testCase.Lb = lb;
            testCase.StorePath = sp;
        end
    end

    methods (TestMethodTeardown)
        function cleanupStore(testCase)
            if ~isempty(testCase.Lb) && isvalid(testCase.Lb)
                try testCase.Lb.closeStore(); catch; end %#ok<CTCH>
            end
            if ~isempty(testCase.StorePath)
                if isfolder(testCase.StorePath); rmdir(testCase.StorePath, 's'); end
                lmp = core.MibBigDataLabels.levelMapPathFor(testCase.StorePath);
                if isfile(lmp); delete(lmp); end
            end
        end
    end

    methods (Test, TestTags = {'Unit'})

        function testWriteSetsMatLevel(testCase)
            lb = testCase.Lb;
            o = testCase.opts(2);                          % mag 2 -> working level 2
            level = lb.pickLevel(o);
            disk = testCase.disk(2, 30);
            lb.setData63(disk, 'selection', 3, [], o);
            testCase.verifyGreaterThan(nnz(lb.matLevel == level), 0, ...
                'matLevel must be set to the working level for touched tiles');
        end

        function testReadCleanLevelNoHalo(testCase)
            lb = testCase.Lb;
            o = testCase.opts(2);
            disk = testCase.disk(2, 30);
            lb.setData63(disk, 'selection', 3, [], o);
            back = squeeze(lb.getData63('selection', 3, [], o));
            diskR = imresize(disk, size(back), 'nearest');
            halo = nnz(back & ~imdilate(diskR, strel('disk', 2)));
            testCase.verifyEqual(halo, 0, 'reading the painting level must add no halo');
        end

        function testZoomInRecomputeAndCache(testCase)
            lb = testCase.Lb;
            o2 = testCase.opts(2);
            lb.setData63(testCase.disk(2, 30), 'selection', 3, [], o2);
            o1 = struct('magFactor', 1, 'x', [1 256], 'y', [1 256], 'z', [1 1], 't', [1 1]);
            s1 = squeeze(lb.getData63('selection', 3, [], o1));
            testCase.verifyGreaterThan(nnz(s1), 0, 'zoom-in must reconstruct the edit');
            testCase.verifyEqual(min(lb.matLevel(lb.matLevel > 0)), uint8(1), ...
                'zoom-in must materialize visited tiles to level 1');
            s1b = squeeze(lb.getData63('selection', 3, [], o1));
            testCase.verifyEqual(s1b, s1, 'second read must be identical (cached)');
        end

        function testSaveMaterializesAll(testCase)
            lb = testCase.Lb;
            o = testCase.opts(8);                          % coarsest working level
            lb.setData63(testCase.disk(8, 8), 'selection', 3, [], o);
            lb.materializeAll([]);
            nonzero = lb.matLevel(lb.matLevel > 0);
            testCase.verifyTrue(all(nonzero == 1), 'Save must materialize all tiles to level 1');
        end

        function testSideFileRoundTrip(testCase)
            lb = testCase.Lb;
            lb.setData63(testCase.disk(2, 30), 'selection', 3, [], testCase.opts(2));
            mapBefore = lb.matLevel;
            lb.closeStore();
            testCase.verifyTrue(isfile(core.MibBigDataLabels.levelMapPathFor(testCase.StorePath)), ...
                'closeStore must write the side-file');
            bm = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            lb2 = core.MibBigDataLabels([], bm); lb2.openStore(testCase.StorePath);
            testCase.Lb = lb2;                             % teardown closes this one
            testCase.verifyEqual(lb2.matLevel, mapBefore, 'matLevel must round-trip');
        end

        function testVersion1SideFileFillsEveryLayer(testCase)
            % a side-file written before the level map was split per layer holds one
            % 3-D map; it is what every layer meant, so each layer gets a copy
            lb = testCase.Lb;
            lb.setData63(testCase.disk(2, 30), 'labels', 3, 1, testCase.opts(2));
            singleMap = max(lb.matLevel, [], 4);
            lb.closeStore();
            S = struct('matLevel', singleMap, 'mapVersion', 1, 'coarsestSize', lb.modelLevelSizes(end, :));
            save(core.MibBigDataLabels.levelMapPathFor(testCase.StorePath), '-struct', 'S', '-v7', '-mat');
            bm = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            lb2 = core.MibBigDataLabels([], bm); lb2.openStore(testCase.StorePath);
            testCase.Lb = lb2;
            testCase.verifyEqual(lb2.matLevel, repmat(singleMap, [1 1 1 3]), ...
                'a version 1 map must be copied to the labels, mask and selection layers');
            testCase.verifyTrue(all(lb2.selectionTiles(:)), ...
                'a version 1 map does not say where the selection is: every tile is a candidate');
        end

        function testSelectionTilesRoundTrip(testCase)
            lb = testCase.Lb;
            lb.setData63(testCase.disk(2, 10), 'selection', 3, [], testCase.opts(2));
            tilesBefore = lb.selectionTiles;
            testCase.assertTrue(any(tilesBefore(:)));
            lb.closeStore();
            bm = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            lb2 = core.MibBigDataLabels([], bm); lb2.openStore(testCase.StorePath);
            testCase.Lb = lb2;
            testCase.verifyEqual(lb2.selectionTiles, tilesBefore, 'selectionTiles must round-trip');
        end

        function testWriteMarksOnlyTheTilesItChanged(testCase)
            % A level-3 write over the whole slice that changes one corner: only
            % the corner tile becomes authoritative at level 3, the checkerboard
            % tiles keep level 1 and their full-resolution data.
            lb = testCase.Lb;
            fineLabels = testCase.writeFineCheckerboard();
            levelThree = squeeze(lb.getData63('labels', 3, [], testCase.opts(4)));
            levelThree(64, 64) = 3;                         % full-res rows/cols 253:256
            lb.setData63(levelThree, 'labels', 3, [], testCase.opts(4));
            testCase.verifyEqual(lb.matLevel(32, 32, 1, 1), uint8(3), 'the changed tile is marked');
            testCase.verifyTrue(all(lb.matLevel(1:16, 1:16, 1, 1) == 1, 'all'), 'the unchanged tiles are not');
            labelsAfter = squeeze(lb.getData63('labels', 3, [], testCase.opts(1)));
            testCase.verifyEqual(labelsAfter(1:128, 1:128), fineLabels(1:128, 1:128), ...
                'the full-resolution data of the unchanged tiles survives');
        end

        function testFallbackWhenSideFileMissing(testCase)
            % An imported / externally-created model has precise data at EVERY level but
            % no sidecar. Opening it must assume "fully precise" (matLevel = 1) and must
            % NOT degrade the finer levels by upsampling the coarsest.
            lb = testCase.Lb;
            % write at the FINEST level so all levels get proper precise data (emulates
            % an external import where the whole pyramid is consistent)
            lb.setData63(testCase.disk(1, 60), 'selection', 3, [], testCase.opts(1));
            finestBefore = squeeze(lb.getData63('selection', 3, [], testCase.opts(1)));
            lb.closeStore();
            delete(core.MibBigDataLabels.levelMapPathFor(testCase.StorePath));  % external import: no sidecar
            bm = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            lb2 = core.MibBigDataLabels([], bm); lb2.openStore(testCase.StorePath);  % must not error
            testCase.Lb = lb2;
            testCase.verifyTrue(all(lb2.matLevel(:) == 1), ...
                'fallback must assume fully materialized (precise) levels');
            finestAfter = squeeze(lb2.getData63('selection', 3, [], testCase.opts(1)));
            testCase.verifyEqual(finestAfter, finestBefore, ...
                'imported finest level must NOT be degraded on load (no coarsest upsample)');
        end

        function testClearSelectionAtLowMag(testCase)
            lb = testCase.Lb;
            o = testCase.opts(8);
            lb.setData63(testCase.disk(8, 8), 'selection', 3, [], o);
            testCase.assumeGreaterThan(nnz(squeeze(lb.getData63('selection', 3, [], o))), 0, ...
                'precondition: selection present');
            lb.clearLayer('selection', [], [], [1 1], [1 1], 8);
            testCase.verifyEqual(nnz(squeeze(lb.getData63('selection', 3, [], o))), 0, ...
                'clear must remove selection at low magnification');
        end

        function testAddMaterialThenSelectionKeepsMaterial(testCase)
            lb = testCase.Lb;
            o = testCase.opts(2);
            box = zeros(128, 128, 'uint8'); box(40:90, 40:90) = 1;
            lb.setData63(box, 'labels', 3, 1, o);
            before = nnz(squeeze(lb.getData63('labels', 3, [], o)) == 1);
            sel = zeros(128, 128, 'uint8'); sel(50:80, 50:80) = 1;
            lb.setData63(sel, 'selection', 3, [], o);
            after = nnz(squeeze(lb.getData63('labels', 3, [], o)) == 1);
            testCase.verifyEqual(after, before, 'painting selection must not remove material');
        end

        function testSelectionBBoxTracking(testCase)
            % the selection footprint box grows on a selection write and resets when
            % the selection is cleared over a covering region (used to scope a/s/r/c).
            lb = testCase.Lb;
            o = testCase.opts(2);
            testCase.verifyEmpty(lb.selectionBBoxFull, 'box starts empty');

            d = testCase.disk(2, 30);
            lb.setData63(d, 'selection', 3, [], o);
            bb = lb.selectionBBoxFull;
            testCase.verifyNotEmpty(bb, 'box must be set after a selection write');
            testCase.verifyNumElements(bb, 6);
            testCase.verifyGreaterThanOrEqual(bb(1), 1);
            testCase.verifyLessThanOrEqual(bb(2), testCase.H);
            testCase.verifyLessThanOrEqual(bb(4), testCase.W);
            testCase.verifyLessThanOrEqual(bb(1), bb(2));   % non-degenerate
            testCase.verifyLessThanOrEqual(bb(3), bb(4));

            % a material-only write must NOT touch the selection box
            box = zeros(128, 128, 'uint8'); box(40:90, 40:90) = 1;
            lb.setData63(box, 'labels', 3, 1, o);
            testCase.verifyEqual(lb.selectionBBoxFull, bb, 'material write must not change selection box');

            % clearing the selection over a covering region resets the box
            lb.setData63(zeros(size(d), 'uint8'), 'selection', 3, [], o);
            testCase.verifyEmpty(lb.selectionBBoxFull, 'box must reset when selection cleared');
        end

    end

    methods (Test, TestTags = {'Unit'})
        % -----------------------------------------------------------------
        % A write of one layer at a coarse level must not damage the finer data
        % of the other layers (one level map per layer)
        % -----------------------------------------------------------------

        function testCoarseSelectionStrokeKeepsFineLabels(testCase, coarseLayer)
            lb = testCase.Lb;
            fineLabels = testCase.writeFineCheckerboard();
            % a stroke of the selection or mask drawn at 25% zoom (level 3) over the
            % checkerboard
            stroke = zeros(64, 64, 'uint8'); stroke(5:20, 5:20) = 1;
            lb.setData63(stroke, coarseLayer, 3, [], testCase.opts(4));

            labelsAfter = squeeze(lb.getData63('labels', 3, [], testCase.opts(1)));
            testCase.verifyEqual(labelsAfter, fineLabels, ...
                sprintf('a %s stroke at a coarse level must leave the full-resolution labels intact', coarseLayer));
            strokeAfter = squeeze(lb.getData63(coarseLayer, 3, [], testCase.opts(1)));
            testCase.verifyGreaterThan(nnz(strokeAfter(17:84, 17:84)), 0.9 * 64^2, ...
                sprintf('the %s stroke must still be there at full resolution', coarseLayer));
        end

        function testCoarseClearSelectionKeepsFineLabels(testCase)
            lb = testCase.Lb;
            fineLabels = testCase.writeFineCheckerboard();
            selection = zeros(256, 256, 'uint8'); selection(20:60, 20:60) = 1;
            lb.setData63(selection, 'selection', 3, [], testCase.opts(1));

            lb.clearLayer('selection', [], [], [1 1], [1 1], 8);    % 'c' at 12.5% zoom
            testCase.verifyEqual(nnz(squeeze(lb.getData63('selection', 3, [], testCase.opts(1)))), 0, ...
                'the selection must be cleared at full resolution');
            testCase.verifyEqual(squeeze(lb.getData63('labels', 3, [], testCase.opts(1))), fineLabels, ...
                'clearing the selection at a coarse level must leave the full-resolution labels intact');
        end

        function testZoomInKeepsCleanTilesBetweenCoarseEdits(testCase)
            % Two strokes at level 3 in opposite corners, then a full-resolution edit
            % between them. Reading level 1 rebuilds the corner tiles from level 3;
            % the tiles between them hold newer level-1 data and must stay as they are.
            lb = testCase.Lb;
            corner = zeros(64, 64, 'uint8');
            corner(1:4, 1:4) = 1; corner(61:64, 61:64) = 1;
            lb.setData63(corner, 'labels', 3, 1, testCase.opts(4));
            fine = zeros(256, 256, 'uint8');
            fine(97:2:160, 97:160) = 2;                     % one-pixel stripes
            lb.setData63(fine, 'labels', 3, [], testCase.opts(1));

            labelsAfter = squeeze(lb.getData63('labels', 3, [], testCase.opts(1)));
            testCase.verifyEqual(labelsAfter(97:160, 97:160), fine(97:160, 97:160), ...
                'full-resolution data between two coarse edits must survive a zoom-in');
        end
    end

    methods (Test, TestTags = {'Unit'})
        % -----------------------------------------------------------------
        % uint16 instance layout (16383): bits 1-14 index, 15 mask, 16 selection
        % -----------------------------------------------------------------

        function testUint8StoreIsDefault(testCase)
            lb = testCase.Lb;
            testCase.verifyEqual(lb.containerClass, 'uint8');
            testCase.verifyEqual(lb.maxMaterials, 63);
            testCase.verifyEqual(class(lb.readPackedLevel(1, [1 4], [1 4], [1 1])), 'uint8');
        end

        function testUint16StoreKeepsLargeIndicesAndFlags(testCase)
            lb = testCase.buildUint16Store();
            o = testCase.opts(2);
            % two objects with indices whose high bits sit next to the flag bits
            objects = zeros(128, 128, 'uint16');
            objects(20:60, 20:60)   = 300;
            objects(70:110, 70:110) = 16383;
            lb.setData63(objects, 'labels', 3, [], o);
            mask = zeros(128, 128, 'uint8'); mask(1:64, :) = 1;
            lb.setData63(mask, 'mask', 3, [], o);
            selection = zeros(128, 128, 'uint8'); selection(:, 1:64) = 1;
            lb.setData63(selection, 'selection', 3, [], o);

            testCase.verifyEqual(squeeze(lb.getData63('labels', 3, [], o)), objects, ...
                'mask/selection writes must keep 14-bit indices');
            testCase.verifyEqual(squeeze(lb.getData63('mask', 3, [], o)), mask);
            testCase.verifyEqual(squeeze(lb.getData63('selection', 3, [], o)), selection);
            testCase.verifyEqual(lb.maxIndexUsed, 16383, 'the written maximum is tracked');

            % full resolution is materialized from the working level on read
            full = squeeze(lb.getData63('labels', 3, [], testCase.opts(1)));
            testCase.verifyEqual(class(full), 'uint16');
            testCase.verifyEqual(full(90*2, 90*2), uint16(16383), 'finer level keeps the index');
            testCase.verifyEqual(full(40*2, 40*2), uint16(300));
        end

        function testUint16StoreReopens(testCase)
            lb = testCase.buildUint16Store();
            storePath = char(lb.modelStorePath);
            objects = zeros(128, 128, 'uint16'); objects(10:20, 10:20) = 12345;
            lb.setData63(objects, 'labels', 3, [], testCase.opts(2));
            lb.closeStore();

            meta = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            reopened = core.MibBigDataLabels([], meta);
            reopened.openStore(storePath);
            testCase.addTeardown(@() reopened.closeStore());
            testCase.verifyEqual(reopened.containerClass, 'uint16', 'layout follows the array type');
            testCase.verifyEqual(reopened.maxMaterials, 16383);
            testCase.verifyEqual(reopened.maxIndexUsed, 12345, 'maxIndexUsed is persisted');
            testCase.verifyEqual(reopened.countMaterials(), 12345, 'count answers without a scan');
            testCase.verifyEqual(squeeze(reopened.getData63('labels', 3, [], testCase.opts(2))), objects);
        end

        function testSmoothUpsampleFallsBackForManyLabels(testCase)
            % above 64 distinct labels the per-label SDF is replaced by nearest
            labels = uint16(reshape(1:100, 10, 10));
            upsampled = core.MibBigDataLabels.smoothLabelUpsampleYX(labels, [20 20]);
            testCase.verifyEqual(class(upsampled), 'uint16');
            testCase.verifyEqual(upsampled, imresize(labels, [20 20], 'nearest'));
        end

    end

    methods (Access = private)
        function lb = buildUint16Store(testCase)
            % same 4-level pyramid as buildStore, as a uint16 (16383) store
            pyramid = struct();
            pyramid.axisOrder         = 'yxz';
            pyramid.levelImageSizes   = [256 256 1; 128 128 1; 64 64 1; 32 32 1];
            pyramid.levelScaleFactors = [1 1 1; 2 2 1; 4 4 1; 8 8 1];
            pyramid.chunkSizes        = {[64 64 1], [64 64 1], [64 64 1], [32 32 1]};
            meta = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            storePath = [tempname '_levelmap16.zarr3'];
            lb = core.MibBigDataLabels([], meta);
            lb.setLayout('uint16');
            lb.createStore([256 256 1], storePath, pyramid);
            testCase.addTeardown(@() MibBigDataLevelMapTest.removeStore(storePath));
            testCase.addTeardown(@() MibBigDataLevelMapTest.closeQuietly(lb));   % runs first (LIFO)
        end

        function o = opts(testCase, magFactor)
            o = struct('magFactor', magFactor, 'x', [1 testCase.W], 'y', [1 testCase.H], ...
                'z', [1 1], 't', [1 1]);
        end

        function fineLabels = writeFineCheckerboard(testCase)
            % one-pixel checkerboard of materials 1 and 2 over rows/columns 1:128,
            % written at full resolution, so any rebuild from a coarser level shows
            fineLabels = zeros(testCase.H, testCase.W, 'uint8');
            [columns, rows] = meshgrid(1:128, 1:128);
            fineLabels(1:128, 1:128) = uint8(1 + mod(rows + columns, 2));
            testCase.Lb.setData63(fineLabels, 'labels', 3, [], testCase.opts(1));
        end

        function d = disk(testCase, magFactor, radius)
            dy = round(testCase.H/magFactor); dx = round(testCase.W/magFactor);
            [xx, yy] = meshgrid(1:dx, 1:dy);
            d = uint8((xx - dx/2).^2 + (yy - dy/2).^2 <= radius^2);
        end
    end

    methods (Static, Access = private)
        function closeQuietly(labels)
            if isvalid(labels) && labels.exists
                try labels.closeStore(); catch; end %#ok<CTCH>
            end
        end

        function removeStore(storePath)
            if isfolder(storePath); rmdir(storePath, 's'); end
            levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
            if isfile(levelMapPath); delete(levelMapPath); end
        end
    end
end
