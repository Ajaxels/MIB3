function imOut = storeLoadImages(fn, getDataOptions)
% STORELOADIMAGES - Load an image file for use with ``imageDatastore`` in DeepMIB.
%
% Syntax:
%   .. code-block:: matlab
%
%      imOut = storeLoadImages(fn, getDataOptions)
%
% Input Arguments:
%   - **fn** - [string] full path to the image file
%   - **getDataOptions** - struct with load options:
%
%     - ``.mibBioformatsCheck`` - [logical] ``true`` to use the BioFormats reader,
%       ``false`` for the standard reader
%     - ``.BioFormatsIndices`` - [numeric] series index for BioFormats, or slice
%       index within a TIF file (default: ``1``)
%     - ``.Workflow`` - [char] active workflow (``obj.BatchOpt.Workflow{1}``)
%     - ``.randomCrop`` - ``[cropH cropW]`` for random cropping; ``[0 0]`` to disable
%     - ``.ZarrLevel`` - *(optional)* [numeric] 1-based pyramid level read from a
%       zarr store (``fn`` is then the store folder); passed on to the zarr
%       loader by ``io.loadImagesWrapper``. A level the store does not have is
%       ignored by the loader, which then asks for the level in a dialog, so
%       callers check it beforehand
%     - ``.ZarrGroupPath`` - *(optional)* [char] image group inside a zarr
%       container, so a container holding several images is read without the
%       group picker
%
% Output Arguments:
%   - **imOut** - loaded image array
%

if nargin < 2
    getDataOptions = struct();
end
if ~isfield(getDataOptions, 'mibBioformatsCheck'); getDataOptions.mibBioformatsCheck = false; end
if ~isfield(getDataOptions, 'BioFormatsIndices'); getDataOptions.BioFormatsIndices = 1; end
if ~isfield(getDataOptions, 'randomCrop'); getDataOptions.randomCrop = [0 0]; end
if ~isfield(getDataOptions, 'Workflow'); getDataOptions.Workflow = '2D Semantic'; end

[~, ~, fnExt] = fileparts(fn);

if getDataOptions.mibBioformatsCheck % use BioFormats reader
    imOut = io.loadImagesWrapper(fn, getDataOptions);
elseif ismember(fnExt, {'.mibImg', '.mask', '.mibCat'})
    % load MATLAB MAT-based formats
    inp = load(fn, '-mat');
    if isfield(inp, 'imgVariable')
        imOut = inp.(inp.imgVariable);
    else
        f = fields(inp);
        imOut = inp.(f{1});
    end
    if ndims(imOut) < 5
        sz = ones(1, 5);
        sz(1:ndims(imOut)) = size(imOut);
        imOut = reshape(imOut, sz);
    end
else
    imOut = io.loadImagesWrapper(fn, getDataOptions);
end

% do a random crop of the patch if needed
if getDataOptions.randomCrop(1) ~= 0
    % Generate random coordinates for the top-left corner of the crop
    dY = randi(size(imOut, 1) - getDataOptions.randomCrop(1) + 1);
    dX = randi(size(imOut, 2) - getDataOptions.randomCrop(2) + 1);

    % Perform the random crop
    imOut = imOut(dY:dY+getDataOptions.randomCrop(1)-1, dX:dX+getDataOptions.randomCrop(2)-1, :, :, :);
end
end
