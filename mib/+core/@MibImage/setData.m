function result = setData(obj, dataset, layerType, orient, colChannel, options) 
% SETDATA - Set dataset to MibBaseImage class.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setData(dataset, layerType, orient, colChannel, options)
%
% Input Arguments:
%   - **dataset** — matrix with the dataset to update MibBaseImage.data
%   - **layerType** — char with the type of layer to obtain, used for MibLabels63 class, otherwise can be empty.
%     Values are 'labels', 'mask', 'selection', or 'everything' to get all
%     layers at once, *default* = 'image'
%   - **orient** — *(optional)*, can be ``[]``; default ``3``:
%
%     - ``1`` — updates transposed dataset from ZX configuration: ``[x,z,y,c,t]`` → ``[y,x,z,c,t]``
%     - ``2`` — updates transposed dataset from ZY configuration: ``[y,z,x,c,t]`` → ``[y,x,z,c,t]``
%     - ``3`` — updates original dataset from YX configuration: ``[y,x,z,c,t]``
%
%   - **colChannel** — *(optional)*, can be ``[]``; when ``[]`` sets all color channels or materials:
%
%     - for ``type = 'image'``: vector of color channel indices; ``[]`` = all channels
%     - for ``type = 'labels'``: integer material index (returned as binary 0/1); ``[]`` = all materials
%   - **options** — *(optional)*, a structure with extra parameters
%
%     - ``.y`` *(optional)*, [ymin, ymax] coordinates of the dataset to set after transpose, can be a single number
%     - ``.x`` *(optional)*, [xmin, xmax] coordinates of the dataset to set after transpose, can be a single number
%     - ``.z`` *(optional)*, [zmin, zmax] coordinates of the dataset to set after transpose, can be a single number
%     - ``.t`` *(optional)*, [tmin, tmax] coordinates of the dataset to set after transpose, can be a single number
%
% Output Arguments:
%   - **result** — **1** - success, **0** - error
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.setData(dataset, [], 3, []);% set the complete dataset in the YX orientation
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
%     obj.setData(dataset, [], [], colChannel, options);% set subvolume = [100:200, 100:200] at slice 100, color channel 1
%


% Updates
%
result = false;

if nargin < 6; options = struct(); end
if nargin < 5; colChannel = []; end
if nargin < 4; orient = []; end
if nargin < 3; layerType = 'image'; end

% for core.MibModel63 use a dedicated function to set the specific layer
if isa(obj, 'core.MibLabels63') && ~strcmp(layerType, 'image')
    result = obj.setData63(dataset, layerType, orient, colChannel, options);
    return;
end

if isempty(orient); orient = 3; end

materialIndex = []; % for the labels type index of material to get
if isempty(colChannel) || (isscalar(colChannel) && colChannel == 0) % take all color channels or materials
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

    if strcmp(obj.type, 'image') || isempty(materialIndex)
        obj.data{1}(:,:,:,colChannel,:) = dataset;
    else % labels type
        obj.data{1}(obj.data{1} == materialIndex) = 0;
        obj.data{1}(dataset == 1) = materialIndex;
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

    if strcmp(obj.type, 'image') || isempty(materialIndex)
        obj.data{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)) = dataset;
    else % labels type, set only specific object
        currentDataset = obj.data{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2));
        currentDataset(currentDataset == materialIndex) = 0;
        currentDataset(dataset == 1) = materialIndex;

        obj.data{1}(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)) = currentDataset;
    end
end
result = true;
end
