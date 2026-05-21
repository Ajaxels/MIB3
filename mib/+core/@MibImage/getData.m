function dataset = getData(obj, layerType, orient, colChannel, options) % get complete 5D dataset
% GETDATA - Get dataset from MibImage class.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getData(layerType, orient, colChannel, options) % get complete 5D dataset
%
% Input Arguments:
%   - **layerType** — char with the type of layer to obtain, used for MibLabels63 class, otherwise can be empty.
%     Values are 'labels', 'mask', 'selection', or 'everything' to get all
%     layers at once, *default* = 'image'
%   - **orient** — *(optional)*, can be ``[]``; when ``[]`` orient defaults to ``3``:
%
%     - ``1`` — returns transposed dataset in ZX configuration: ``[y,x,z,c,t]`` → ``[x,z,y,c,t]``
%     - ``2`` — returns transposed dataset in ZY configuration: ``[y,x,z,c,t]`` → ``[y,z,x,c,t]``
%     - ``3`` — returns original dataset in YX configuration: ``[y,x,z,c,t]``
%
%   - **colChannel** — *(optional)*, can be ``[]``; when ``[]`` returns all color channels or materials:
%
%     - for ``type = 'image'``: vector of color channel indices; ``[]`` = all channels
%     - for ``type = 'labels'``: integer material index (returned as binary 0/1); ``[]`` = all materials
%   - **options** — *(optional)*, a structure with extra parameters
%
%     - ``.y`` *(optional)*, [ymin, ymax] coordinates of the dataset to take after transpose, can be a single number
%     - ``.x`` *(optional)*, [xmin, xmax] coordinates of the dataset to take after transpose, can be a single number
%     - ``.z`` *(optional)*, [zmin, zmax] coordinates of the dataset to take after transpose, can be a single number
%     - ``.t`` *(optional)*, [tmin, tmax] coordinates of the dataset to take after transpose, can be a single number
%
% Output Arguments:
%   - **dataset** — 5D stack, [1:height, 1:width, 1:depth, 1:colors, 1:time]
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.getData(3, []);% get the complete dataset in the YX orientation
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     options.x = [100 200];
%     options.y = [100 200];
%     options.z = 100;
%     options.t = 1;
%     colChannel = 2;
%     dataset = obj.getData([], [], colChannel, options);% get subvolume = [100:200, 100:200] at slice 100, color channel 2
%     dataset = obj.(type).getData([], [], colChannel, options);% get subvolume from MibDataset, where type='image', 'label', 'mask', 'selection'
%     dataset = obj.mibModel.I{obj.mibModel.id}.(type).getData([], [], colChannel, options);% get subvolume from MibController, where type='image', 'label', 'mask', 'selection'
%


% Updates
%

if nargin < 5; options=struct(); end
if nargin < 4; colChannel = []; end
if nargin < 3; orient = []; end
if nargin < 2; layerType = 'image'; end

% for core.MibModel63 use a dedicated function to get the specific layer
if isa(obj, 'core.MibLabels63') && ~strcmp(layerType, 'image')
    dataset = obj.getData63(layerType, orient, colChannel, options);
    return;
end

if isempty(orient); orient = 3; end

materialIndex = []; % for the labels type index of material to get
if isempty(colChannel) || (isscalar(colChannel) && isnan(colChannel)) % take all color channels or materials
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
    Xlim = [1 size(obj.data{1}, 2)];
    Ylim = [1 size(obj.data{1}, 1)];
    Zlim = [1 size(obj.data{1}, 3)];
    Tlim = [1 size(obj.data{1}, 5)];

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
    Xlim = [max([Xlim(1) 1]) min([Xlim(2) floor(size(obj.data{1}, 2))])];
    Ylim = [max([Ylim(1) 1]) min([Ylim(2) floor(size(obj.data{1}, 1))])];
    Zlim = [max([Zlim(1) 1]) min([Zlim(2) size(obj.data{1}, 3)])];
    Tlim = [max([Tlim(1) 1]) min([Tlim(2) size(obj.data{1}, 5)])];

    if colChannel == 0; colChannel = 1:size(obj.data{1}, 4); end

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

% For label-type objects (MibLabels, mask, selection) with a single colour
% channel, remove the singleton 4th dimension so that the output is
% [H,W,Z,T] — consistent with getData63 for MibLabels63.
if ~strcmp(obj.type, 'image') && size(dataset, 4) == 1
    dataset = reshape(dataset, size(dataset,1), size(dataset,2), size(dataset,3), size(dataset,5));
end
