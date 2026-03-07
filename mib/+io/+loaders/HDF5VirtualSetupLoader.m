classdef HDF5VirtualSetupLoader < io.loaders.BaseImageLoader
    % classdef HDF5VirtualSetupLoader < io.loaders.BaseImageLoader
    % Virtual-mode setup loader for HDF5/XML datasets.
    %
    % Wraps either HDF5HeaderLoader (XML+H5) or HDF5NoHeaderLoader (bare H5)
    % and adapts them for virtual stacking mode:
    %
    %   loadMetadata  ->  delegates entirely to the inner loader (XML parsing,
    %                     pixel-size extraction, dataset selection dialog, etc.)
    %   loadImages    ->  does NOT read pixel data; instead returns the H5
    %                     file path(s) as a cell array and stores the Virtual
    %                     struct in imginfo{"Virtual"} so that
    %                     MibVirtualImage.initialize can wire it up.
    %
    % The objectType field is normalised to 'matlab.hdf5' for all plain HDF5
    % variants so that MibVirtualImage.getDataVirt dispatches correctly to
    % io.loaders.HDF5VirtualLoader.
    %
    % --- Relationship to HDF5VirtualLoader -----------------------------------
    %
    % These two classes serve different phases of the virtual dataset lifecycle
    % and should not be confused:
    %
    %   HDF5VirtualSetupLoader  — runs ONCE when the user opens a file.
    %     Phase   : dataset initialisation (MibModel.loadImages)
    %     Job     : parse metadata, build the Virtual struct, return H5 paths.
    %     Reads pixels? No.
    %     Lifetime: discarded immediately after open; implements BaseImageLoader.
    %     Created by: LoaderFactory
    %
    %   HDF5VirtualLoader  — runs on EVERY slice request during the session.
    %     Phase   : on-demand pixel reading (MibVirtualImage.getDataVirt)
    %     Job     : call h5read for the requested sub-region; cache axis order.
    %     Reads pixels? Yes — one h5read call per z-group per getDataVirt call.
    %     Lifetime: cached in MibVirtualImage.loaders{} for the session; does
    %               NOT implement BaseImageLoader.
    %     Created by: MibVirtualImage.getOrCreateLoader (lazily, per file)
    %
    % -------------------------------------------------------------------------
    %
    % Usage:
    % @code
    % loader = io.loaders.HDF5VirtualSetupLoader(options, true);  % XML+H5
    % loader = io.loaders.HDF5VirtualSetupLoader(options, false); % bare H5
    % [imginfo, files] = loader.loadMetadata({'stack.xml'}, options);
    % [img, imginfo]   = loader.loadImages(files, imginfo, options);
    % % img is {'C:\data\stack.h5'} and imginfo{"Virtual"} holds the struct
    % @endcode

    properties
        innerLoader
        % io.loaders.HDF5HeaderLoader or io.loaders.HDF5NoHeaderLoader instance
        % that handles all format-specific metadata parsing
    end

    methods
        function obj = HDF5VirtualSetupLoader(options, hasHeader)
            % obj = HDF5VirtualSetupLoader(options, hasHeader)
            % Constructor
            %
            % Parameters:
            % options   : [@em optional, struct] options passed to the inner loader
            % hasHeader : [logical] true = XML+H5 (HDF5HeaderLoader),
            %                       false = bare H5 (HDF5NoHeaderLoader)

            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            if nargin < 2; hasHeader = true; end

            obj.Options = obj.mergeOptions(obj.Options, options);

            if hasHeader
                obj.innerLoader = io.loaders.HDF5HeaderLoader(options);
            else
                obj.innerLoader = io.loaders.HDF5NoHeaderLoader(options);
            end
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % [imginfo, files] = loadMetadata(obj, filenames, options)
            % Delegate metadata loading to the inner loader unchanged.
            %
            % For XML+H5, this parses the XML header and resolves the H5
            % dataset path and pixel sizes.  For bare H5, this runs the
            % dataset-selection dialog and reads dimensions.
            %
            % After this call:
            %   files(i).filename   — path to the actual H5 file
            %   files(i).seriesName — HDF5 internal dataset path
            %   files(i).objecttype — 'matlab.hdf5', 'bdv.hdf5', or 'hdf5image'
            %   files(i).noLayers   — number of z-slices in this file

            [imginfo, files] = obj.innerLoader.loadMetadata(filenames, options);
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options) %#ok<INUSD>
            % [img, imginfo] = loadImages(obj, files, imginfo, options)
            % Virtual-mode image setup — does NOT load pixel data.
            %
            % Returns the H5 file path(s) as a cell array (consumed by
            % MibVirtualImage.initialize as obj.data{}) and populates
            % imginfo{"Virtual"} with the struct fields required by
            % MibVirtualImage:
            %   .objectType    — normalised type string per file
            %   .seriesName    — HDF5 dataset path per file
            %   .slicesPerFile — z-slice count per file
            %   .filenames     — H5 file paths
            %   .readerId      — [1 x totalZ] map: slice index -> file index
            %
            % Parameters:
            % files   : structure array from loadMetadata
            % imginfo : dictionary from loadMetadata
            % options : (unused in virtual mode)
            %
            % Return values:
            % img     : {1 x nFiles} cell array of H5 file paths
            % imginfo : updated dictionary with imginfo{"Virtual"} added

            nFiles = numel(files);
            img = cell(1, nFiles);

            Virtual.objectType    = cell(1, nFiles);
            Virtual.seriesName    = cell(1, nFiles);
            Virtual.slicesPerFile = zeros(1, nFiles);
            Virtual.filenames     = cell(1, nFiles);
            Virtual.transMatrix   = cell(1, nFiles);  % [] when not set (bare H5 without axis reorder)

            for i = 1:nFiles
                img{i}                   = files(i).filename;   % H5 path (resolved by inner loader)
                Virtual.filenames{i}     = files(i).filename;
                Virtual.seriesName{i}    = files(i).seriesName;
                Virtual.slicesPerFile(i) = files(i).noLayers;

                % Propagate transMatrix from SelectHDFSeries so HDF5VirtualLoader
                % can reconstruct the correct native axis order without relying
                % on a JSON attribute that may not be present in bare HDF5 files.
                if isfield(files(i), 'transMatrix') && ~isempty(files(i).transMatrix) ...
                        && isnumeric(files(i).transMatrix) && ~isnan(files(i).transMatrix(1))
                    Virtual.transMatrix{i} = files(i).transMatrix;
                else
                    Virtual.transMatrix{i} = [];
                end

                % Normalise objectType so getDataVirt dispatch works:
                % 'hdf5image' (HDF5NoHeaderLoader) -> 'matlab.hdf5'
                switch lower(files(i).objecttype)
                    case {'matlab.hdf5', 'hdf5_image', 'hdf5image'}
                        Virtual.objectType{i} = 'matlab.hdf5';
                    otherwise
                        Virtual.objectType{i} = files(i).objecttype;  % e.g. 'bdv.hdf5'
                end
            end

            % Build readerId: maps each global z-slice index to its source file index
            totalSlices      = sum(Virtual.slicesPerFile);
            Virtual.readerId = zeros(1, totalSlices);
            idx = 1;
            for i = 1:nFiles
                n = Virtual.slicesPerFile(i);
                Virtual.readerId(idx : idx+n-1) = i;
                idx = idx + n;
            end

            % Update imginfo dimensions from files.
            % HDF5NoHeaderLoader.loadImages normally does this, but virtual
            % mode skips that call, so the initializeImgInfo defaults (512x512)
            % remain in imginfo unless we set them here explicitly.
            imginfo{"Height"} = max([files.height]);
            imginfo{"Width"}  = max([files.width]);
            imginfo{"Depth"}  = sum([files.noLayers]);
            imginfo{"Colors"} = max([files.color]);
            imginfo{"Time"}   = max([files.time]);

            imginfo{"Virtual"} = Virtual;
        end
    end
end
