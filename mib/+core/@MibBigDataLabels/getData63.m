function dataset = getData63(obj, type, orient, materialIndex, options)
% GETDATA63 - read a packed layer block from the disk-backed BigData model pyramid.
%
% Override of ``core.MibLabels63.getData63``. Selects the pyramid level that
% matches ``options.magFactor`` (or ``options.pyramidLevel``), reads the
% requested region from that level, and resizes it to the displayed resolution
% exactly like the image reader (``MibVirtualImage.getDataZarr``) so the model
% lines up with the image. Bit semantics and the return shape match the parent.
%
% Input/Output: see core.MibLabels63.getData63.

if nargin < 5; options = struct(); end
if nargin < 4; materialIndex = []; end
if nargin < 3; orient = []; end
if nargin < 2; type = []; end

if ~obj.exists || isempty(obj.modelArrays); dataset = []; return; end
if isempty(type); type = 'labels'; end
if isempty(orient); orient = 3; end
if ~strcmp(type, 'labels'); materialIndex = []; end

% --- full-resolution (level-0) sub-block from options + orientation -------
fullX = [1, obj.width];
fullY = [1, obj.height];
fullZ = [1, obj.depth];
switch orient
    case 1  % xz
        if isfield(options, 'x'); fullZ = [options.x(1), options.x(end)]; end
        if isfield(options, 'z'); fullY = floor([options.z(1), options.z(end)]); end
        if isfield(options, 'y'); fullX = floor([options.y(1), options.y(end)]); end
    case 2  % yz
        if isfield(options, 'x'); fullZ = [options.x(1), options.x(end)]; end
        if isfield(options, 'y'); fullY = floor([options.y(1), options.y(end)]); end
        if isfield(options, 'z'); fullX = floor([options.z(1), options.z(end)]); end
    otherwise  % 3, yx
        if isfield(options, 'x'); fullX = floor([options.x(1), options.x(end)]); end
        if isfield(options, 'y'); fullY = floor([options.y(1), options.y(end)]); end
        if isfield(options, 'z'); fullZ = [options.z(1), options.z(end)]; end
end
fullX = [max(fullX(1), 1), min(fullX(2), obj.width)];
fullY = [max(fullY(1), 1), min(fullY(2), obj.height)];
fullZ = [max(fullZ(1), 1), min(fullZ(2), obj.depth)];

% --- select level and scale the coordinates to it -------------------------
levelIdx = obj.pickLevel(options);
sf       = obj.modelScaleFactors(levelIdx, :);    % [yS xS zS]
lvlSize  = obj.modelLevelSizes(levelIdx, :);
Yl = core.MibBigDataLabels.clampRange([ceil(fullY(1)/sf(1)), ceil(fullY(2)/sf(1))], lvlSize(1));
Xl = core.MibBigDataLabels.clampRange([ceil(fullX(1)/sf(2)), ceil(fullX(2)/sf(2))], lvlSize(2));
Zl = core.MibBigDataLabels.clampRange([ceil(fullZ(1)/sf(3)), ceil(fullZ(2)/sf(3))], lvlSize(3));

packed = obj.readPackedLevel(levelIdx, Yl, Xl, Zl);   % [ny nx nz], native [y x z]

% --- resize to display resolution (mirror getDataZarr) --------------------
mf = 1;
if isfield(options, 'magFactor') && ~isempty(options.magFactor); mf = options.magFactor; end
explicitLevel = isfield(options, 'pyramidLevel') && ~isempty(options.pyramidLevel);
resizeFactor = mf / sf(1);
if ~explicitLevel && abs(resizeFactor - 1) > 1e-3
    newY = max(1, round(size(packed, 1) / resizeFactor));
    newX = max(1, round(size(packed, 2) / resizeFactor));
    if ~isequal([newY newX], [size(packed,1) size(packed,2)])
        resized = zeros(newY, newX, size(packed, 3), 'uint8');
        for z = 1:size(packed, 3)
            resized(:, :, z) = imresize(packed(:, :, z), [newY newX], 'nearest');
        end
        packed = resized;
    end
end

% --- shape to [ny, nx, nz, 1, 1] and orient -------------------------------
packed = reshape(packed, size(packed, 1), size(packed, 2), size(packed, 3), 1, 1);
if orient == 1
    packed = permute(packed, [2 3 1 4 5]);
elseif orient == 2
    packed = permute(packed, [1 3 2 4 5]);
end

% --- unpack the requested layer -------------------------------------------
switch type
    case 'labels'
        if ~isempty(materialIndex)
            dataset = uint8(bitand(packed, 63) == materialIndex(1));
        else
            dataset = bitand(packed, 63);
        end
    case 'mask'
        dataset = bitget(packed, 7);
    case 'selection'
        dataset = bitget(packed, 8);
    case 'everything'
        dataset = packed;
end
end
