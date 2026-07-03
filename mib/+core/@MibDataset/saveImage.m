function fnOut = saveImage(obj, layerType, filename, options)
% SAVEIMAGE - Save a data layer from a MibDataset to a file.
%
% Syntax:
%   .. code-block:: matlab
%
%       fnOut = obj.saveImage(layerType, filename, options)
%
% This is the INTERMEDIATE-LEVEL save entry point.  It sits between
% models.MibModel.saveImage() (which handles batch processing, filename
% policies and directory resolution) and the low-level
% core.MibImage.save() / core.MibLabels.save() methods.
%
% Responsibilities of MibDataset.saveImage():
%   1. Validate that the requested layer exists (e.g., mask must exist).
%   2. Inject dataset-level metadata that the layer objects lack:
%
%      - ``.pixSize`` — from ``obj.image.pixSize``
%      - ``.boundingBox`` — from ``obj.image.boundingBox``
%      - ``.layerType`` — for format-dispatch (AmiraMesh, HDF5, etc.)
%
%   3. Delegate to the appropriate layer object:
%
%      - ``'image'`` — routes to ``obj.image.save(filename, options)``
%      - ``'labels'`` — routes to ``obj.labels.save(filename, options)``
%      - ``'mask'`` — directly assemble data + dispatch via ``SaverFactory`` (stored as raw numeric array, not ``MibImage`` subclass)
%
% This method works WITHOUT a MibModel — it is the natural entry point
% for scripted pipelines that load or create a MibDataset object directly.
%
% Input Arguments:
%   - **layerType** — [char] which layer to save:
%
%     - ``'image'`` — pixel intensity data (``obj.image``)
%     - ``'labels'`` — segmentation model (``obj.labels``)
%     - ``'mask'`` — binary mask layer (``obj.mask``)
%
%   - **filename** — [char] full output path including extension (e.g., ``'/data/stack.tif'``,
%     ``'C:\data\Labels_stack.model'``); when ``[]`` or ``''``, falls back to dataset's own filename
%     with appropriate prefix/suffix
%   - **options** *(optional)* — [struct] passed through to the layer saver:
%
%     - ``.Format`` — [char] format string; inferred from extension when absent
%     - ``.Saving3DPolicy`` — [char] ``'3D stack'`` (default) or ``'2D sequence'``
%     - ``.showWaitbar`` — [logical] default ``true``
%     - ``.silent`` — [logical] default ``false``
%     - ``.overwrite`` — [logical] default ``true``
%     - ``.FilenameGenerator`` — [char] filename policy for 2-D sequences
%     - ``.MaterialIndex`` — [numeric or ``[]``] for labels: ``[]`` = all materials, integer = single material
%     - ``.Compression`` — [char] compression type (TIF/JPG)
%     - ``.Quality`` — [numeric] JPEG quality ``0–100``
%     - ``.ParentFigure`` — [handle] main MIB application window; injected automatically by ``MibModel.saveImage()`` when called from GUI; omit for standalone/scripted use
%     - ``.mibPath`` — [char] path to MIB installation directory; used by savers for resource lookup; injected automatically by ``MibModel.saveImage()``
%     - ``.MaskColor`` — [numeric] mask overlay RGB colour ``[R G B]`` in range ``[0–1]`` (default: ``[1 0 1]``); mask-specific
%     - ``.annotations`` — [struct] with fields ``.labelText``, ``.labelValue``, ``.labelPosition`` to include annotation data in ``.model`` files; labels-specific
%
% Output Arguments:
%   - **fnOut** — [char or cell] saved path(s); ``[]`` on failure
%
% **Example 1** — Save image layer as a 3-D TIFF stack:
%
%   .. code-block:: matlab
%
%       opts.Format         = 'TIF format uncompressed (*.tif)';
%       opts.Saving3DPolicy = '3D stack';
%       opts.showWaitbar    = false;
%       opts.silent         = true;
%       opts.overwrite      = true;
%       opts.ParentFigure   = obj.mibGUI;
%       opts.mibPath        = obj.mibPath;
%       fnOut = obj.mibModel.I{BatchOpt.id}.saveImage('image', '/output/stack.tif', opts);
%       fprintf('Saved: %s\n', fnOut);
%
% **Example 2** — Save segmentation model in MIB native format:
%
%   .. code-block:: matlab
%
%       opts.Format      = 'Matlab format (*.model)';
%       opts.showWaitbar = false;
%       opts.silent      = true;
%       opts.overwrite   = true;
%       opts.ParentFigure   = obj.mibGUI;
%       opts.mibPath        = obj.mibPath;
%       fnOut = obj.mibModel.I{BatchOpt.id}.saveImage('labels', '/output/Labels_stack.model', opts);
%
% **Example 3** — Save binary mask as TIFF 2-D sequence:
%
%   .. code-block:: matlab
%
%       opts.Format            = 'TIF format (*.tif)';
%       opts.Saving3DPolicy    = '2D sequence';
%       opts.FilenameGenerator = 'Use sequential filename';
%       opts.MaskColor         = [1 0 1];
%       opts.showWaitbar       = false;
%       opts.silent            = true;
%       opts.overwrite         = true;
%       opts.ParentFigure   = obj.mibGUI;
%       opts.mibPath        = obj.mibPath;
%       fnOut = obj.mibModel.I{BatchOpt.id}.saveImage('mask', '/output/Mask_slice.tif', opts);
%
% **Example 4** — Save labels, export single material only:
%
%   .. code-block:: matlab
%
%       opts.Format        = 'TIF format (*.tif)';
%       opts.MaterialIndex = 2;    % export material index 2 as binary 0/1
%       opts.showWaitbar   = false;
%       opts.silent        = true;
%       opts.overwrite     = true;
%       opts.ParentFigure   = obj.mibGUI;
%       opts.mibPath        = obj.mibPath;
%       fnOut = obj.mibModel.I{BatchOpt.id}.saveImage('labels', '/output/Labels_mat2.tif', opts);
%
% **Example 5** — Save labels with annotations:
%
%   .. code-block:: matlab
%
%       [lText, lValue, lPos] = dataset.annotations.getLabels();
%       opts.annotations.labelText     = lText;
%       opts.annotations.labelValue    = lValue;
%       opts.annotations.labelPosition = lPos;
%       opts.Format    = 'Matlab format (*.model)';
%       opts.overwrite = true;
%       opts.ParentFigure   = obj.mibGUI;
%       opts.mibPath        = obj.mibPath;
%       fnOut = obj.mibModel.I{BatchOpt.id}.saveImage('labels', '/output/Labels_annotated.model', opts);
%
% **Example 6** — Fall back on dataset filename when none provided:
%
%   .. code-block:: matlab
%
%       opts.Format    = 'Matlab format (*.mask)';
%       opts.overwrite = true;
%       fnOut = obj.mibModel.I{BatchOpt.id}.saveImage('mask', '', opts);
%       % Uses dataset.image.maskFilename or generates 'Mask_<imageName>.mask'
%
% See also:
%   core.MibImage.save, core.MibLabels.save, models.MibModel.saveImage, io.SaverFactory
%

