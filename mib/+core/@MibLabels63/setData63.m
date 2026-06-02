function result = setData63(obj, dataset, type, orient, materialIndex, options) 
% SETDATA63 - Set dataset to MibLabels63 class.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setData63(dataset, type, orient, materialIndex, options)
%
% Input Arguments:
%   - **dataset** — matrix with the dataset to update MibBaseImage.img
%   - **type** — char with the type of layer to obtain, 'labels', 'mask', 'selection', or 'everything' to get all layers at once
%   - **orient** — *(optional)*, can be ``[]``; default ``3``:
%
%     - ``1`` — updates transposed dataset from ZX configuration: ``[x,z,y,c,t]`` → ``[y,x,z,c,t]``
%     - ``2`` — updates transposed dataset from ZY configuration: ``[y,z,x,c,t]`` → ``[y,x,z,c,t]``
%     - ``3`` — updates original dataset from YX configuration: ``[y,x,z,c,t]``
%
%   - **materialIndex** — *(optional)*, can be ``[]``:
%
%     - for ``type = 'labels'``: integer material index (returned as binary 0/1); ``[]`` = all materials
%     - for ``type = 'mask'``, ``'selection'``, ``'everything'``: not used
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
%     obj.setData63(dataset, 'labels', 3, []);% set the complete model in the YX orientation
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
%     obj.setData63(dataset, 'labels', [], colChannel, options);% set subvolume = [100:200, 100:200] at slice 100, color channel 1
%


% Updates
%
result = false;

if nargin < 6; options = struct(); end
if nargin < 5; materialIndex = []; end
if nargin < 4; orient = []; end
if nargin < 3; type = []; end

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

if isempty(dataset); return; end
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

    switch type
        case 'labels'
            if ~isempty(materialIndex)      % take only specific material
                obj.data(bitand(obj.data, 63)==materialIndex) = bitand(obj.data(bitand(obj.data, 63)==materialIndex), 192);  % 192 = 11000000, remove Material from the model
                obj.data(dataset==1) = bitand(obj.data(dataset==1), 192);    % empty positions for the new material
                obj.data(dataset==1) = bitor(obj.data(dataset==1), materialIndex);    % update new material
            else
                obj.data = bitand(obj.data, 192); % clear current model
                obj.data = bitor(obj.data, dataset);
            end
        case 'mask'
            obj.data = bitset(obj.data, 7, 0);    % clear current mask
            obj.data = bitor(obj.data, dataset*64);
        case 'selection'
            obj.data = bitset(obj.data, 8, 0);    % clear existing selection
            obj.data = bitor(obj.data, dataset*128);
        case 'everything'
            obj.data = dataset;
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

    switch type
        case 'labels'
            if ~isempty(materialIndex)      % take only specific material
                currentDataset = obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2));
                currentDataset(bitand(currentDataset, 63)==materialIndex) = bitand(currentDataset(bitand(currentDataset, 63)==materialIndex), 192);  % 192 = 11000000, remove Material from the model
                currentDataset(dataset==1) = bitand(currentDataset(dataset==1), 192);    % empty positions for the new material
                currentDataset(dataset==1) = bitor(currentDataset(dataset==1), materialIndex);
                obj.data(Ylim(1):Ylim(2),Xlim(1):Xlim(2),Zlim(1):Zlim(2),Tlim(1):Tlim(2)) = currentDataset;
            else
                currentDataset = bitand(obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)), 192); % clear current model    
                obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)) = bitor(currentDataset, dataset);
            end
        case 'mask'
            currentDataset = obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2));
            currentDataset = bitset(currentDataset, 7, 0);    % clear mask
            currentDataset = bitor(currentDataset, dataset*64);
            obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)) = currentDataset;
        case 'selection'
            currentDataset = obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2));
            currentDataset = bitset(currentDataset, 8, 0);    % clear selection
            currentDataset = bitor(currentDataset, dataset*128);
            obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)) = currentDataset;
        case 'everything'
            obj.data(Ylim(1):Ylim(2), Xlim(1):Xlim(2), Zlim(1):Zlim(2), colChannel, Tlim(1):Tlim(2)) = dataset;
    end
end
result = true;
end
