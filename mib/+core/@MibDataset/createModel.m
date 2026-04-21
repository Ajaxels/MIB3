function createModel(obj, modelType, modelMaterialNames)
% function createModel(obj, modelType, modelMaterialNames)
% Create an empty model: allocate memory for a new model
%
% This function reinitializes the labels layer (obj.labels) with a
% zero-filled matrix of the appropriate class and dimensions.
% When switching between the packed type-63 model (core.MibLabels63) and
% the separate-layer models (core.MibLabels, types 255/65535/4294967295),
% the selection and mask layers are converted automatically.
%
% Parameters:
% modelType: [@em optional] a number that defines the type of model
% - @b 63  - a segmentation model with up to 63 materials; 'Labels', 'Mask',
%             and 'Selection' layers are packed in a single uint8 matrix
%             (core.MibLabels63) to reduce memory consumption
% - @b 255 - a segmentation model with up to 255 materials; layers stored
%             in separate matrices (core.MibLabels)
% - @b 65535 - a segmentation model with up to 65535 materials
% - @b 4294967295 - a segmentation model with up to 4294967295 materials
% modelMaterialNames: [@em optional] a cell array with names of materials;
%   not used for modelType > 255
%
% Return values:
%

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.createModel(63);  // allocate a new type-63 model @endcode
% @code obj.mibModel.I{obj.mibModel.id}.createModel(255, {'Nucleus','Cytoplasm'});  // type-255 with names @endcode

% Updates
% Ported from MIB2 mibImage.createModel

if nargin < 3; modelMaterialNames = []; end
if nargin < 2; modelType = NaN; end

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

if modelType == 63
    if currentModelType == 63
        % Already type 63: clear model bits (bits 1–6), preserve mask (bit 7)
        % and selection (bit 8)
        if obj.labels.exists
            obj.labels.data{1} = bitand(obj.labels.data{1}, uint8(192));
            [h, w, d, ~, t] = size(obj.labels.data{1});
            obj.labels.height    = h;
            obj.labels.width     = w;
            obj.labels.depth     = d;
            obj.labels.colors    = 1;
            obj.labels.time      = t;
            obj.labels.dim_yxzct = [h, w, d, 1, t];
        else
            obj.labels = core.MibLabels63(zeros(dims, 'uint8'), meta);
        end
    else
        % Was type 255+: pack existing selection/mask into a single uint8 matrix
        newData = zeros(dims, 'uint8');
        if obj.selection.exists
            selData = obj.selection.data{1};
            newData(selData == 1) = bitset(newData(selData == 1), 8, 1);
        end
        if obj.maskExist && obj.mask.exists
            maskData = obj.mask.data{1};
            newData(maskData == 1) = bitset(newData(maskData == 1), 7, 1);
        end
        obj.labels    = core.MibLabels63(newData, meta);
        % Clear the now-redundant separate layers
        obj.selection = core.MibLabels([], meta);
        obj.mask      = core.MibLabels([], meta);
    end
else
    % Switching to type 255, 65535, or 4294967295
    if currentModelType == 63 && obj.labels.exists
        % Extract selection and mask from packed bits before replacing the labels
        selData = uint8(bitand(obj.labels.data{1}, uint8(128)) / 128);
        obj.selection = core.MibLabels(selData, meta);
        if obj.maskExist
            maskData = uint8(bitand(obj.labels.data{1}, uint8(64)) / 64);
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
[~, baseFn] = fileparts(obj.image.filename);
obj.labels.filename = sprintf('Labels_%s.model', baseFn);
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
