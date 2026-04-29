classdef LoaderFactory
% LOADERFACTORY - Factory class to create appropriate image loader based on file format.
%
% This factory creates concrete loader instances based on the loader
% information provided by ExtensionRegistryLoad. Each loader implements
% a standard interface with loadMetadata and loadImages methods.

    methods (Static)
        function loader = create(loaderInfo, options)
            % CREATE - Create an image loader instance based on the loader information.
            %
            % Syntax:
            %   function loader = create(loaderInfo, options)
            %
            % This is the main factory method that instantiates the appropriate
            % loader class based on the loaderId field in loaderInfo structure.
            %
            % Input Arguments:
            %   - **loaderInfo** — [*struct]* structure returned by ExtensionRegistryLoad.resolveLoader
            %   - .loaderId - [char] identifier of the file reader to use
            %   - .mode - [char] dataset mode ('Standard', 'Virtual', 'BigData')
            %   - .reader - [char] reader type ('Default', 'BioFormats')
            %   - .extension - [char] file extension without leading dot
            %   - .imageFormatType - [char] format type identifier
            %   - **options** — [*struct]* options to pass to the loader constructor
            %   - .UseBioFormats - [logical] use BioFormats library
            %   - .waitbar - [logical] show waitbar during loading
            %   - .mibPath - [char] path to MIB directory
            %   - .virtual - [logical] virtual stacking mode
            %   - .customSections - [logical] load custom sections only
            %   - additional format-specific options
            %   - .bioFormatsMemoizerMemoDir - location of MemoizerMemo for bioformats
            %
            % Output Arguments:
            %   - **loader** — loader object implementing loadMetadata and loadImages methods
            %
            % Usage:
            %   Example 1 - Basic usage::
            %
            %     % Basic usage
            %     extReg = io.ExtensionRegistryLoad();
            %     loaderInfo = extReg.resolveLoader('image.tif', 'Standard', 'Default'); % loaderInfo = extReg.resolveLoader('image.tif', obj.I{obj.id}.datasetType, 'Default');
            %     options.waitbar = true;
            %     options.mibPath = 'c:\mib';
            %     loader = io.LoaderFactory.create(loaderInfo, options);
            %     [imginfo, files] = loader.loadMetadata({'image.tif'}, options);
            %     [img, imginfo] = loader.loadImages(files, imginfo, options);
            %
            %
            %   Example 2 - BioFormats example::
            %
            %     % BioFormats example
            %     loaderInfo = extReg.resolveLoader('image.czi', 'Standard', 'BioFormats');
            %     loader = io.LoaderFactory.create(loaderInfo, options);
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
                    % BioFormats reader for virtual stacking mode
                    loader = io.loaders.BioFormatsVirtualSetupLoader(options);

                case "OmeZarr"
                    % OME-Zarr v3 format — setup loader for all dataset modes.
                    % Pass the dataset mode so Zarr3VirtualSetupLoader can decide
                    % whether to load pixels (Standard) or return path only (Virtual/BigData).
                    opts = options;
                    opts.datasetMode = char(loaderInfo.mode);
                    loader = io.loaders.Zarr3VirtualSetupLoader(opts);

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
            % GETAVAILABLELOADERS - Get a list of all available loader types.
            %
            % Syntax:
            %   function loaderList = getAvailableLoaders()
            %
            % Returns a cell array with all supported loader identifiers
            % and their descriptions.
            %
            % Output Arguments:
            %   - **loaderList** — [*struct* array] array of structures with loader information
            %   - .loaderId - [char] loader identifier
            %   - .description - [char] human-readable description
            %   - .extensions - [cell] typical file extensions
            %
            % Usage:
            %   Example 1::
            %
            %     loaderList = io.LoaderFactory.getAvailableLoaders();
            %     fprintf('Available loaders:\n');
            %     for i = 1:numel(loaderList)
            %         fprintf('  %s: %s\n', loaderList(i).loaderId, loaderList(i).description);
            %     end
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
