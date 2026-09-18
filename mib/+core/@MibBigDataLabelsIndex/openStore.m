function openStore(obj, storePath, imageReference)
% OPENSTORE - Attach an existing label pyramid, registered against the open image.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.openStore(storePath, imageReference)
%
% Opens every level of an OME-Zarr label group as an ``io.zarr.Array`` and places
% the pyramid inside the **image's** scale space rather than its own. The store is
% never written to, and nothing is read here except metadata plus one small
% pyramid level - the finest that fits a fixed voxel budget - used to estimate the
% object count.
%
% **The registration is the point.** A label pyramid published from a coarse level
% down - which is what a whole-volume inference segmentation is - has its own
% level 0 somewhere in the middle of the image's magnification axis:
% ``jrc_mus-kidney``'s ``nuc`` starts at 128 nm, which is the EM's ``s4``.
% :attr:`modelScaleFactors` is therefore ``[16 32 64 128 256]`` and not
% ``[1 2 4 8 16]``. ``io.loaders.OmeZarrMetadataUtils.registerLevelScales`` derives
% that and refuses the pairing outright when the two pyramids do not cover the same
% volume, which is the only thing standing between a scale factor and labels placed
% at the origin at the wrong size.
%
% **The dimensions come from the image, not the store.** ``height``/``width``/
% ``depth`` are the image's full-resolution extent, because that is the coordinate
% system every caller asks in - ``options.x/y/z`` are dataset coordinates, and
% :meth:`getData` maps them onto whichever level serves the request.
%
% ``pixSize`` and ``boundingBox`` are deliberately **not** set here; they belong to
% the dataset and are applied by the caller through ``MibDataset.setPixSize``, the
% same way every other model type receives them.
%
% Input Arguments:
%   - **storePath** - [char|string] path or URL of the OME-Zarr label group; v2
%     (``.zattrs``) and v3 (``zarr.json``) are both detected, since the level arrays
%     are opened through ``io.zarr.Array``, which reads either
%   - **imageReference** - [struct] describing the image this attaches to, with
%     fields:
%
%     - ``.shapeYXZ`` - [1x3 numeric] the image's full-resolution ``[y x z]`` voxel
%       counts
%     - ``.voxelSizesXYZ`` - [nImageLevels x 3 numeric] voxel size ``[x y z]`` per
%       image level **in micrometres**, row 1 being full resolution; micrometres
%       because the two stores may declare different units and an absolute one is
%       the only one that cannot be misread
%     - ``.outerBoxUm`` - [1x6 numeric] the image's outer physical extent
%       ``[xmin xmax ymin ymax zmin zmax]`` in micrometres, edge-based as
%       ``OmeZarrMetadataUtils.outerBoundingBox`` returns it
%
% Raises an error rather than half-attaching: an unreadable store, a group with no
% multiscales, or a pyramid that does not register all throw, because the caller
% decided this route was available before getting here and a silent fallback would
% put the labels somewhere plausible and wrong.

storePath = char(storePath);

% The native engine reads both zarr formats with no external dependency, so only
% the opt-in python backend has anything to verify up front.
if io.zarr.Config.isPython()
    try
        io.zarr.PyBackend.ensureLoaded();
    catch ME
        error('core:MibBigDataLabelsIndex:openStore', ...
            ['Cannot start the Python Zarr backend selected in\n' ...
             'Preferences -> Input/output -> Zarr library:\n%s\n' ...
             'Switching that setting to ''native'' (zarrMex) reads these stores without python.'], ...
            ME.message);
    end
    io.zarr.PyBackend.ensureRemoteSupport(storePath);
end

