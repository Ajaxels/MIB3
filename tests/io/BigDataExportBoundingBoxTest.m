classdef BigDataExportBoundingBoxTest < matlab.unittest.TestCase
% BIGDATAEXPORTBOUNDINGBOXTEST - voxel size survives BigData -> TIFF export.
%
% BioFormats-backed BigData images carry an EMPTY boundingBox (their voxel size
% lives only in the pyramid). When such a dataset is exported to a standard
% format, MibImage.save must synthesize a physical BoundingBox from the
% level-scaled pixSize so the voxel size round-trips - otherwise the reloaded
% dataset defaults to voxel 1. This reproduces that case with a zarr3 pyramid
% whose boundingBox is cleared to mimic the BioFormats backend.

    properties (Access = private)
        OrigZarrLib
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function nativeBackend(testCase)
            testCase.OrigZarrLib = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');
        end
    end

    methods (TestMethodTeardown)
        function restore(testCase)
            io.zarr.Config.setLibrary(testCase.OrigZarrLib);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function emptyBoundingBox_exportWritesPhysicalBox(testCase)
            here     = fileparts(mfilename('fullpath'));            % tests/io
            repoRoot = fileparts(fileparts(here));
            mibPath  = fullfile(repoRoot, 'mib');

            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            sp  = fullfile(tmp.Folder, 'src.zarr3');

            % build a single-level zarr3 with a known anisotropic voxel
            vol = reshape(uint8(mod(0:32*24*6-1, 251) + 1), [32 24 6]);   % [Y X Z]
            io.savers.Zarr3Saver().save(vol, ...
                struct('pixSize', struct('x',0.5,'y',0.6,'z',2,'units','um','t',1,'tunits','s')), ...
                sp, struct('Levels', 1));

            % open as a BigData image, then clear the box to mimic the BioFormats backend
            o0 = struct('datasetMode','BigData','silentMode',true,'ParentFigure',[],'mibPath',mibPath);
            Ld = io.loaders.Zarr3VirtualSetupLoader(o0);
            [mi, fl]  = Ld.loadMetadata({sp}, o0);
            [img, mi2] = Ld.loadImages(fl, mi, o0);
            bigImg = core.MibBigDataImage(img, mi2);
            bigImg.boundingBox = [];   % BioFormats-backed BigData has no boundingBox

            % reconstruct the full-res pixSize the way MibDataset.saveImage does
            v0 = bigImg.pyramid.levelVoxelSizes(1, :);   % [y x z]
            ps = struct('x',v0(2),'y',v0(1),'z',v0(3),'t',1,'units','um','tunits','s');

            tif = fullfile(tmp.Folder, 'out.tif');
            bigImg.save(tif, struct('pixSize',ps,'silent',true,'showWaitbar',false, ...
                'overwrite',true,'Format','TIF format uncompressed (*.tif)'));

            info = imfinfo(tif);
            hasDesc = isfield(info, 'ImageDescription') && ~isempty(info(1).ImageDescription);
            testCase.verifyTrue(hasDesc && contains(info(1).ImageDescription, 'BoundingBox'), ...
                'export must write a BoundingBox even when the image has none');

            bb = sscanf(info(1).ImageDescription, 'BoundingBox %f %f %f %f %f %f')';
            % physical extent = (dim-1)*voxel, origin 0: X=(24-1)*0.5, Y=(32-1)*0.6, Z=(6-1)*2
            testCase.verifyEqual(bb, [0 11.5 0 18.6 0 10], 'AbsTol', 1e-6, ...
                'BoundingBox must encode the physical voxel extent so the voxel size round-trips');
        end

        function boundingBoxOnly_reloadRecoversVoxel(testCase)
            % End-to-end: a TIFF whose ImageDescription is ONLY a BoundingBox (no
            % action log, hence no |/tab/newline separator) must still restore the
            % voxel size on load - the ImreadLoader parse used to require a separator.
            here     = fileparts(mfilename('fullpath'));
            repoRoot = fileparts(fileparts(here));
            mibPath  = fullfile(repoRoot, 'mib');

            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tif = fullfile(tmp.Folder, 'bbonly.tif');

            % 6-slice stack with a separator-less BoundingBox description
            vol = reshape(uint8(mod(0:32*24*6-1, 251) + 1), [32 24 6]);   % [Y X Z]
            desc = 'BoundingBox 0.000000 11.500000 0.000000 18.600000 0.000000 10.000000';
            for z = 1:6
                mode = 'append'; if z == 1; mode = 'overwrite'; end
                imwrite(vol(:,:,z), tif, 'tif', 'WriteMode', mode, 'Description', desc);
            end

            mibModel = models.MibModel(1, mibPath);
            mibModel.loadImages('Combine datasets', ...
                struct('Filenames', {{tif}}, 'showWaitbar', false, 'id', 1));
            p = mibModel.I{1}.image.pixSize;

            testCase.verifyEqual(p.x, 0.5, 'AbsTol', 1e-6, 'x voxel must come from the BoundingBox');
            testCase.verifyEqual(p.y, 0.6, 'AbsTol', 1e-6, 'y voxel must come from the BoundingBox');
            testCase.verifyEqual(p.z, 2.0, 'AbsTol', 1e-6, 'z voxel must come from the BoundingBox');
        end

    end
end