fnOut = [];

if nargin < 4; options = struct(); end
if nargin < 3; filename = []; end
if nargin < 2
    error('MibDataset:save:missingLayerType', ...
        'layerType must be provided: ''image'', ''labels'', or ''mask''.');
end

% --- defaults ---
if ~isfield(options,'showWaitbar');    options.showWaitbar    = true;   end
if ~isfield(options,'silent');         options.silent         = false;  end
if ~isfield(options,'overwrite');      options.overwrite      = true;   end
if ~isfield(options,'Saving3DPolicy'); options.Saving3DPolicy = '3D stack'; end

% --- inject dataset-level metadata into options ---
% These are not stored by MibImage/MibLabels themselves
options.pixSize    = obj.image.pixSize;
options.layerType  = layerType;

% Virtual / BigData images do not populate obj.image.pixSize (the full-res voxel
% size lives in the pyramid metadata). Reconstruct a full-resolution pixSize struct
% from the level-0 voxel size so MibImage.save can scale it to the exported level.
if (~isstruct(options.pixSize) || isempty(options.pixSize)) && ...
        isa(obj.image, 'core.MibVirtualImage') && ~isempty(obj.image.pyramid.levelNames)
    voxel0 = obj.image.pyramid.levelVoxelSizes(1, :);   % [y x z] at full resolution
    options.pixSize = struct('x', voxel0(2), 'y', voxel0(1), 'z', voxel0(3), ...
        't', 1, 'units', 'um', 'tunits', 's');
end

% boundingBox lives on obj.image (core.MibImage); access it directly.
% It is used below for label/mask saves that bypass MibImage.save().
% For the 'image' case MibImage.save() reads obj.image.boundingBox itself.
options.boundingBox = obj.image.boundingBox;

