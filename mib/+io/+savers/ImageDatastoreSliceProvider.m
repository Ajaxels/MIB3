classdef ImageDatastoreSliceProvider < io.savers.SliceProvider
% IMAGEDATASTORESLICEPROVIDER - SliceProvider over an imageDatastore (one file per Z-slice).
%
% Streams a directory of single-slice image files (as opened by
% ``imageDatastore``) one slice at a time, so a large stack is written to disk
% without ever being gathered into memory. Used by the file-conversion plugin
% (``ImageConverter``) to feed ``io.savers.Zarr3Saver.saveStream`` when the
% native (``zarrMex``) backend writes a Zarr v3 pyramid.
%
% Each file is one Z-slice; depth = number of files, time = 1 (file stacks carry
% no time axis). Height / width / channels / class are discovered from a probe
% read of the first file in the constructor.
%
% See also: io.savers.SliceProvider, io.savers.Zarr3Saver,
% plugins.FileProcessing.ImageConverter.ImageConverter
%
% **Example** — stream a folder of TIFFs into a Zarr v3 pyramid:
%
%   .. code-block:: matlab
%
%      ds       = imageDatastore('C:\slices', 'FileExtensions', '.tif');
%      provider = io.savers.ImageDatastoreSliceProvider(ds);
%      io.savers.Zarr3Saver(struct()).saveStream(provider, ...
%          struct('pixSize', struct('x',0.01,'y',0.01,'z',0.03)), ...
%          'C:\out\stack.zarr3', struct('silent', true));

    properties (Access = private)
        Datastore   % matlab.io.datastore.ImageDatastore
    end

    methods
        function obj = ImageDatastoreSliceProvider(imgDS)
            % IMAGEDATASTORESLICEPROVIDER - Wrap an imageDatastore (one file per Z-slice).
            %
            % Input Arguments:
            %   - **imgDS** — a ``matlab.io.datastore.ImageDatastore`` whose files are
            %     ordered Z-slices (the order in ``imgDS.Files``).
            obj.Datastore = copy(imgDS);   % isolate read position from the caller

            numFiles = numel(obj.Datastore.Files);
            probe = obj.readFile(1);
            H = size(probe, 1);
            W = size(probe, 2);
            C = size(probe, 3);

            obj.SliceSize   = [H W];
            obj.NumChannels = C;
            obj.NumSlices   = numFiles;
            obj.NumFrames   = 1;
            obj.DataClass   = class(probe);
            obj.OutputSize  = [H, W, numFiles, C, 1];
        end

        function slice = getSlice(obj, z, ~)
            % GETSLICE - Return slice [H W C] for the z-th file (frame index ignored; T==1).
            slice = obj.readFile(z);
        end
    end

    methods (Access = private)
        function img = readFile(obj, z)
            % READFILE - Read the z-th file as [H W C].
            img = readimage(obj.Datastore, z);
        end
    end
end
