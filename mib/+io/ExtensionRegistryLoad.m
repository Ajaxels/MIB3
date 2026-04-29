classdef ExtensionRegistryLoad < handle
% EXTENSIONREGISTRYLOAD - class to store filename extensions that MIB is capable to load.
%
% grouped under a dictionary obj.extensionSets

    properties (Access = private)
        extensionSets dictionary
        % dictionary containing extensions for each mode:
        % @li Standard.Default -> standard dataset loaded to memory, default reader
        % @li Virtual.Default  -> virtual dataset, default reader
        % @li BigData.Default -> bigdata dataset, default reader
        % @li Standard.BioFormats  -> standard dataset loaded to memory, bio-formats reader
        % @li Virtual.BioFormats -> virtual dataset, bio-formats reader
        % @li BigData.BioFormats -> bigdata dataset, bio-formats reader
        imreadExtensions
        % cell array with standard matlab image format filename extensions that are loaded with imread
        videoExtensions
        % cell array with standard matlab video extensions
    end

    methods
        function obj = ExtensionRegistryLoad()
            % EXTENSIONREGISTRYLOAD - Constructor - init the class and initiate it with default.
            %
            % Syntax:
            %   function obj = ExtensionRegistryLoad()
            %
            % file extension formats

            obj.extensionSets = dictionary();
            obj.initDefaults();
        end

        function loaderInfo = resolveLoader(obj, filename, mode, reader)
            % RESOLVELOADER - find a loader that should be used for this specific dataset mode, selected reader and filename extension.
            %
            % Syntax:
            %   function loaderInfo = resolveLoader(obj, filename, mode, reader)
            %
            % Input Arguments:
            %   - **filename** — [char] first filename in the sequence of files to load
            %   - **mode** — [char] defining type of MIB dataset,
            %   - 'Standard' standard dataset that is loaded into memory
            %   - 'Virtual' virtual dataset that is loaded on demand
            %   - **reader** — [char] defining the type of file reader
            %   - 'Default' matlab imread, custom and other readers
            %   - 'BioFormats' use the BioFormats library to read images
            %
            % Output Arguments:
            %   - **loaderInfo** — a structure that encodes the potential loader to use or empty
            %     .mode - [char] mode from input
            %     .reader -[char] reader from input
            %     extension - [char] filename extension without a leading dot
            %     loaderId' - loader to use
            %
            
            % get the filename extension
            [~, ~, ext] = fileparts(filename); % get the filename extension with '.'
            ext = lower(strrep(ext, '.', '')); % remove the dot
            
            % generate the dictionary key
            key = obj.generateKey(mode, reader);

            % check whether the extension is compatible
            if ~ismember(ext, lower(obj.extensionSets{key}))
                if ismember(ext, {'zarr', 'zarr3'})
                    loaderInfo = sprintf('io.ExtensionRegistryLoad.resolveRoute:\nExtension "%s" not allowed for\nmode="%s" reader="%s"\n\nTo load Zarr v3 format switch to the Virtual mode!', ext, mode, reader);
                else    
                    loaderInfo = sprintf('io.ExtensionRegistryLoad.resolveRoute:\nExtension "%s" not allowed for\nmode="%s" reader="%s"', ext, mode, reader);
                end
                return;
                %error('io:ExtensionRegistryLoad:NotAllowed', ...
                %    'io.ExtensionRegistryLoad.resolveRoute: Extension "%s" not allowed for mode=%s reader=%s', ext, mode, reader);
            end

            % Route is just "what family of loader to use"
            loaderInfo = struct( ...
                'mode', mode, ...
                'reader', reader, ...
                'extension', ext, ...
                'loaderId', obj.defaultLoaderId(mode, reader, ext));
        end

        function ext = getAllowedExtensions(obj, mode, reader, withDot)
            % GETALLOWEDEXTENSIONS - get registered extensions for the specified mode and reader.
            %
            % Syntax:
            %   function ext = getAllowedExtensions(obj, mode, reader, withDot)
            %
            % Input Arguments:
            %   - **mode** — [char] defining type of MIB dataset,
            %   - 'Standard' standard dataset that is loaded into memory
            %   - 'Virtual' virtual dataset that is loaded on demand
            %   - **reader** — [char] defining the type of file reader
            %   - 'Default' matlab imread, custom and other readers
            %   - 'BioFormats' use the BioFormats library to read images
            %   - **withDot** — [logical] return the list of extensions with or without leading dot
            %   - true return the list as cell array without dots
            %   - false return the list as cell array with leading dots
            %
            % Output Arguments:
            %   - **ext** — cell array with filename extensions
            %
            % Usage:
            %   // get the list of extensions that can be loaded for
            %   the Standard dataset using BioFormats reader and return with
            %   leading dots
            %   <code>
            %   ext = extReg.getAllowedExtensions('Standard', 'BioFormats', false);
            %   <endcode>
            %   Usage from MibModel
            %   <code>
            %   // default reader
            %   ext = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false);
            %   // BioFormats reader
            %   ext = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'BioFormats', false);
            %   <endcode>
            %
            
            if nargin < 4; withDot = true; end
            ext = obj.extensionSets{obj.generateKey(mode, reader)};
            if withDot; ext = strcat('.', ext); end
        end

        function setAllowedExtensions(obj, mode, reader, extensionList)
            % SETALLOWEDEXTENSIONS - update the filename extensions for the corresponding mode and.
            %
            % Syntax:
            %   function setAllowedExtensions(obj, mode, reader, extensionList)
            %
            % reader
            %
            % Input Arguments:
            %   - **mode** — [char] defining type of MIB dataset,
            %   - 'Standard' standard dataset that is loaded into memory
            %   - 'Virtual' virtual dataset that is loaded on demand
            %   - **reader** — [char] defining the type of file reader
            %   - 'Default' matlab imread, custom and other readers
            %   - 'BioFormats' use the BioFormats library to read images
            %   - **extensionList** — cell array with a new list of extensions, with or
            %     without leading dots (e.g. '.tif' and 'tif' are both accepted)
            %

            % Ensure extensions are stored without leading dots to keep
            % internal storage consistent with getAllowedExtensions behavior
            extensionList = regexprep(extensionList, '^\.', '');
            obj.extensionSets{obj.generateKey(mode, reader)} = sort(extensionList);
        end

    end

    methods (Access=private)
        function initDefaults(obj)
            % INITDEFAULTS - init obj.extensionSets.
            %
            % Syntax:
            %   function initDefaults(obj)
            %

            % define standard formats
            stdImgFormats = imformats;  % get readable image formats
            obj.imreadExtensions = [stdImgFormats.ext];
            
            % get video formats
            video_formats = VideoReader.getFileFormats(); % get readable image formats
            obj.videoExtensions = {video_formats.Extension};

            % combine all standard formats into a single cell array
            stdImgFormats = [stdImgFormats.ext 'mrc' 'rec' 'am' 'nrrd' 'h5' 'xml' 'st' 'preali' 'mibImg' 'zarr3' obj.videoExtensions];
            % standard image extensions
            obj.extensionSets("Standard.Default") = {sort(stdImgFormats)};
            % zarr2 removed: Zarr3Matlab library only supports zarr v3
            obj.extensionSets("Virtual.Default") = {sort({'h5','hdf5','xml', 'zarr', 'zarr3'})};
            obj.extensionSets("BigData.Default") = {sort({'zarr3'})};
            
            % list of compatible Bio-Formats
            bioFormats = {'nii','mov','pic','ics','ids','lei','stk','nd','nd2','sld','pict'...
                ,'lsm','mdb','psd','img','hdr','svs','dv','r3d','dcm','dicom','fits','liff'...
                ,'jp2','lif','l2d','mnc','mrc','oib','oif','pgm','zvi','gel','ims','dm3','naf'...
                ,'seq','xdce','ipl','mrw','mng','nrrd','ome','amiramesh','labels','fli'...
                ,'arf','al3d','sdt','czi','c01','flex','ipw','raw','ipm','xv','lim','nef','apl','mtb'...
                ,'tnb','obsep','cxd','vws','xys','xml','dm4','ndpi'};
            
            
            obj.extensionSets("Standard.BioFormats") = {sort(bioFormats)};
            obj.extensionSets("Virtual.BioFormats") = {sort([{'am'}, bioFormats])};
            obj.extensionSets("BigData.BioFormats") = {''};

            % Model file extensions (used by MibModel.loadModel)
            % Include imread-compatible formats so *.*  browsing works for
            % all image types that can carry label data (png, bmp, jpg, etc.)
            modelExts = unique([{'am','h5','hdf5','mat','mibcat','model','mrc','nrrd','rec','st','tif','tiff','xml'}, obj.imreadExtensions]);
            obj.extensionSets("Model.Default") = {sort(modelExts)};
        end

        function key = generateKey(~, mode, reader)
            % GENERATEKEY - generate dictionary key from mode and reader.
            %
            % Syntax:
            %   function key = generateKey(~, mode, reader)
            %
            % Input Arguments:
            %   - **mode** — [char] defining type of MIB dataset,
            %   - 'Standard' standard dataset that is loaded into memory
            %   - 'Virtual' virtual dataset that is loaded on demand
            %   - **reader** — [char] defining the type of file reader
            %   - 'Default' matlab imread, custom and other readers
            %   - 'BioFormats' use the BioFormats library to read images
            %
            % Output Arguments:
            %   - **key** — [char] with the key, e.g. "Standard.Default"
            %

            mode = string(mode); 
            reader = string(reader);
            % add dot between mode and reader to match the dict key
            key = mode + '.' + reader;   % keep your tokens consistent upstream
        end

        function id = defaultLoaderId(obj, mode, reader, ext)
            % DEFAULTLOADERID - obtain file reader id to use for image loading.
            %
            % Syntax:
            %   function id = defaultLoaderId(obj, mode, reader, ext)
            %
            % Input Arguments:
            %   - **mode** — [char] defining type of MIB dataset,
            %   - 'Standard' standard dataset that is loaded into memory
            %   - 'Virtual' virtual dataset that is loaded on demand
            %   - **reader** — [char] defining the type of file reader
            %   - 'Default' matlab imread, custom and other readers
            %   - 'BioFormats' use the BioFormats library to read images
            %   - **ext** — [char] - filename extension without a leading dot
            %
            % Output Arguments:
            %   - **id** — [char] identifier of the file reader to use
            %     'BioFormatsVirtual' use bio-formats reader to load data in the virtual mode
            %     'BioFormatsStd' use bio-formats to load data in the standard mode
            %     'AmiraMesh' AmiraMesh reader of MIB
            %     'imread' MATLAB standard image reader
            %     'mibImg' custom image format for MIB
            %     'hdf5-header' HDF5 with header for MIB or BigDataViewer in Fiji
            %     'hdf5-no-header' HDF5 without header for Ilastik
            %     'OmeZarr' MIB implementation of OME-Zarr v3 reader (Zarr3VirtualSetupLoader)
            %     'imod' IMOD reader
            %     'nrrd' NRRD reader
            %     'VideoReader' MATLAB reader for video files
            %
            
            % Model loading: route to format-appropriate loader
            if mode == "Model"
                switch lower(ext)
                    case {'model', 'mat', 'mibcat'}
                        id = 'MatModel';
                    case 'am'
                        id = 'AmiraMesh';
                    case 'xml'
                        id = 'hdf5-header';
                    case {'h5', 'hdf5'}
                        id = 'hdf5-no-header';
                    case {'mrc', 'rec', 'st'}
                        id = 'imod';
                    case 'nrrd'
                        id = 'nrrd';
                    otherwise
                        id = 'imread';
                end
                return;
            end

            % check
            if reader == "BioFormats"
                if mode == "Virtual" || mode == "BigData"
                    id = "BioFormatsVirtual";
                else
                    id = "BioFormatsStd";
                end
                return;
            end

            % Virtual/BigData HDF5: use setup loaders that return file paths
            % instead of loading pixels, so MibVirtualImage can be initialised
            if mode == "Virtual" || mode == "BigData"
                switch lower(ext)
                    case 'xml'
                        id = 'hdf5-header-virtual';
                        return;
                    case {'hdf5', 'h5'}
                        id = 'hdf5-no-header-virtual';
                        return;
                end
            end

            switch lower(ext)
                case 'am'
                    id = 'AmiraMesh';
                case obj.imreadExtensions
                    id = 'imread';
                case 'mibimg'
                    id = 'mibImg';
                case 'xml'
                    id = 'hdf5-header';
                case {'hdf5', 'h5'}
                    id = 'hdf5-no-header';
                case {'zarr', 'zarr3'}
                    id = 'OmeZarr';
                case {'rec', 'mrc', 'st', 'pre', 'ali'}
                    id = 'imod';
                case 'nrrd'
                    id = 'nrrd';
                case obj.videoExtensions
                    id = 'VideoReader';
            end
        end
    end
end
