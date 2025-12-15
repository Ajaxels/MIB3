function clearLayer(obj, y, x, z, t, blockModeSwitch)
% function clearLayer(obj, y, x, z, t, blockModeSwitch)
% Clear the layer. It is also possible to specify the area where the layer should be cleared.
%
% Parameters:
% y: [@em optional], can be @b [], a vector of Y for example [1:obj.height] or [minY, maxY]; or a string with the mode ('2D', '3D', '4D') 
% x: [@em optional], can be @b [], a vector of X, for example [1:obj.width] or [minX, maxX]
% z: [@em optional] a vector of z-values, for example [1:obj.depth] or [minZ, maxZ]
% t: [@em optional] a vector of t-values, for example [1:obj.time] or [minT, maxT]
% blockModeSwitch: [@em optional] a switch use (1) or not (0) the blockMode
%
% Return values:
% 

%| 
% Examples:
% @code obj.mibModel.I{obj.mibModel.Id}.clearSelection(); // call from mibController, clear the Selection layer completely @endcode
% @code obj.mibModel.I{obj.mibModel.Id}.clearSelection(1:imageData.y, 1:imageData.x, 1:3); //  call from mibController, clear the Selection layer only in 3 first slices  @endcode

% @code obj.clearLayer();      // clear the layer, call from the class @endcode
% dataset = obj.(type).clearLayer(); // clear the layer call from MibDataset, where type='image', 'label', 'mask', 'selection'
% dataset = obj.mibModel.I{obj.mibModel.id}.(type).clearLayer(); // clear the layer call from MibController, where type='image', 'label', 'mask', 'selection'


% Updates
% 

if nargin < 6; blockModeSwitch = 0; end
if nargin < 5; t = []; end
if nargin < 4; z = []; end
if nargin < 3; x = []; end
if nargin < 2; y = '4D'; end

if ischar(y)
    getDataOptions.blockModeSwitch = blockModeSwitch;
    [h, w, c, d, t] = obj.getDatasetDimensions('image', [], getDataOptions);

    if blockModeSwitch == 1
        getDataOptions.x = ceil(obj.axesX);
        getDataOptions.y = ceil(obj.axesY);
    end

    switch y
        case '2D'
            img = zeros([h, w, 1, c], 'uint8');
            getDataOptions.z = [obj.slices{obj.orientation}(1) obj.slices{obj.orientation}(1)];
            getDataOptions.t = [obj.slices{5}(1) obj.slices{5}(1)];
            
            obj.setData(img, 'selection', [], [], getDataOptions);
        case '3D'
            img = zeros([h, w, d, c], 'uint8');
            getDataOptions.t = [obj.slices{5}(1) obj.slices{5}(1)];
            obj.setData(img, 'selection', [], [], getDataOptions);
        case '4D'
            img = zeros([h, w, d, c, t], 'uint8');
            obj.setData(img, 'selection');
    end
else
    if isempty(t)
        t = 1:obj.time; 
    elseif numel(t) == 2   % t = [minT, maxT] format
        t = max([1 t(1)]):min([t(2) obj.time]); 
    else
        t = t(1); 
    end

    if isempty(z)
        z = 1:obj.depth; 
    elseif numel(z) == 2    % z = [minZ, maxZ] format
        z = max([1 z(1)]):min([z(2) obj.depth]); 
    else
        z = z(1);
    end
    if isempty(x)
        x = 1:obj.width; 
    elseif numel(x) == 2    % x = [minX, maxX] format
        x = max([1 x(1)]):min([x(2) obj.width]); 
    else
        x = x(1);
    end

    if isempty(y)
        y = 1:obj.height; 
    elseif numel(y) == 2  && ~ischar(y)   % y = [minY, maxY] format
        y = max([1 y(1)]):min([y(2) obj.height]); 
    else
        y = y(1);
    end
    c = 1:obj.colors;

    
    if ~isa(obj, 'core.MibLabels63') 
        if nargin < 2
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, obj.colors, obj.time], obj.dataClass);
        else
            obj.data{1}(y, x, z, c, t) = 0;
        end
    else
        if isempty(obj.data{1}); return; end    % selection is disabled
        if nargin < 2
            obj.data{1} = bitset(obj.data{1}, 8, 0);
        else
            obj.data{1}(y, x, z, 1, t) = bitset(obj.data{1}(y, x, z, 1, t), 8, 0);
        end
    end
end
end