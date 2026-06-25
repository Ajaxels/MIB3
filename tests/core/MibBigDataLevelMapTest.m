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

    methods (Access = private)
        function o = opts(testCase, magFactor)
            o = struct('magFactor', magFactor, 'x', [1 testCase.W], 'y', [1 testCase.H], ...
                'z', [1 1], 't', [1 1]);
        end

        function d = disk(testCase, magFactor, radius)
            dy = round(testCase.H/magFactor); dx = round(testCase.W/magFactor);
            [xx, yy] = meshgrid(1:dx, 1:dy);
            d = uint8((xx - dx/2).^2 + (yy - dy/2).^2 <= radius^2);
        end
    end
end
