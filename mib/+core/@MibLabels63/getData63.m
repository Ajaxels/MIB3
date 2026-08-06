function dataset = getData63(obj, type, orient, materialIndex, options) % get complete 5D dataset
% GETDATA63 - Get dataset from MibLabels63 class.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getData63(type, orient, materialIndex, options) % get complete 5D dataset
%
% Input Arguments:
%   - **type** - char with the type of layer to obtain, 'labels', 'mask', 'selection', or 'everything' to get all layers at once
%   - **orient** - *(optional)*, can be ``[]``; default ``3``:
%
%     - ``1`` - returns transposed dataset in ZX configuration: ``[y,x,z,c,t]`` → ``[x,z,y,c,t]``
%     - ``2`` - returns transposed dataset in ZY configuration: ``[y,x,z,c,t]`` → ``[y,z,x,c,t]``
%     - ``3`` - returns original dataset in YX configuration: ``[y,x,z,c,t]``
%
%   - **materialIndex** - *(optional)*, can be ``[]``:
%
%     - for ``type = 'labels'``: integer material index (returned as binary 0/1); ``[]`` = all materials
%     - for ``type = 'mask'``, ``'selection'``, ``'everything'``: not used
%   - **options** - *(optional)*, a structure with extra parameters
%
%     - ``.y`` *(optional)*, [ymin, ymax] coordinates of the dataset to take after transpose, can be a single number
%     - ``.x`` *(optional)*, [xmin, xmax] coordinates of the dataset to take after transpose, can be a single number
%     - ``.z`` *(optional)*, [zmin, zmax] coordinates of the dataset to take after transpose, can be a single number
%     - ``.t`` *(optional)*, [tmin, tmax] coordinates of the dataset to take after transpose, can be a single number
%
% Output Arguments:
%   - **dataset** - 5D stack, [1:height, 1:width, 1:depth, 1:colors, 1:time]
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.getData('mask', 3, []);% get mask for the complete dataset in the YX orientation
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
%     materialIndex = 2;
%     dataset = obj.getData('labels', [], materialIndex, options);% get labels, subvolume = [100:200, 100:200] at slice 100, material 2
%


% Updates
%

if nargin < 5; options=struct(); end
if nargin < 4; materialIndex = []; end
if nargin < 3; orient = []; end
if nargin < 2; type = []; end

% no dataset, return empty
if ~obj.exists; dataset = []; return; end

% MibLabels63 has the color dimension of 1
colChannel = 1;

if isempty(type); type = 'labels'; end
if isempty(orient); orient = 3; end

% set materialIndex to empty for the selection and mask layers
if ~strcmp(type, 'labels'); materialIndex = []; end

blockModeSwitchLocal = 0;
if isfield(options, 'y') || isfield(options, 'x') || isfield(options, 'z') || (isfield(options, 't') && obj.time > 1)
    blockModeSwitchLocal = 1;
end

% split the operations for better performance
if blockModeSwitchLocal == 0  % return the full dataset
    % the color dimension is always 1 - operate on obj.data directly:
    % orient 3 passes a copy-on-write alias (no copy); the bit-unpacking
    % below produces the single output copy
    if orient==3 % yx orientation
        dataset = obj.data;
    elseif orient==1    % xz; get permuted dataset
        dataset = permute(obj.data, [2 3 1 4 5]);
    elseif orient==2    % yz; get permuted dataset
        dataset = permute(obj.data, [1 3 2 4 5]);
    end

    % extract required layer
    switch type
        case 'labels'
            if ~isempty(materialIndex)      % take only specific material
                dataset = uint8(bitand(dataset, 63) == materialIndex(1));
            else                            % get all labels objects
                dataset = bitand(dataset, 63);
            end
        case 'mask'
            dataset = bitget(dataset, 7);   % bit 7 = 64 = 01000000
        case 'selection'
            dataset = bitget(dataset, 8);   % bit 8 = 128 = 10000000
        case 'everything'
            % do nothing - orient 3 returns a copy-on-write alias of obj.data
    end
else  % return a subvolume of the full dataset
    % get coordinates of the shown block for the original dataset in the yx dimension
    Xlim = [1 size(obj.data, 2)];
    Ylim = [1 size(obj.data, 1)];
    Zlim = [1 size(obj.data, 3)];
    Tlim = [1 size(obj.data, 5)];

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
    Xlim = [max([Xlim(1) 1]) min([Xlim(2) floor(size(obj.data, 2))])];
    Ylim = [max([Ylim(1) 1]) min([Ylim(2) floor(size(obj.data, 1))])];
    Zlim = [max([Zlim(1) 1]) min([Zlim(2) size(obj.data, 3)])];
    Tlim = [max([Tlim(1) 1]) min([Tlim(2) size(obj.data, 5)])];

    dataset = obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2));
    if orient==1     % permute to xz
        dataset = permute(dataset,[2 3 1 4 5]);
    elseif orient==2 % permute to yz
        dataset = permute(dataset,[1 3 2 4 5]);
    end
    
    switch type
        case 'labels'
            if ~isempty(materialIndex)      % take only specific material
                dataset = uint8(bitand(dataset, 63) == materialIndex(1));
            else
                dataset = bitand(dataset, 63);     % get all model objects
            end
        case 'mask'
            dataset = bitget(dataset, 7);   % bit 7 = 64 = 01000000
        case 'selection'
            dataset = bitget(dataset, 8);   % bit 8 = 128 = 10000000
        case 'everything'
            % do nothing
    end
end
