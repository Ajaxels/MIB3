classdef BigDataMaskStreamTest < matlab.unittest.TestCase
% BIGDATAMASKSTREAMTEST - Stream a BigData mask layer (packed bit 7) to disk.
%
% MibDataset.saveImage('mask',...) routes a BigData (pyramidal) mask through a
% MibImageSliceProvider at a chosen pyramid level instead of gathering the full
% level-0 mask. This test locks the capability that branch relies on: the
% generic provider reads the mask bit at a given level, and a streaming saver
% writes it pixel-exact.
%
% Bit scheme (labels63): material = bitand(x,63), mask = bitand(x,64)/64.

    properties (Access = private)
        Lb
        StorePath
        H
        W
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
            pyramid.axisOrder         = 'yxz';
            pyramid.levelImageSizes   = [256 256 1; 128 128 1; 64 64 1; 32 32 1];
            pyramid.levelScaleFactors = [1 1 1; 2 2 1; 4 4 1; 8 8 1];
            pyramid.chunkSizes        = {[64 64 1], [64 64 1], [64 64 1], [32 32 1]};
            bm = core.MibImage.initializeImgInfo('Height', 256, 'Width', 256, ...
                'Depth', 1, 'Time', 1, 'Colors', 1);
            sp = [tempname '_maskstream.zarr3'];
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

        function maskStreamsPixelExactAtFinestLevel(testCase)
            lb = testCase.Lb;
            o1 = struct('magFactor', 1, 'x', [1 256], 'y', [1 256], 'z', [1 1], 't', [1 1]);

            % paint a mask (bit 7) disk at the finest level
            [xx, yy] = meshgrid(1:256, 1:256);
            maskDisk = uint8((xx - 128).^2 + (yy - 128).^2 <= 50^2);
            lb.setData63(maskDisk, 'mask', 3, [], o1);
            expected = squeeze(lb.getData63('mask', 3, [], o1));
            testCase.assumeGreaterThan(nnz(expected), 0, 'precondition: mask present');

            % stream the mask level-0 through the generic provider + a streaming saver
            provider = io.savers.MibImageSliceProvider(lb, 'mask', 1, [], 1, 1, 1);
            testCase.verifyEqual(provider.OutputSize, [256 256 1 1 1], ...
                'provider must expose the full-resolution mask size');

            tmpDir  = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            outFile = fullfile(tmpDir.Folder, 'Mask_synthetic.tif');
            meta = struct('colorType','grayscale','dataClass','uint8', ...
                'imageDescription','','lutColors',[1 0 1]);
            opts = struct('Saving3DPolicy','3D stack','silent',true,'showWaitbar',false, ...
                'FilenameGenerator','Use sequential filename','overwrite',true,'Compression','none');

            saver = io.savers.TiffSaver(struct());
            fnOut = saver.saveStream(provider, meta, outFile, opts);

            testCase.verifyTrue(isfile(fnOut), 'mask TIFF must be written');
            back = imread(fnOut);
            testCase.verifyEqual(back, expected, 'streamed mask must be pixel-exact');
        end

        function providerExposesCoarserLevelSize(testCase)
            % A coarser export level reports the downsampled mask dimensions, so the
            % saveImage branch can offer a pyramid-level choice like the image path.
            lb = testCase.Lb;
            provider = io.savers.MibImageSliceProvider(lb, 'mask', 2, [], 1, 1, 1);
            testCase.verifyEqual(provider.OutputSize(1:2), [128 128], ...
                'level 2 must expose half-resolution mask dimensions');
        end

    end
end