% --- resolve fallback filename when none provided ---
if isempty(filename)
    filename = resolveFallbackFilename(obj, layerType, options);
    if isempty(filename)
        error('MibDataset:save:noFilename', ...
            'No filename was provided and a fallback could not be determined.');
    end
end

% --- layer-specific dispatch ---
switch lower(layerType)

    case 'image'
        % Delegate to MibImage.save() — pixSize already in options
        fnOut = obj.image.save(filename, options);

    case 'labels'
        % Validate that a model exists
        if ~obj.modelExist
            warning('MibDataset:save:noLabels', ...
                'No segmentation model found in this dataset. Nothing saved.');
            return;
        end

        % Optionally pass annotation data from dataset
        if ~isfield(options,'annotations')
            try
                if obj.annotations.getLabelsNumber() > 1
                    [lText, lValue, lPos] = obj.annotations.getLabels();
                    options.annotations.labelText     = lText;
                    options.annotations.labelValue    = lValue;
                    options.annotations.labelPosition = lPos;
                end
            catch  %#ok<CTCH> % annotations may not be available
            end
        end

        % Propagate per-slice filenames from the image layer so that
        % MibLabels.save() can populate metadata.sliceName.  Labels objects
        % never carry their own slice names, so without this the
        % 'Use original filename' policy in 2-D sequence savers always falls
        % back to sequential numbering.
        if ~isfield(options, 'imageSliceNames') || isempty(options.imageSliceNames)
            options.imageSliceNames = obj.image.sliceName;
        end
        if ~isfield(options, 'imageSliceSizes') || isempty(options.imageSliceSizes)
            options.imageSliceSizes = obj.image.sliceSize;
        end

        % Delegate to MibLabels.save()
        fnOut = obj.labels.save(filename, options);

        % Store saved path so subsequent "Save" (no dialog) reuses it, but
        % ONLY for the native *.model format. Exports to other formats
        % (*.am, *.tif, *.nrrd, ...) must not change the model's canonical
        % filename nor the default destination directory used by later
        % Save / Save-as operations.
        if ~isempty(fnOut)
            if iscell(fnOut); savedLabelsPath = fnOut{1};
            else;             savedLabelsPath = fnOut;
            end
            [~, ~, savedLabelsExt] = fileparts(savedLabelsPath);
            if strcmpi(savedLabelsExt, '.model')
                obj.labels.filename = savedLabelsPath;
            end
        end

    case 'mask'
        % Validate that a mask exists
        if ~obj.maskExist
            warning('MibDataset:save:noMask', ...
                'No mask layer found in this dataset. Nothing saved.');
            return;
        end

        % Default mask colour
        if ~isfield(options,'MaskColor'); options.MaskColor = [1 0 1]; end

        % Determine output format
        if ~isfield(options,'Format') || isempty(options.Format)
            options.Format = io.SaverFactory.getDefaultFormat('mask', filename);
        end

        % Build mask metadata (mask is always single-channel uint8, C=1)
        metadata.filename       = obj.image.filename;
        metadata.colorType      = 'grayscale';
        metadata.lutColors      = [1 0 1];
        metadata.dataClass      = 'uint8';
        metadata.maxInt         = 1;
        metadata.pixSize        = options.pixSize;
        metadata.boundingBox    = options.boundingBox;
        metadata.maskFilename   = obj.image.maskFilename;
        metadata.maskColor      = options.MaskColor;
        metadata.materialNames  = {'Mask'};
        metadata.materialColors = options.MaskColor;
        metadata.sliceName      = {};
        if ~isempty(obj.image.sliceName); metadata.sliceName = obj.image.sliceName; end
        metadata.sliceSize      = [];
        if ~isempty(obj.image.sliceSize); metadata.sliceSize = obj.image.sliceSize; end
        metadata.layerType        = 'mask';
        metadata.imageDescription = core.MibImage.buildImageDescription( ...
            obj.image.boundingBox, obj.image.actionLog);

        saver = io.SaverFactory.create(options.Format, options);

        % BigData (pyramidal) mask: stream the chosen pyramid level slice-by-slice
        % so the full-resolution mask is never gathered into memory. The mask lives
        % in packed bit 7 of the disk-backed model, read at a level through the same
        % MibImageSliceProvider as the image path. Standard datasets keep the
        % in-memory gather path below.
        isPyramidalMask = isa(obj.labels, 'core.MibBigDataLabels') && ...
            ~isempty(obj.labels.modelLevelSizes);
        if isPyramidalMask
            nLevels = size(obj.labels.modelLevelSizes, 1);
            exportLevel = 1;
            if isfield(options, 'PyramidLevel') && ~isempty(options.PyramidLevel)
                exportLevel = max(1, min(round(options.PyramidLevel), nLevels));
            end
            % the exported level's voxel size is the full-res pixSize scaled by the
            % level's XY/Z scale factor (the bounding box is identical across levels)
            levelScale = obj.labels.modelScaleFactors(exportLevel, :);   % [yScale xScale zScale]
            metadata.pixSize.y = metadata.pixSize.y * levelScale(1);
            metadata.pixSize.x = metadata.pixSize.x * levelScale(2);
            metadata.pixSize.z = metadata.pixSize.z * levelScale(3);
            resolution = utils.calculateResolution(metadata.pixSize);
            metadata.xResolution = resolution(1);
            metadata.yResolution = resolution(2);

            numSlices = obj.labels.modelLevelSizes(exportLevel, 3);
            zScale    = obj.labels.modelScaleFactors(exportLevel, 3);
            provider  = io.savers.MibImageSliceProvider(obj.labels, 'mask', exportLevel, ...
                [], numSlices, 1, zScale);
            fnOut = saver.saveStream(provider, metadata, filename, options);
        else
            % Get full 5-D mask data [H, W, D, C, T] → use getData3D for all T
            maskData = obj.getData3D('mask', NaN, 3, NaN);   % returns {[H, W, D]}
            maskData = maskData{1};                          % unpack cell → [H, W, D]
            maskData = reshape(maskData, [size(maskData,1), size(maskData,2), ...
                size(maskData,3), 1, 1]);                    % → [H, W, D, 1, 1]
            fnOut = saver.save(maskData, metadata, filename, options);
        end

        % Store new mask filename in dataset
        if ~isempty(fnOut)
            if iscell(fnOut); obj.image.maskFilename = fnOut{1};
            else;             obj.image.maskFilename = fnOut;
            end
        end

    otherwise
        error('MibDataset:save:unknownLayerType', ...
            'Unknown layerType: "%s". Use ''image'', ''labels'', or ''mask''.', ...
            layerType);
