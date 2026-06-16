function fnOut = save(obj, filename, options)
% SAVE - Save label/segmentation data from a MibLabels63 object to a file.
%
% Syntax:
%   .. code-block:: matlab
%
%       fnOut = obj.save(filename, options)
%
% This method OVERRIDES core.MibImage.save() to inject label-specific
% metadata (material names, material colours, labels variable name) into
% the metadata struct before dispatching to io.SaverFactory.
%
% MibLabels63 packs model (bits 1-6), mask (bit 7), and selection (bit 8)
% into a single uint8 array.  This override calls getData63() to correctly
% unpack the model layer before saving — whereas the base MibImage.save()
% would write the raw packed bytes.
%
% Supported formats: same as core.MibLabels.save (see io.SaverFactory.getFormats('labels'))
%
% NOTE ON pixSize:
% MibLabels63 does not store pixel size.
% Supply options.pixSize, or it defaults to 1x1x1 um.
%
% Input Arguments:
%   - **obj** — ``MibLabels63`` instance
%   - **filename** — (char) full output path including extension
%   - **options** — *(optional)* struct with saving options:
%
%     - ``.Format`` — (char) format string; inferred from extension when absent
%     - ``.Saving3DPolicy`` — (char) ``'3D stack'`` | ``'2D sequence'``; default ``'3D stack'``
%     - ``.showWaitbar`` — (logical) default ``true``
%     - ``.silent`` — (logical) suppress dialogs; default ``false``
%     - ``.overwrite`` — (logical) default ``true``
%     - ``.MaterialIndex`` — (double|[]) which material to export:
%
%       - ``[]`` or ``NaN`` — all materials
%       - integer — single material (returned as binary 0/1)
%
%     - ``.FilenameGenerator`` — (char) filename policy for 2D sequences:
%       ``'Use original filename'`` | ``'Use sequential filename'``
%     - ``.imageSliceNames`` — (cell of char) *(optional)* per-slice source
%       filenames from the parent image layer, injected by
%       ``MibDataset.saveImage()``.  When present and the labels object has
%       no own ``sliceName``, these names are forwarded to
%       ``metadata.sliceName`` so that 2-D sequence savers can apply the
%       ``'Use original filename'`` policy.
%     - ``.pixSize`` — (struct) injected by ``MibDataset.saveImage()``
%     - ``.boundingBox`` — ([1×6]) injected by ``MibDataset.saveImage()``
%     - ``.annotations`` — (struct) injected by ``MibDataset.saveImage()`` when present
%
% Output Arguments:
%   - **fnOut** — (char or cell of char) saved filename(s); ``[]`` on failure
%
% Usage:
%   **Example 1** — Save type-63 model via MibDataset (recommended: pixSize injected)
%
%   .. code-block:: matlab
%
%
%     opts.Format      = 'Matlab format (*.model)';
%     opts.showWaitbar = false;
%     opts.silent      = true;
%     opts.overwrite   = true;
%     fnOut = obj.mibModel.I{obj.mibModel.id}.saveImage('labels', '/output/model.model', opts);
%
%   **Example 2** — Direct call (standalone, no MibDataset)
%
%   .. code-block:: matlab
%
%
%     opts.Format      = 'Matlab format (*.model)';
%     opts.showWaitbar = false;
%     opts.silent      = true;
%     opts.overwrite   = true;
%     opts.pixSize     = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%     opts.boundingBox = [0 16.6 0 16.6 0 10];
%     fnOut = labels63.save('/output/model63.model', opts);
%

% Updates

fnOut = [];

if nargin < 3; options = struct(); end
if nargin < 2 || isempty(filename)
    error('MibLabels63:save:missingFilename', ...
        'A filename must be provided to MibLabels63.save().');
end

% --- defaults ---
if ~isfield(options,'showWaitbar');    options.showWaitbar    = true;      end
if ~isfield(options,'silent');         options.silent         = false;     end
if ~isfield(options,'overwrite');      options.overwrite      = true;      end
if ~isfield(options,'Saving3DPolicy'); options.Saving3DPolicy = '3D stack'; end
if ~isfield(options,'layerType');      options.layerType      = 'labels';  end

% --- ensure full path ---
[pathStr, ~, ext] = fileparts(filename);
if isempty(pathStr)
    filename = fullfile(pwd, filename);
    [pathStr, ~, ext] = fileparts(filename);
end
if exist(pathStr,'dir') ~= 7; mkdir(pathStr); end
ext = lower(ext);

% --- determine output format ---
if ~isfield(options,'Format') || isempty(options.Format)
    options.Format = io.SaverFactory.getDefaultFormat('labels', ext);
end

% --- default pixSize ---
if ~isfield(options,'pixSize') || isempty(options.pixSize)
    options.pixSize = struct('x',1,'y',1,'z',1,'t',1,'units','um','tunits','s');
end

