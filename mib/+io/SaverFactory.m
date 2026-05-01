classdef SaverFactory
% SAVERFACTORY - Factory for instantiating appropriate savers based on output format.
%
% Mirrors ``io.LoaderFactory`` for the writing side of the pipeline. Maps format
% strings to concrete ``io.savers.XxxSaver`` instances. Maintains separate registries
% for different data types (image, mask, labels) since the same format (e.g. TIF)
% may have different defaults and validation rules per category.
%
% **Architecture:**
% ``SaverFactory.create(formatStr)`` instantiates the appropriate saver class.
% Registries are built on-demand and cached. Format strings exactly match those
% used in ``core.MibDataset.save()`` and ``models.MibModel.save()`` dropdown menus.
%
% **High-level usage** (recommended):
%
%   .. code-block:: matlab
%
%      obj.mibModel.saveImage('image',  filename, BatchOptIn);
%      obj.mibModel.saveImage('mask',   filename, BatchOptIn);
%      obj.mibModel.saveImage('labels', filename, BatchOptIn);
%
% **Direct factory use** (advanced/scripted):
%
%   .. code-block:: matlab
%
%      saver = io.SaverFactory.create('TIF format uncompressed (*.tif)');
%      fnOut = saver.save(data, metadata, '/tmp/out.tif', options);
%
% **GUI context** (pass ParentFigure/mibPath so progress dialogs attach to MIB):
%
%   .. code-block:: matlab
%
%      ctorOpts.ParentFigure = obj.mibModel.mibGUI;
%      ctorOpts.mibPath = obj.mibModel.mibPath;
%      saver = io.SaverFactory.create('Amira Mesh binary (*.am)', ctorOpts);
%
% **List all formats** for a given layer type:
%
%   .. code-block:: matlab
%
%      imageFormats = io.SaverFactory.getFormats('image');
%      maskFormats = io.SaverFactory.getFormats('mask');
%      labelFormats = io.SaverFactory.getFormats('labels');
%
% **See also:** ``io.LoaderFactory``, ``io.savers.BaseSaver``,
% ``core.MibDataset.save``, ``models.MibModel.save``

    methods (Static)

        function saver = create(formatStr, options)
            % CREATE - Instantiate the saver that handles the requested output format.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      saver = io.SaverFactory.create(formatStr, options)
            %
            % Instantiates the appropriate ``BaseSaver`` subclass based on the format
            % string. Format strings must exactly match those from ``getFormats()``.
            %
            % Input Arguments:
            %   - **formatStr** — [char] format descriptor as it appears in Format dropdown:
            %
            %     - ``'TIF format uncompressed (*.tif)'``
            %     - ``'Amira mesh binary (*.am)'``
            %     - ``'Matlab format (*.model)'``
            %     - (see ``getFormats()`` for the complete list)
            %
            %   - **options** — *(optional)* struct passed to saver constructor
            %     via ``BaseSaver.initBaseProps()``. Important fields when calling from
            %     GUI context:
            %
            %     - ``.ParentFigure`` — [handle] to main MIB window;
            %       enables ``uiprogressdlg`` dialogs attached to the GUI
            %       (typically ``obj.mibGUI`` from MibModel). Leave empty for standalone use.
            %     - ``.mibPath`` — [char] MIB installation directory;
            %       used for resource and icon lookup by dialogs.
            %     - All other options are typically passed at ``save()`` time.
            %
            % Output Arguments:
            %   - **saver** — concrete ``BaseSaver`` subclass instance
            %
            % **Throws:**
            %   - ``io:SaverFactory:UnknownFormat`` — if ``formatStr`` is not registered
            %
            % **Example 1** — standalone scripted use:
            %
            %   .. code-block:: matlab
            %
            %      saver = io.SaverFactory.create('TIF format uncompressed (*.tif)');
            %      opts.Format = 'TIF format uncompressed (*.tif)';
            %      opts.Saving3DPolicy = '3D stack';
            %      opts.showWaitbar = false;
            %      opts.silent = true;
            %      opts.Compression = 'none';
            %      opts.overwrite = true;
            %      meta.filename = 'source.tif';
            %      meta.colorType = 'grayscale';
            %      meta.lutColors = [1 1 1];
            %      meta.dataClass = 'uint8';
            %      meta.maxInt = 255;
            %      meta.sliceName = {};
            %      meta.pixSize = struct('x',0.1,'y',0.1,'z',0.5,'units','um','t',1,'tunits','s');
            %      data = uint8(rand(64,64,10,1,1)*255);
            %      fnOut = saver.save(data, meta, '/tmp/out.tif', opts);
            %
            % **Example 2** — GUI context with progress dialogs:
            %
            %   .. code-block:: matlab
            %
            %      ctorOpts.ParentFigure = obj.mibModel.mibGUI;
            %      ctorOpts.mibPath = obj.mibModel.mibPath;
            %      saver = io.SaverFactory.create('Amira Mesh binary (*.am)', ctorOpts);
            %      opts.Format = 'Amira Mesh binary (*.am)';
            %      opts.Saving3DPolicy = '3D stack';
            %      opts.showWaitbar = true;
            %      opts.silent = true;
            %      opts.overwrite = true;
            %      opts.ParentFigure = obj.mibModel.mibGUI;
            %      opts.mibPath = obj.mibModel.mibPath;
            %      opts.pixSize = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
            %      meta.filename = 'source.tif';
            %      meta.colorType = 'grayscale';
            %      meta.lutColors = [1 0 0];
            %      meta.dataClass = 'uint8';
            %      meta.maxInt = 255;
            %      meta.sliceName = {};
            %      data = uint8(rand(128,128,20,1,1)*255);
            %      fnOut = saver.save(data, meta, '/tmp/stack.am', opts);
            %
            % **Example 3** — save segmentation model in native MIB format:
            %
            %   .. code-block:: matlab
            %
            %      saver = io.SaverFactory.create('Matlab format (*.model)');
            %      opts.Format = 'Matlab format (*.model)';
            %      opts.showWaitbar = false;
            %      opts.silent = true;
            %      opts.overwrite = true;
            %      meta.filename = 'image.tif';
            %      meta.materialNames = {'Nucleus'; 'Mitochondria'};
            %      meta.materialColors = [0 0 1; 0 1 0];
            %      meta.labelsVariable = 'mibModel';
            %      meta.dataClass = 'uint8';
            %      meta.pixSize = struct('x',0.1,'y',0.1,'z',0.5,'units','um','t',1,'tunits','s');
            %      labels = uint8(rand(64,64,10,1,1)*2);
            %      fnOut = saver.save(labels, meta, '/tmp/Labels_image.model', opts);
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
            % GETFORMATS - Return available format strings for a given layer type.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      formats = io.SaverFactory.getFormats(layerType)
            %
            % Returns a sorted cell array of format strings suitable for populating
            % Format dropdowns in ``MibModel.save()`` and ``MibDataset.save()``.
            %
            % Input Arguments:
            %   - **layerType** — *(optional)* [char], default: ``'all'``
            %
            %     - ``'image'`` — formats for pixel-data saving
            %     - ``'mask'`` — formats for binary mask saving
            %     - ``'labels'`` — formats for multi-material segmentation
            %     - ``'all'`` or omitted — returns all registered formats
            %
            % Output Arguments:
            %   - **formats** — cell array of [char] sorted format strings
            %
            % **Example 1** — get available formats by layer type:
            %
            %   .. code-block:: matlab
            %
            %      imageFormats = io.SaverFactory.getFormats('image');
            %      maskFormats = io.SaverFactory.getFormats('mask');
            %      labelFormats = io.SaverFactory.getFormats('labels');
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
            % GETDEFAULTFORMAT - Return the default format string for a layer type.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      defaultFormat = io.SaverFactory.getDefaultFormat(layerType, filenameOrExt)
            %
            % Returns a default format string, optionally guided by a filename or
            % file extension. Used to initialize ``BatchOpt.Format{1}`` in ``MibModel.save()``.
            %
            % Input Arguments:
            %   - **layerType** — [char] layer type:
            %
            %     - ``'image'`` — default: ``'Amira mesh binary (*.am)'``
            %     - ``'mask'`` — default: ``'Matlab format (*.mask)'``
            %     - ``'labels'`` — default: ``'Matlab format (*.model)'``
            %     - ``'everything'`` — same as ``'all'``, falls back to TIF
            %
            %   - **filenameOrExt** — *(optional)* [char] full filename (e.g. ``'out.tif'``)
            %     or bare extension (e.g. ``'tif'``). When supplied, function first
            %     tries to resolve format from extension; if unknown, falls back to
            %     layer-type default.
            %
            % Output Arguments:
            %   - **defaultFormat** — [char] default format string matching ``getFormats()`` output
            %
            % **Example 1** — get default format by layer type and extension:
            %
            %   .. code-block:: matlab
            %
            %      def = io.SaverFactory.getDefaultFormat('image');
            %      % def == 'Amira mesh binary (*.am)'
            %      def = io.SaverFactory.getDefaultFormat('image', 'tif');
            %      % def == 'TIF format uncompressed (*.tif)'
            %      def = io.SaverFactory.getDefaultFormat('image', 'result.png');
            %      % def == 'Portable Network Graphics (*.png)'
            %      def = io.SaverFactory.getDefaultFormat('labels');
            %      % def == 'Matlab format (*.model)'
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
            % BUILDREGISTRY - Build the format-string to saver-class-name dictionary.
            %
            % Syntax:
            %
            %   .. code-block:: matlab
            %
            %      registry = io.SaverFactory.buildRegistry()
            %
            % Constructs a MATLAB dictionary mapping format strings to saver class names.
            % Using class-name strings (rather than handles) avoids loading every saver
            % class at startup.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **registry** — ``dictionary(string, string)`` format→class mapping
            %
            % **Adding a new saver:**
            %
            %   1. Create ``mib/+io/+savers/MyFormatSaver.m``
            %   2. Add registry entry: ``registry("My format (*.xyz)") = "io.savers.MyFormatSaver";``
            %   3. Add format string to ``getFormats()`` above.
            %

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