% ---- the group's multiscales ---------------------------------------------
% Both formats are probed rather than declared: this class is reached from a URL
% the user picked and from a batch protocol that only records the path, so the
% format is not always known by the caller. Two small metadata reads at worst.
attributes  = io.loaders.OmeZarrMetadataUtils.readGroupAttributes(storePath, 3);
multiscales = io.loaders.OmeZarrMetadataUtils.extractMultiscales(attributes);
if isempty(multiscales)
    attributes  = io.loaders.OmeZarrMetadataUtils.readGroupAttributes(storePath, 2);
    multiscales = io.loaders.OmeZarrMetadataUtils.extractMultiscales(attributes);
end
if isempty(multiscales)
    error('core:MibBigDataLabelsIndex:openStore', ...
        'No OME-Zarr multiscales metadata found at "%s"', storePath);
end
multiscale = multiscales(1);

axisOrder  = io.loaders.OmeZarrMetadataUtils.extractAxisOrder(multiscale);
axisLabels = io.loaders.OmeZarrMetadataUtils.axisOrderToLabels(axisOrder);
nAxes      = numel(axisLabels);
yIndex = find(strcmp(axisLabels, 'y'), 1);
xIndex = find(strcmp(axisLabels, 'x'), 1);
zIndex = find(strcmp(axisLabels, 'z'), 1);

storeUnit = io.loaders.OmeZarrMetadataUtils.extractAxisUnit(multiscale, yIndex);
toMicrometres = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(storeUnit);

levelNames = {multiscale.datasets.path};
nLevels    = numel(levelNames);

obj.modelArrays     = cell(1, nLevels);
obj.modelArrayMeta  = cell(1, nLevels);
obj.modelLevelPaths = cell(1, nLevels);
obj.modelLevelNames = cell(1, nLevels);
levelSizesYXZ       = zeros(nLevels, 3);
levelVoxelSizesXYZ  = zeros(nLevels, 3);
level0CentreBox     = [];
storeDataType       = '';

for levelIndex = 1:nLevels
    levelName = char(levelNames{levelIndex});
    obj.modelLevelNames{levelIndex} = levelName;

    if io.RemoteStore.isRemote(storePath)
        levelPath = io.RemoteStore.join(storePath, levelName);
    else
        levelPath = fullfile(storePath, levelName);
    end

    levelArray = io.zarr.Array(levelPath);
    levelMeta  = levelArray.info();
    obj.modelArrays{levelIndex}     = levelArray;
    obj.modelArrayMeta{levelIndex}  = levelMeta;
    obj.modelLevelPaths{levelIndex} = levelPath;

    shape = double(levelMeta.shape);
    levelSizesYXZ(levelIndex, :) = [ ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, yIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, xIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, zIndex, 1)];

    levelScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT( ...
        multiscale.datasets(levelIndex).coordinateTransformations, nAxes);
    levelVoxelSizesXYZ(levelIndex, :) = [ ...
        io.loaders.OmeZarrMetadataUtils.safeGetScale(levelScales, xIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetScale(levelScales, yIndex, 1), ...
        io.loaders.OmeZarrMetadataUtils.safeGetScale(levelScales, zIndex, 1)];

    if levelIndex == 1
        level0CentreBox = io.loaders.OmeZarrMetadataUtils.worldBoundingBox( ...
            multiscale, 1, shape);
        if isfield(levelMeta, 'dataType'); storeDataType = char(string(levelMeta.dataType)); end
    end
end

% ---- register the pyramid in the image's scale space ---------------------
if isempty(level0CentreBox)
    error('core:MibBigDataLabelsIndex:openStore', ...
        'The label group at "%s" declares no usable coordinate transformations.', storePath);
end
level0OuterBoxUm = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
    level0CentreBox, levelVoxelSizesXYZ(1, :)) * toMicrometres;

registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
    levelVoxelSizesXYZ * toMicrometres, level0OuterBoxUm, ...
    imageReference.voxelSizesXYZ, imageReference.outerBoxUm);
if ~registration.ok
    error('core:MibBigDataLabelsIndex:openStore', ...
        'These labels cannot be placed on the open image.\n%s', registration.reason);
end

