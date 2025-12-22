classdef ExtensionRegistryLoad < handle
    % class to store filename extensions that MIB is capable to load
    % grouped under a dictionary obj.extensionSets 

    properties (Access = private)
        extensionSets dictionary
        % dictionary containing extensions for each mode:
        % @li Std.Default -> standard dataset loaded to memory, default reader
        % @li Virtual.Default  -> virtual dataset, default reader
        % @li BigData.Default -> bigdata dataset, default reader
        % @li Std.BioFormats  -> standard dataset loaded to memory, bio-formats reader
        % @li Virtual.BioFormats -> virtual dataset, bio-formats reader
        % @li BigData.BioFormats -> bigdata dataset, bio-formats reader
        imreadExtensions
        % cell array with standard matlab image format filename extensions that are loaded with imread
        videoExtensions
        % cell array with standard matlab video extensions
    end

    methods
        function obj = ExtensionRegistryLoad()
            % Constructor - init the class and initiate it with default
            % file extension formats

            obj.extensionSets = dictionary();
            obj.initDefaults();
        end

        function loaderInfo = resolveLoader(obj, filename, mode, reader)
            % function loaderInfo = resolveLoader(obj, filename, mode, reader)
            % find a loader that should be used for this specific dataset mode, selected reader and filename extension
            %
            % Parameters:
            % filename: [char] first filename in the sequence of files to load
            % mode: [char] defining type of MIB dataset,
            % @li 'Std' -> standard dataset that is loaded into memory
            % @li 'Virtual' -> virtual dataset that is loaded on demand
            % reader: [char] defining the type of file reader
            % @li 'Default' -> matlab imread, custom and other readers 
            % @li 'BioFormats' -> use the BioFormats library to read images
            %
            % Return values:
            % loaderInfo: a structure that encodes the potential loader to use or empty
            % .mode - [char] mode from input
            % .reader -[char] reader from input
            % extension - [char] filename extension without a leading dot
            % loaderId' - loader to use
            
            % get the filename extension
            [~, ~, ext] = fileparts(filename); % get the filename extension with '.'
            ext = strrep(ext, '.', ''); % remove the dot
            
            % generate the dictionary key
            key = obj.generateKey(mode, reader);

            % check whether the extension is compatible
            if ~ismember(ext, obj.extensionSets{key})
                loaderInfo = [];
                error('io:ExtensionRegistryLoad:NotAllowed', ...
                    'io.ExtensionRegistryLoad.resolveRoute: Extension "%s" not allowed for mode=%s reader=%s', ext, mode, reader);
            end

            % Route is just "what family of loader to use"
            loaderInfo = struct( ...
                'mode', mode, ...
                'reader', reader, ...
                'extension', ext, ...
                'loaderId', obj.defaultLoaderId(mode, reader, ext));
        end

        function ext = getAllowedExtensions(obj, mode, reader, withoutDots)
            % function ext = getAllowedExtensions(obj, mode, reader, withoutDots)
            % get registered extensions for the specified mode and reader
            %
            % Parameters:
            % mode: [char] defining type of MIB dataset,
            % @li 'Std' -> standard dataset that is loaded into memory
            % @li 'Virtual' -> virtual dataset that is loaded on demand
            % reader: [char] defining the type of file reader
            % @li 'Default' -> matlab imread, custom and other readers 
            % @li 'BioFormats' -> use the BioFormats library to read images
            % withDot: [logical] -> return the list of extensions with or without leading dot
            % @li true -> return the list as cell array without dots
            % @li false -> return the list as cell array with leading dots
            %
            % Return values:
            % ext: cell array with filename extensions

            % Examples:
            % // get the list of extensions that can be loaded for
            % the Standard dataset using BioFormats reader and return with
            % leading dots
            % <code> 
            % ext = extReg.getAllowedExtensions('Std', 'BioFormats', false); 
            % <endcode> 

            if nargin < 4; withoutDots = true; end
            ext = obj.extensionSets{obj.generateKey(mode, reader)};
            if withoutDots; ext = strcat('.', ext); end
        end

        function setAllowedExtensions(obj, mode, reader, extensionList)
            % function setAllowedExtensions(obj, mode, reader, extensionList)
            % update the filename extensions for the corresponding mode and
            % reader
            % 
            % Parameters:
            % mode: [char] defining type of MIB dataset,
            % @li 'Std' -> standard dataset that is loaded into memory
            % @li 'Virtual' -> virtual dataset that is loaded on demand
            % reader: [char] defining the type of file reader
            % @li 'Default' -> matlab imread, custom and other readers 
            % @li 'BioFormats' -> use the BioFormats library to read images
            % extensionList: cell array with a new list of extensions

            obj.extensionSets{obj.generateKey(mode, reader)} = sort(extensionList);
        end

    end

    methods (Access=private)
        function initDefaults(obj)
            % function initDefaults(obj)
            % init obj.extensionSets

            % define standard formats
            stdImgFormats = imformats;  % get readable image formats
            obj.imreadExtensions = [stdImgFormats.ext];
            
            % get video formats
            video_formats = VideoReader.getFileFormats(); % get readable image formats
            obj.videoExtensions = {video_formats.Extension};

            % combine all standard formats into a single cell array
            stdImgFormats = [stdImgFormats.ext 'mrc' 'rec' 'am' 'nrrd' 'h5' 'xml' 'st' 'preali' 'mibImg' obj.videoExtensions];
            % standard image extensions
            obj.extensionSets("Std.Default") = {sort(stdImgFormats)};
            obj.extensionSets("Virtual.Default") = {sort({'h5','hdf5','xml', 'zarr', 'zarr2', 'zarr3'})};
            obj.extensionSets("BigData.Default") = {''};
            
            % list of compatible Bio-Formats
            bioFormats = {'nii','mov','pic','ics','ids','lei','stk','nd','nd2','sld','pict'...
                ,'lsm','mdb','psd','img','hdr','svs','dv','r3d','dcm','dicom','fits','liff'...
                ,'jp2','lif','l2d','mnc','mrc','oib','oif','pgm','zvi','gel','ims','dm3','naf'...
                ,'seq','xdce','ipl','mrw','mng','nrrd','ome','amiramesh','labels','fli'...
                ,'arf','al3d','sdt','czi','c01','flex','ipw','raw','ipm','xv','lim','nef','apl','mtb'...
                ,'tnb','obsep','cxd','vws','xys','xml','dm4','ndpi'};
            
            
            obj.extensionSets("Std.BioFormats") = {sort(bioFormats)};
            obj.extensionSets("Virtual.BioFormats") = {sort([{'am'}, bioFormats])};
            obj.extensionSets("BigData.BioFormats") = {''};
        end

        function key = generateKey(~, mode, reader)
            % function key = generateKey(~, mode, reader)
            % generate dictionary key from mode and reader 
            %
            % Parameters:
            % mode: [char] defining type of MIB dataset,
            % @li 'Std' -> standard dataset that is loaded into memory
            % @li 'Virtual' -> virtual dataset that is loaded on demand
            % reader: [char] defining the type of file reader
            % @li 'Default' -> matlab imread, custom and other readers 
            % @li 'BioFormats' -> use the BioFormats library to read images
            %
            % Return values:
            % key: [char] with the key, e.g. "Std.Default"

            mode = string(mode); 
            reader = string(reader);
            % add dot between mode and reader to match the dict key
            key = mode + '.' + reader;   % keep your tokens consistent upstream
        end

        function id = defaultLoaderId(obj, mode, reader, ext)
            % function id = defaultLoaderId(obj, mode, reader, ext)
            % obtain file reader id to use for image loading
            % 
            % Parameters:
            % mode: [char] defining type of MIB dataset,
            % @li 'Std' -> standard dataset that is loaded into memory
            % @li 'Virtual' -> virtual dataset that is loaded on demand
            % reader: [char] defining the type of file reader
            % @li 'Default' -> matlab imread, custom and other readers 
            % @li 'BioFormats' -> use the BioFormats library to read images
            % ext: [char] - filename extension without a leading dot
            %
            % Return values:
            % id: [char] identifier of the file reader to use
            % 'BioFormatsVirtual' -> use bio-formats reader to load data in the virtual mode
            % 'BioFormatsStd' -> use bio-formats to load data in the standard mode
            % 'AmiraMesh' -> AmiraMesh reader of MIB
            % 'imread' -> MATLAB standard image reader
            % 'mibImg' -> custom image format for MIB
            % 'hdf5-header' -> HDF5 with header for MIB or BigDataViewer in Fiji
            % 'hdf5-no-header' -> HDF5 without header for Ilastik
            % 'OmeZarr' -> MIB implementation of Ome-Zarr v2/3 reader
            % 'imod' -> IMOD reader
            % 'nrrd' -> NRRD reader
            % 'VideoReader' -> MATLAB reader for video files
            
            % check
            if reader == "BioFormats"
                if mode == "Virtual" || mode == "BigData"
                    id = "BioFormatsVirtual";
                else
                    id = "BioFormatsStd";
                end
                return;
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
                case {'zarr', 'zarr2', 'zarr3'}
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
