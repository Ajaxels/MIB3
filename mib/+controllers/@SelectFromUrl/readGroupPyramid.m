function pyramidInfo = readGroupPyramid(obj, groupUrl)
% READGROUPPYRAMID - Read everything about one OME-Zarr group needed to place it in space.
%
% Syntax:
%   .. code-block:: matlab
%
%      pyramidInfo = obj.readGroupPyramid(groupUrl)
%
% Goes further than :meth:`probeGroup`, which only describes a group well enough
% to show it in the info panel. Placing a group against another one needs every
% level's shape and world box, not just level 0's, because the level that pairs
% with a sibling pyramid is rarely level 0 - for the OpenOrganelle ground-truth
% crops it is ``s1``, since the crops are annotated at 2 nm and the EM they came
% from is 4 nm.
%
% Costs one metadata read per level, so results are cached per URL for the
% session alongside the ordinary probe cache.
%
% Input Arguments:
%   - **groupUrl** - [char] URL of the group
%
% Output Arguments:
%   - **pyramidInfo** - [struct] with fields:
%
%     - ``.ok`` - [logical] false when the group has no usable multiscales
%     - ``.multiscale`` - [struct] the first multiscales entry
%     - ``.axisOrder`` - [char] e.g. ``'zyx'``
%     - ``.levelNames`` - {1xN cell} level paths
%     - ``.levelShapesYXZ`` - [N x 3] voxel counts per level
%     - ``.levelVoxelSizesXYZ`` - [N x 3] voxel size per level, store units
%     - ``.levelWorldBoxes`` - [N x 6] centre-based boxes, store units
%     - ``.unit`` - [char] the store's length unit
%     - ``.dataType`` - [char] MATLAB class of level 0
%     - ``.annotation`` - [struct] the ``cellmap.annotation`` block, or empty
%     - ``.className`` - [char] annotated class name, or ``''``
%     - ``.annotationType`` - [char] ``'semantic_segmentation'`` /
%       ``'instance_segmentation'`` / ``''``
%     - ``.encoding`` - [struct] the ``absent``/``present``/``unknown`` values

pyramidInfo = struct('ok', false, 'multiscale', [], 'axisOrder', '', ...
    'levelNames', {{}}, 'levelShapesYXZ', [], 'levelVoxelSizesXYZ', [], ...
    'levelWorldBoxes', [], 'unit', 'um', 'dataType', '', 'annotation', [], ...
    'className', '', 'annotationType', '', 'encoding', []);

if isempty(groupUrl) || isempty(obj.zarrFormat); return; end

cacheKey = "pyramid:" + string(groupUrl);
if isKey(obj.probeCache, cacheKey)
    pyramidInfo = obj.probeCache{cacheKey};
    return;
end

zarrFormatNumber = 3;
if strcmp(obj.zarrFormat, 'zarr2'); zarrFormatNumber = 2; end

attributes  = io.loaders.OmeZarrMetadataUtils.readGroupAttributes(groupUrl, zarrFormatNumber);
multiscales = io.loaders.OmeZarrMetadataUtils.extractMultiscales(attributes);
if isempty(multiscales)
    obj.probeCache{cacheKey} = pyramidInfo;
    return;
end

multiscale = multiscales(1);
axisOrder  = io.loaders.OmeZarrMetadataUtils.extractAxisOrder(multiscale);
axisLabels = io.loaders.OmeZarrMetadataUtils.axisOrderToLabels(axisOrder);
yIndex = find(strcmp(axisLabels, 'y'), 1);
xIndex = find(strcmp(axisLabels, 'x'), 1);
zIndex = find(strcmp(axisLabels, 'z'), 1);

levelNames = {multiscale.datasets.path};
nLevels    = numel(levelNames);

levelShapesYXZ     = zeros(nLevels, 3);
levelVoxelSizesXYZ = zeros(nLevels, 3);
levelWorldBoxes    = zeros(nLevels, 6);
dataType           = '';

for levelIndex = 1:nLevels
    levelUrl = io.RemoteStore.join(groupUrl, levelNames{levelIndex});
    if zarrFormatNumber == 2
        arrayMeta = io.RemoteStore.readJson(io.RemoteStore.join(levelUrl, '.zarray'));
    else
        arrayMeta = io.RemoteStore.readJson(io.RemoteStore.join(levelUrl, 'zarr.json'));
    end
    if isempty(arrayMeta) || ~isfield(arrayMeta, 'shape')
        % A level the multiscales declares but the store does not hold. Fail the
        % whole group rather than silently pairing against a partial pyramid.
        obj.probeCache{cacheKey} = pyramidInfo;
        return;
    end
    shape = double(arrayMeta.shape(:))';

    levelShapesYXZ(levelIndex, :) = [ ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, yIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, xIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, zIndex, 1)];

    box = io.loaders.OmeZarrMetadataUtils.worldBoundingBox(multiscale, levelIndex, shape);
    if ~isempty(box); levelWorldBoxes(levelIndex, :) = box; end

    scales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT( ...
        multiscale.datasets(levelIndex).coordinateTransformations, numel(axisLabels));
    levelVoxelSizesXYZ(levelIndex, :) = [ ...
        io.loaders.OmeZarrMetadataUtils.safeGetScale(scales, xIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetScale(scales, yIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetScale(scales, zIndex, 1)];

    if levelIndex == 1
        if isfield(arrayMeta, 'dtype')
            dataType = io.loaders.Zarr2VirtualSetupLoader.zarrV2TypeToMatlabClass(arrayMeta.dtype);
        elseif isfield(arrayMeta, 'data_type')
            dataType = char(string(arrayMeta.data_type));
        end
    end
end

pyramidInfo.ok                 = true;
pyramidInfo.multiscale         = multiscale;
pyramidInfo.axisOrder          = axisOrder;
pyramidInfo.levelNames         = levelNames;
pyramidInfo.levelShapesYXZ     = levelShapesYXZ;
pyramidInfo.levelVoxelSizesXYZ = levelVoxelSizesXYZ;
pyramidInfo.levelWorldBoxes    = levelWorldBoxes;
pyramidInfo.unit               = io.loaders.OmeZarrMetadataUtils.extractAxisUnit(multiscale, yIndex);
pyramidInfo.dataType           = dataType;

% ---- COSEM cellmap annotation block ------------------------------------
% Each ground-truth group says what it is and how its values are encoded, so
% none of this has to be guessed from the group name. Absent for an ordinary
% image group, which is exactly how an image group is told apart from a label one.
if isfield(attributes, 'cellmap') && isstruct(attributes.cellmap) && ...
        isfield(attributes.cellmap, 'annotation')
    annotation = attributes.cellmap.annotation;
    pyramidInfo.annotation = annotation;
    if isfield(annotation, 'class_name')
        pyramidInfo.className = char(string(annotation.class_name));
    end
    if isfield(annotation, 'annotation_type') && isstruct(annotation.annotation_type)
        annotationType = annotation.annotation_type;
        if isfield(annotationType, 'type')
            pyramidInfo.annotationType = char(string(annotationType.type));
        end
        if isfield(annotationType, 'encoding')
            pyramidInfo.encoding = annotationType.encoding;
        end
    end
end

obj.probeCache{cacheKey} = pyramidInfo;
end