end
end

% ------------------------------------------------------------------ %
function filename = resolveFallbackFilename(obj, layerType, options)
% RESOLVEFALLBACKFILENAME - Build a default output filename from the dataset.
%
% Syntax:
%   function filename = resolveFallbackFilename(obj, layerType, options)
%
% Called when the caller passes an empty or missing filename to saveImage().
% Uses the dataset's current image filename as a base, then derives a
% layer-appropriate name using a fixed naming convention.
%
% Input Arguments:
%   obj       — MibDataset instance
%   layerType — (char) 'image' | 'labels' | 'mask'
%   options   — (struct) forwarded options; only .Format is inspected for
%   the 'image' case, to pick the correct file extension
%
% Output Arguments:
%   filename  — (char) resolved absolute path, or '' if layerType is unknown
%
%   Naming conventions applied:
%   'image'  → <dir>/<name>.<ext>  where <ext> is extracted from
%   options.Format ('*.<ext>)') or defaults to '.tif'
%   'labels' → <dir>/Labels_<name>.model
%   'mask'   → obj.image.maskFilename  (if set), otherwise
%   <dir>/Mask_<name>.mask
%

[fileDir, baseName] = fileparts(obj.image.filename);
switch lower(layerType)
    case 'image'
        fileExt = '';
        if isfield(options,'Format')
            % Extract extension from format string: '...(*.<ext>)'
            extToken = regexp(options.Format, '\*\.(\w+)\)', 'tokens', 'once');
            if ~isempty(extToken); fileExt = ['.' extToken{1}]; end
        end
        if isempty(fileExt); fileExt = '.tif'; end
        filename = fullfile(fileDir, [baseName fileExt]);
    case 'labels'
        filename = fullfile(fileDir, ['Labels_' baseName '.model']);
    case 'mask'
        if ~isempty(obj.image.maskFilename)
            filename = obj.image.maskFilename;
        else
            filename = fullfile(fileDir, ['Mask_' baseName '.mask']);
        end
    otherwise
        filename = '';
end
end

