function dataset = getDataZarr(obj, type, orient, colChannel, options)
% GETDATAZARR - Read a subvolume from a Zarr pyramid dataset with optional slicing.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getDataZarr( type, orient, colChannel, options)
%
% Input Arguments:
%   - **type** — type of layer — only 'image' is functional in virtual mode
%   - **orient** — *(optional)*, orientation of returned dataset; default ``3``:
%
%     - ``1`` — XZ: output ``[x, z, y, c, t]``
%     - ``2`` — YZ: output ``[y, z, x, c, t]``
%     - ``3`` — YX: output ``[y, x, z, c, t]`` *(default)*
%   - **colChannel** — *(optional)*, vector of 1-based colour channel indices;
%     [] = all channels
%   - **options** — *(optional)*, struct with optional fields:
%
%     - ``.y``, ``.x``, ``.z``  — [min, max] coordinate ranges (1-based, full resolution)
%     - ``.t``          — [tmin, tmax] time-point range
%     - ``.magFactor``  — magnification factor used to select pyramid level
%       (default 1 = full resolution); ignored when pyramidLevel provided
%
%     - ``.pyramidLevel`` — explicit pyramid level index (1-based); overrides magFactor
%
% Output Arguments:
%   - **dataset** — 5D array [y, x, z, c, t] for orient==3;
%     [x, z, y, c, t] for orient==1;
%     [y, z, x, c, t] for orient==2
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.getDataZarr('image');% full YX image
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.getDataZarr('image', 3, [1 2], options);% channels 1+2
%

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

% --- map screen options to physical data ranges, scale to level, clamp ----
% options: .x = horizontal screen range, .y = vertical, .z = slice/depth.
% Each orientation maps these onto the physical data axes (Y, X, Z); each
% physical range is then scaled by THAT axis' own pyramid factor and clamped to
% THAT physical dimension. (The previous version clamped screen-axis ranges
% against the dimension mapped to that screen axis, so for XZ/YZ the slice
% coordinate was clamped against the wrong dimension and produced inverted
% bounding boxes. The permute below — which defines the on-screen arrangement —
% is unchanged, so only the region selection is corrected; YX is identical.)
fullSize = obj.pyramid.levelImageSizes(1, :);   % [Y X Z]
switch orient
    case 1  % xz: vertical = X, horizontal = Z, slice = Y
        if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(2)]; end
        if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(3)]; end
        if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(1)]; end
        physYfull = options.z; physXfull = options.y; physZfull = options.x;
    case 2  % yz: vertical = Y, horizontal = Z, slice = X
        if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(1)]; end
        if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(3)]; end
        if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(2)]; end
        physYfull = options.y; physXfull = options.z; physZfull = options.x;
    otherwise  % 3 yx: vertical = Y, horizontal = X, slice = Z
        if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(1)]; end
        if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(2)]; end
        if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(3)]; end
        physYfull = options.y; physXfull = options.x; physZfull = options.z;
end
if ~isfield(options, 't') || isempty(options.t); options.t = [1, obj.time]; end

sf  = obj.pyramid.levelScaleFactors(levelIdx, :);   % [yScale xScale zScale]
lvl = obj.pyramid.levelImageSizes(levelIdx, :);      % [Y X Z]
physYlim = ceil(physYfull ./ sf(1));
physXlim = ceil(physXfull ./ sf(2));
physZlim = ceil(physZfull ./ sf(3));
physYlim = [max(physYlim(1), 1), min(physYlim(2), lvl(1))];
physXlim = [max(physXlim(1), 1), min(physXlim(2), lvl(2))];
physZlim = [max(physZlim(1), 1), min(physZlim(2), lvl(3))];
Tidx = [max(options.t(1), 1), min(options.t(2), obj.time)];

% --- lazy-create / retrieve cached Zarr3VirtualLoader --------------------
if isempty(obj.loaders) || numel(obj.loaders) < 1 || isempty(obj.loaders{1}) || ...
        ~isa(obj.loaders{1}, 'io.loaders.Zarr3VirtualLoader')
    axOrder = 'tczyx';
    if isfield(obj.pyramid, 'axisOrder') && ~isempty(obj.pyramid.axisOrder)
        axOrder = obj.pyramid.axisOrder;
    end
    obj.loaders{1} = io.loaders.Zarr3VirtualLoader(obj.filePaths{1}, axOrder);
end

% --- colour selection (1-based inclusive for Zarr3VirtualLoader) ----------
if strcmp(type, 'image')
    if isempty(colChannel)
        Clim = [1, obj.colors];
    else
        Clim = [colChannel(1), colChannel(end)];
    end
end

% --- zarr path for this level --------------------------------------------
levelPath = obj.pyramid.levelNames{levelIdx};

% --- read subvolume via Zarr3VirtualLoader --------------------------------
% block arrives as MIB3 [y, x, z, c, t]
block = obj.loaders{1}.readRegion(levelPath, physYlim, physXlim, physZlim, ...
    Clim, Tidx, obj.dataClass);

% --- permute [y,x,z,c,t] to the requested screen orientation -------------
switch orient
    case 1  % xz: [y,x,z,c,t] -> [x, z, y, c, t]
        dataset = permute(block, [2, 3, 1, 4, 5]);
    case 2  % yz: [y,x,z,c,t] -> [y, z, x, c, t]
        dataset = permute(block, [1, 3, 2, 4, 5]);
    case 3  % yx: [y,x,z,c,t] — already in MIB3 order
        dataset = block;
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
