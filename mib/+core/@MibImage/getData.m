function dataset = getData(obj, orient, colChannel, options) % get complete 5D dataset
% function dataset = getData(obj, orient, colChannel, options)
% Get dataset from MibImage class
%
% Parameters:
% orient: [@em optional, can be [], default == 3];
% @li when @b 1 returns the transposed dataset to the zx configuration, [y,x,z,c,t] -> [x,z,y,c,t]
% @li when @b 2 returns the transposed dataset to the zy configuration, [y,x,z,c,t] -> [y,z,x,c,t]
% @li when @b 3 returns the original dataset to the yx configuration, [y,x,z,c,t]
% colChannel: [@em optional, default==[] ],
% @li when obj.type == 'image', @b colChannel is a vector with color numbers to take, when [] take all color channels
% @li when obj.type == 'labels', @b colChannel is an integer to take material with this specific index (returned with value == 1), when [] - take all materials
% options: [@em optional], a structure with extra parameters
% @li .y -> [@em optional], [ymin, ymax] coordinates of the dataset to take after transpose, can be a single number
% @li .x -> [@em optional], [xmin, xmax] coordinates of the dataset to take after transpose, can be a single number
% @li .z -> [@em optional], [zmin, zmax] coordinates of the dataset to take after transpose, can be a single number
% @li .t -> [@em optional], [tmin, tmax] coordinates of the dataset to take after transpose, can be a single number
%
% Return values:
% dataset: 5D stack, [1:height, 1:width, 1:depth, 1:colors, 1:time]

%|
% @b Examples:
% @code dataset = obj.getData(3, []);      // get the complete dataset in the YX orientation @endcode
% @code
% options.x = [100 200];
% options.y = [100 200];
% options.z = 100;
% options.t = 1;
% colChannel = 2;
% dataset = obj.getData([], colChannel, options);      // get subvolume = [100:200, 100:200] at slice 100, color channel 2
% @endcode


% Updates
%

if nargin < 4; options=struct(); end
if nargin < 3; colChannel = []; end
if nargin < 2; orient = []; end

if isempty(orient); orient = 3; end

materialIndex = []; % for the labels type index of material to get
if isempty(colChannel) % take all color channels or materials
    colChannel = 1:obj.colors;
else
    if strcmp(obj.type, 'labels')
        materialIndex = colChannel;
        colChannel = 1;
    end
end

blockModeSwitchLocal = 0;
if isfield(options, 'y') || isfield(options, 'x') || isfield(options, 'z') || (isfield(options, 't') && obj.time > 1)
    blockModeSwitchLocal = 1;
end

% split the operations for better performance
if blockModeSwitchLocal == 0  % return the full dataset
    if strcmp(obj.type, 'image') || isempty(materialIndex)
        dataset = obj.data{1}(:,:,:,colChannel,:);
    else % labels type
        dataset = zeros(size(obj.data{1}), 'uint8');   
        dataset(obj.data{1} == materialIndex) = 1;
    end

    if orient==1    % xz; get permuted dataset
        dataset = permute(dataset, [2 3 1 4 5]);
    elseif orient==2    % yz; get permuted dataset
        dataset = permute(dataset, [1 3 2 4 5]);
    end
else  % return a subvolume of the full dataset
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

    if strcmp(obj.type, 'image') || isempty(materialIndex)
        dataset = obj.data{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2));
    else % labels
        dataset = uint8((obj.data{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)) == materialIndex));
    end

    if orient==1     % permute to xz
        dataset = permute(dataset,[2 3 1 4 5]);
    elseif orient==2 % permute to yz
        dataset = permute(dataset,[1 3 2 4 5]);
    end
end