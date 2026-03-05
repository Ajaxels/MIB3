classdef MibVirtualImage < core.MibImage
    % classdef MibVirtualImage < core.MibImage
    % Virtual image class for MIB3 — reads slices from disk on demand.
    %
    % The dataset is NOT loaded into memory; obj.data{} stores either:
    %   - file-path strings  (hdf5 / BioFormats mode)
    %   - loci.formats.Memoizer reader handles (BioFormats mode, when opened)
    %   - a zarr path string in obj.data{1}  (Zarr/pyramid mode)
    %
    % Dispatch logic in getData():
    %   ~isempty(obj.pyramid.levelNames)  ->  getDataZarr
    %   otherwise                         ->  getDataVirt  (BioFormats / HDF5)
    %
    % Key differences vs MIB2:
    %   - dimension order: [y, x, z, c, t]  (MIB3) vs [y, x, c, z, t] (MIB2)
    %   - YX orientation  = 3               (MIB3) vs 4               (MIB2)
    %   - image data      = obj.data{}      (MIB3) vs obj.img{}        (MIB2)
    %   - image class     = obj.dataClass   (MIB3) vs obj.meta('imgClass') (MIB2)

    properties
        Virtual
        % a structure describing the virtual stack layout:
        % @li .readerId        - [1 x depth] index into obj.data{} for each slice
        % @li .objectType      - {1 x nReaders} cell of reader type strings:
        %                        'bioformats', 'matlab.hdf5', 'hdf5_image'
        % @li .seriesName      - {1 x nReaders} series name / HDF5 dataset path per reader
        % @li .slicesPerFile   - [1 x nReaders] number of z-slices contributed by each file
        % @li .filenames       - {1 x nReaders} full file paths
    end

    methods
        % declaration of functions in external files

        initialize(obj, data, meta)          % Initialize with dummy placeholder or provided file paths (overrides MibImage.initialize)

        dataset = getData(obj, layerType, orient, colChannel, options)    % Get dataset — dispatches to getDataZarr or getDataVirt

        dataset = getDataZarr(obj, type, orient, colChannel, options)        % Read a subvolume from a Zarr pyramid dataset with optional slicing.

        dataset = getDataVirt(obj, type, orient, colChannel, options)        % Read a virtual dataset (BioFormats or HDF5) from disk on demand.

        closeVirtualDataset(obj)             % Close open virtual readers (BioFormats Memoizer handles)

        function obj = MibVirtualImage(data, meta)
            % obj = MibVirtualImage(data, meta)
            % Constructor — delegates to MibImage then initialises Virtual struct.
            %
            % Parameters:
            % data: ignored (virtual images are not pre-loaded); pass [] or omit
            % meta: metadata dictionary / struct, passed to MibImage constructor

            if nargin < 2; meta = utils.defaults.initializeImgInfo(); end
            if nargin < 1; data = []; end

            % call superclass constructor
            obj = obj@core.MibImage(data, meta);

            % mark type
            obj.type = 'virtual';

            % initialise empty Virtual struct
            obj.Virtual = struct( ...
                'readerId',      [], ...
                'objectType',    {{}}, ...
                'seriesName',    {{}}, ...
                'slicesPerFile', [], ...
                'filenames',     {{}} ...
            );
        end
    end
end
