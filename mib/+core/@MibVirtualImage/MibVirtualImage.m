classdef MibVirtualImage < core.MibImage
    % MIBVIRTUALIMAGE - Virtual image class for MIB3 - reads slices from disk on demand.
    %
    % Subclass of ``core.MibImage`` that defers image data loading to disk.
    % Data is accessed slice-by-slice from external files (HDF5, BioFormats, Zarr) without
    % pre-loading the entire dataset into memory.
    %
    % **Data storage:**
    %   ``obj.filePaths{}`` stores file references (not pixel data):
    %
    %     - File-path strings (HDF5 / BioFormats mode)
    %     - ``loci.formats.Memoizer`` reader handles (BioFormats mode, when opened)
    %     - Zarr pyramid path string in ``obj.filePaths{1}`` (Zarr/pyramid mode)
    %
    % **Dispatch logic in getData():**
    %   - When ``~isempty(obj.pyramid.levelNames)`` → calls ``getDataZarr()``
    %   - Otherwise → calls ``getDataVirt()`` (BioFormats / HDF5)
    %
    % **Key differences from MIB2:**
    %
    %   | Property | MIB3 | MIB2 |
    %   |----------|------|------|
    %   | Dimension order | ``[y, x, z, c, t]`` | ``[y, x, c, z, t]`` |
    %   | YX orientation | ``3`` | ``4`` |
    %   | Image data | ``obj.data{}`` | ``obj.img{}`` |
    %   | Image class | ``obj.dataClass`` | ``obj.meta('imgClass')`` |

    properties
        filePaths = {}
        % ``{1 x nFiles}`` cell array of file-path strings (or ``loci.formats.Memoizer``
        % handles in legacy BioFormats mode) used by virtual loader dispatch.
        % Replaces the earlier pattern of storing paths in ``obj.data{}``.
        Virtual
        % a structure describing the virtual stack layout:
        %
        % - ``.readerId`` - ``[1 x depth]`` index into ``obj.Virtual.filenames`` for each slice
        % - ``.objectType`` - ``{1 x nReaders}`` cell of reader type strings:
        %   ``'bioformats'``, ``'matlab.hdf5'``, ``'hdf5_image'``
        % - ``.seriesName`` - ``{1 x nReaders}`` series name / HDF5 dataset path per reader;
        %   for ``'bioformats'`` this is a 1-based numeric series index
        % - ``.slicesPerFile`` - ``[1 x nReaders]`` number of z-slices contributed by each file
        % - ``.filenames`` - ``{1 x nReaders}`` full file paths
        bioFormatsMemoizerMemoDir = ''
        % [char] path to the directory used by the BioFormats Memoizer for memo files.
        % Mirrors MibDataset.bioFormatsMemoizerMemoDir - set from there when a
        % virtual dataset is initialised so that getOrCreateLoader can access it.
        loaders = {}
        % {1 x nReaders} cell array of virtual loader objects, one per source file.
        % Each element is either an io.loaders.HDF5VirtualLoader or an
        % io.loaders.BioFormatsVirtualLoader, created lazily on first access
        % by getOrCreateLoader() and cleared by initialize() / closeVirtualDataset().
    end

    methods
        % declaration of methods in external files
        initialize(obj, data, meta)          % Initialize with dummy placeholder or provided file paths (overrides MibImage.initialize)
        dataset = getData(obj, layerType, orient, colChannel, options)    % Get dataset - dispatches to getDataZarr or getDataVirt
        dataset = getDataZarr(obj, type, orient, colChannel, options)        % Read a subvolume from a Zarr pyramid dataset with optional slicing.
        dataset = getDataVirt(obj, type, orient, colChannel, options)        % Read a virtual dataset (BioFormats or HDF5) from disk on demand.
        loader = getOrCreateLoader(obj, fileIdx)   % Return (or lazily create) the virtual loader for file index fileIdx.
        closeVirtualDataset(obj)             % Close open virtual readers and loader objects.
        insertSlice(obj, img, insertPosition, dim, virtMeta, options)    % Insert virtual file references along depth; updates Virtual struct and sliceName

        function obj = MibVirtualImage(data, meta)
            % MIBVIRTUALIMAGE - obj = MibVirtualImage(data, meta).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MibVirtualImage(data, meta)
            %
            % Constructor - delegates to MibImage then initialises Virtual struct.
            %
            % Input Arguments:
            %   - **data** - ignored (virtual images are not pre-loaded); pass [] or omit
            %   - **meta** - metadata dictionary / struct, passed to MibImage constructor
            %

            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; data = []; end

            % call superclass constructor - this calls MibVirtualImage.initialize,
            % which may populate obj.Virtual from meta{"Virtual"} when loading
            % an HDF5 virtual dataset via HDF5VirtualSetupLoader
            obj = obj@core.MibImage(data, meta);

            % mark type
            obj.type = 'virtual';

            % Set the dummy default Virtual struct only when initialize() did NOT
            % already configure it (obj.Virtual is empty for blank placeholders;
            % it is a struct when loaded from meta{"Virtual"})
            if isempty(obj.Virtual)
                obj.Virtual = struct( ...
                    'readerId',      1, ...
                    'objectType',    {{'matlab.hdf5'}}, ...
                    'seriesName',    {{'/im_browser_dummy'}}, ...
                    'slicesPerFile', 1, ...
                    'filenames',     {'im_browser_dummy.h5'}, ...
                    'transMatrix',   {{[]}} ...
                );
            end
        end
    end
end
