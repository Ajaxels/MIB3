function insertSlice(obj, img, insertPosition, dim, BackgroundColorIntensity)
% function insertSlice(obj, img, insertPosition, dim, BackgroundColorIntensity)
% Low-level insert of img into obj.data{1} along the depth (z) or time (t) dimension.
%
% This is the pure data-manipulation layer: no dialogs, no waitbars, no
% annotation handling. All validation and user interaction is done by the
% caller (core.MibDataset.insertSlice).
%
% Parameters:
% img: 5D array [height, width, depth, colors, time] to insert; must already
%   be the correct class. Use the same conventions as obj.data{1}.
% insertPosition: 1-based insertion index (already clamped to a valid range
%   by the caller). 0 or NaN means append to the end.
% dim: 'depth' (default) inserts along dimension 3 (z);
%      'time' inserts along dimension 5 (t)
% BackgroundColorIntensity: scalar fill value used when the spatial extents
%   of img exceed those of the current data (default 0)
%
% Return values:
%   none
%
% After the call the following properties are updated:
%   obj.data{1}, obj.height, obj.width, obj.depth, obj.colors, obj.time,
%   obj.dim_yxzct

%|
% @b Examples:
% @code obj.image.insertSlice(img5D, 5, 'depth', 0); @endcode
% @code obj.labels.insertSlice(zeros([H W D 1 T],'uint8'), 5, 'depth', 0); @endcode

% Updates
%

if nargin < 5; BackgroundColorIntensity = 0; end
if nargin < 4; dim = 'depth'; end

[D2_y, D2_x, D2_z, D2_c, D2_t] = size(img);
D1_y = obj.height;  
D1_x = obj.width;  
D1_z = obj.depth;
D1_c = obj.colors;  
D1_t = obj.time;

% clamp insertPosition
if isnan(insertPosition) || insertPosition == 0
    if strcmp(dim, 'depth'); insertPosition = D1_z + 1; else; insertPosition = D1_t + 1; end
end

yMax = max([D1_y, D2_y]);
xMax = max([D1_x, D2_x]);
cMax = max([D1_c, D2_c]);
zMax = max([D1_z, D2_z]);
tMax = max([D1_t, D2_t]);

% -----------------------------------------------------------------------
if strcmp(dim, 'depth')
% -----------------------------------------------------------------------
    insertPosition
    if insertPosition == 1
        Z1_part1 = [D2_z+1, D2_z+D1_z];  Z1_part2 = [];  Z2_part1 = [1, D2_z];
    elseif insertPosition == D1_z+1
        Z1_part1 = [1, D1_z];  Z1_part2 = [];  Z2_part1 = [D1_z+1, D1_z+D2_z];
    else
        Z1_part1 = [1, insertPosition-1];
        Z1_part2 = [insertPosition+D2_z, D2_z+D1_z];
        Z2_part1 = [insertPosition, insertPosition+D2_z-1];
    end
    
    Z1_part2

    if BackgroundColorIntensity ~= 0
        imgOut = zeros([yMax, xMax, D1_z+D2_z, cMax, tMax], obj.dataClass) + BackgroundColorIntensity;
    else
        imgOut = zeros([yMax, xMax, D1_z+D2_z, cMax, tMax], obj.dataClass);
    end
    imgOut(1:D1_y, 1:D1_x, Z1_part1(1):Z1_part1(2), 1:D1_c, 1:D1_t) = ...
        obj.data{1}(:, :, 1:Z1_part1(2)-Z1_part1(1)+1, :, :);
    imgOut(1:D2_y, 1:D2_x, Z2_part1(1):Z2_part1(2), 1:D2_c, 1:D2_t) = img;
    if ~isempty(Z1_part2)
        imgOut(1:D1_y, 1:D1_x, Z1_part2(1):Z1_part2(2), 1:D1_c, 1:D1_t) = ...
            obj.data{1}(:, :, Z1_part1(2)+1:end, :, :);
    end
    obj.data{1} = imgOut;
    obj.depth = D1_z + D2_z;

% -----------------------------------------------------------------------
else  % time
% -----------------------------------------------------------------------
    if insertPosition == 1
        T1_part1 = [D2_t+1, D2_t+D1_t];  T1_part2 = [];  T2_part1 = [1, D2_t];
    elseif insertPosition == D1_t+1
        T1_part1 = [1, D1_t];  T1_part2 = [];  T2_part1 = [D1_t+1, D1_t+D2_t];
    else
        T1_part1 = [1, insertPosition-1];
        T1_part2 = [insertPosition+D2_t, D2_t+D1_t];
        T2_part1 = [insertPosition, insertPosition+D2_t-1];
    end

    if BackgroundColorIntensity ~= 0
        imgOut = zeros([yMax, xMax, zMax, cMax, D1_t+D2_t], obj.dataClass) + BackgroundColorIntensity;
    else
        imgOut = zeros([yMax, xMax, zMax, cMax, D1_t+D2_t], obj.dataClass);
    end
    imgOut(1:D1_y, 1:D1_x, 1:D1_z, 1:D1_c, T1_part1(1):T1_part1(2)) = ...
        obj.data{1}(:, :, :, :, 1:T1_part1(2)-T1_part1(1)+1);
    imgOut(1:D2_y, 1:D2_x, 1:D2_z, 1:D2_c, T2_part1(1):T2_part1(2)) = img;
    if ~isempty(T1_part2)
        imgOut(1:D1_y, 1:D1_x, 1:D1_z, 1:D1_c, T1_part2(1):T1_part2(2)) = ...
            obj.data{1}(:, :, :, :, T1_part1(2)+1:end);
    end
    obj.data{1} = imgOut;
    obj.time = D1_t + D2_t;
end

% update common dimension properties
obj.height = yMax;
obj.width  = xMax;
obj.colors = cMax;
obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

end
