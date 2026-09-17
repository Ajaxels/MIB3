function groupSummary = probeGroup(obj, groupUrl)
% PROBEGROUP - Read a group's metadata and decide whether it can be opened.
%
% Syntax:
%   .. code-block:: matlab
%
%      groupSummary = obj.probeGroup(groupUrl)
%
% A group is openable when it carries an OME-NGFF ``multiscales`` attribute.
% When it does, the pyramid is described in the info panel and Open is enabled;
% otherwise Open stays disabled and the user is told to keep looking. Results
% are cached per URL for the session, so re-selecting a node is free.
%
% For ``LoadAs = Labels`` the dimensions are compared against the open image
% here, **before** Open is pressed, because a mismatch is silent otherwise:
% ``core.MibBigDataLabelsZarr2`` takes its extent from the label store itself
% and has no origin concept, so a sub-volume crop would be placed at the origin
% at the wrong scale rather than where it belongs.
%
% Input Arguments:
%   - **groupUrl** - [char] URL of the group to inspect
%
% Output Arguments:
%   - **groupSummary** - [struct] with ``.hasMultiscales``, ``.sizeYXZ``,
%     ``.levelCount``, ``.dataType``, ``.voxelSize``, ``.units``,
%     ``.annotationType``, ``.lines``
%
% ``annotationType`` is carried here rather than left to
% :meth:`readGroupPyramid` because the attributes are already in hand and
% :meth:`resolveLabelRoute` needs it on the path where the dimensions already
% match - which returns before any pyramid is read, and would otherwise pay a
% request per level on the common working case just to ask one question.

groupSummary = struct('hasMultiscales', false, 'sizeYXZ', [0 0 0], ...
    'levelCount', 0, 'dataType', '', 'voxelSize', [0 0 0], 'units', '', ...
    'annotationType', '', 'lines', {{''}});

if isempty(groupUrl) || isempty(obj.zarrFormat); return; end

cacheKey = string(groupUrl);
if isKey(obj.probeCache, cacheKey)
    cached = obj.probeCache{cacheKey};
    groupSummary = cached;
    obj.applySummary(groupUrl, groupSummary);
    return;
end

zarrFormatNumber = 3;
if strcmp(obj.zarrFormat, 'zarr2'); zarrFormatNumber = 2; end

attributes = io.loaders.OmeZarrMetadataUtils.readGroupAttributes(groupUrl, zarrFormatNumber);
multiscales = io.loaders.OmeZarrMetadataUtils.extractMultiscales(attributes);

if isempty(multiscales)
    groupSummary.lines = {'This group has no image pyramid.', ...
        'Expand it to look inside.'};
    obj.probeCache{cacheKey} = groupSummary;
    obj.applySummary(groupUrl, groupSummary);
    return;
end

if isfield(attributes, 'cellmap') && isstruct(attributes.cellmap) && ...
        isfield(attributes.cellmap, 'annotation') && ...
        isstruct(attributes.cellmap.annotation) && ...
        isfield(attributes.cellmap.annotation, 'annotation_type') && ...
        isstruct(attributes.cellmap.annotation.annotation_type) && ...
        isfield(attributes.cellmap.annotation.annotation_type, 'type')
    groupSummary.annotationType = ...
        char(string(attributes.cellmap.annotation.annotation_type.type));
end

multiscale = multiscales(1);
axisOrder  = io.loaders.OmeZarrMetadataUtils.extractAxisOrder(multiscale);
axisLabels = io.loaders.OmeZarrMetadataUtils.axisOrderToLabels(axisOrder);
yIndex = find(strcmp(axisLabels, 'y'), 1);
xIndex = find(strcmp(axisLabels, 'x'), 1);
zIndex = find(strcmp(axisLabels, 'z'), 1);

levelPaths = {multiscale.datasets.path};
groupSummary.levelCount = numel(levelPaths);

% Level 0 describes the full-resolution extent, which is what the user is
% choosing between; the coarser levels only change how it is served.
levelUrl = io.RemoteStore.join(groupUrl, levelPaths{1});
if zarrFormatNumber == 2
    arrayMeta = io.RemoteStore.readJson(io.RemoteStore.join(levelUrl, '.zarray'));
else
    arrayMeta = io.RemoteStore.readJson(io.RemoteStore.join(levelUrl, 'zarr.json'));
end

if ~isempty(arrayMeta) && isfield(arrayMeta, 'shape')
    shape = double(arrayMeta.shape(:))';
    groupSummary.sizeYXZ = [ ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, yIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, xIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, zIndex, 1)];
    % Reported as the MATLAB class the loader will actually produce, not the
    % raw numpy typestring ('|u1'), which means nothing to a user.
    if isfield(arrayMeta, 'dtype')
        groupSummary.dataType = ...
            io.loaders.Zarr2VirtualSetupLoader.zarrV2TypeToMatlabClass(arrayMeta.dtype);
    elseif isfield(arrayMeta, 'data_type')
        groupSummary.dataType = char(string(arrayMeta.data_type));
    end
end

levelScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT( ...
    multiscale.datasets(1).coordinateTransformations, numel(axisLabels));
groupSummary.voxelSize = [ ...
    io.loaders.OmeZarrMetadataUtils.safeGetDim(levelScales, yIndex, 1), ...
    io.loaders.OmeZarrMetadataUtils.safeGetDim(levelScales, xIndex, 1), ...
    io.loaders.OmeZarrMetadataUtils.safeGetDim(levelScales, zIndex, 1)];
groupSummary.units = io.loaders.OmeZarrMetadataUtils.extractAxisUnit(multiscale, yIndex);
groupSummary.hasMultiscales = true;

groupSummary.lines = { ...
    sprintf('Levels : %d  (%s .. %s)', groupSummary.levelCount, levelPaths{1}, levelPaths{end}), ...
    sprintf('Axes   : %s', axisOrder), ...
    sprintf('Size   : %d x %d x %d  (X x Y x Z)', ...
        groupSummary.sizeYXZ(2), groupSummary.sizeYXZ(1), groupSummary.sizeYXZ(3)), ...
    sprintf('Type   : %s', groupSummary.dataType), ...
    sprintf('Voxel  : %g x %g x %g %s', groupSummary.voxelSize(2), ...
        groupSummary.voxelSize(1), groupSummary.voxelSize(3), groupSummary.units), ...
    sprintf('Format : OME-Zarr %s%s', strrep(obj.zarrFormat, 'zarr', 'v'), ...
        obj.pythonNote())};

obj.probeCache{cacheKey} = groupSummary;
obj.applySummary(groupUrl, groupSummary);
end
