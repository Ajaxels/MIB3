function [boundingBox, pixSize] = getSourceBoundingBox(filename, imageSize, loadOptions)
% GETSOURCEBOUNDINGBOX - Bounding box and voxel size of an image file, as MIB derives them when the file is opened.
%
% Syntax:
%   .. code-block:: matlab
%
%      [boundingBox, pixSize] = deepmib.getSourceBoundingBox(filename, imageSize)
%      [boundingBox, pixSize] = deepmib.getSourceBoundingBox(filename, imageSize, loadOptions)
%
% Used by DeepMIB prediction to copy the physical position of each predicted image
% to the model and score files written from it, and by the preprocessing for
% prediction to keep it in the ``.mibImg`` files that the prediction reads later.
% Only the metadata of the file is read (``loader.loadMetadata``), not the pixels.
%
% The rules are those of ``core.MibImage.initialize``, so the box equals the one
% MIB shows after opening the same file:
%
%   1. ``BoundingBox x1 x2 y1 y2 z1 z2`` at the start of ``ImageDescription``
%      (TIF written by MIB, AmiraMesh, HDF5 with a MIB header);
%   2. the ``BoundingBox`` key of the loader metadata overrides it (zarr
%      ``mibBoundingBox``, MIB ``.model`` files, ``.mibImg`` files written with
%      ``options.boundingBox``);
%   3. otherwise ``[0, (w-1)*pixSize.x, 0, (h-1)*pixSize.y, 0, (d-1)*pixSize.z]``
%      with each dimension taken as at least 2, the same "Amira single-layer"
%      tweak as ``core.MibImage.updateBoundingBox``. This default still carries
%      the voxel size of the image (TIF resolution tags, BioFormats metadata).
%
% A file whose metadata can not be read is not an error: a warning is printed
% and empty outputs are returned, so the caller writes its results without a
% bounding box, as it would without this function.
%
% Input Arguments:
%   - **filename** - [char] full path to the image file
%   - **imageSize** - [1x3 double] ``[height, width, depth]`` of the image in
%     pixels; ``depth`` is 1 for a 2D image. Used only for rule 3. When the
%     results are resampled back to the size of the image (prediction with
%     ``P_ImageDownsamplingFactor``), pass the size of the image, not of the
%     downsampled copy
%   - **loadOptions** *(optional)* - struct with the options used to read the
%     image, so the same loader and the same BioFormats series are used:
%
%     - ``.mibBioformatsCheck`` - [logical] use the BioFormats reader, default ``false``
%     - ``.BioFormatsIndices`` - [numeric] BioFormats series, default ``1``
%
% Output Arguments:
%   - **boundingBox** - [1x6 double] ``[xmin xmax ymin ymax zmin zmax]`` in
%     ``pixSize.units``, or ``[]`` when the metadata could not be read
%   - **pixSize** - struct with ``.x .y .z .units`` (and the other fields the
%     loader provides) as reported by the loader, or ``[]``
%
% Usage:
%   **Example 1** - bounding box of a 2D TIF file
%
%   .. code-block:: matlab
%
%      img = io.loadImagesWrapper('C:\data\Images\slice01.tif');
%      boundingBox = deepmib.getSourceBoundingBox('C:\data\Images\slice01.tif', size(img, 1:3));
%
%   **Example 2** - a series of a BioFormats file
%
%   .. code-block:: matlab
%
%      loadOptions = struct('mibBioformatsCheck', true, 'BioFormatsIndices', 2);
%      [boundingBox, pixSize] = deepmib.getSourceBoundingBox('C:\data\stack.czi', [1024 1024 50], loadOptions);
%
% See also:
%   core.MibImage.initialize, core.MibImage.updateBoundingBox, io.loadImagesWrapper

% Updates
%

if nargin < 3 || isempty(loadOptions); loadOptions = struct(); end
% the defaults of io.loadImagesWrapper, so the file is resolved to the same loader
if ~isfield(loadOptions, 'mibBioformatsCheck'); loadOptions.mibBioformatsCheck = false; end
if ~isfield(loadOptions, 'BioFormatsIndices'); loadOptions.BioFormatsIndices = 1; end
if ~isfield(loadOptions, 'verbose'); loadOptions.verbose = false; end
if ~isfield(loadOptions, 'waitbar'); loadOptions.waitbar = false; end
if ~isfield(loadOptions, 'silentMode'); loadOptions.silentMode = true; end

boundingBox = [];
pixSize = [];
try
    reader = 'Default';
    if loadOptions.mibBioformatsCheck; reader = 'BioFormats'; end
    extReg = io.ExtensionRegistryLoad();
    loaderInfo = extReg.resolveLoader(filename, 'Standard', reader);
    if ischar(loaderInfo)
        error('deepmib:getSourceBoundingBox:unsupportedFormat', '%s', loaderInfo);
    end
    loader = io.LoaderFactory.create(loaderInfo, loadOptions);
    imginfo = loader.loadMetadata({filename}, loadOptions);
catch err
    warning('deepmib:getSourceBoundingBox:noMetadata', ...
        'The bounding box of %s is not known, the results are saved without it:\n%s', filename, err.message);
    return;
end
if ~isa(imginfo, 'dictionary') || numEntries(imginfo) == 0
    return;     % the loader reported its own error
end

pixSize = struct('x', 1, 'y', 1, 'z', 1, 'units', 'um');
if isKey(imginfo, "pixSize") && isstruct(imginfo{"pixSize"})
    pixSize = imginfo{"pixSize"};
end

% rule 1: BoundingBox prefix of ImageDescription
coords = [];
if isKey(imginfo, "ImageDescription") && ~isempty(imginfo{"ImageDescription"})
    imgDesc = core.MibImage.splitImageDescription(imginfo{"ImageDescription"});
    coords = sscanf(imgDesc, 'BoundingBox %f %f %f %f %f %f');
end
if numel(coords) == 6
    boundingBox = coords(:)';
end

% rule 2: a box resolved by the loader wins
if isKey(imginfo, "BoundingBox") && numel(imginfo{"BoundingBox"}) == 6
    boundingBox = reshape(double(imginfo{"BoundingBox"}), 1, 6);
end

% rule 3: the extent of the image from its voxel size
if isempty(boundingBox)
    imageSize(end+1:3) = 1;
    boundingBox = [0, (max([imageSize(2), 2]) - 1) * pixSize.x, ...
                   0, (max([imageSize(1), 2]) - 1) * pixSize.y, ...
                   0, (max([imageSize(3), 2]) - 1) * pixSize.z];
end
end
