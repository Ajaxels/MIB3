classdef SaverFactory
% SAVERFACTORY - Factory class that instantiates the appropriate saver for a given.
%
% output format string.
%
% This class mirrors io.LoaderFactory for the writing side of the
% pipeline.  The format strings match exactly those used in
% core.MibDataset.save() and models.MibModel.save() dropdown menus.
%
% ARCHITECTURE
% SaverFactory maps format strings → concrete io.savers.XxxSaver
% instances.  Two separate registries exist:
% getFormats('image')  — formats for pixel-data saving
% getFormats('mask')   — formats for binary mask saving
% getFormats('labels') — formats for multi-material label saving
%
% The registries are intentionally kept separate because the same
% format (e.g. TIF) can appear in multiple categories but with
% different defaults or validation rules.
%
% USAGE
% % Typical usage — via high-level methods (recommended):
% obj.mibModel.saveImage('image',  filename, BatchOptIn);
% obj.mibModel.saveImage('mask',   filename, BatchOptIn);
% obj.mibModel.saveImage('labels', filename, BatchOptIn);
%
% % Direct factory use — for advanced/scripted workflows:
% saver = io.SaverFactory.create('TIF format uncompressed (``*.tif``)');
% fnOut = saver.save(data, metadata, '/tmp/out.tif', options);
%
% % Direct factory use from GUI context — pass ParentFigure/mibPath
% % so that uiprogressdlg attaches to the MIB window:
% ctorOpts.ParentFigure = obj.mibModel.mibGUI;
% ctorOpts.mibPath      = obj.mibModel.mibPath;
% saver = io.SaverFactory.create('Amira Mesh binary (``*.am``)', ctorOpts);
%
% % List all formats available for a given layer type:
% imageFormats  = io.SaverFactory.getFormats('image');
% maskFormats   = io.SaverFactory.getFormats('mask');
% labelFormats  = io.SaverFactory.getFormats('labels');
%
% SEE ALSO
% io.loaders.LoaderFactory, io.savers.BaseSaver,
% core.MibDataset.save, models.MibModel.save

    methods (Static)

        function saver = create(formatStr, options)
            % CREATE - Instantiate the saver that handles the requested format.
            %
            % Syntax:
            %   function saver = create(formatStr, options)
            %
            % Input Arguments:
            %   formatStr — (char) format descriptor exactly as it appears in
            %   the Format dropdown, e.g.
            %   'TIF format uncompressed (``*.tif``)'
            %   'Amira mesh binary (``*.am``)'
            %   'Matlab format (``*.model``)'
            %   See getFormats() for the complete list.
            %   options   — (struct, optional) passed to the saver constructor
            %   via BaseSaver.initBaseProps().  The two most
            %   important fields to include when calling from a
            %   GUI context are:
            %   .ParentFigure — handle to the main MIB window; enables
            %   uiprogressdlg dialogs attached to the GUI
            %   (set from obj.mibGUI in MibModel).
            %   Leave empty or omit for standalone/scripted use.
            %   .mibPath      — (char) MIB installation directory; used for
            %   resource and icon lookup by dialogs.
            %   All other options are typically passed at save() time.
            %
            % Output Arguments:
            %   saver — concrete BaseSaver subclass instance
            %
            %   - **Throws** —
            %   - **io** — SaverFactory:UnknownFormat — if formatStr is not registered
            %
            % Usage:
            %   Example 1::
            %
            %       %% 1. Standalone scripted use — no GUI parent needed
            %       saver = io.SaverFactory.create('TIF format uncompressed (``*.tif``)');
            %       opts.Format         = 'TIF format uncompressed (``*.tif``)';
            %       opts.Saving3DPolicy = '3D stack';
            %       opts.showWaitbar    = false;
            %       opts.silent         = true;
            %       opts.Compression    = 'none';
            %       opts.overwrite      = true;
            %       meta.filename  = 'source.tif';
            %       meta.colorType = 'grayscale';
            %       meta.lutColors = [1 1 1];
            %       meta.dataClass = 'uint8';
            %       meta.maxInt    = 255;
            %       meta.sliceName = {};
            %       meta.pixSize   = struct('x',0.1,'y',0.1,'z',0.5,'units','um','t',1,'tunits','s');
            %       data = uint8(rand(64,64,10,1,1)*255);  % [H W D C T]
            %       fnOut = saver.save(data, meta, '/tmp/out.tif', opts);
            %
            %
            %   Example 2::
            %
            %       %% 2. GUI context — pass ParentFigure and mibPath so that
            %       %      progress dialogs attach to the MIB window and icons
            %       %      load correctly.  Typically called from a controller:
            %       ctorOpts.ParentFigure = obj.mibModel.mibGUI;
            %       ctorOpts.mibPath      = obj.mibModel.mibPath;
            %       saver = io.SaverFactory.create('Amira Mesh binary (``*.am``)', ctorOpts);
            %
            %       opts.Format         = 'Amira Mesh binary (``*.am``)';
            %       opts.Saving3DPolicy = '3D stack';
            %       opts.showWaitbar    = true;
            %       opts.silent         = true;
            %       opts.overwrite      = true;
            %       opts.ParentFigure   = obj.mibModel.mibGUI;
            %       opts.mibPath        = obj.mibModel.mibPath;
            %       opts.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
            %       meta.filename  = 'source.tif';
            %       meta.colorType = 'grayscale';
            %       meta.lutColors = [1 0 0];
            %       meta.dataClass = 'uint8';
            %       meta.maxInt    = 255;
            %       meta.sliceName = {};
            %       data = uint8(rand(128,128,20,1,1)*255);
            %       fnOut = saver.save(data, meta, '/tmp/stack.am', opts);
            %
            %
            %   Example 3::
            %
            %       %% 3. Save a segmentation model in native MIB format
            %       saver = io.SaverFactory.create('Matlab format (``*.model``)');
            %       opts.Format      = 'Matlab format (``*.model``)';
            %       opts.showWaitbar = false;
            %       opts.silent      = true;
            %       opts.overwrite   = true;
            %       meta.filename       = 'image.tif';
            %       meta.materialNames  = {'Nucleus'; 'Mitochondria'};
            %       meta.materialColors = [0 0 1; 0 1 0];
            %       meta.labelsVariable = 'mibModel';
            %       meta.dataClass      = 'uint8';
            %       meta.pixSize        = struct('x',0.1,'y',0.1,'z',0.5,'units','um','t',1,'tunits','s');
            %       labels = uint8(rand(64,64,10,1,1)*2);  % values 0,1,2
            %       fnOut = saver.save(labels, meta, '/tmp/Labels_image.model', opts);
            %

            if nargin < 2; options = struct(); end

            % Build the registry once and look up the saver class name
            registry = io.SaverFactory.buildRegistry();

            if ~isKey(registry, string(formatStr))
                error('io:SaverFactory:UnknownFormat', ...
                    ['Unknown format: "%s".\n' ...
                    'Call io.SaverFactory.getFormats() to see valid options.'], ...
                    formatStr);
            end

            saverClass = char(registry(string(formatStr)));

            % Instantiate by class name string
            saver = feval(saverClass, options);
        end

        % ---------------------------------------------------------------- %

        function formats = getFormats(layerType)
            % GETFORMATS - Return a cell array of format strings available for a layer type.
            %
            % Syntax:
            %   function formats = getFormats(layerType)
            %
            % Use this to populate Format dropdowns in MibModel.save() and
            % MibDataset.save() without hard-coding the lists elsewhere.
            %
            % Input Arguments:
            %   layerType — (char) 'image' | 'mask' | 'labels'
            %   When omitted or 'all', returns all registered formats.
            %
            % Output Arguments:
            %   formats — (cell of char) sorted list of format strings
            %
            % Usage:
            %   Example 1::
            %
            %       imageFormats = io.SaverFactory.getFormats('image');
            %       % imageFormats contains e.g.:
            %       %   'Amira Mesh binary (``*.am``)'
            %       %   'Joint Photographic Experts Group (``*.jpg``)'
            %       %   'TIF format uncompressed (``*.tif``)'
            %       %   ...
            %
            %       maskFormats = io.SaverFactory.getFormats('mask');
            %       labelFormats = io.SaverFactory.getFormats('labels');
            %

            if nargin < 1; layerType = 'all'; end

            switch lower(layerType)
                case 'image'
                    formats = { ...
                        'Amira Mesh binary (*.am)'; ...
                        'Amira Mesh binary file sequence (*.am)'; ...
                        'Big Data Viewer HDF5 (*.h5)'; ...
                        'Joint Photographic Experts Group (*.jpg)'; ...
                        'Hierarchical Data Format (*.h5)'; ...
                        'Hierarchical Data Format with XML header (*.xml)'; ...
                        'MRC format for IMOD (*.mrc)'; ...
                        'NRRD Data Format (*.nrrd)'; ...
                        'OME-TIFF 2D sequence (*.ome.tiff)'; ...
                        'OME-TIFF 5D (*.ome.tiff)'; ...
                        'Portable Network Graphics (*.png)'; ...
                        'TIF format LZW compression (*.tif)'; ...
                        'TIF format uncompressed (*.tif)'; ...
                    };
                case 'mask'
                    formats = { ...
                        'Amira mesh binary (*.am)'; ...
                        'Amira mesh binary RLE compression SLOW (*.am)'; ...
                        'Hierarchical Data Format (*.h5)'; ...
                        'Hierarchical Data Format with XML header (*.xml)'; ...
                        'Matlab format (*.mask)'; ...
                        'PNG format (*.png)'; ...
                        'TIF format (*.tif)'; ...
                    };
                case 'labels'
                    formats = { ...
                        'Amira mesh ascii (*.am)'; ...
                        'Amira mesh binary (*.am)'; ...
                        'Amira mesh binary RLE compression SLOW (*.am)'; ...
                        'Contours for IMOD (*.mod)'; ...
                        'Hierarchical Data Format (*.h5)'; ...
                        'Hierarchical Data Format with XML header (*.xml)'; ...
                        'Matlab categorical format (*.mibCat)'; ...
                        'Matlab format (*.model)'; ...
                        'Matlab format 2D sequence (*.model)'; ...
                        'Matlab format for MIB ver. 1 (*.mat)'; ...
                        'MRC Volume for IMOD (*.mrc)'; ...
                        'NRRD for 3D Slicer (*.nrrd)'; ...
                        'PNG format (*.png)'; ...
                        'STL isosurface as binary (*.stl)'; ...
                        'TIF format (*.tif)'; ...
                    };
                otherwise  % 'all'
                    f1 = io.SaverFactory.getFormats('image');
                    f2 = io.SaverFactory.getFormats('mask');
                    f3 = io.SaverFactory.getFormats('labels');
                    formats = unique([f1; f2; f3]);
            end
        end

        % ---------------------------------------------------------------- %

        function defaultFormat = getDefaultFormat(layerType, filenameOrExt)
            % GETDEFAULTFORMAT - Return the default format string for a given layer type,.
            %
            % Syntax:
            %   function defaultFormat = getDefaultFormat(layerType, filenameOrExt)
            %
            % optionally guided by a filename or bare file extension.
            %
            % Used to initialise BatchOpt.Format{1} in MibModel.save().
            %
            % Input Arguments:
            %   layerType     — (char) 'image' | 'mask' | 'labels' | 'everything'
            %   'everything' is treated identically to 'all' and
            %   falls back to the TIF default.
            %   filenameOrExt — (char, optional) full filename (e.g. 'out.tif')
            %   or bare extension (e.g. 'tif').  When supplied,
            %   the function first tries to resolve a format from
            %   the extension; if the extension is unknown it
            %   falls back to the layer-type default.
            %
            % Output Arguments:
            %   defaultFormat — (char) default format string
            %
            % Usage:
            %   Example 1::
            %
            %       def = io.SaverFactory.getDefaultFormat('image');
            %       % def == 'TIF format uncompressed (``*.tif``)'
            %       def = io.SaverFactory.getDefaultFormat('image', 'tif');
            %       % def == 'TIF format uncompressed (``*.tif``)'
            %       def = io.SaverFactory.getDefaultFormat('image', 'result.png');
            %       % def == 'Portable Network Graphics (``*.png``)'
            %       def = io.SaverFactory.getDefaultFormat('labels');
            %       % def == 'Matlab format (``*.model``)'
            %

            % --- resolve extension ----------------------------------------
            if nargin < 2 || isempty(filenameOrExt)
                ext = '';
            else
                % fileparts('file.ome.tiff') returns '.tiff'; detect compound extension first
                if endsWith(lower(filenameOrExt), '.ome.tiff')
                    ext = 'ome.tiff';
                else
                    [~, ~, dotExt] = fileparts(filenameOrExt);
                    if isempty(dotExt)
                        ext = lower(filenameOrExt);   % bare extension, no dot
                    else
                        ext = lower(dotExt(2:end));   % strip leading dot
                    end
                end
            end

            % --- normalise layerType ('everything' → 'all') ---------------
            lt = lower(layerType);
            if strcmp(lt, 'everything'); lt = 'all'; end

            % --- extension-based lookup (per layer type) ------------------
            if ~isempty(ext)
                switch lt
                    case 'image'
                        switch ext
                            case 'am'
                                defaultFormat = 'Amira Mesh binary (*.am)'; return;
                            case 'h5'
                                defaultFormat = 'Hierarchical Data Format (*.h5)'; return;
                            case {'jpg','jpeg'}
                                defaultFormat = 'Joint Photographic Experts Group (*.jpg)'; return;
                            case 'mrc'
                                defaultFormat = 'MRC format for IMOD (*.mrc)'; return;
                            case 'nrrd'
                                defaultFormat = 'NRRD Data Format (*.nrrd)'; return;
                            case 'ome.tiff'
                                defaultFormat = 'OME-TIFF 5D (*.ome.tiff)'; return;
                            case 'png'
                                defaultFormat = 'Portable Network Graphics (*.png)'; return;
                            case {'tif','tiff'}
                                defaultFormat = 'TIF format uncompressed (*.tif)'; return;
                            case 'xml'
                                defaultFormat = 'Hierarchical Data Format with XML header (*.xml)'; return;
                        end
                    case 'mask'
                        switch ext
                            case 'am'
                                defaultFormat = 'Amira mesh binary (*.am)'; return;
                            case 'h5'
                                defaultFormat = 'Hierarchical Data Format (*.h5)'; return;
                            case 'mask'
                                defaultFormat = 'Matlab format (*.mask)'; return;
                            case 'png'
                                defaultFormat = 'PNG format (*.png)'; return;
                            case {'tif','tiff'}
                                defaultFormat = 'TIF format (*.tif)'; return;
                            case 'xml'
                                defaultFormat = 'Hierarchical Data Format with XML header (*.xml)'; return;
                        end
                    case 'labels'
                        switch ext
                            case 'am'
                                defaultFormat = 'Amira mesh binary (*.am)'; return;
                            case 'h5'
                                defaultFormat = 'Hierarchical Data Format (*.h5)'; return;
                            case 'mat'
                                defaultFormat = 'Matlab format for MIB ver. 1 (*.mat)'; return;
                            case 'mibcat'
                                defaultFormat = 'Matlab categorical format (*.mibCat)'; return;
                            case 'mod'
                                defaultFormat = 'Contours for IMOD (*.mod)'; return;
                            case 'model'
                                defaultFormat = 'Matlab format (*.model)'; return;
                            case 'mrc'
                                defaultFormat = 'MRC Volume for IMOD (*.mrc)'; return;
                            case 'nrrd'
                                defaultFormat = 'NRRD for 3D Slicer (*.nrrd)'; return;
                            case 'png'
                                defaultFormat = 'PNG format (*.png)'; return;
                            case 'stl'
                                defaultFormat = 'STL isosurface as binary (*.stl)'; return;
                            case {'tif','tiff'}
                                defaultFormat = 'TIF format (*.tif)'; return;
                            case 'xml'
                                defaultFormat = 'Hierarchical Data Format with XML header (*.xml)'; return;
                        end
                end
                % extension supplied but not matched → fall through to type default
            end

            % --- layer-type fallback defaults -----------------------------
            switch lt
                case 'image';  defaultFormat = 'Amira mesh binary (*.am)';
                case 'mask';   defaultFormat = 'Matlab format (*.mask)';
                case 'labels'; defaultFormat = 'Matlab format (*.model)';
                otherwise;     defaultFormat = 'TIF format uncompressed (*.tif)';
            end
        end

    end  % Static methods

    % ------------------------------------------------------------------ %
    %   Private helpers                                                    %
    % ------------------------------------------------------------------ %
    methods (Static, Access = private)

        function registry = buildRegistry()
            % BUILDREGISTRY - Build the format-string → saver-class-name dictionary.
            %
            % Syntax:
            %   function registry = buildRegistry()
            %
            % The registry is a MATLAB dictionary (string→string).
            % Using class-name strings (rather than class handles) avoids
            % loading every saver class at start-up.
            %
            % To add a new saver:
            % 1. Create mib/+io/+savers/MyFormatSaver.m
            % 2. Add an entry here:
            % registry("My format (``*.xyz``)") = "io.savers.MyFormatSaver";
            % 3. Add the format string to getFormats() above.

            registry = configureDictionary("string", "string");

            % ---- TIFF -------------------------------------------------- %
            registry("TIF format uncompressed (*.tif)")    = "io.savers.TiffSaver";
            registry("TIF format LZW compression (*.tif)") = "io.savers.TiffSaver";
            registry("TIF format (*.tif)")                 = "io.savers.TiffSaver"; % mask/labels variant

            % ---- PNG --------------------------------------------------- %
            registry("Portable Network Graphics (*.png)") = "io.savers.PngSaver";
            registry("PNG format (*.png)")                = "io.savers.PngSaver";  % mask/labels variant

            % ---- JPEG -------------------------------------------------- %
            registry("Joint Photographic Experts Group (*.jpg)") = "io.savers.JpgSaver";

            % ---- Matlab native formats ---------------------------------- %
            registry("Matlab format (*.model)")             = "io.savers.MatlabSaver";
            registry("Matlab format 2D sequence (*.model)") = "io.savers.MatlabSaver";
            registry("Matlab format for MIB ver. 1 (*.mat)") = "io.savers.MatlabSaver";
            registry("Matlab categorical format (*.mibCat)") = "io.savers.MatlabSaver";
            registry("Matlab format (*.mask)")              = "io.savers.MatlabSaver";

            % ---- HDF5 -------------------------------------------------- %
            registry("Hierarchical Data Format (*.h5)")               = "io.savers.HDF5Saver";
            registry("Hierarchical Data Format with XML header (*.xml)") = "io.savers.HDF5Saver";
            registry("Big Data Viewer HDF5 (*.h5)")                   = "io.savers.HDF5Saver";

            % ---- Amira Mesh -------------------------------------------- %
            registry("Amira Mesh binary (*.am)")                       = "io.savers.AmiraMeshSaver";
            registry("Amira Mesh binary file sequence (*.am)")         = "io.savers.AmiraMeshSaver";
            registry("Amira mesh binary (*.am)")                       = "io.savers.AmiraMeshSaver";
            registry("Amira mesh binary RLE compression SLOW (*.am)")  = "io.savers.AmiraMeshSaver";
            registry("Amira mesh ascii (*.am)")                        = "io.savers.AmiraMeshSaver";

            % ---- NRRD -------------------------------------------------- %
            registry("NRRD Data Format (*.nrrd)")   = "io.savers.NrrdSaver";
            registry("NRRD for 3D Slicer (*.nrrd)") = "io.savers.NrrdSaver";

            % ---- IMOD MRC ---------------------------------------------- %
            registry("MRC format for IMOD (*.mrc)") = "io.savers.MrcSaver";
            registry("MRC Volume for IMOD (*.mrc)")      = "io.savers.MrcSaver";

            % ---- OME-TIFF ---------------------------------------------- %
            registry("OME-TIFF 5D (*.ome.tiff)")          = "io.savers.OmeTiffSaver";
            registry("OME-TIFF 2D sequence (*.ome.tiff)") = "io.savers.OmeTiffSaver";

            % ---- IMOD Contours ----------------------------------------- %
            registry("Contours for IMOD (*.mod)") = "io.savers.ImodContourSaver";

            % ---- STL isosurface ---------------------------------------- %
            registry("STL isosurface as binary (*.stl)") = "io.savers.StlSaver";
        end

    end  % private static methods
end
