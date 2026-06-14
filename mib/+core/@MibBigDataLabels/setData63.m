function result = setData63(obj, dataset, type, orient, materialIndex, options)
% SETDATA63 - write a packed layer block to the disk-backed BigData model pyramid.
%
% Override of ``core.MibLabels63.setData63``. The incoming data is at the
% displayed resolution; it is resized to the working level (the level matching
% ``options.magFactor``), merged into that level with the parent's bit logic,
% written, and then **propagated** to every other pyramid level (nearest-
% neighbour resize of the merged packed bytes) so all levels stay consistent.
%
% Input/Output: see core.MibLabels63.setData63.

result = false;

if nargin < 6; options = struct(); end
if nargin < 5; materialIndex = []; end
if nargin < 4; orient = []; end
if nargin < 3; type = []; end

if ~obj.exists || isempty(obj.modelArrays); return; end
if isempty(type); type = 'labels'; end
if isempty(orient); orient = 3; end
if ~strcmp(type, 'labels'); materialIndex = []; end
if isempty(dataset); return; end
if islogical(dataset(1)); dataset = uint8(dataset); end

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

% --- incoming data into native [y, x, z] order ----------------------------
if orient == 1
    dataset = ipermute(dataset, [2 3 1 4 5]);
elseif orient == 2
    dataset = ipermute(dataset, [1 3 2 4 5]);
end
dataset = reshape(dataset, size(dataset, 1), size(dataset, 2), []);   % [dy dx dz]

% --- working level + its region ------------------------------------------
levelIdx = obj.pickLevel(options);
[Yl, Xl, Zl] = levelRegion(obj, levelIdx, fullY, fullX, fullZ);
wSize = [Yl(2)-Yl(1)+1, Xl(2)-Xl(1)+1, Zl(2)-Zl(1)+1];

% resize the displayed-resolution data down/up to the working level region
dataLevel = core.MibBigDataLabels.resizeBlockNearest(dataset, wSize);

% --- read / merge / write the working level ------------------------------
packed = obj.readPackedLevel(levelIdx, Yl, Xl, Zl);
packed = mergePacked(packed, dataLevel, type, materialIndex);
obj.writePackedLevel(levelIdx, packed, Yl, Xl, Zl);

% --- propagate the merged region to every other level --------------------
for L2 = 1:size(obj.modelLevelSizes, 1)
    if L2 == levelIdx; continue; end
    [A2, B2, C2] = levelRegion(obj, L2, fullY, fullX, fullZ);
    t2 = [A2(2)-A2(1)+1, B2(2)-B2(1)+1, C2(2)-C2(1)+1];
    block2 = core.MibBigDataLabels.resizeBlockNearest(packed, t2);
    obj.writePackedLevel(L2, block2, A2, B2, C2);
end

result = true;
end

% ------------------------------------------------------------------------
function [Yl, Xl, Zl] = levelRegion(obj, levelIdx, fullY, fullX, fullZ)
% map a full-resolution YXZ region to a level's clamped index range
sf = obj.modelScaleFactors(levelIdx, :);
lv = obj.modelLevelSizes(levelIdx, :);
Yl = core.MibBigDataLabels.clampRange([ceil(fullY(1)/sf(1)), ceil(fullY(2)/sf(1))], lv(1));
Xl = core.MibBigDataLabels.clampRange([ceil(fullX(1)/sf(2)), ceil(fullX(2)/sf(2))], lv(2));
Zl = core.MibBigDataLabels.clampRange([ceil(fullZ(1)/sf(3)), ceil(fullZ(2)/sf(3))], lv(3));
end

% ------------------------------------------------------------------------
function packed = mergePacked(packed, data, type, materialIndex)
% merge a layer into the packed uint8 block using the MibLabels63 bit scheme
data = reshape(uint8(data), size(packed));
switch type
    case 'labels'
        if ~isempty(materialIndex)
            lowBits = bitand(packed, 63);
            lowBits = lowBits .* uint8(lowBits ~= materialIndex);   % remove material
            lowBits(data == 1) = materialIndex;                     % write new material
            packed = bitor(bitand(packed, 192), lowBits);           % keep mask+selection
        else
            packed = bitor(bitand(packed, 192), data);              % replace all materials
        end
    case 'mask'
        packed = bitor(bitset(packed, 7, 0), data * 64);
    case 'selection'
        packed = bitor(bitset(packed, 8, 0), data * 128);
    case 'everything'
        packed = data;
end
end
