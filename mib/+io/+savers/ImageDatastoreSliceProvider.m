classdef ImageDatastoreSliceProvider < io.savers.SliceProvider
% IMAGEDATASTORESLICEPROVIDER - SliceProvider over an imageDatastore of image files or volumes.
%
% Streams the files of an ``imageDatastore`` one Z-slice at a time, so a large
% stack is written to disk without ever being gathered into memory. Used by the
% file-conversion plugin (``ImageConverter``) to feed the streaming writers of
% ``io.savers.Zarr3Saver`` when the native (``zarrMex``) backend writes a Zarr
% pyramid.
%
% **Files and slices.** The datastore's reader returns ``[H W C]`` for a file
% that holds one image and ``[H W C Z]`` for a volume (``ImageConverter``'s
% loader-based reader does both). The output depth is the sum of the slices of
% all files, in the order of ``imgDS.Files``; time = 1 (a 5th dimension larger
% than one is refused with ``io:ImageDatastoreSliceProvider:timeSeries``).
% Height / width / channels / class come from a probe read of the first file in
% the constructor. When the first file holds one image, every file is taken to
% hold one, as in a folder of 2D slices - no file is opened twice; when it is a
% volume, the slice count of every other file comes from ``fileDepthFcn`` (e.g.
% the loader's metadata) or, without one, from reading the file. A file whose
% read depth differs from the count raises ``io:ImageDatastoreSliceProvider:depthMismatch``.
%
% **Volumes in memory.** A volume is read whole (the loaders read whole files)
% and kept while its slices are taken in order, then released after its last
% slice: peak memory adds one file of ``LargestFileDepth`` slices per process.
% With a pool each worker holds its own copy of the provider, so each worker
% reads a volume once per run of consecutive slab tasks on it.
%
% **Rows of a slice.** For TIFF files ``getSliceRows`` reads only a band of rows
% (``imread`` with ``PixelRegion``, which decodes only the strips or tiles that
% hold them), so ``Zarr3Saver.saveStreamResumable`` can convert slices larger
% than memory in bands (``BandHeight``). ``SupportsRowReads`` is true only when
% every file is a single-image TIFF and the first rows ``imread`` returns for
% the first file equal those of the datastore's reader - a reader that converts
% the data (colormap, other pages, class) would make a band differ from the
% slice. A TIFF stored as a single strip is decoded whole for every band: still
% bounded in memory, but the decoding is repeated once per band.
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
        LargestFileDepth = 1       % slices of the deepest file; > 1 when a file is a volume
    end

    properties (Access = private)
        Datastore            % matlab.io.datastore.ImageDatastore
        FileDepths           % [numFiles x 1] slices in each file
        FirstSliceOfFile     % [numFiles x 1] output Z of the first slice of each file
        CachedFileIndex = 0  % file held in CachedVolume, 0 = none
        CachedVolume = []    % [H W C Z] the volume being streamed
    end

    methods
        function obj = ImageDatastoreSliceProvider(imgDS, fileDepthFcn)
            % IMAGEDATASTORESLICEPROVIDER - Wrap an imageDatastore of image files or volumes.
            %
            % Input Arguments:
            %   - **imgDS** - a ``matlab.io.datastore.ImageDatastore`` whose files are
            %     in Z order (the order in ``imgDS.Files``); its reader returns
            %     ``[H W C]`` or, for a volume, ``[H W C Z]``.
            %   - **fileDepthFcn** - *(optional)* function handle, ``depth =
            %     fileDepthFcn(filename)``, the number of Z-slices in a file without
            %     reading its pixels. Used only when the first file is a volume and
            %     there are more files; default ``[]`` = read those files to count.
            if nargin < 2; fileDepthFcn = []; end
            obj.Datastore = copy(imgDS);   % isolate read position from the caller

            numFiles = numel(obj.Datastore.Files);
            probe = obj.readFile(1);
            if size(probe, 5) > 1
                error('io:ImageDatastoreSliceProvider:timeSeries', ...
                    'Time series cannot be converted, the file has %d time points:\n%s', ...
                    size(probe, 5), obj.Datastore.Files{1});
            end
            H = size(probe, 1);
            W = size(probe, 2);
            C = size(probe, 3);

            fileDepths = ones(numFiles, 1);
            fileDepths(1) = size(probe, 4);
            if fileDepths(1) > 1
                for fileIndex = 2:numFiles
                    if isempty(fileDepthFcn)
                        fileDepths(fileIndex) = size(obj.readFile(fileIndex), 4);
                    else
                        fileDepths(fileIndex) = fileDepthFcn(obj.Datastore.Files{fileIndex});
                    end
                end
                % the probe is not kept: the provider goes to the pool workers whole
            end
            obj.FileDepths = fileDepths;
            obj.FirstSliceOfFile = cumsum([1; fileDepths(1:end-1)]);
            obj.LargestFileDepth = max(fileDepths);
            numSlices = sum(fileDepths);

            obj.SliceSize   = [H W];
            obj.NumChannels = C;
            obj.NumSlices   = numSlices;
            obj.NumFrames   = 1;
            obj.DataClass   = class(probe);
            obj.OutputSize  = [H, W, numSlices, C, 1];

            [~, ~, extensions] = cellfun(@fileparts, obj.Datastore.Files, 'UniformOutput', false);
            if obj.LargestFileDepth == 1 && all(ismember(lower(extensions), {'.tif', '.tiff'}))
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
            % GETSLICE - Return slice [H W C] at output depth z (frame index ignored; T==1).
            fileIndex = find(obj.FirstSliceOfFile <= z, 1, 'last');
            if obj.FileDepths(fileIndex) == 1
                slice = obj.readFile(fileIndex);
                obj.verifyDepth(fileIndex, size(slice, 4));
                return;
            end
            if obj.CachedFileIndex ~= fileIndex
                obj.CachedVolume = [];   % release the previous volume before reading the next
                obj.CachedVolume = obj.readFile(fileIndex);
                obj.CachedFileIndex = fileIndex;
                obj.verifyDepth(fileIndex, size(obj.CachedVolume, 4));
            end
            sliceInFile = z - obj.FirstSliceOfFile(fileIndex) + 1;
            slice = obj.CachedVolume(:, :, :, sliceInFile);
            if sliceInFile == obj.FileDepths(fileIndex)
                obj.CachedVolume = [];
                obj.CachedFileIndex = 0;
            end
        end

        function rows = getSliceRows(obj, z, rowFirst, rowLast)
            % GETSLICEROWS - Return rows rowFirst..rowLast [rows W C] of the z-th file.
            %
            % Reads only those rows from a TIFF (``imread`` with ``PixelRegion``);
            % valid when ``SupportsRowReads`` is true (one image per file, so the
            % z-th slice is the z-th file), otherwise an error.
            if ~obj.SupportsRowReads
                error('io:ImageDatastoreSliceProvider:noRowReads', ...
                    'These files cannot be read in rows; use getSlice.');
            end
            rows = imread(obj.Datastore.Files{z}, 'PixelRegion', {[rowFirst rowLast], [1 obj.SliceSize(2)]});
        end
    end

    methods (Access = private)
        function img = readFile(obj, fileIndex)
            % READFILE - Read a file as [H W C] or, for a volume, [H W C Z].
            img = readimage(obj.Datastore, fileIndex);
        end

        function verifyDepth(obj, fileIndex, readDepth)
            % VERIFYDEPTH - Error when a file holds another number of slices than counted.
            if readDepth ~= obj.FileDepths(fileIndex)
                error('io:ImageDatastoreSliceProvider:depthMismatch', ...
                    ['The file holds %d slice(s), %d were expected (when the first file holds ' ...
                    'a single image, every file must hold one):\n%s'], ...
                    readDepth, obj.FileDepths(fileIndex), obj.Datastore.Files{fileIndex});
            end
        end
    end
end
