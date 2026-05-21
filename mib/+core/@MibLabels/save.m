function fnOut = save(obj, filename, options)
% SAVE - Save label/segmentation data from a MibLabels object to a file.
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
% MibLabels (and its sibling MibLabels63) stores multi-material segmentation data:
%
%   - ``data{1}`` is a uint8/uint16 array where each voxel value indicates
%     the material index (0 = exterior/background, 1..N = materials)
%   - ``materialNames`` — cell array of strings naming each material
%   - ``materialColors`` — ``[N x 3]`` matrix of per-material RGB colours (0..1)
%   - ``labelsVariable`` — name used as the variable in ``.model/.mat`` files
%
% **Supported formats** (from ``io.SaverFactory.getFormats('labels')``)
%
%   - ``'Matlab format (*.model)'`` — MIB3 native model file
%   - ``'Matlab format 2D sequence (*.model)'`` — one file per Z-slice
%   - ``'Matlab format for MIB ver. 1 (*.mat)'`` — legacy MIB v1 compatibility
%   - ``'Matlab categorical format (*.mibCat)'`` — MATLAB categorical array
%   - ``'Amira mesh binary (*.am)'`` — Amira binary mesh
%   - ``'Amira mesh binary RLE compression SLOW (*.am)'`` — Amira RLE
%   - ``'Amira mesh ascii (*.am)'`` — Amira ASCII mesh
%   - ``'Hierarchical Data Format (*.h5)'`` — HDF5
%   - ``'Hierarchical Data Format with XML header (*.xml)'`` — HDF5 + XML
%   - ``'NRRD for 3D Slicer (*.nrrd)'`` — NRRD (3D Slicer)
%   - ``'MRC Volume for IMOD (*.mrc)'`` — IMOD MRC volume
%   - ``'Contours for IMOD (*.mod)'`` — IMOD model contours
%   - ``'PNG format (*.png)'`` — PNG 2D sequence
%   - ``'TIF format (*.tif)'`` — TIFF (stack or sequence)
%   - ``'STL isosurface as binary (*.stl)'`` — STL mesh per material
%
% **NOTE ON pixSize:**
% Like MibImage, MibLabels does not store pixel size.
% Supply ``options.pixSize``, or it defaults to 1×1×1 µm.
%
% Input Arguments:
%   - **obj** — [MibLabels or MibLabels63] instance
%   - **filename** — [char] full output path including extension, e.g. ``'/data/Labels_stack.model'``
%   - **options** — *(optional)* [struct] with saving options:
%
%     - ``.Format`` — [char] format string (see list above); inferred from file extension when absent
%     - ``.Saving3DPolicy`` — [char] ``'3D stack'`` | ``'2D sequence'`` (default: ``'3D stack'``)
%     - ``.showWaitbar`` — [logical] display progress bar (default: ``true``)
%     - ``.silent`` — [logical] suppress dialogs (default: ``false``)
%     - ``.overwrite`` — [logical] silently overwrite files (default: ``true``)
%     - ``.MaterialIndex`` — [numeric or []] which material to export:
%
%       - ``[]`` or ``NaN`` — all materials
%       - integer — single material (returned as binary 0/1)
%
%     - ``.FilenameGenerator`` — [char] filename policy for 2D sequences:
%       ``'Use original filename'`` | ``'Use sequential filename'``
%     - ``.imageSliceNames`` — [cell of char] *(optional)* per-slice source
%       filenames from the parent image layer, injected by
%       ``MibDataset.saveImage()``.  When present and the labels object has
%       no own ``sliceName``, these names are forwarded to
%       ``metadata.sliceName`` so that 2-D sequence savers can apply the
%       ``'Use original filename'`` policy.
%     - ``.pixSize`` — [struct] injected by ``MibDataset.save()``
%     - ``.boundingBox`` — [1 x 6 numeric] injected by ``MibDataset.save()``
%     - ``.annotations`` — [struct] *(optional)* injected by ``MibDataset.save()``:
%
%       - ``.labelText`` — text label
%       - ``.labelValue`` — numeric value
%       - ``.labelPosition`` — coordinate position
%
% Output Arguments:
%   - **fnOut** — [char or cell of char] saved filename(s); ``[]`` on failure
%
% **Example 1** — save labels in MIB native format (standalone, no MibDataset needed):
%
%   .. code-block:: matlab
%
%      labels = core.MibLabels(uint8(zeros(256,256,50,1,1)));
%       labels.materialNames  = {'Nucleus'; 'ER'; 'Mitochondria'};
%       labels.materialColors = [0 0 1; 0 1 0; 1 0 0];
%       labels.labelsVariable = 'mibModel';
%
%       opts.Format      = 'Matlab format (*.model)';
%       opts.showWaitbar = false;
%       opts.silent      = true;
%       opts.overwrite   = true;
%       opts.pixSize     = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%       opts.boundingBox = [0 16.6 0 16.6 0 10];
%
%       fnOut = labels.save('/output/Labels_stack.model', opts);
%
% **Example 2** — export only one material as TIFF sequence:
%
%   .. code-block:: matlab
%
%      opts.Format         = 'TIF format (*.tif)';
%       opts.Saving3DPolicy = '2D sequence';
%       opts.MaterialIndex  = 2;   % export material 2 (ER) only; voxels → 1
%       opts.showWaitbar    = true;
%       opts.silent         = true;
%       opts.overwrite      = true;
%       opts.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%       fnOut = labels.save('/output/Labels_ER.tif', opts);
%
% **Example 3** — save labels as Amira mesh (binary):
%
%   .. code-block:: matlab
%
%      opts.Format      = 'Amira mesh binary (*.am)';
%       opts.showWaitbar = true;
%       opts.silent      = true;
%       opts.overwrite   = true;
%       opts.pixSize     = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%       opts.boundingBox = [0 16.6 0 16.6 0 10];
%       opts.layerType   = 'labels';  % required for AmiraMeshSaver to choose correct writer
%       fnOut = labels.save('/output/Labels_stack.am', opts);
%
% **Example 4** — via MibDataset (recommended: pixSize and boundingBox are injected):
%
%   .. code-block:: matlab
%
%      opts.Format      = 'Matlab format (*.model)';
%       opts.showWaitbar = false;
%       opts.silent      = true;
%       opts.overwrite   = true;
%       fnOut = dataset.save('labels', '/output/Labels_stack.model', opts);
%
% See also:
%   core.MibImage.save, core.MibDataset.save, models.MibModel.save, io.SaverFactory, io.savers.MatlabSaver, io.savers.AmiraMeshSaver
%

