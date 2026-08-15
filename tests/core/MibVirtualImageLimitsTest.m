classdef MibVirtualImageLimitsTest < matlab.unittest.TestCase
% MIBVIRTUALIMAGELIMITSTEST - block-mode limits on a Virtual/BigData buffer.
%
% ``core.MibDataset.initialize`` leaves ``axesX``/``axesY`` as a **scalar**
% ``NaN``, meaning "the axes are not laid out yet", and the block mode feeds
% ``ceil(obj.axesX)`` straight into ``options.x``. A repaint can therefore ask
% for a region that cannot be computed, which is what closing an S3/BigData
% dataset with the Display adjustment dialog open does - its ``NewDataset``
% listener calls ``getData2D`` with ``blockModeSwitch = 1``.
%
% **The fix belongs in the caller, and these tests pin why.** Making the read
% paths tolerate a scalar - the way ``core.MibImage.getData`` does, by reading
% first-and-last so ``NaN`` becomes ``[NaN NaN]`` and the NaN-ignoring clamp
% falls back to the full extent - looks like the tidy fix and is far worse.
% ``getDataZarr`` selects its pyramid level from ``magFactor``, which is 1 at
% open, so the full extent is the **full-resolution** slice: about 3900 chunks
% and several GB on ``jrc_mus-liver-6``. It was tried, and it turned the crash
% into an apparent hang at "Opening the dataset...".
%
% So the read paths keep failing loudly and cheaply, and
% ``controllers.DisplayAdjust.updateHist`` returns early while the axes are
% still NaN. That guard needs a live controller and a window, so it is not
% covered here; per the "keep single-use logic inline" rule in CLAUDE.md it was
% not extracted merely to be reachable.

    properties (Access = private)
        TempDir
        OriginalZarrLibrary
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function makeTempDir(testCase)
            testCase.OriginalZarrLibrary = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');
            testCase.TempDir = fullfile(tempdir, 'mib_virtual_limits_test');
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
            mkdir(testCase.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function cleanUp(testCase)
            io.zarr.Config.setLibrary(testCase.OriginalZarrLibrary);
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
        end
    end

    methods (Test, TestTags = {'Unit'})

        function uninitialisedAxesAreRefusedRatherThanReadingEverything(testCase)
            % The virtual (non-pyramid) path. Failing is the intended outcome:
            % a caller must not be able to turn "I do not know what is visible"
            % into "then fetch all of it".
            [mibModel, datasetId] = testCase.buildVirtualPlaceholder();

            testCase.verifyError(@() mibModel.getData2D('image', [], [], 1, ...
                struct('blockModeSwitch', 1, 'id', datasetId)), ?MException, ...
                'block mode with uninitialised axes must not silently succeed');
        end

        function aPyramidReadAlsoRefusesUninitialisedAxes(testCase)
            % getData dispatches to getDataZarr whenever a pyramid exists, so
            % this - not getDataVirt - is the path a live zarr or S3 dataset
            % takes, and the one where a full-extent fallback is ruinous.
            virtualImage = testCase.buildPyramidImage();

            testCase.verifyError(@() virtualImage.getData('image', 3, 1, ...
                struct('x', NaN, 'y', NaN, 'z', [1 1])), ?MException);
        end

        function anExplicitBlockRegionIsStillHonoured(testCase)
            % The counterpart: an ordinary [min max] request must read exactly
            % that region, on both paths. Without this, "refuse everything"
            % would pass the two tests above.
            [mibModel, datasetId] = testCase.buildVirtualPlaceholder();
            mibModel.I{datasetId}.setAxesLimits([10 137], [20 83]);

            block = mibModel.getData2D('image', [], [], 1, ...
                struct('blockModeSwitch', 1, 'id', datasetId));

            testCase.verifySize(block{1}, [64, 128], ...
                'a real axes range must crop the read to itself');
        end

        function aPyramidReadStillHonoursARealRegion(testCase)
            virtualImage = testCase.buildPyramidImage();

            slice = virtualImage.getData('image', 3, 1, ...
                struct('x', [5 20], 'y', [9 40], 'z', [1 1]));

            testCase.verifySize(squeeze(slice), [32, 16], ...
                'an explicit region must crop the read to itself');
        end
    end

    methods (Access = private)
        function [mibModel, datasetId] = buildVirtualPlaceholder(~)
            % BUILDVIRTUALPLACEHOLDER - the buffer state a dataset close leaves.
            %
            % switchDatasetMode with the bundled default.h5 is exactly what
            % controllers.MibActiveDataset.buffers_ContextMenu does when it
            % closes a Virtual or BigData dataset, and it leaves the axes NaN
            % on its own - they are reset explicitly only so the test states
            % the precondition it depends on.
            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.preferences.System.DeveloperMode = false;
            datasetId = mibModel.getActiveId();

            placeholder = {fullfile(mibModel.mibPath, 'assets', 'images', 'default.h5')};
            mibModel.I{datasetId}.switchDatasetMode(2, ...
                mibModel.preferences.System.EnableSelection, placeholder);
            mibModel.I{datasetId}.axesX = NaN;
            mibModel.I{datasetId}.axesY = NaN;
        end

        function virtualImage = buildPyramidImage(testCase)
            % BUILDPYRAMIDIMAGE - a one-level local OME-Zarr v2 group, opened
            % Virtual. One level is enough: the fault is in the range
            % arithmetic that runs before any level is read.
            storePath = fullfile(testCase.TempDir, 'probe.zarr2');
            shape = [8 64 64];   % z y x, matching the declared axes below

            group = io.zarr.Group.create(storePath, 'zarrFormat', 2);
            level0 = group.createArray('s0', shape, 'uint8', ...
                'chunkShape', [4 32 32], 'fillValue', 0);
            level0.write(uint8(mod(reshape(1:prod(shape), shape), 251)));

            axesDefinition = {struct('name', 'z', 'type', 'space', 'unit', 'nanometer'), ...
                              struct('name', 'y', 'type', 'space', 'unit', 'nanometer'), ...
                              struct('name', 'x', 'type', 'space', 'unit', 'nanometer')};
            group.setAttributes(struct('multiscales', {{struct('version', '0.4', ...
                'axes', {axesDefinition}, 'datasets', {{struct('path', 's0', ...
                'coordinateTransformations', ...
                {{struct('type', 'scale', 'scale', [1 1 1])}})}})}}));

            options = struct('datasetMode', 'Virtual', 'ParentFigure', []);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            [imginfo, files] = loader.loadMetadata({storePath}, options);
            [~, imginfo] = loader.loadImages(files, imginfo, options);

            virtualImage = core.MibVirtualImage();
            virtualImage.initialize({storePath}, imginfo);
        end
    end
end
