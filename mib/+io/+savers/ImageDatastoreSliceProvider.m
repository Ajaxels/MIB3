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
% **Rows of a slice.** For TIFF files ``getSliceRows`` reads only a band of rows
% (``imread`` with ``PixelRegion``, which decodes only the strips or tiles that
% hold them), so ``Zarr3Saver.saveStreamResumable`` can convert slices larger
% than memory in bands (``BandHeight``). ``SupportsRowReads`` is true only when
% every file is a TIFF and the first rows ``imread`` returns for the first file
% equal those of the datastore's reader - a reader that converts the data
% (colormap, other pages, class) would make a band differ from the slice. A TIFF stored as a
% single strip is decoded whole for every band: still bounded in memory, but the
% decoding is repeated once per band.
%
% See also: io.savers.SliceProvider, io.savers.Zarr3Saver,
% plugins.FileProcessing.ImageConverter.ImageConverter
%
% **Example** - stream a folder of TIFFs into a Zarr v3 pyramid:
%
%   .. code-block:: matlab
%
%      ds       = imageDatastore('C:\slices', 'FileExtensions', '.tif');
%      provider = io.savers.ImageDatastoreSliceProvider(ds);
%      io.savers.Zarr3Saver(struct()).saveStream(provider, ...
%          struct('pixSize', struct('x',0.01,'y',0.01,'z',0.03)), ...
%          'C:\out\stack.zarr3', struct('silent', true));

    properties (SetAccess = private)
        SupportsRowReads = false   % getSliceRows returns rows identical to getSlice
    end

    properties (Access = private)
        Datastore   % matlab.io.datastore.ImageDatastore
    end

    methods
        function obj = ImageDatastoreSliceProvider(imgDS)
            % IMAGEDATASTORESLICEPROVIDER - Wrap an imageDatastore (one file per Z-slice).
            %
            % Input Arguments:
            %   - **imgDS** - a ``matlab.io.datastore.ImageDatastore`` whose files are
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

            [~, ~, extensions] = cellfun(@fileparts, obj.Datastore.Files, 'UniformOutput', false);
            if all(ismember(lower(extensions), {'.tif', '.tiff'}))
                try
                    % a few rows suffice to catch a converting reader, and do not
                    % hold a second copy of a slice that may be huge
                    checkRows = min(16, H);
                    firstRows = imread(obj.Datastore.Files{1}, 'PixelRegion', {[1 checkRows], [1 W]});
                    obj.SupportsRowReads = isequal(firstRows, probe(1:checkRows, :, :));
                catch
                    obj.SupportsRowReads = false;
                end
            end
        end

        function slice = getSlice(obj, z, ~)
            % GETSLICE - Return slice [H W C] for the z-th file (frame index ignored; T==1).
            slice = obj.readFile(z);
        end

        function rows = getSliceRows(obj, z, rowFirst, rowLast)
            % GETSLICEROWS - Return rows rowFirst..rowLast [rows W C] of the z-th file.
            %
            % Reads only those rows from a TIFF (``imread`` with ``PixelRegion``);
            % valid when ``SupportsRowReads`` is true, otherwise an error.
            if ~obj.SupportsRowReads
                error('io:ImageDatastoreSliceProvider:noRowReads', ...
                    'These files cannot be read in rows; use getSlice.');
            end
            rows = imread(obj.Datastore.Files{z}, 'PixelRegion', {[rowFirst rowLast], [1 obj.SliceSize(2)]});
        end
    end

    methods (Access = private)
        function img = readFile(obj, z)
            % READFILE - Read the z-th file as [H W C].
            img = readimage(obj.Datastore, z);
        end
    end
end