obj.modelStorePath    = string(storePath);
obj.modelAxisOrder    = axisOrder;
obj.modelLevelSizes   = levelSizesYXZ;
obj.modelScaleFactors = registration.scaleFactorsYXZ;
obj.imageScaleFactors = registration.referenceScaleFactorsYXZ;

% ---- dimensions are the IMAGE's, at full resolution ---------------------
imageShapeYXZ = reshape(double(imageReference.shapeYXZ), 1, 3);
obj.height    = imageShapeYXZ(1);
obj.width     = imageShapeYXZ(2);
obj.depth     = imageShapeYXZ(3);
obj.colors    = 1;
obj.time      = 1;
obj.dim_yxzct = [obj.height, obj.width, obj.depth, 1, 1];

% ---- model type: wide enough for the store's own values -----------------
% The two existing MIB families above 255 are 65535 (uint16) and 4294967295
% (uint32). An unknown dtype is assumed to fit 16 bits, which every published
% label store does; a wider store gets the wider family rather than a wrapped id.
if needsWideLabelType(storeDataType)
    obj.maxMaterials = 4294967295;
    obj.dataClass    = 'uint32';
else
    obj.maxMaterials = 65535;
    obj.dataClass    = 'uint16';
end
obj.maxInt = obj.maxMaterials;

% Materials follow the convention already in place for models above 255
% (controllers.MibSegmentation.updateMaterialsTable:81-83): exactly two slots,
% each carrying its material INDEX in the name string, over a cyclic palette.
obj.materialNames  = {'1'; '2'};
obj.materialColors = rand(65535, 3);
obj.labelsVariable = 'mibModel';
obj.filename       = '';
obj.exists         = true;

% ---- how many objects, from the finest level worth a single request ----
% Reading the COARSEST level is not enough, which only a deep pyramid shows:
% jrc_mus-kidney-2's nuc bottoms out at 3 x 3 x 3, by which point every nucleus
% has been downsampled out of existence and the count comes back as 1 - a lower
% bound so loose it says nothing at all. Walk towards finer levels instead and
% take the last one still inside a small read budget; here that is s3 at about a
% megavoxel rather than s8 at 27 voxels.
%
% Still a LOWER bound - a thin structure can lose its rarest ids well before that
% level - and still the right trade against scanning a 510 GiB remote volume, the
% alternative core.MibLabels.countMaterials would take. Nothing here needs an
% exact count: materialsCount feeds MibDataset.addMaterial, which this class
% blocks.
probeVoxelBudget = 2e6;   % about 4 MB at uint16, one ranged request
probeLevel = nLevels;
for levelIndex = nLevels:-1:1
    if prod(levelSizesYXZ(levelIndex, :)) > probeVoxelBudget; break; end
    probeLevel = levelIndex;
end

obj.materialsCount = 1;
for levelIndex = probeLevel:nLevels
    try
        block = obj.modelArrays{levelIndex}.read();
    catch
        % An unreadable level says nothing about the volume and must not stop the
        % attach - the count is cosmetic, the registration is not. Fall back to a
        % coarser, smaller one rather than giving up.
        continue;
    end
    highestId = double(max(block(:)));
    if highestId > 0; obj.materialsCount = highestId; end
    break;   % the first level that reads is the answer; coarser ones only lose ids
end
end

% =========================================================================
function tf = needsWideLabelType(dataType)
% NEEDSWIDELABELTYPE - Does this store's dtype hold ids past 65535?
% Both zarr spellings are accepted: v3 declares 'uint32', v2's numpy typestring
% arrives as '<u4'. Anything unrecognised is assumed to fit 16 bits, which is
% what every published label store uses.
tf = ismember(lower(char(dataType)), ...
    {'uint32', 'int32', 'uint64', 'int64', ...
     '<u4', '>u4', '|u4', 'u4', '<i4', '>i4', 'i4', ...
     '<u8', '>u8', 'u8', '<i8', '>i8', 'i8'});
end