% --- pyramid level selection (disk-backed BigData model only) -------------
% A BigData model mirrors the image pyramid; a chosen level is streamed
% slice-by-slice so the full model volume is never loaded. The level's voxel
% size is pixSize scaled by the level's scale factors (XY, and Z when the
% pyramid downsamples Z); the physical bounding box is identical across levels.
isPyramidalModel = isa(obj, 'core.MibBigDataLabels') && obj.exists && ~isempty(obj.modelLevelNames);
exportLevel = 1;
if isfield(options, 'PyramidLevel') && ~isempty(options.PyramidLevel)
    exportLevel = round(options.PyramidLevel);
end
if isPyramidalModel
    nLevels = numel(obj.modelLevelNames);
    exportLevel = max(1, min(exportLevel, nLevels));
    levelScale = obj.modelScaleFactors(exportLevel, :);   % [yScale xScale zScale]
    options.pixSize.y = options.pixSize.y * levelScale(1);
    options.pixSize.x = options.pixSize.x * levelScale(2);
    options.pixSize.z = options.pixSize.z * levelScale(3);
end

% Show indeterminate progress dialog immediately so the user sees feedback
% while the (potentially slow) data-extraction step runs.
earlyWb = [];
if options.showWaitbar && isfield(options,'ParentFigure') && ~isempty(options.ParentFigure)
    try
        if isvalid(options.ParentFigure)
            earlyWb = uiprogressdlg(options.ParentFigure, ...
                'Title',         'Saving labels', ...
                'Message',       'Preparing data...', ...
                'Indeterminate', 'on', ...
                'Cancelable',    'on');
            options.waitbarHandle = earlyWb;
        end
    catch
    end
end

% --- handle MaterialIndex: extract a specific material if requested ---
selMaterial = [];  % [] means all
if isfield(options,'MaterialIndex') && ~isempty(options.MaterialIndex)
    if ~isnan(options.MaterialIndex)
        selMaterial = options.MaterialIndex;
    end
end

% --- assemble metadata ---
metadata.filename       = obj.filename;
metadata.colorType      = obj.colorType;
metadata.lutColors      = obj.lutColors;
metadata.dataClass      = 'uint8';   % MibLabels63 always stores uint8
metadata.maxInt         = obj.maxInt;
metadata.pixSize        = options.pixSize;
metadata.materialNames  = obj.materialNames;
metadata.materialColors = obj.materialColors;
labelsVar = obj.labelsVariable;
if ~(ischar(labelsVar) || isstring(labelsVar)); labelsVar = ''; end   % opened models may leave this empty
metadata.labelsVariable = strrep(char(labelsVar), '-', '_');
metadata.layerType      = options.layerType;
metadata.modelType      = obj.maxMaterials;   % 63

if isfield(options,'boundingBox')
    metadata.boundingBox = options.boundingBox;
else
    metadata.boundingBox = [0, obj.width, 0, obj.height, 0, obj.depth];
end
if isfield(options,'annotations') && ~isempty(options.annotations)
    metadata.annotations = options.annotations;
end
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
elseif isfield(options, 'imageSliceNames') && ~isempty(options.imageSliceNames)
    % Use per-slice filenames from the parent image layer (injected by
    % MibDataset.saveImage) so that 2-D sequence savers can apply the
    % 'Use original filename' policy for labels.
    metadata.sliceName = options.imageSliceNames;
else
    metadata.sliceName = {};
end
if ~isempty(obj.sliceSize)
    metadata.sliceSize = obj.sliceSize;
elseif isfield(options, 'imageSliceSizes') && ~isempty(options.imageSliceSizes)
    metadata.sliceSize = options.imageSliceSizes;
else
    metadata.sliceSize = [];
end
options.FilenamePrefix = 'Labels_';

% --- trim metadata to a single material when requested (both paths) ---
if ~isempty(selMaterial)
    nMat = numel(metadata.materialNames);
    if selMaterial >= 1 && selMaterial <= nMat
        metadata.materialNames  = metadata.materialNames(selMaterial);
        metadata.materialColors = metadata.materialColors(selMaterial, :);
    end
end

% --- dispatch ---
% getData63 with type='labels' returns unpacked uint8 material indices (0..63),
% or a binary 0/1 volume when a single material is requested.
saver = io.SaverFactory.create(options.Format, options);

if isPyramidalModel
    % Stream the selected model pyramid level slice-by-slice (memory bounded to
    % one slice; non-streaming savers gather only this single level).
    numSlices = obj.modelLevelSizes(exportLevel, 3);
    zScale    = obj.modelScaleFactors(exportLevel, 3);
    provider  = io.savers.MibImageSliceProvider(obj, 'labels', exportLevel, selMaterial, numSlices, 1, zScale);
    fnOut = saver.saveStream(provider, metadata, filename, options);
else
    if isempty(selMaterial)
        data = obj.getData63('labels', 3, []);   % all materials → multi-valued uint8
    else
        data = obj.getData63('labels', 3, selMaterial);  % binary: 1 where == selMaterial
    end

    % Check if user cancelled during data extraction
    if ~isempty(earlyWb) && isvalid(earlyWb) && earlyWb.CancelRequested
        delete(earlyWb);
        fnOut = [];
        return;
    end

    fnOut = saver.save(data, metadata, filename, options);
end
end
