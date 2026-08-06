function img = loadImagesWrapper(filename, options)
% LOADIMAGESWRAPPER - Load a single image file using MIB3 LoaderFactory; returns [H, W, Z, C, T].
%
% Syntax:
%   function img = loadImagesWrapper(filename, options)
%
% Input Arguments:
%   - **filename** - [char] full path to the image file
%   - **options** - *(optional)* struct with loading options:
%
%     - ``.mibBioformatsCheck`` - (logical) use BioFormats reader; default ``false``
%     - ``.BioFormatsIndices`` - (numeric) BioFormats series index; default ``1``
%     - ``.verbose`` - (logical) show timing info; default ``false``
%
% Output Arguments:
%   - **img** - image array [height, width, depth, color, time]
%
% Usage:
%   **Example 1** - Load a standard TIF image (returns [H, W, 1, C, 1] for a single slice)
%
%   .. code-block:: matlab
%
%
%     img = io.loadImagesWrapper('C:\data\image.tif');
%
%   **Example 2** - Load an Amira mesh file without verbose output
%
%   .. code-block:: matlab
%
%
%     img = io.loadImagesWrapper('C:\data\stack.am', struct('verbose', false));
%
%   **Example 3** - Load a PNG file and check output dimensions
%
%   .. code-block:: matlab
%
%
%     img = io.loadImagesWrapper('C:\data\patch.png');
%     fprintf('Size: %d x %d x %d x %d x %d\n', size(img,1), size(img,2), size(img,3), size(img,4), size(img,5));
%
%   **Example 4** - Load with BioFormats reader, selecting series index 2
%
%   .. code-block:: matlab
%
%
%     opts.mibBioformatsCheck = true;
%     opts.BioFormatsIndices = 2;
%     img = io.loadImagesWrapper('C:\data\multiSeries.czi', opts);
%
%   **Example 5** - Use as a ReadFcn in an imageDatastore
%
%   .. code-block:: matlab
%
%
%     opts.verbose = false;
%     opts.mibBioformatsCheck = false;
%     opts.BioFormatsIndices = 1;
%     ds = imageDatastore('C:\data\Images', 'FileExtensions', '.tif', ...
%         'ReadFcn', @(fn) io.loadImagesWrapper(fn, opts));
%     img = read(ds);   % returns [H, W, Z, C, T]
%
%   **Example 6** - Discover supported extensions, then load a file
%
%   .. code-block:: matlab
%
%
%     extReg = io.ExtensionRegistryLoad();
%     standardExts   = extReg.getAllowedExtensions('Standard', 'Default');
%     bioformatsExts = extReg.getAllowedExtensions('Standard', 'BioFormats');
%     img = io.loadImagesWrapper('C:\data\image.tif');
%

if nargin < 2; options = struct(); end
if ~isfield(options, 'mibBioformatsCheck'); options.mibBioformatsCheck = false; end
if ~isfield(options, 'BioFormatsIndices'); options.BioFormatsIndices = 1; end
if ~isfield(options, 'verbose'); options.verbose = false; end
if ~isfield(options, 'waitbar'); options.waitbar = false; end
if ~isfield(options, 'silentMode'); options.silentMode = true; end
if ~isfield(options, 'imgStretch'); options.imgStretch = 0; end

reader = 'Default';
if options.mibBioformatsCheck; reader = 'BioFormats'; end

extReg = io.ExtensionRegistryLoad();
loaderInfo = extReg.resolveLoader(filename, 'Standard', reader);
if ischar(loaderInfo)
    error('io:loadImagesWrapper:unsupportedFormat', '%s', loaderInfo);
end

loader = io.LoaderFactory.create(loaderInfo, options);
[imginfo, files] = loader.loadMetadata({filename}, options);
[img, ~] = loader.loadImages(files, imginfo, options);

% loader already returns [H, W, Z, C, T] - ensure 5D
if ndims(img) < 5
    sz = ones(1, 5);
    sz(1:ndims(img)) = size(img);
    img = reshape(img, sz);
end
end
