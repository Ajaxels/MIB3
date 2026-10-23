function createModel(obj, modelType, modelMaterialNames)
% CREATEMODEL - Create an empty model: allocate memory for a new model.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.createModel()
%      obj.createModel(modelType)
%      obj.createModel(modelType, modelMaterialNames)
%
% This function reinitializes the labels layer (obj.labels) with a
% zero-filled matrix of the appropriate class and dimensions.
% When switching between the packed models (core.MibLabels63: type 63 in
% uint8, type 16383 in uint16) and the separate-layer models (core.MibLabels,
% types 255/65535/4294967295), the selection and mask layers are converted
% automatically.
%
% For a BigData dataset the model is a disk store of type 63; the interactive
% path (models.MibModel.createModel) also builds type 16383 stores.
%
% Input Arguments:
%   - **modelType** *(optional)* - [numeric] model type (default: current model type):
%
%     - ``63`` - packed type-63 model with up to 63 materials; 'Labels', 'Mask', and
%       'Selection' layers packed in single uint8 matrix (``core.MibLabels63``) to reduce memory
%     - ``255`` - separate-layer type-255 model with up to 255 materials (``core.MibLabels``)
%     - ``16383`` - packed instance model with up to 16383 objects; index, 'Mask' and
%       'Selection' packed in a single uint16 matrix (``core.MibLabels63``, uint16 layout)
%     - ``65535`` - large-capacity type-65535 model with up to 65535 materials
%     - ``4294967295`` - very-large-capacity type-4294967295 model with up to 4294967295 materials
%
%   - **modelMaterialNames** *(optional)* - [cell] cell array with names of materials; only
%     used for model types 63 and 255; ignored for larger types
%
% Output Arguments:
%   (none)
%
% **Example 1** - Create a type-63 model (memory-efficient):
%
%   .. code-block:: matlab
%
%      obj.createModel(63);
%
% **Example 2** - Create a type-255 model with material names:
%
%   .. code-block:: matlab
%
%      obj.createModel(255, {'Nucleus', 'Cytoplasm'});
%
% **Example 3** - Create a large-capacity type-65535 model:
%
%   .. code-block:: matlab
%
%      obj.createModel(65535);

% Updates
% Ported from MIB2 mibImage.createModel

if nargin < 3; modelMaterialNames = []; end
if nargin < 2; modelType = NaN; end

% BigData: the model is kept on disk as a packed pyramidal zarr (not in
% memory). Only the packed types are supported: 16383 (uint16 store) when asked
% for, otherwise 63. Creating the model allocates the disk store and enables
% segmentation for the browse-only set.
if strcmp(obj.datasetType, 'BigData')
    meta = core.MibImage.initializeImgInfo( ...
        'pixSize', obj.image.pixSize, ...
        'Height',  obj.image.height, ...
        'Width',   obj.image.width,  ...
        'Depth',   obj.image.depth,  ...
        'Time',    obj.image.time,   ...
        'Colors',  1);
    % Direct/batch callers get a temp-scratch store; the interactive path
    % (MibModel.createModel) builds the store at a user-chosen location instead.
    % Either way the model mirrors the image pyramid levels.
    obj.labels = core.MibBigDataLabels([], meta);
    if modelType == 16383; obj.labels.setLayout('uint16'); end
    obj.labels.createStore([obj.image.height, obj.image.width, obj.image.depth], ...
        '', obj.image.pyramid);
    obj.labels.labelsVariable = 'mibModel';
    obj.labels.filename = '';   % not saved yet; Phase 3 "save as" suggests the name
    if modelType == 16383
        % instance model: two name slots and generated colours, as for 65535
        obj.labels.materialNames  = {'1'; '2'};
        obj.labels.materialColors = rand(65535, 3);
        obj.labels.materialsCount = 0;
        obj.labels.objects3D      = true;   % one index per object through the volume
        obj.modelExist = true;
        obj.enableSelection = true;
        obj.selectedMaterial = 3;
        obj.selectedAddToMaterial = 3;
        obj.lastSegmSelection = [2 1];
        obj.annotations.clearContents();
        return;
    end
    if ~isempty(modelMaterialNames)
        if size(modelMaterialNames, 1) < size(modelMaterialNames, 2)
            obj.labels.materialNames = modelMaterialNames';
        else
            obj.labels.materialNames = modelMaterialNames;
        end
        obj.labels.materialsCount = numel(modelMaterialNames);
    else
        obj.labels.materialNames = {};
        obj.labels.materialsCount = 0;
    end
    obj.modelExist = true;
    obj.enableSelection = true;   % BigData starts browse-only; a model enables segmentation
    obj.selectedMaterial = 2;
    obj.selectedAddToMaterial = 2;
    obj.lastSegmSelection = [2 1];
    obj.annotations.clearContents();
    return;
end

% Determine current model type from the labels class
currentModelType = obj.labels.maxMaterials;

if isnan(modelType); modelType = currentModelType; end

