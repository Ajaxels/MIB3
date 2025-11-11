function result = setData(obj, dataset, orient, col_channel, options) 
% function result = setData(obj, dataset, orient, col_channel, options) 
% Set dataset to MibBaseImage class
%
% Parameters:
% dataset: matrix with the dataset to update MibBaseImage.img 
% orient: [@em optional, can be [], default == 3];
% @li when @b 1 updates transposed dataset from the zx configuration, [x,z,y,c,t] -> [y,x,z,c,t]
% @li when @b 2 updates transposed dataset from the zy configuration, [y,z,x,c,t] -> [y,x,z,c,t]
% @li when @b 3 updates original dataset from the yx configuration, [y,x,z,c,t]
% col_channel: [@em optional, default==[] ],
% @li when obj.type == 'image', @b col_channel is a vector with color numbers to take, when [] take all color channels
% @li when obj.type == 'labels', @b col_channel is an integer to take material with this specific index (returned with value == 1), when [] - take all materials
% options: [@em optional], a structure with extra parameters
% @li .y -> [@em optional], [ymin, ymax] coordinates of the dataset to set after transpose, can be a single number
% @li .x -> [@em optional], [xmin, xmax] coordinates of the dataset to set after transpose, can be a single number
% @li .z -> [@em optional], [zmin, zmax] coordinates of the dataset to set after transpose, can be a single number
% @li .t -> [@em optional], [tmin, tmax] coordinates of the dataset to set after transpose, can be a single number
%
% Return values:
% result: -> @b 1 - success, @b 0 - error

%|
% @b Examples:
% @code obj.setData(dataset, 3, []);      // set the complete dataset in the YX orientation @endcode
% @code
% options.x = [100 200];
% options.y = [100 200];
% options.z = 100;
% options.t = 1;
% col_channel = 2;
% obj.setData(dataset, [], col_channel, options);      //set subvolume = [100:200, 100:200] at slice 100, color channel 1
% @endcode


% Updates
%
result = false;

if nargin < 5; options=struct(); end
if nargin < 4; col_channel = []; end
if nargin < 3; orient = []; end

if isempty(orient); orient = 3; end

materialIndex = NaN; % for the labels type index of material to get
if isempty(col_channel) % take all color channels or materials
    col_channel = 1:obj.colors;
else
    if strcmp(obj.type, 'labels')
        materialIndex = col_channel;
        col_channel = 1;
    end
end

blockModeSwitchLocal = 0;
if isfield(options, 'y') || isfield(options, 'x') || isfield(options, 'z') || (isfield(options, 't') && obj.time > 1)
    blockModeSwitchLocal = 1;
end

% convert from optional logical
if islogical(dataset(1)); dataset = uint8(dataset); end

% split the operations for better performance
if blockModeSwitchLocal == 0  % set the full dataset
    % permute to the target orientation
    if orient==1    % xz; get permuted dataset
        dataset = ipermute(dataset, [2 3 1 4 5]);
    elseif orient==2    % yz; get permuted dataset
        dataset = ipermute(dataset, [1 3 2 4 5]);
    end

    if strcmp(obj.type, 'image') || isnan(materialIndex)
        obj.img{1}(:,:,:,col_channel,:) = dataset;
    else % labels type
        obj.img{1}(obj.img{1} == materialIndex) = 0;
        obj.img{1}(dataset == 1) = materialIndex;
    end
else  % set a part of the dataset
    % get coordinates of the shown block for the original dataset in the yx dimension
    Xlim = [1 obj.width];
    Ylim = [1 obj.height];
    Zlim = [1 obj.depth];
    Tlim = [1 obj.time];

    % convert coordinates to the original dataset
    if orient==1     % xz
        if isfield(options, 'x'); Zlim = [options.x(1) options.x(numel(options.x))]; end
        if isfield(options, 'z'); Ylim = floor([options.z(1) options.z(numel(options.z))]); end
        if isfield(options, 'y'); Xlim = floor([options.y(1) options.y(numel(options.y))]); end
    elseif orient==2 % yz
        if isfield(options, 'x'); Zlim = [options.x(1) options.x(numel(options.x))]; end
        if isfield(options, 'y'); Ylim = floor([options.y(1) options.y(numel(options.y))]); end
        if isfield(options, 'z'); Xlim = floor([options.z(1) options.z(numel(options.z))]); end
    elseif orient==3 % yx
        if isfield(options, 'x'); Xlim = floor([options.x(1) options.x(numel(options.x))]); end
        if isfield(options, 'y'); Ylim = floor([options.y(1) options.y(numel(options.y))]); end
        if isfield(options, 'z'); Zlim = [options.z(1) options.z(numel(options.z))]; end
    end
    % obtain time-values
    if isfield(options, 't')
        options.t = [options.t(1) options.t(numel(options.t))];
        Tlim = options.t; 
    end

    % make sure that the coordinates within the dimensions of the dataset
    Xlim = [max([Xlim(1) 1]) min([Xlim(2) floor(obj.width)])];
    Ylim = [max([Ylim(1) 1]) min([Ylim(2) floor(obj.height)])];
    Zlim = [max([Zlim(1) 1]) min([Zlim(2) obj.depth])];
    Tlim = [max([Tlim(1) 1]) min([Tlim(2) obj.time])];

    % permute to the target orientation
    if orient==1    % xz; get permuted dataset
        dataset = ipermute(dataset, [2 3 1 4 5]);
    elseif orient==2    % yz; get permuted dataset
        dataset = ipermute(dataset, [1 3 2 4 5]);
    end

    if strcmp(obj.type, 'image') || isnan(materialIndex)
        obj.img{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), col_channel, Tlim(1):Tlim(2)) = dataset;
    else % labels type, set only specific object
        currentDataset = obj.img{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), col_channel, Tlim(1):Tlim(2));
        currentDataset(currentDataset == materialIndex) = 0;
        currentDataset(dataset == 1) = materialIndex;

        obj.img{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), col_channel, Tlim(1):Tlim(2)) = currentDataset;
    end
end
result = true;
end
