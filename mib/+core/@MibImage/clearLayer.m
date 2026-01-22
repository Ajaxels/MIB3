function clearLayer(obj, layerName, y, x, z, t)
% function clearLayer(obj, layerName, y, x, z, t)
% Clear the layer, use parameters to specify the area where the layer should be cleared.
%
% Parameters:
% layerName: char with the target layer name, can be []
% @li [] -> 'selection'
% @li 'selection' -> clear the selection layer
% @li 'mask' -> clear the mask layer
% @li 'labels' -> clear the labels layer
% @li 'everything' -> clear selection, mask, labels layers for core.MibLabels63 class only
% @li 'image' -> clear the image layer
% y: [@em optional], a vector of y-values, can be []
%       @li when @b [], y = '4D', to clear complete dataset
%       @li vector of Y-min Y-max values - [minY, maxY]; 
%       @li char '2D', '3D', '4D' with the mode
% x: [@em optional], can be @b [], vector of X-min and X-max values [minX, maxX]
% z: [@em optional] vector of Z-min, Z-max, for example [minZ, maxZ]
% t: [@em optional] vector of T-min, T-max values, for example [minT, maxT]
%
% Return values:
% 

%| 
% Examples:
% @code obj.mibModel.I{obj.mibModel.id}.selection.clearLayer(); // call from mibController, clear the Selection layer completely @endcode
% @code obj.mibModel.I{obj.mibModel.id}.selection.clearLayer([], 1:imageData.y, 1:imageData.x, 1:3); //  call from mibController, clear the Selection layer only in 3 first slices  @endcode

% @code obj.clearLayer('selection');      // clear the layer, call from the class @endcode
% @code dataset = obj.clearLayer('everything'); // clear the layer call from MibController, where type='image', 'label', 'mask', 'selection', 'everything'

% Updates
% 

if nargin < 6; t = []; end
if nargin < 5; z = []; end
if nargin < 4; x = []; end
if nargin < 3; y = '4D'; end
if nargin < 2; layerName = 'selection'; end

if isempty(obj.data{1}); return; end    % selection is disabled

if ischar(y)
    [h, w, c, d, t] = obj.getDatasetDimensions([], [], blockModeSwitch);
    if ~isempty(x) && ~isempty(y)
        getDataOptions.x = x;
        getDataOptions.y = y;
        h = diff(y)+1;
        w = diff(x)+1;
    end

    switch y
        case '2D'
            img = zeros([h, w, 1, c], obj.dataClass);
            getDataOptions.z = [obj.slices{obj.orientation}(1) obj.slices{obj.orientation}(1)];
            getDataOptions.t = [obj.slices{5}(1) obj.slices{5}(1)];

            obj.setData(img, layerName, [], [], getDataOptions);
        case '3D'
            img = zeros([h, w, d, c], obj.dataClass);
            getDataOptions.t = [obj.slices{5}(1) obj.slices{5}(1)];
            obj.setData(img, layerName, [], [], getDataOptions);
        case '4D'
            img = zeros([h, w, d, c, t], obj.dataClass);
            obj.setData(img, layerName);
            obj.exists = false; % set indicator that it is a dummy model
    end
else
    % update time
    if isempty(t)
        getDataOptions.t = [1 obj.time]; 
    elseif numel(t) == 2   % t = [minT, maxT] format
        getDataOptions.t = [max([1 t(1)]) min([t(2) obj.time])]; 
    else
        getDataOptions.t = [t(1) t(1)]; 
    end
    dt = diff(getDataOptions.t)+1;

    % update depth
    if isempty(z)
        getDataOptions.z = [1 obj.depth]; 
    elseif numel(z) == 2    % z = [minZ, maxZ] format
        getDataOptions.z = [max([1 z(1)]) min([z(2) obj.depth])]; 
    else
        getDataOptions.z = [z(1) z(1)];
    end
    dz = diff(getDataOptions.z)+1;

    % update width
    if isempty(x)
        getDataOptions.x = [1 obj.width]; 
    elseif numel(x) == 2    % x = [minX, maxX] format
        getDataOptions.x = [max([1 x(1)]) min([x(2) obj.width])]; 
    else
        getDataOptions.x = [x(1) x(1)];
    end
    dx = diff(getDataOptions.x)+1;

    % update height
    if isempty(y)
        getDataOptions.y = [1 obj.height]; 
    elseif numel(y) == 2    % y = [minY, maxY] format
        getDataOptions.y = [max([1 y(1)]) min([y(2) obj.height])]; 
    else
        getDataOptions.y = [y(1) y(1)];
    end
    dy = diff(getDataOptions.y)+1;

    % define color vector
    c = 1:obj.colors;

    if ~isa(obj, 'core.MibLabels63') 
        if nargin < 3
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, obj.colors, obj.time], obj.dataClass);
        else
            obj.data{1}(getDataOptions.y(1):getDataOptions.y(2), ...
                        getDataOptions.x(1):getDataOptions.x(2), ...
                        getDataOptions.z(1):getDataOptions.z(2), ...
                        c, ...
                        getDataOptions.t(1):getDataOptions.t(2)) = 0;
        end
    else
        img = zeros([dy, dx, dz, numel(c), dt], obj.dataClass);
        obj.setData(img, layerName, [], [], getDataOptions);
    end
end

end