% Build metadata for new label layers from the current image
meta = core.MibImage.initializeImgInfo( ...
    'pixSize', obj.image.pixSize, ...
    'Height',  obj.image.height, ...
    'Width',   obj.image.width,  ...
    'Depth',   obj.image.depth,  ...
    'Time',    obj.image.time,   ...
    'Colors',  1);

dims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];

if modelType == 63 || modelType == 16383
    % packed types: 63 in uint8, 16383 in uint16 (core.MibLabels63.setLayout)
    if modelType == 63; containerClass = 'uint8'; else; containerClass = 'uint16'; end
    if currentModelType == modelType
        % Already this packed type: clear the model bits, preserve the mask and
        % selection bits
        if obj.labels.exists
            obj.labels.data = bitand(obj.labels.data, obj.labels.flagsMask);
            [h, w, d, ~, t] = size(obj.labels.data);
            obj.labels.height    = h;
            obj.labels.width     = w;
            obj.labels.depth     = d;
            obj.labels.colors    = 1;
            obj.labels.time      = t;
            obj.labels.dim_yxzct = [h, w, d, 1, t];
        else
            obj.labels = core.MibLabels63(zeros(dims, containerClass), meta);
        end
    else
        % Was another type: pack the existing selection/mask into a single matrix
        newLabels = core.MibLabels63(zeros(dims, containerClass), meta);
        newData = newLabels.data;
        if isa(obj.labels, 'core.MibLabels63')
            % the other packed type: move the two flags to this layout's bits
            if obj.labels.exists
                newData = bitor(newData, cast(bitget(obj.labels.data, obj.labels.selectionBit), containerClass) * cast(newLabels.selectionValue, containerClass));
                newData = bitor(newData, cast(bitget(obj.labels.data, obj.labels.maskBit), containerClass) * cast(newLabels.maskValue, containerClass));
            end
        else
            if obj.selection.exists
                newData = bitor(newData, cast(obj.selection.data, containerClass) * cast(newLabels.selectionValue, containerClass));
            end
            if obj.maskExist && obj.mask.exists
                newData = bitor(newData, cast(obj.mask.data, containerClass) * cast(newLabels.maskValue, containerClass));
            end
        end
        newLabels.data = newData;
        obj.labels    = newLabels;
        % Clear the now-redundant separate layers
        obj.selection = core.MibLabels([], meta);
        obj.mask      = core.MibLabels([], meta);
    end
    if modelType == 16383
        obj.labels.materialColors = rand(65535, 3);   % instance model: generated colours
    end
else
    % Switching to type 255, 65535, or 4294967295
    if isa(obj.labels, 'core.MibLabels63') && obj.labels.exists
        % Extract selection and mask from packed bits before replacing the labels
        selData = uint8(bitget(obj.labels.data, obj.labels.selectionBit));
        obj.selection = core.MibLabels(selData, meta);
        if obj.maskExist
            maskData = uint8(bitget(obj.labels.data, obj.labels.maskBit));
            obj.mask = core.MibLabels(maskData, meta);
        end
    end

    % Allocate model data with the appropriate MATLAB class
    switch modelType
        case 255
            newData = zeros(dims, 'uint8');
            meta{'imgClass'} = 'uint8';
        case 65535
            newData = zeros(dims, 'uint16');
            meta{'imgClass'} = 'uint16';
        case 4294967295
            newData = zeros(dims, 'uint32');
            meta{'imgClass'} = 'uint32';
        otherwise
            newData = zeros(dims, 'uint8');
            meta{'imgClass'} = 'uint8';
    end

    obj.labels = core.MibLabels(newData, meta);
    obj.labels.maxMaterials = modelType;

    % Generate random display colours for large models
    if modelType >= 65535
        obj.labels.materialColors = rand(65535, 3);
    end
end

% Update model state
obj.modelExist = true;
obj.labels.labelsVariable = 'mibModel';
obj.labels.filename = '';   % not saved yet; Save As dialog will suggest the name
if isprop(obj.labels, 'maskFilename')
    obj.labels.maskFilename = obj.image.maskFilename;
end
obj.lastSegmSelection = [2 1];

if modelType < 256
    if ~isempty(modelMaterialNames)
        if size(modelMaterialNames, 1) < size(modelMaterialNames, 2)
            obj.labels.materialNames = modelMaterialNames';
        else
            obj.labels.materialNames = modelMaterialNames;
        end
        obj.labels.materialsCount = numel(modelMaterialNames);
    else
        obj.labels.materialNames = {};
        obj.labels.materialsCount = 0;
    end
    obj.selectedMaterial = 2;
    obj.selectedAddToMaterial = 2;
else
    obj.labels.materialNames = {'1'; '2'};
    obj.labels.materialsCount = 0;   % no pixel data yet
    obj.selectedMaterial = 3;
    obj.selectedAddToMaterial = 3;
end

obj.annotations.clearContents();
end
