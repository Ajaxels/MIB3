function dataset = getDataZarr(obj, type, orient, colChannel, options)
% function dataset = getDataZarr(obj, type, orient, colChannel, options)
% Read a subvolume from a Zarr pyramid dataset with optional slicing.
%
% Ported from MIB2/@MibImage/getDataZarr with the following adaptations:
%   - obj.data{1} instead of obj.img{1}  (zarr root path)
%   - obj.dataClass instead of obj.meta('imgClass')
%   - YX orientation is 3 (MIB3) not 4 (MIB2)
%   - Output dimension order [y, x, z, c, t] (MIB3) not [y, x, c, z, t] (MIB2)
%   - colChannel [] = all channels (MIB3) instead of NaN / 0 (MIB2)
%   - options.magFactor defaults to 1 (not obj.magFactor which lives in MibDataset)
%
% Parameters:
% type: type of layer — only 'image' is functional in virtual mode
% orient: [@em optional], orientation of returned dataset
%   @li 1 — xz: output [x, z, y, c, t]
%   @li 2 — yz: output [y, z, x, c, t]
%   @li 3 — yx: output [y, x, z, c, t]  (@b default)
% colChannel: [@em optional], vector of 1-based colour channel indices;
%             [] = all channels
% options: [@em optional], struct with optional fields:
%   @li .y, .x, .z  — [min, max] coordinate ranges (1-based, full resolution)
%   @li .t          — [tmin, tmax] time-point range
%   @li .magFactor  — magnification factor used to select pyramid level
%                     (default 1 = full resolution); ignored when pyramidLevel provided
%   @li .pyramidLevel — explicit pyramid level index (1-based); overrides magFactor
%
% Return values:
% dataset: 5D array [y, x, z, c, t] for orient==3;
%          [x, z, y, c, t] for orient==1;
%          [y, z, x, c, t] for orient==2
%|
% @b Examples:
% @code dataset = obj.getDataZarr('image');                         // full YX image @endcode
% @code dataset = obj.getDataZarr('image', 3, [1 2], options);     // channels 1+2 @endcode

%% Updates
%
if nargin < 5; options = struct(); end
if nargin < 4; colChannel = []; end
if nargin < 3; orient = []; end
if nargin < 2; type = 'image'; end

if isempty(orient); orient = 3; end

% --- select pyramid level -------------------------------------------------
if isfield(options, 'pyramidLevel') && ~isempty(options.pyramidLevel)
    levelIdx = options.pyramidLevel;
else
    options.pyramidLevel = [];
    if ~isfield(options, 'magFactor') || isempty(options.magFactor)
        options.magFactor = 1;   % MibVirtualImage has no magFactor; caller may override
    end
    effectiveScales = obj.pyramid.levelScaleFactors(:, 1);
    differences     = abs(effectiveScales - options.magFactor);
    [~, levelIdx]   = min(differences);
end

% --- map orient to pyramid dimension indices ------------------------------
% pyramid.levelImageSizes columns: [y, x, z]
switch orient
    case 1  % xz
        outDimYind = 3;   % data Z  -> screen Y
        outDimXind = 1;   % data Y  -> screen X
        outDimZind = 2;   % data X  -> screen Z
    case 2  % yz
        outDimYind = 1;   % data Y  -> screen Y
        outDimXind = 3;   % data Z  -> screen X
        outDimZind = 2;   % data X  -> screen Z
    case 3  % yx  (MIB3 default; MIB2 used case 4)
        outDimYind = 1;   % data Y  -> screen Y
        outDimXind = 2;   % data X  -> screen X
        outDimZind = 3;   % data Z  -> screen Z
    otherwise
        error('core.MibVirtualImage.getDataZarr: unsupported orientation %d', orient);
end

% --- full-resolution size and default coordinate ranges ------------------
fullSize = obj.pyramid.levelImageSizes(1, :);   % [y, x, z]

if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(outDimXind)]; end
if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(outDimYind)]; end
if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(outDimZind)]; end
if ~isfield(options, 't') || isempty(options.t); options.t = [1, obj.time]; end

% --- scale coordinates to the chosen pyramid level -----------------------
sf = obj.pyramid.levelScaleFactors(levelIdx, :);  % [yScale, xScale, zScale]

