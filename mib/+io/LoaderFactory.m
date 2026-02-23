classdef LoaderFactory
    % classdef LoaderFactory
    % Factory class to create appropriate image loader based on file format
    %
    % This factory creates concrete loader instances based on the loader
    % information provided by ExtensionRegistryLoad. Each loader implements
    % a standard interface with loadMetadata and loadImages methods.

    methods (Static)
        function loader = create(loaderInfo, options)
            % function loader = create(loaderInfo, options)
            % Create an image loader instance based on the loader information
            %
            % This is the main factory method that instantiates the appropriate
            % loader class based on the loaderId field in loaderInfo structure.
            %
            % Parameters:
            % loaderInfo: [@em struct] structure returned by ExtensionRegistryLoad.resolveLoader
            %   @li .loaderId - [char] identifier of the file reader to use
            %   @li .mode - [char] dataset mode ('Standard', 'Virtual', 'BigData')
            %   @li .reader - [char] reader type ('Default', 'BioFormats')
            %   @li .extension - [char] file extension without leading dot
            %   @li .imageFormatType - [char] format type identifier
            % options: [@em struct] options to pass to the loader constructor
            %   @li .UseBioFormats - [logical] use BioFormats library
            %   @li .waitbar - [logical] show waitbar during loading
            %   @li .mibPath - [char] path to MIB directory
            %   @li .virtual - [logical] virtual stacking mode
            %   @li .customSections - [logical] load custom sections only
            %   @li additional format-specific options
            %   @li .bioFormatsMemoizerMemoDir - location of MemoizerMemo for bioformats
            %
            % Return values:
            % loader: loader object implementing loadMetadata and loadImages methods
            %
            % Example:
            % @code
            % % Basic usage
            % extReg = io.ExtensionRegistryLoad();
            % loaderInfo = extReg.resolveLoader('image.tif', 'Standard', 'Default'); % loaderInfo = extReg.resolveLoader('image.tif', obj.I{obj.id}.datasetType, 'Default');
            % options.waitbar = true;
            % options.mibPath = 'c:\mib';
            % loader = io.LoaderFactory.create(loaderInfo, options);
            % [imginfo, files] = loader.loadMetadata({'image.tif'}, options);
            % [img, imginfo] = loader.loadImages(files, imginfo, options);
            % @endcode
            %
            % @code
            % % BioFormats example
            % loaderInfo = extReg.resolveLoader('image.czi', 'Standard', 'BioFormats');
            % loader = io.LoaderFactory.create(loaderInfo, options);
            % @endcode

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
                    loader = io.loaders.BioFormatsVirtualLoader(options);

                case "OmeZarr"
                    % OME-Zarr format (v2/v3)
                    loader = io.loaders.OmeZarrLoader(options);

                case "AmiraMesh"
                    % Amira Mesh format (.am)
                    loader = io.loaders.AmiraMeshLoader(options);

                case "hdf5-header"
                    % HDF5 with XML header (MIB format or BigDataViewer)
                    loader = io.loaders.HDF5HeaderLoader(options);

                case "hdf5-no-header"
                    % HDF5 without header (Ilastik format, raw HDF5)
                    loader = io.loaders.HDF5NoHeaderLoader(options);

                case "mibImg"
                    % MIB's custom MATLAB-based image format
                    loader = io.loaders.MibImgLoader(options);

                case "imod"
                    % IMOD MRC format (.mrc, .rec, .st, .preali)
                    loader = io.loaders.ImodLoader(options);

                case "nrrd"
                    % NRRD format (Nearly Raw Raster Data)
                    loader = io.loaders.NrrdLoader(options);

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
            % function loaderList = getAvailableLoaders()
            % Get a list of all available loader types
            %
            % Returns a cell array with all supported loader identifiers
            % and their descriptions.
            %
            % Return values:
            % loaderList: [@em struct array] array of structures with loader information
            %   @li .loaderId - [char] loader identifier
            %   @li .description - [char] human-readable description
            %   @li .extensions - [cell] typical file extensions
            %
            % Example:
            % @code
            % loaderList = io.LoaderFactory.getAvailableLoaders();
            % fprintf('Available loaders:\n');
            % for i = 1:numel(loaderList)
            %     fprintf('  %s: %s\n', loaderList(i).loaderId, loaderList(i).description);
            % end
            % @endcode

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
            loaderList(idx).description = 'OME-Zarr format';
            loaderList(idx).extensions = {'zarr', 'zarr2', 'zarr3'};
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

            loaderList(idx).loaderId = 'VideoReader';
            loaderList(idx).description = 'Video files';
            loaderList(idx).extensions = {'avi', 'mp4', 'mov'};
        end
    end
end
