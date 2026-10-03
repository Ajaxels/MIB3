classdef MatlabSaver < io.savers.BaseSaver
% MATLABSAVER - Saver for MIB native MATLAB-based binary formats.
%
% Handles all native serialisation formats used by MIB:
%
% 'Matlab format (``*.model``)'            - MIB2/MIB3 native segmentation model.
% Variables saved: <modelVariable>, modelMaterialNames,
% modelMaterialColors, BoundingBox, modelVariable, modelType,
% [labelText, labelValue, labelPosition if annotations present]
%
% 'Matlab format 2D sequence (``*.model``)' - one .model file per Z-slice;
% useful for very large datasets where a full 3-D .model is too large.
%
% 'Matlab format for MIB ver. 1 (``*.mat``)' - legacy format for MIB v1
% compatibility.  Variables: <modelVariable>, material_list,
% color_list, bounding_box, model_var.
%
% 'Matlab categorical format (``*.mibCat``)' - saves labels as a MATLAB
% categorical array, 3-D stack or 2-D sequence.
% Variables: imgOut (categorical), imgVariable, options.
%
% 'Matlab format (``*.mask``)'             - binary mask in a MAT-file.
% Variable saved: maskImg (logical [H W D]).
%
% DATA DIMENSIONS
% Input data : [H, W, D, C, T]  - C=1 expected for all Matlab formats
% (labels/masks are always single channel)
%
% METADATA FIELDS USED
% .materialNames  - cell array of material name strings (labels formats)
% .materialColors - [M x 3] material RGB colours (labels formats)
% .labelsVariable - (char) variable name to use inside the .model file,
% default 'mibModel'
% .modelType      - (integer) model type (e.g. 255, 63)
% .pixSize        - struct with voxel dimensions
% .boundingBox    - [xmin xmax ymin ymax zmin zmax]
% .annotations    - (optional) struct with .labelText, .labelValue,
% .labelPosition from obj.annotations.getLabels()
%
% USAGE EXAMPLES
%
% .. code-block:: matlab
%
%     %% 1. Save a segmentation model (MIB native format)
%     saver = io.SaverFactory.create('Matlab format (``*.model``)');
%
%     opts.Format      = 'Matlab format (``*.model``)';
%     opts.showWaitbar = true;
%     opts.silent      = true;
%     opts.overwrite   = true;
%
%     meta.filename       = 'myImage.tif';
%     meta.materialNames  = {'Nucleus'; 'ER'; 'Mitochondria'};
%     meta.materialColors = [0 0 1; 0 1 0; 1 0 0];  % R, G, B per material
%     meta.labelsVariable = 'mibModel';
%     meta.modelType      = 255;        % uint8 labels
%     meta.dataClass      = 'uint8';
%     meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%     meta.boundingBox    = [0 41.6 0 41.6 0 6];
%
%     labels = uint8(rand(256,256,30,1,1) * 3);  % values 0,1,2,3
%     fnOut = saver.save(labels, meta, '/output/Labels_myImage.model', opts);
%
%
%
% .. code-block:: matlab
%
%     %% 2. Save mask in native MIB mask format
%     saver = io.SaverFactory.create('Matlab format (``*.mask``)');
%
%     opts.Format      = 'Matlab format (``*.mask``)';
%     opts.showWaitbar = false;
%     opts.overwrite   = true;
%
%     meta.filename    = 'myImage.tif';
%     meta.dataClass   = 'uint8';
%     meta.pixSize     = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%
%     mask = uint8(rand(256,256,30,1,1) > 0.8);  % binary mask
%     fnOut = saver.save(mask, meta, '/output/Mask_myImage.mask', opts);
%
%
%
% .. code-block:: matlab
%
%     %% 3. Save as categorical format (for deep learning pipelines)
%     saver = io.SaverFactory.create('Matlab categorical format (``*.mibCat``)');
%
%     opts.Format         = 'Matlab categorical format (``*.mibCat``)';
%     opts.Saving3DPolicy = '3D stack';   % or '2D sequence'
%     opts.FilenamePolicy = 'Use existing name';
%     opts.showWaitbar    = false;
%     opts.overwrite      = true;
%
%     meta.materialNames  = {'Exterior'; 'Nucleus'; 'Background'};
%     meta.materialColors = [0.5 0.5 0.5; 0 0 1; 0 1 0];
%     meta.labelsVariable = 'imgOut';
%     meta.dataClass      = 'uint8';
%     meta.modelType      = 255;
%     meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%
%     labels = uint8(rand(256,256,30,1,1) * 3);
%     fnOut = saver.save(labels, meta, '/output/Labels.mibCat', opts);
%
%
%
% .. code-block:: matlab
%
%     %% 4. Via MibModel (recommended for GUI/batch workflows)
%     BatchOpt.LayerType       = {'labels'};
%     BatchOpt.Format          = {'Matlab format (``*.model``)'};
%     BatchOpt.OutputDirectoryPolicy = {'Same as image'};
%     BatchOpt.FilenamePolicy  = {'Use existing name'};
%     BatchOpt.showWaitbar     = true;
%     BatchOpt.mibBatchTooltip.LayerType = '';
%     model.save('labels', [], BatchOpt);
%
%
% SEE ALSO
% io.SaverFactory, io.savers.BaseSaver,
% core.MibLabels.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = MatlabSaver(options)
            % MATLABSAVER - Constructor for MatlabSaver class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      saver = io.savers.MatlabSaver(options)
            %
            % Input Arguments:
            %   - **options** - *(optional)* struct, saver-level options (usually empty;
            %     per-save options are passed to ``save()`` instead)
            %
            % Output Arguments:
            %   - **obj** - instance of the MatlabSaver class
            %
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - Return format strings handled by MatlabSaver.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      formats = obj.getSupportedFormats()
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **formats** - cell array of format strings for MATLAB-based output
            %
            formats = { ...
                'Matlab format (*.model)'; ...
                'Matlab format 2D sequence (*.model)'; ...
                'Matlab format for MIB ver. 1 (*.mat)'; ...
                'Matlab categorical format (*.mibCat)'; ...
                'Matlab format (*.mask)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - Serialise data to one of the MIB MATLAB-native formats.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.save(data, metadata, filename, options)
            %
            % The active format is selected by ``options.Format``:
            %
            % - ``'Matlab format (``*.mask``)'`` → ``saveMask()``
            % - ``'Matlab format (``*.model``)'`` → ``saveModel3D()``
            % - ``'Matlab format 2D sequence (``*.model``)'`` → ``saveModel2DSeq()``
            % - ``'Matlab format for MIB ver. 1 (``*.mat``)'`` → ``saveModelV1()``
            % - ``'Matlab categorical format (``*.mibCat``)'`` → ``saveModelCat()``
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] label/mask array
            %   - **metadata** - struct with image metadata (see class-level docs)
            %   - **filename** - full output path for the serialized file
            %   - **options** - struct with format selection and save options
            %
            % Output Arguments:
            %   - **fnOut** - [char] or [cell] path(s) of saved file(s), ``[]`` on failure
            %
            % **See Also** - class-level documentation for detailed parameter descriptions.

            fnOut = [];
            if ~isfield(options,'showWaitbar'); options.showWaitbar = true;  end
            if ~isfield(options,'silent');      options.silent      = false; end
            if ~isfield(options,'overwrite');   options.overwrite   = true;  end
            if ~isfield(options,'Format');      options.Format      = 'Matlab format (*.model)'; end

            switch options.Format
                case 'Matlab format (*.mask)'
                    fnOut = obj.saveMask(data, metadata, filename, options);
                case 'Matlab format (*.model)'
                    fnOut = obj.saveModel3D(data, metadata, filename, options);
                case 'Matlab format 2D sequence (*.model)'
                    fnOut = obj.saveModel2DSeq(data, metadata, filename, options);
                case 'Matlab format for MIB ver. 1 (*.mat)'
                    fnOut = obj.saveModelV1(data, metadata, filename, options);
                case 'Matlab categorical format (*.mibCat)'
                    fnOut = obj.saveModelCat(data, metadata, filename, options);
                otherwise
                    error('MatlabSaver:unknownFormat', ...
                        'Unsupported Matlab format: %s', options.Format);
            end
        end

        function fnOut = saveStream(obj, provider, metadata, filename, options)
            % SAVESTREAM - Memory-bounded save from a SliceProvider.
            %
            % Streams the native ``.model`` (3-D) format slice-by-slice via a
            % writable ``matfile`` (the label volume is grown on disk, never held
            % whole). All other Matlab formats fall back to the gather-based
            % default (bounded by the selected pyramid level).
            %
            % See ``io.savers.BaseSaver.saveStream``.
            %
            % **Example** - stream a BigData model level to a native ``.model`` file:
            %
            %   .. code-block:: matlab
            %
            %      labels   = mibModel.I{mibModel.getActiveId()}.labels;   % MibBigDataLabels
            %      numZ     = labels.modelLevelSizes(1,3);
            %      zScale   = labels.modelScaleFactors(1,3);
            %      provider = io.savers.MibImageSliceProvider(labels,'labels',1,[],numZ,1,zScale);
            %      saver    = io.savers.MatlabSaver(struct());
            %      meta.materialNames = labels.materialNames; meta.materialColors = labels.materialColors;
            %      meta.modelType = labels.maxMaterials; meta.boundingBox = [0 1 0 1 0 1];
            %      saver.saveStream(provider, meta, 'C:\out\Labels_stack.model', ...
            %          struct('Format','Matlab format (*.model)','silent',true,'showWaitbar',false));
            if nargin < 5; options = struct(); end
            if ~isfield(options,'Format'); options.Format = 'Matlab format (*.model)'; end
            switch options.Format
                case 'Matlab format (*.model)'
                    fnOut = obj.saveModel3DStream(provider, metadata, filename, options);
                otherwise
                    % gather the (level-bounded) volume and use the standard save
                    fnOut = saveStream@io.savers.BaseSaver(obj, provider, metadata, filename, options);
            end
        end

    end  % public

    % ------------------------------------------------------------------ %
    methods (Access = private)

        function fnOut = saveMask(obj, data, ~, filename, options)
            % SAVEMASK - Save binary mask as MAT-file (variable: ``maskImg``).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveMask(data, [], filename, options)
            %
            % Uses ``save('-struct',...)`` to avoid ``eval()`` and dynamic variable
            % names. The loaded file contains a top-level variable ``maskImg``.
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] mask array
            %   - **filename** - full output path (``*.mask``)
            %   - **options** - struct with ``showWaitbar`` and ``overwrite`` fields
            %
            % Output Arguments:
            %   - **fnOut** - [char] path of saved file
            %
            fnOut = [];
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving mask', filename, false);
            end
            % Pack into struct so save('-struct') writes top-level variable
            vars.maskImg = logical(squeeze(data(:,:,:,1,1)));
            if ~isempty(wb); wb.Value = 0.4; end
            save(filename, '-struct', 'vars', '-v7.3');
            if ~isempty(wb); wb.Value = 1; delete(wb); end
            fnOut = filename;
            fprintf('MatlabSaver: mask saved → %s\n', filename);
        end

        function fnOut = saveModel3D(obj, data, metadata, filename, options)
            % SAVEMODEL3D - Save full 3-D model in MIB2/MIB3 native ``.model`` format.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveModel3D(data, metadata, filename, options)
            %
            % Uses ``save('-struct', 'vars', ...)`` to store each variable
            % under its proper name without ``eval()``.
            %
            % **Saved variables** (top-level in the ``.model`` MAT-file):
            %
            % - ``<labelsVariable>`` - uint8/uint16 [H W D] label array
            % - ``modelMaterialNames`` - cell array of material names
            % - ``modelMaterialColors`` - [M x 3] RGB colours
            % - ``BoundingBox`` - [xmin xmax ymin ymax zmin zmax]
            % - ``modelVariable`` - char (= labelsVariable)
            % - ``modelType`` - integer (255 for uint8 model)
            % - ``modelObjects3D`` - logical, instance models (``modelType`` above
            %   255) only, from ``metadata.objects3D``: objects numbered through
            %   the volume (true) or per slice (false). Absent from older files
            % - ``labelText``, ``labelValue``, ``labelPosition`` - if ``.annotations`` present
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] label array
            %   - **metadata** - struct with model metadata
            %   - **filename** - full output path (``*.model``)
            %   - **options** - struct with ``showWaitbar`` and other save options
            %
            % Output Arguments:
            %   - **fnOut** - [char] path of saved file
            %
            fnOut = [];
            labVar = obj.getLabelsVariable(metadata);

            wb = [];
            if options.showWaitbar
                [~, fn, ex] = fileparts(filename);
                wb = obj.createProgressDialog('Saving model', sprintf('%s\n%s', fileparts(filename), [fn ex]), false);
            end

            % Build a struct whose fields become top-level MAT variables
            vars.(labVar)               = squeeze(data(:,:,:,1,1));
            vars.modelMaterialNames     = obj.getMaterialNames(metadata);
            vars.modelMaterialColors    = obj.getMaterialColors(metadata);
            vars.BoundingBox            = obj.getBoundingBox(metadata);
            vars.modelVariable          = labVar;
            vars.modelType              = obj.getModelType(metadata);
            if vars.modelType > 255 && isfield(metadata, 'objects3D')
                vars.modelObjects3D     = logical(metadata.objects3D);
            end

            if ~isempty(wb); wb.Value = 0.4; end

            if isfield(metadata,'annotations') && ~isempty(metadata.annotations)
                ann = metadata.annotations;
                vars.labelText     = ann.labelText;
                vars.labelValue    = ann.labelValue;
                vars.labelPosition = ann.labelPosition;
            end
            save(filename, '-struct', 'vars', '-mat', '-v7.3');

            if ~isempty(wb); wb.Value = 1; delete(wb); end
            fnOut = filename;
            fprintf('MatlabSaver: model saved → %s\n', filename);
        end

        function fnOut = saveModel3DStream(obj, provider, metadata, filename, options)
            % SAVEMODEL3DSTREAM - Stream a full 3-D ``.model`` via a writable matfile.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveModel3DStream(provider, metadata, filename, options)
            %
            % Writes the same top-level variables as ``saveModel3D`` (``<labVar>``,
            % ``modelMaterialNames``, ``modelMaterialColors``, ``BoundingBox``,
            % ``modelVariable``, ``modelType``, optional annotations), but grows the
            % label volume on disk one Z-slice at a time from ``provider`` so the full
            % model is never resident in memory.
            %
            % **Example** - usually reached via ``saveStream`` rather than directly:
            %
            %   .. code-block:: matlab
            %
            %      provider = io.savers.MibImageSliceProvider(labels, 'labels', 1, [], numZ, 1, zScale);
            %      meta.materialNames = labels.materialNames; meta.labelsVariable = 'mibModel';
            %      fnOut = io.savers.MatlabSaver(struct()).saveModel3DStream( ...
            %          provider, meta, 'C:\out\model.model', struct('showWaitbar',false));
            fnOut = [];
            labVar = obj.getLabelsVariable(metadata);
            sz = provider.OutputSize;
            H = sz(1); W = sz(2); D = sz(3);
            dataClass = provider.DataClass;

            wb = [];
            if options.showWaitbar
                [~, fn, ex] = fileparts(filename);
                wb = obj.createProgressDialog('Saving model', ...
                    sprintf('%s\n%s', fileparts(filename), [fn ex]), true);
            end

            % Fresh file (matfile would otherwise merge into an existing one)
            if exist(filename, 'file'); delete(filename); end
            m = matfile(filename, 'Writable', true);

            % Pre-allocate the label volume on disk (sets the last element; disk
            % op, not a full in-memory allocation), then fill slice by slice.
            m.(labVar)(H, W, D) = cast(0, dataClass);
            for z = 1:D
                if ~isempty(wb) && wb.CancelRequested
                    delete(wb);
                    % A cancelled save must leave nothing behind. The file at this
                    % point holds the slices written so far and none of the
                    % metadata variables, so it would open as a valid model of the
                    % wrong extent - worse than no file at all. Dropping the
                    % matfile handle first is what lets Windows remove it.
                    m = [];   %#ok<NASGU> - closes the writable matfile
                    if exist(filename, 'file'); delete(filename); end
                    return;
                end
                slice = cast(reshape(provider.getSlice(z, 1), H, W), dataClass);
                if D == 1
                    % matfile drops a trailing singleton, so the pre-allocation
                    % above created a 2-D variable and a 3-subscript write into it
                    % errors on the dimension count. Reachable for any pyramid
                    % level whose Z has been downsampled to a single slice, which
                    % the coarsest level of a deep pyramid usually is.
                    m.(labVar) = slice;
                else
                    m.(labVar)(:, :, z) = slice;
                end
                if ~isempty(wb); wb.Value = z / D; end
            end

            % Scalar / small metadata variables (top-level, matching saveModel3D)
            m.modelMaterialNames  = obj.getMaterialNames(metadata);
            m.modelMaterialColors = obj.getMaterialColors(metadata);
            m.BoundingBox         = obj.getBoundingBox(metadata);
            m.modelVariable       = labVar;
            m.modelType           = obj.getModelType(metadata);
            if isfield(metadata, 'annotations') && ~isempty(metadata.annotations)
                ann = metadata.annotations;
                m.labelText     = ann.labelText;
                m.labelValue    = ann.labelValue;
                m.labelPosition = ann.labelPosition;
            end

            if ~isempty(wb); delete(wb); end
            fnOut = filename;
            fprintf('MatlabSaver: model streamed → %s\n', filename);
        end

        function fnOut = saveModel2DSeq(obj, data, metadata, filename, options)
            % SAVEMODEL2DSEQ - Save a 2-D sequence of ``.model`` files (one per Z-slice).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveModel2DSeq(data, metadata, filename, options)
            %
            % Each slice uses ``save('-struct')`` so every field becomes a
            % separate top-level variable - same format as ``saveModel3D()``.
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] label array
            %   - **metadata** - struct with model metadata
            %   - **filename** - full path template (``*.model``)
            %   - **options** - struct with ``showWaitbar`` and filename policy
            %
            % Output Arguments:
            %   - **fnOut** - cell array of saved file paths
            %
            fnOut = [];
            labVar = obj.getLabelsVariable(metadata);
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.model'; end
            if isempty(pathStr); pathStr = pwd; end

            nZ = size(data,3);

            % Detect whether FilenameGenerator was explicitly set by the
            % caller (batch/scripted mode) or is absent (simple GUI mode).
            callerSetFilename = isfield(options, 'FilenameGenerator');
            if ~isfield(options, 'showWaitbar'); options.showWaitbar = true;  end
            if ~isfield(options, 'silent');      options.silent      = false; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end

            % When slice names are available and the caller has not pre-set
            % FilenameGenerator, give the user a choice - mirrors TiffSaver.
            hasSliceNames = isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nZ;
            hasSliceSizes = isfield(metadata, 'sliceSize') && size(metadata.sliceSize, 1) == nZ;
            if ~options.silent && ~callerSetFilename && nZ > 1 && hasSliceNames
                parentFig = [];
                if isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
                    parentFig = options.ParentFigure;
                end
                mibPathLocal = '';
                if isfield(options, 'mibPath'); mibPathLocal = options.mibPath; end
                dlgOpts.mibPath     = mibPathLocal;
                dlgOpts.WindowStyle = 'modal';
                prompts = {'Filename generator:'};
                defAns  = {{'Use sequential filename', 'Use original filename', 1}};
                if hasSliceSizes
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
                answer = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, ...
                    'Model 2D sequence saving options', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
                if hasSliceSizes
                    options.RestoreOriginalSize = strcmp(answer{2}, 'Yes');
                end
            end

            sliceNames = obj.buildSliceNames(baseName, pathStr, nZ, ext, options, metadata);

            % Pre-compute shared variables
            sharedVars.modelMaterialNames  = obj.getMaterialNames(metadata);
            sharedVars.modelMaterialColors = obj.getMaterialColors(metadata);
            sharedVars.BoundingBox         = obj.getBoundingBox(metadata);
            sharedVars.modelVariable       = labVar;
            sharedVars.modelType           = obj.getModelType(metadata);

            hasAnnotations = isfield(metadata,'annotations') && ~isempty(metadata.annotations);
            if hasAnnotations
                ann = metadata.annotations;
                sharedVars.labelText     = ann.labelText;
                sharedVars.labelValue    = ann.labelValue;
                sharedVars.labelPosition = ann.labelPosition;
            end

            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving model', 'Saving 2D model sequence...', true);
            end

            for z = 1:nZ
                if ~isempty(wb) && wb.CancelRequested
                    delete(wb); return;
                end
                vars          = sharedVars;
                vars.(labVar) = squeeze(data(:,:,z,1,1));
                if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && ...
                        hasSliceSizes
                    vars.(labVar) = obj.cropSliceToOriginalSize(vars.(labVar), metadata.sliceSize(z, :));
                end
                save(sliceNames{z}, '-struct', 'vars', '-mat', '-v7.3');
                if ~isempty(wb); wb.Value = z/nZ; end
            end
            if ~isempty(wb); delete(wb); end
            fnOut = sliceNames;
            fprintf('MatlabSaver: 2D model sequence saved → %s\n', pathStr);
        end

        function fnOut = saveModelV1(obj, data, metadata, filename, options) %#ok<INUSD>
            % SAVEMODELV1 - Save in legacy MIB v1 format (``.mat``) for backward compatibility.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveModelV1(data, metadata, filename, options)
            %
            % **Saved variables** (top-level): ``<labVar>``, ``material_list``, ``color_list``,
            % ``bounding_box``, ``model_var``
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] label array
            %   - **metadata** - struct with model metadata
            %   - **filename** - full output path (``*.mat``)
            %   - **options** - struct with save options (``showWaitbar``, ``overwrite``)
            %
            % Output Arguments:
            %   - **fnOut** - [char] path of saved file
            %
            fnOut = [];
            labVar = obj.getLabelsVariable(metadata);

            vars.(labVar)         = squeeze(data(:,:,:,1,1));
            vars.material_list    = obj.getMaterialNames(metadata);
            vars.color_list       = obj.getMaterialColors(metadata);
            vars.bounding_box     = obj.getBoundingBox(metadata);
            vars.model_var        = labVar;

            if isfield(metadata,'annotations') && ~isempty(metadata.annotations)
                ann = metadata.annotations;
                vars.labelText     = ann.labelText;
                vars.labelPosition = ann.labelPosition;
            end
            save(filename, '-struct', 'vars', '-mat', '-v7.3');
            fnOut = filename;
            fprintf('MatlabSaver: MIB v1 model saved → %s\n', filename);
        end

        function fnOut = saveModelCat(obj, data, metadata, filename, options)
            % SAVEMODELCAT - Save as MATLAB categorical array (``.mibCat``).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveModelCat(data, metadata, filename, options)
            %
            % The label volume is converted to a categorical with class names
            % derived from ``metadata.materialNames`` (prepended with ``'Exterior'``
            % for index 0 if not already present).
            %
            % ``options.Saving3DPolicy`` controls whether the output is a
            % single 3-D ``.mibCat`` file or a 2-D sequence.
            % ``options.FilenamePolicy`` controls filename generation for 2-D sequences.
            % When both are absent and ``silent=false`` a dialog is shown (mirrors MIB2).
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] label array
            %   - **metadata** - struct with model metadata (materialNames, materialColors, etc.)
            %   - **filename** - full output path (``*.mibCat``)
            %   - **options** - struct with ``Saving3DPolicy``, ``FilenamePolicy``, ``silent``, ``showWaitbar``
            %
            % Output Arguments:
            %   - **fnOut** - [char] or [cell] path(s) of saved file(s)
            %
            fnOut = [];

            % Capture before defaults: FilenamePolicy is only present in
            % batch/scripted mode; absent in simple GUI mode → show dialog.
            % (Mirrors TiffSaver's callerSetFilename pattern.  We cannot
            % use Saving3DPolicy because MibLabels.save always pre-sets it.)
            callerSetPolicy = isfield(options, 'FilenamePolicy');

            if ~isfield(options,'silent');         options.silent         = false; end
            if ~isfield(options,'Saving3DPolicy'); options.Saving3DPolicy = '3D stack'; end
            if ~isfield(options,'FilenamePolicy'); options.FilenamePolicy = 'Use sequential filename'; end

            % --- Show options dialog when not in silent/batch mode ---
            if ~options.silent && ~callerSetPolicy
                parentFig = [];
                if isfield(options,'ParentFigure') && ~isempty(options.ParentFigure)
                    parentFig = options.ParentFigure;
                end
                mibPathLocal = '';
                if isfield(options,'mibPath'); mibPathLocal = options.mibPath; end

                prompts = {'Saving policy:'; 'Filename policy (2D sequence only):'};
                defAns  = {{'3D stack', '2D sequence', 1}; ...
                           {'Use sequential filename', 'Use existing name', 1}};
                dlgOpt.mibPath = mibPathLocal;
                answer = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, ...
                    'mibCat saving options', dlgOpt);
                if isempty(answer); return; end
                options.Saving3DPolicy = answer{1};
                options.FilenamePolicy  = answer{2};
            end

            % Map FilenamePolicy → FilenameGenerator so buildSliceNames
            % (which uses FilenameGenerator) honours the chosen policy.
            if ~isfield(options, 'FilenameGenerator')
                if strcmp(options.FilenamePolicy, 'Use existing name')
                    options.FilenameGenerator = 'Use original filename';
                else
                    options.FilenameGenerator = 'Use sequential filename';
                end
            end

            matNames = obj.getMaterialNames(metadata);
            % Prepend Exterior if not present
            if isempty(matNames) || ~strcmp(matNames{1}, 'Exterior')
                classNames = [{'Exterior'}; matNames(:)];
            else
                classNames = matNames(:);
            end

            % Build shared modelOptions struct saved to file as 'options'
            % (must match the field name MIB2 and the MIB3 loader expect)
            modelOptions.dimOrder            = 'yxczt';
            modelOptions.modelType           = obj.getModelType(metadata);
            modelOptions.modelMaterialColors = obj.getMaterialColors(metadata);
            modelOptions.modelMaterialNames  = classNames;

            if strcmp(options.Saving3DPolicy, '3D stack')
                % Save full 3-D volume as a single .mibCat file.
                % The loaded file contains: imgOut (categorical), imgVariable, options.
                vars.imgOut      = categorical(squeeze(data(:,:,:,1,1)), ...
                    0:numel(classNames)-1, classNames);
                vars.imgVariable = 'imgOut';
                vars.options     = modelOptions;
                save(filename, '-struct', 'vars', '-mat', '-v7.3');
                fnOut = filename;
            else
                % 2-D sequence - one .mibCat per Z-slice
                % Use splitFilename only for path/stem; always force the
                % correct mixed-case extension (.mibCat) because
                % splitFilename lowercases all extensions.
                [pathStr, baseName, ~] = obj.splitFilename(filename);
                ext = '.mibCat';
                nZ = size(data,3);
                sliceNames = obj.buildSliceNames(baseName, pathStr, nZ, ext, options, metadata);

                wb = [];
                if options.showWaitbar
                    wb = obj.createProgressDialog('Saving model', 'Saving categorical sequence...', true);
                end
                for z = 1:nZ
                    if ~isempty(wb) && wb.CancelRequested
                        delete(wb); return;
                    end
                    vars.imgOut      = categorical(squeeze(data(:,:,z,1,1)), ...
                        0:numel(classNames)-1, classNames);
                    vars.imgVariable = 'imgOut';
                    vars.options     = modelOptions;
                    save(sliceNames{z}, '-struct', 'vars', '-mat', '-v7.3');
                    if ~isempty(wb); wb.Value = z/nZ; end
                end
                if ~isempty(wb); delete(wb); end
                fnOut = sliceNames;
            end
            fprintf('MatlabSaver: categorical model saved → %s\n', filename);
        end

        % ================================================================== %
        %   Small metadata helper methods                                    %
        % ================================================================== %

        function v = getLabelsVariable(~, metadata)
            % GETLABELSVARIABLE - Extract labels variable name with MATLAB compliance.
            %
            % Input Arguments:
            %   - **metadata** - struct with ``labelsVariable`` field
            %
            % Output Arguments:
            %   - **v** - [char] variable name (``'mibModel'`` if not specified)
            %
            if isfield(metadata,'labelsVariable') && ~isempty(metadata.labelsVariable)
                v = strrep(metadata.labelsVariable, '-', '_');
            else
                v = 'mibModel';
            end
        end

        function v = getMaterialNames(~, metadata)
            % GETMATERIALNAMES - Extract material name list with defaults.
            %
            % Input Arguments:
            %   - **metadata** - struct with ``materialNames`` field
            %
            % Output Arguments:
            %   - **v** - cell array of material names (``{'Material 1'}`` if not specified)
            %
            if isfield(metadata,'materialNames') && ~isempty(metadata.materialNames)
                v = metadata.materialNames(:);
            else
                v = {'Material 1'};
            end
        end

        function v = getMaterialColors(~, metadata)
            % GETMATERIALCOLORS - Extract material RGB colors with defaults.
            %
            % Input Arguments:
            %   - **metadata** - struct with ``materialColors`` field
            %
            % Output Arguments:
            %   - **v** - [M x 3] RGB colours (random if not specified)
            %
            if isfield(metadata,'materialColors') && ~isempty(metadata.materialColors)
                v = metadata.materialColors;
            else
                v = rand(1,3);
            end
        end

        function v = getBoundingBox(~, metadata)
            % GETBOUNDINGBOX - Extract bounding box with defaults.
            %
            % Input Arguments:
            %   - **metadata** - struct with ``boundingBox`` field
            %
            % Output Arguments:
            %   - **v** - [1 x 6] bounding box [xmin xmax ymin ymax zmin zmax]
            %
            if isfield(metadata,'boundingBox') && ~isempty(metadata.boundingBox)
                v = metadata.boundingBox;
            else
                v = [0 1 0 1 0 1];
            end
        end

        function v = getModelType(~, metadata)
            % GETMODELTYPE - Extract or infer model type from metadata.
            %
            % Input Arguments:
            %   - **metadata** - struct with ``modelType`` or ``dataClass`` fields
            %
            % Output Arguments:
            %   - **v** - [numeric] model type (``255`` for uint8, ``65535`` for uint16)
            %
            if isfield(metadata,'modelType') && ~isempty(metadata.modelType)
                v = metadata.modelType;
            elseif isfield(metadata,'dataClass')
                switch metadata.dataClass
                    case 'uint8';  v = 255;
                    case 'uint16'; v = 65535;
                    otherwise;     v = 255;
                end
            else
                v = 255;
            end
        end

    end  % private
end