switch orient
    case 1  % xz
        Xidx = ceil(options.y ./ sf(outDimXind));
        Yidx = ceil(options.z ./ sf(outDimYind));
        Zidx = ceil(options.x ./ sf(outDimZind));
    case 2  % yz
        Xidx = ceil(options.z ./ sf(outDimXind));
        Yidx = ceil(options.y ./ sf(outDimYind));
        Zidx = ceil(options.x ./ sf(outDimZind));
    case 3  % yx
        Xidx = ceil(options.x ./ sf(outDimXind));
        Yidx = ceil(options.y ./ sf(outDimYind));
        Zidx = ceil(options.z ./ sf(outDimZind));
end
Tidx = [options.t(1), options.t(2)];

% clamp to valid pyramid-level dimensions
Xidx = [max([Xidx(1) 1]),  min([Xidx(2), obj.pyramid.levelImageSizes(levelIdx, outDimXind)])];
Yidx = [max([Yidx(1) 1]),  min([Yidx(2), obj.pyramid.levelImageSizes(levelIdx, outDimYind)])];
Zidx = [max([Zidx(1) 1]),  min([Zidx(2), obj.pyramid.levelImageSizes(levelIdx, outDimZind)])];
Tidx = [max([Tidx(1) 1]),  min([Tidx(2), obj.time])];

% convert to 0-based indices for Python
Xlim = Xidx - 1;
Ylim = Yidx - 1;
Zlim = Zidx - 1;
Tlim = Tidx - 1;

% --- colour selection (0-based for Python) --------------------------------
if strcmp(type, 'image')
    if isempty(colChannel)
        Clim = (1:obj.colors) - 1;    % all channels
    else
        Clim = colChannel - 1;
    end
end

% --- zarr path for this level --------------------------------------------
zarrPathLevel = sprintf('%s/%s', obj.data{1}, obj.pyramid.levelNames{levelIdx});

% --- read subvolume from zarr via Python ---------------------------------
% zarr stores as [t, c, z, y, x]; Python slicing is 0-based half-open
sliceStr = sprintf('%d:%d, %d:%d, %d:%d, %d:%d, %d:%d', ...
    Tlim(1), Tlim(end)+1, Clim(1), Clim(end)+1, ...
    Zlim(1), Zlim(end)+1, Ylim(1), Ylim(end)+1, Xlim(1), Xlim(end)+1);

block = pyrun({ ...
    sprintf("z = zarr.open('%s')", zarrPathLevel), ...
    sprintf("a = np.array(z[%s], dtype=z.dtype)", sliceStr) ...
    }, "a");

% --- convert to MATLAB class and permute to MIB3 [y, x, z, c, t] --------
% zarr block arrives as [t, c, z, y, x] (dims 1..5 in MATLAB after cast)
dataset = cast(block, obj.dataClass);

switch orient
    case 1  % xz: [t,c,z,y,x] -> [x, z, y, c, t]
        dataset = permute(dataset, [5 3 4 2 1]);
    case 2  % yz: [t,c,z,y,x] -> [y, z, x, c, t]
        dataset = permute(dataset, [4 3 5 2 1]);
    case 3  % yx: [t,c,z,y,x] -> [y, x, z, c, t]
        dataset = permute(dataset, [4 5 3 2 1]);
end

% --- resize to match requested magFactor (when not using explicit level) --
if isempty(options.pyramidLevel) && strcmp(type, 'image')
    currentMag   = obj.pyramid.levelScaleFactors(levelIdx, 1);
    resizeFactor = options.magFactor / currentMag;

    if abs(resizeFactor - 1) > 1e-3
        newY    = round(size(dataset, 1) / resizeFactor);
        newX    = round(size(dataset, 2) / resizeFactor);
        % dim order after permute: [y, x, z, c, t]
        resized = zeros(newY, newX, size(dataset,3), size(dataset,4), size(dataset,5), obj.dataClass);

        for t = 1:size(dataset, 5)
            for c = 1:size(dataset, 4)   % dim 4 = colours (MIB3)
                for z = 1:size(dataset, 3)   % dim 3 = z (MIB3)
                    resized(:, :, z, c, t) = imresize(dataset(:, :, z, c, t), [newY newX], 'nearest');
                end
            end
        end
        dataset = resized;
    end
end
end
