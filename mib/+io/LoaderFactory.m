classdef LoaderFactory
% LOADERFACTORY - Factory for instantiating appropriate image loaders based on file format.
%
% Creates concrete loader instances based on the loader information provided by
% ``ExtensionRegistryLoad``. Each loader implements a standard interface with
% ``loadMetadata`` and ``loadImages`` methods.

    methods (Static)
        function loader = create(loaderInfo, options)
            % CREATE - Create an image loader instance for a given file format.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.LoaderFactory.create(loaderInfo, options)
            %
            % Main factory method that instantiates the appropriate loader class based on
            % the ``loaderId`` field in the loaderInfo structure. Routes to ``imread``,
            % BioFormats, HDF5, NRRD, IMOD, AmiraMesh, OME-Zarr, or other readers.
            %
            % Input Arguments:
            %   - **loaderInfo** — struct returned by ``ExtensionRegistryLoad.resolveLoader``:
            %
            %     - ``.loaderId`` — [char] identifier of the file reader to use
            %     - ``.mode`` — [char] dataset mode (``'Standard'``, ``'Virtual'``, ``'BigData'``)
            %     - ``.reader`` — [char] reader type (``'Default'``, ``'BioFormats'``)
            %     - ``.extension`` — [char] filename extension without leading dot
            %     - ``.imageFormatType`` — [char] format type identifier
            %
            %   - **options** — *(optional)* struct with configuration options:
            %
            %     - ``.UseBioFormats`` — [logical] use BioFormats library
            %     - ``.waitbar`` — [logical] show progress bar during loading
            %     - ``.mibPath`` — [char] path to MIB installation directory
            %     - ``.virtual`` — [logical] virtual stacking mode
            %     - ``.customSections`` — [logical] load custom sections only
            %     - ``.bioFormatsMemoizerMemoDir`` — [char] location of MemoizerMemo cache for BioFormats
            %     - Additional format-specific options passed to the loader constructor
            %
            % Output Arguments:
            %   - **loader** — loader object instance implementing ``loadMetadata`` and ``loadImages`` methods
            %
            % **Example 1** — basic usage with Standard mode and imread:
            %
            %   .. code-block:: matlab
            %
            %      extReg = io.ExtensionRegistryLoad();
            %      loaderInfo = extReg.resolveLoader('image.tif', 'Standard', 'Default');
            %      options.waitbar = true;
            %      options.mibPath = 'c:\mib';
            %      loader = io.LoaderFactory.create(loaderInfo, options);
            %      [imginfo, files] = loader.loadMetadata({'image.tif'}, options);
            %      [img, imginfo] = loader.loadImages(files, imginfo, options);
            %
            % **Example 2** — using BioFormats for complex formats:
            %
            %   .. code-block:: matlab
            %
            %      loaderInfo = extReg.resolveLoader('image.czi', 'Standard', 'BioFormats');
            %      loader = io.LoaderFactory.create(loaderInfo, options);
            %

            if nargin < 2; options = struct(); end

            % Ensure loaderId is a string for switch statement
            loaderId = string(loaderInfo.loaderId);

            % Create appropriate loader based on loaderId
            switch loaderId
                case "imread"
                    % Standard MATLAB imread-compatible formats (TIF, PNG, JPEG, etc.)
                    loader = io.loaders.ImreadLoader(options);

                case "BioFormatsStd"
                    % BioFormats reader for standard (memory-resident) mode
                    loader = io.loaders.BioFormatsStdLoader(options);

                case "BioFormatsVirtual"
                    % BioFormats reader for virtual stacking / BigData mode.
                    % Pass the dataset mode so the setup loader can decide between a
                    % flat virtual stack (Virtual) and a pyramid-aware direct-read
                    % setup (BigData) — mirrors the OmeZarr case.
                    opts = options;
                    opts.datasetMode  = char(loaderInfo.mode);
                    opts.readerFamily = char(loaderInfo.reader);   % 'BioFormats' | 'OpenSlide'
                    loader = io.loaders.BioFormatsVirtualSetupLoader(opts);

                case "OmeZarr"
                    % OME-Zarr v3 format — setup loader for all dataset modes.
                    % Pass the dataset mode so Zarr3VirtualSetupLoader can decide
                    % whether to load pixels (Standard) or return path only (Virtual/BigData).
                    opts = options;
                    opts.datasetMode = char(loaderInfo.mode);
                    loader = io.loaders.Zarr3VirtualSetupLoader(opts);

                case "OmeZarrV2"
                    % OME-Zarr v2 format — python-backed setup loader for all dataset
                    % modes (Standard/Virtual/BigData) plus Model (segmentation labels).
                    % Pass the dataset mode so Zarr2VirtualSetupLoader can decide whether
                    % to load pixels (Standard/Model) or return path only (Virtual/BigData).
                    opts = options;
                    opts.datasetMode = char(loaderInfo.mode);
                    loader = io.loaders.Zarr2VirtualSetupLoader(opts);

                case "AmiraMesh"
                    % Amira Mesh format (.am)
                    loader = io.loaders.AmiraMeshLoader(options);

                case "hdf5-header"
                    % HDF5 with XML header (MIB format or BigDataViewer)
                    loader = io.loaders.HDF5HeaderLoader(options);

                case "hdf5-header-virtual"
                    % XML+H5 in virtual stacking mode — metadata from XML, pixels on demand
                    loader = io.loaders.HDF5VirtualSetupLoader(options, true);

                case "hdf5-no-header"
                    % HDF5 without header (Ilastik format, raw HDF5)
                    loader = io.loaders.HDF5NoHeaderLoader(options);

                case "hdf5-no-header-virtual"
                    % Bare H5 in virtual stacking mode — pixels on demand
                    loader = io.loaders.HDF5VirtualSetupLoader(options, false);

                case "mibImg"
                    % MIB's custom MATLAB-based image format
                    loader = io.loaders.MibImgLoader(options);

                case "imod"
                    % IMOD MRC format (.mrc, .rec, .st, .preali)
                    loader = io.loaders.ImodLoader(options);

                case "nrrd"
                    % NRRD format (Nearly Raw Raster Data)
                    loader = io.loaders.NrrdLoader(options);

                case "MatModel"
                    % MATLAB-format segmentation model (.model, .mat, .mibCat)
                    loader = io.loaders.MatModelLoader(options);

                case "VideoReader"
                    % MATLAB VideoReader for movie files
                    loader = io.loaders.VideoReaderLoader(options);

                otherwise
                    error('io:LoaderFactory:UnknownReader', ...
                        'Unknown loaderId: "%s". Please check ExtensionRegistryLoad configuration.', ...
                        loaderInfo.loaderId);
            end
        end

        function loaderList = getAvailableLoaders()
            % GETAVAILABLELOADERS - Get a list of all available loader types with descriptions.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      loaderList = io.LoaderFactory.getAvailableLoaders()
            %
            % Returns a struct array containing all supported loader identifiers,
            % their descriptions, and typical file extensions.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **loaderList** — struct array with loader information:
            %
            %     - ``.loaderId`` — [char] loader identifier
            %     - ``.description`` — [char] human-readable description
            %     - ``.extensions`` — cell array of [char] typical file extensions
            %
            % **Example 1** — display all available loaders:
            %
            %   .. code-block:: matlab
            %
            %      loaderList = io.LoaderFactory.getAvailableLoaders();
            %      fprintf('Available loaders:\n');
            %      for i = 1:numel(loaderList)
            %          fprintf('  %s: %s\n', loaderList(i).loaderId, loaderList(i).description);
            %      end
            %

            loaderList = struct( ...
                'loaderId', {}, ...
                'description', {}, ...
                'extensions', {} ...
                );

            idx = 1;

            loaderList(idx).loaderId = 'imread';
            loaderList(idx).description = 'MATLAB standard image reader';
            loaderList(idx).extensions = {'tif', 'tiff', 'png', 'jpg', 'jpeg', 'bmp', 'gif'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'BioFormatsStd';
            loaderList(idx).description = 'Bio-Formats (standard mode)';
            loaderList(idx).extensions = {'czi', 'lsm', 'lif', 'nd2', 'oib', 'vsi'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'BioFormatsVirtual';
            loaderList(idx).description = 'Bio-Formats (virtual mode)';
            loaderList(idx).extensions = {'czi', 'lsm', 'lif', 'nd2', 'oib', 'vsi'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'OmeZarr';
            loaderList(idx).description = 'OME-Zarr v3 format';
            loaderList(idx).extensions = {'zarr', 'zarr3'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'OmeZarrV2';
            loaderList(idx).description = 'OME-Zarr v2 format (python-backed)';
            loaderList(idx).extensions = {'zarr2'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'AmiraMesh';
            loaderList(idx).description = 'Amira Mesh format';
            loaderList(idx).extensions = {'am'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'hdf5-header';
            loaderList(idx).description = 'HDF5 with XML header';
            loaderList(idx).extensions = {'xml'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'hdf5-no-header';
            loaderList(idx).description = 'HDF5 without header';
            loaderList(idx).extensions = {'h5', 'hdf5'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'mibImg';
            loaderList(idx).description = 'MIB custom format';
            loaderList(idx).extensions = {'mibimg'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'imod';
            loaderList(idx).description = 'IMOD MRC format';
            loaderList(idx).extensions = {'mrc', 'rec', 'st', 'preali'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'nrrd';
            loaderList(idx).description = 'NRRD format';
            loaderList(idx).extensions = {'nrrd'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'MatModel';
            loaderList(idx).description = 'MATLAB-format segmentation model';
            loaderList(idx).extensions = {'model', 'mat', 'mibcat'};
            idx = idx + 1;

            loaderList(idx).loaderId = 'VideoReader';
            loaderList(idx).description = 'Video files';
            loaderList(idx).extensions = {'avi', 'mp4', 'mov'};
        end
    end
end