fnOut = [];

if nargin < 3; options = struct(); end
if nargin < 2 || isempty(filename)
    error('MibLabels:save:missingFilename', ...
        'A filename must be provided to MibLabels.save().');
end

% --- defaults ---
if ~isfield(options,'showWaitbar');    options.showWaitbar    = true;    end
if ~isfield(options,'silent');         options.silent         = false;   end
if ~isfield(options,'overwrite');      options.overwrite      = true;    end
if ~isfield(options,'Saving3DPolicy'); options.Saving3DPolicy = '3D stack'; end
if ~isfield(options,'layerType');      options.layerType      = 'labels'; end

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
metadata.dataClass      = obj.dataClass;
metadata.maxInt         = obj.maxInt;
metadata.pixSize        = options.pixSize;
metadata.materialNames  = obj.materialNames;
metadata.materialColors = obj.materialColors;
metadata.labelsVariable = strrep(obj.labelsVariable, '-', '_');
metadata.layerType      = options.layerType;

if isfield(options,'boundingBox')
    metadata.boundingBox = options.boundingBox;
else
    metadata.boundingBox = [0, obj.width, 0, obj.height, 0, obj.depth];
end
if isfield(options,'modelType')
    metadata.modelType = options.modelType;
else
    % Infer modelType from data class
    switch obj.dataClass
        case 'uint8';  metadata.modelType = 255;
        case 'uint16'; metadata.modelType = 65535;
        otherwise;     metadata.modelType = 255;
    end
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

% --- get data [H, W, D, C, T] ---
% When a specific material is requested getData returns a binary volume
if isempty(selMaterial)
    data = obj.getData('labels', 3, []);   % all materials → multi-valued
else
    data = obj.getData('labels', 3, selMaterial);  % binary: 1 where == selMaterial

    % Trim metadata to single material
    nMat = numel(metadata.materialNames);
    if selMaterial >= 1 && selMaterial <= nMat
        metadata.materialNames  = metadata.materialNames(selMaterial);
        metadata.materialColors = metadata.materialColors(selMaterial, :);
    end
end

% Check if user cancelled during data extraction
if ~isempty(earlyWb) && isvalid(earlyWb) && earlyWb.CancelRequested
    delete(earlyWb);
    fnOut = [];
    return;
end

% --- dispatch ---
saver = io.SaverFactory.create(options.Format, options);
fnOut = saver.save(data, metadata, filename, options);
end

