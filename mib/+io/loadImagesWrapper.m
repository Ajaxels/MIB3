function img = loadImagesWrapper(filename, options)
% function img = loadImagesWrapper(filename, options)
% Load a single image file using MIB3 LoaderFactory; returns [H, W, Z, C, T].
%
% Parameters:
% filename: [char] full path to the image file
% options: [@em optional, struct] loading options
%   .mibBioformatsCheck - [logical] use BioFormats reader (default: false)
%   .BioFormatsIndices - [numeric] BioFormats series index (default: 1)
%   .verbose - [logical] show timing info (default: false)
%
% Return values:
% img: image array [height, width, depth, color, time]
%
% @b Examples:
% @code
% % Load a standard TIF image (returns [H, W, 1, C, 1] for a single slice)
% img = io.loadImagesWrapper('C:\data\image.tif');
% @endcode
% @code
% % Load an Amira mesh file without verbose output
% img = io.loadImagesWrapper('C:\data\stack.am', struct('verbose', false));
% @endcode
% @code
% % Load a PNG file and check output dimensions
% img = io.loadImagesWrapper('C:\data\patch.png');
% fprintf('Size: %d x %d x %d x %d x %d\n', size(img,1), size(img,2), size(img,3), size(img,4), size(img,5));
% @endcode
% @code
% % Load with BioFormats reader, selecting series index 2
% opts.mibBioformatsCheck = true;
% opts.BioFormatsIndices = 2;
% img = io.loadImagesWrapper('C:\data\multiSeries.czi', opts);
% @endcode
% @code
% % Use as a ReadFcn in an imageDatastore
% opts.verbose = false;
% opts.mibBioformatsCheck = false;
% opts.BioFormatsIndices = 1;
% ds = imageDatastore('C:\data\Images', 'FileExtensions', '.tif', ...
%     'ReadFcn', @(fn) io.loadImagesWrapper(fn, opts));
% img = read(ds);   % returns [H, W, Z, C, T]
% @endcode

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

% loader already returns [H, W, Z, C, T] — ensure 5D
if ndims(img) < 5
    sz = ones(1, 5);
    sz(1:ndims(img)) = size(img);
    img = reshape(img, sz);
end
end
