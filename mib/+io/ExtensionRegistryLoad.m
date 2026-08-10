classdef ExtensionRegistryLoad < handle
% EXTENSIONREGISTRYLOAD - Registry of supported image file extensions for loading by mode and reader.
%
% Manages a dictionary (``extensionSets``) of allowed filename extensions for each
% combination of dataset mode (``Standard``, ``Virtual``, ``BigData``, ``Model``) and
% file reader (``Default`` or ``BioFormats``). Provides methods to resolve which loader
% should be used for a given filename, mode, and reader combination.

    properties (Access = private)
        extensionSets dictionary
        % Dictionary mapping mode.reader combinations to extension lists:
        %
        %   - ``Standard.Default`` - standard dataset loaded to memory, default reader
        %   - ``Virtual.Default`` - virtual dataset, default reader
        %   - ``BigData.Default`` - bigdata dataset, default reader
        %   - ``Standard.BioFormats`` - standard dataset loaded to memory, bio-formats reader
        %   - ``Virtual.BioFormats`` - virtual dataset, bio-formats reader
        %   - ``BigData.BioFormats`` - bigdata dataset, bio-formats reader
        %   - ``Model.Default`` - model files (labels/segmentation)
        %
        imreadExtensions
        % Cell array with standard MATLAB image format filename extensions (e.g. ``'tif'``, ``'png'``)
        % loaded via ``imread``.
        videoExtensions
        % Cell array with standard MATLAB video extensions (e.g. ``'avi'``, ``'mp4'``).
    end

    methods
        function obj = ExtensionRegistryLoad()
            % EXTENSIONREGISTRYLOAD - Constructor for ExtensionRegistryLoad.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      registry = io.ExtensionRegistryLoad()
            %
            % Initializes the registry with default file extension sets for all
            % supported modes and readers.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **obj** - instance of ExtensionRegistryLoad

            obj.extensionSets = dictionary();
            obj.initDefaults();
        end

        function loaderInfo = resolveLoader(obj, filename, mode, reader)
            % RESOLVELOADER - Find the appropriate loader for a file given mode, reader, and extension.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      loaderInfo = obj.resolveLoader(filename, mode, reader)
            %
            % Extracts the filename extension and returns a structure identifying
            % which loader should be used. If the extension is not compatible with
            % the requested mode/reader combination, returns an error message.
            %
            % Input Arguments:
            %   - **filename** - [char] first filename in the sequence of files to load
            %   - **mode** - [char] dataset type:
            %
            %     - ``'Standard'`` - dataset loaded into memory
            %     - ``'Virtual'`` - dataset loaded on demand
            %     - ``'BigData'`` - large dataset using OME-Zarr v3
            %     - ``'Model'`` - segmentation labels/masks
            %
            %   - **reader** - [char] file reader type:
            %
            %     - ``'Default'`` - MATLAB ``imread``, custom, and other native readers
            %     - ``'BioFormats'`` - BioFormats library reader
            %
            % Output Arguments:
            %   - **loaderInfo** - struct encoding the loader configuration:
            %
            %     - ``.mode`` - [char] mode from input
            %     - ``.reader`` - [char] reader from input
            %     - ``.extension`` - [char] filename extension without leading dot
            %     - ``.loaderId`` - [char] identifier of the loader to use (e.g. ``'BioFormatsStd'``, ``'imread'``)
            %
            %     When the extension is incompatible, returns a [char] error message instead.
            %
            
            % get the filename extension
            [~, ~, ext] = fileparts(filename); % get the filename extension with '.'
            ext = lower(strrep(ext, '.', '')); % remove the dot

            % The plain ".zarr" extension does not say which zarr version the
            % store uses, and the two are read by different loaders, so probe
            % the store itself. Without this a v2 store in a "*.zarr" folder
            % (the OME-Zarr / OpenOrganelle default naming) is handed to the v3
            % loader, which cannot read it.
            if strcmp(ext, 'zarr')
                ext = io.ExtensionRegistryLoad.detectZarrFormatExtension(filename);
            end

            % generate the dictionary key
            key = obj.generateKey(mode, reader);

            % check whether the extension is compatible
            if ~ismember(ext, lower(obj.extensionSets{key}))
                if ismember(ext, {'zarr', 'zarr2', 'zarr3'})
                    loaderInfo = sprintf('io.ExtensionRegistryLoad.resolveRoute:\nExtension "%s" not allowed for\nmode="%s" reader="%s"\n\nTo load Zarr v2/v3 format switch to the Virtual (or BigData) mode!', ext, mode, reader);
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
            % GETALLOWEDEXTENSIONS - Get registered extensions for specified mode and reader.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      ext = obj.getAllowedExtensions(mode, reader, withDot)
            %
            % Input Arguments:
            %   - **mode** - [char] dataset type:
            %
            %     - ``'Standard'`` - dataset loaded into memory
            %     - ``'Virtual'`` - dataset loaded on demand
            %     - ``'BigData'`` - large dataset using OME-Zarr v3
            %     - ``'Model'`` - segmentation labels/masks
            %
            %   - **reader** - [char] file reader type:
            %
            %     - ``'Default'`` - MATLAB ``imread``, custom, and other native readers
            %     - ``'BioFormats'`` - BioFormats library reader
            %
            %   - **withDot** - *(optional)* logical, default: ``true``
            %
            %     - ``true`` - return extensions without leading dots (e.g. ``{'tif', 'png'}``)
            %     - ``false`` - return extensions with leading dots (e.g. ``{'.tif', '.png'}``)
            %
            % Output Arguments:
            %   - **ext** - cell array of [char] filename extensions
            %
            % **Example 1** - get Standard dataset extensions for BioFormats reader with leading dots:
            %
            %   .. code-block:: matlab
            %
            %      ext = extReg.getAllowedExtensions('Standard', 'BioFormats', false);
            %
            % **Example 2** - access from MibModel with Default reader:
            %
            %   .. code-block:: matlab
            %
            %      ext = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false);
            %
            % **Example 3** - access from MibModel with BioFormats reader:
            %
            %   .. code-block:: matlab
            %
            %      ext = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'BioFormats', false);
            %
            
            if nargin < 4; withDot = true; end
            key = obj.generateKey(mode, reader);
            if ~isKey(obj.extensionSets, key)
                ext = {};   % unknown mode/reader combination → no extensions
                return;
            end
            ext = obj.extensionSets{key};
            % Always return a cellstr ROW with empty placeholders removed. A
            % single-element set stored as {''} would otherwise be unwrapped by the
            % dictionary {}-indexing to a bare char '' and then collapse downstream
            % (e.g. ['all known', char] -> a char), crashing dropdown .Items.
            ext = reshape(cellstr(ext), 1, []);
            ext = ext(~cellfun(@isempty, ext));
            if withDot && ~isempty(ext); ext = strcat('.', ext); end
        end

        function setAllowedExtensions(obj, mode, reader, extensionList)
            % SETALLOWEDEXTENSIONS - Update filename extensions for specified mode and reader.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      obj.setAllowedExtensions(mode, reader, extensionList)
            %
            % Updates the list of allowed extensions for a given mode/reader combination.
            % Extensions are stored internally without leading dots for consistency.
            %
            % Input Arguments:
            %   - **mode** - [char] dataset type:
            %
            %     - ``'Standard'`` - dataset loaded into memory
            %     - ``'Virtual'`` - dataset loaded on demand
            %     - ``'BigData'`` - large dataset using OME-Zarr v3
            %     - ``'Model'`` - segmentation labels/masks
            %
            %   - **reader** - [char] file reader type:
            %
            %     - ``'Default'`` - MATLAB ``imread``, custom, and other native readers
            %     - ``'BioFormats'`` - BioFormats library reader
            %
            %   - **extensionList** - cell array of [char], new extension list;
            %     may include or omit leading dots (e.g. both ``'.tif'`` and ``'tif'`` are accepted)
            %
            % Output Arguments:
            %   (none)
            %

            % Ensure extensions are stored without leading dots to keep
            % internal storage consistent with getAllowedExtensions behavior
            extensionList = regexprep(extensionList, '^\.', '');
            obj.extensionSets{obj.generateKey(mode, reader)} = sort(extensionList);
        end

    end

    methods (Access=private)
        function initDefaults(obj)
            % INITDEFAULTS - Initialize extension registry with default sets for all modes and readers.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      obj.initDefaults()
            %
            % Populates ``extensionSets`` dictionary with standard extensions for
            % Standard, Virtual, BigData, and Model modes using Default and BioFormats readers.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   (none)
            %

            % define standard formats
            stdImgFormats = imformats;  % get readable image formats
            obj.imreadExtensions = [stdImgFormats.ext];
            
            % get video formats
            video_formats = VideoReader.getFileFormats(); % get readable image formats
            obj.videoExtensions = {video_formats.Extension};

            % combine all standard formats into a single cell array
            stdImgFormats = [stdImgFormats.ext 'mrc' 'rec' 'am' 'nrrd' 'h5' 'xml' 'st' 'preali' 'mibImg' 'zarr2' 'zarr3' obj.videoExtensions];
            % standard image extensions
            obj.extensionSets("Standard.Default") = {sort(stdImgFormats)};
            % zarr v3: native zarr-matlab library; zarr v2: python-backed
            % (io.zarr.PyBackend) - see io.loaders.Zarr2VirtualSetupLoader.
            obj.extensionSets("Virtual.Default") = {sort({'h5','hdf5','xml', 'zarr', 'zarr2', 'zarr3'})};
            % BigData zarr2: image pyramid browsing + a read-only existing
            % labels overlay only (core.MibBigDataLabelsZarr2) - no editable
            % disk-backed model store, unlike zarr3.
            obj.extensionSets("BigData.Default") = {sort({'zarr2', 'zarr3'})};
            
            % list of compatible Bio-Formats
            bioFormats = {'nii','mov','pic','ics','ids','lei','stk','nd','nd2','sld','pict'...
                ,'lsm','mdb','psd','img','hdr','svs','dv','r3d','dcm','dicom','fits','liff'...
                ,'jp2','lif','l2d','mnc','mrc','oib','oif','pgm','zvi','gel','ims','dm3','naf'...
                ,'seq','xdce','ipl','mrw','mng','nrrd','ome','amiramesh','labels','fli'...
                ,'arf','al3d','sdt','czi','c01','flex','ipw','raw','ipm','xv','lim','nef','apl','mtb'...
                ,'tnb','obsep','cxd','vws','xys','xml','dm4','ndpi', 'tiff'};
            
            
            obj.extensionSets("Standard.BioFormats") = {sort(bioFormats)};
            obj.extensionSets("Virtual.BioFormats") = {sort([{'am'}, bioFormats])};
            % BigData direct-read via BioFormats (WSI pyramids + any BioFormats file,
            % read on-demand per pyramid level - see development/bigdata/bigdata_implementation_plan.md).
            obj.extensionSets("BigData.BioFormats") = {sort(bioFormats)};

            % OpenSlide reader - classic whole-slide formats. Until the native
            % MATLAB openslideread engine is wired (Phase D), an OpenSlide selection
            % opens through the BioFormats loaders (defaultLoaderId routes it like
            % BioFormats). The extension list is what populates the file-filter
            % dropdown when OpenSlide is selected.
            % OpenSlide-supported virtual-slide formats (per the OpenSlide vendor list):
            % Aperio svs, ARGOS avs, DICOM dcm, Hamamatsu vms/vmu/ndpi, Huron/Trestle/
            % Ventana/Generic tif, Leica scn, MIRAX mrxs, Philips tiff, Sakura svslide,
            % Ventana bif, Zeiss czi.
            openSlideFormats = {'svs','avs','dcm','vms','vmu','ndpi','tif','tiff','scn','mrxs','svslide','bif','czi'};
            obj.extensionSets("Standard.OpenSlide") = {sort(openSlideFormats)};
            obj.extensionSets("Virtual.OpenSlide")  = {sort(openSlideFormats)};
            obj.extensionSets("BigData.OpenSlide")  = {sort(openSlideFormats)};

            % Model file extensions (used by MibModel.loadModel)
            % Include imread-compatible formats so *.*  browsing works for
            % all image types that can carry label data (png, bmp, jpg, etc.)
            modelExts = unique([{'am','h5','hdf5','mat','mibcat','model','mrc','nrrd','rec','st','tif','tiff','xml','zarr2','zarr3'}, obj.imreadExtensions]);
            obj.extensionSets("Model.Default") = {sort(modelExts)};
        end

        function key = generateKey(~, mode, reader)
            % GENERATEKEY - Generate dictionary key from mode and reader strings.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      key = obj.generateKey(mode, reader)
            %
            % Input Arguments:
            %   - **mode** - [char|string] dataset type:
            %
            %     - ``'Standard'`` - dataset loaded into memory
            %     - ``'Virtual'`` - dataset loaded on demand
            %     - ``'BigData'`` - large dataset using OME-Zarr v3
            %     - ``'Model'`` - segmentation labels/masks
            %
            %   - **reader** - [char|string] file reader type:
            %
            %     - ``'Default'`` - MATLAB ``imread``, custom, and other native readers
            %     - ``'BioFormats'`` - BioFormats library reader
            %
            % Output Arguments:
            %   - **key** - [string] dictionary key in the format ``'<mode>.<reader>'``,
            %     e.g. ``"Standard.Default"``, ``"Virtual.BioFormats"``
            %

            mode = string(mode); 
            reader = string(reader);
            % add dot between mode and reader to match the dict key
            key = mode + '.' + reader;   % keep your tokens consistent upstream
        end

        function id = defaultLoaderId(obj, mode, reader, ext)
            % DEFAULTLOADERID - Determine the loader ID for a given mode, reader, and file extension.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      id = obj.defaultLoaderId(mode, reader, ext)
            %
            % Routes to the appropriate loader class based on the combination of dataset
            % mode, file reader type, and filename extension.
            %
            % Input Arguments:
            %   - **mode** - [char|string] dataset type:
            %
            %     - ``'Standard'`` - dataset loaded into memory
            %     - ``'Virtual'`` - dataset loaded on demand
            %     - ``'BigData'`` - large dataset using OME-Zarr v3
            %     - ``'Model'`` - segmentation labels/masks
            %
            %   - **reader** - [char|string] file reader type:
            %
            %     - ``'Default'`` - MATLAB ``imread``, custom, and other native readers
            %     - ``'BioFormats'`` - BioFormats library reader
            %
            %   - **ext** - [char|string] filename extension without leading dot
            %     (e.g. ``'tif'``, ``'png'``, ``'h5'``)
            %
            % Output Arguments:
            %   - **id** - [char|string] identifier of the loader class to instantiate:
            %
            %     - ``'BioFormatsVirtual'`` - BioFormats reader for virtual mode
            %     - ``'BioFormatsStd'`` - BioFormats reader for standard mode
            %     - ``'AmiraMesh'`` - AmiraMesh format reader
            %     - ``'imread'`` - MATLAB standard image reader
            %     - ``'mibImg'`` - custom MIB image format (.mibimg)
            %     - ``'hdf5-header'`` - HDF5 with header metadata (MIB or BigDataViewer format)
            %     - ``'hdf5-no-header'`` - HDF5 without header (Ilastik format)
            %     - ``'hdf5-header-virtual'`` - HDF5 header-based reader for virtual mode
            %     - ``'hdf5-no-header-virtual'`` - HDF5 headerless reader for virtual mode
            %     - ``'OmeZarr'`` - OME-Zarr v3 reader (implemented via Zarr3VirtualSetupLoader)
            %     - ``'OmeZarrV2'`` - OME-Zarr v2 reader, python-backed (Zarr2VirtualSetupLoader)
            %     - ``'imod'`` - IMOD model/mesh format reader
            %     - ``'nrrd'`` - NRRD format reader
            %     - ``'VideoReader'`` - MATLAB video file reader
            %     - ``'MatModel'`` - MATLAB ``.model``, ``.mat``, or ``.mibcat`` segmentation format
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
                    case 'zarr2'
                        id = 'OmeZarrV2';
                    case 'zarr3'
                        id = 'OmeZarr';
                    otherwise
                        id = 'imread';
                end
                return;
            end

            % BioFormats and OpenSlide both route to the BioFormats loader family for
            % now (the native OpenSlide engine is wired in a later phase; the engine
            % is resolved inside the loader, not here).
            if reader == "BioFormats" || reader == "OpenSlide"
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
                case 'zarr2'
                    id = 'OmeZarrV2';
                case {'rec', 'mrc', 'st', 'pre', 'ali'}
                    id = 'imod';
                case 'nrrd'
                    id = 'nrrd';
                case obj.videoExtensions
                    id = 'VideoReader';
            end
        end
    end

    methods (Static)
        function ext = detectZarrFormatExtension(zarrPath)
            % DETECTZARRFORMATEXTENSION - Resolve a plain ".zarr" folder to 'zarr2' or 'zarr3'.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      ext = io.ExtensionRegistryLoad.detectZarrFormatExtension(zarrPath)
            %
            % The two zarr versions are read by different loaders (v3 by the
            % native zarr-matlab library, v2 by the python backend) but share
            % the conventional ".zarr" folder suffix, so the version has to come
            % from the store: v3 nodes carry ``zarr.json``, v2 nodes carry
            % ``.zgroup`` / ``.zattrs`` / ``.zarray``.
            %
            % Input Arguments:
            %   - **zarrPath** - [char] path to the zarr root folder
            %
            % Output Arguments:
            %   - **ext** - [char] ``'zarr2'`` or ``'zarr3'``; ``'zarr3'`` when
            %     the store cannot be probed (URLs, missing folder), preserving
            %     the previous behaviour

            ext = 'zarr3';
            try
                if isfile(fullfile(zarrPath, 'zarr.json'))
                    ext = 'zarr3';
                elseif isfile(fullfile(zarrPath, '.zgroup')) || ...
                       isfile(fullfile(zarrPath, '.zattrs')) || ...
                       isfile(fullfile(zarrPath, '.zarray'))
                    ext = 'zarr2';
                end
            catch
                % not probeable (e.g. a URL) -> keep the v3 default
            end
        end
    end
end
