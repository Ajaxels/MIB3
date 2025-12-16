function clearLayer(obj, layer, y, x, z, t, blockModeSwitch)
% function clearLayer(obj, layer, y, x, z, t, blockModeSwitch)
% Clear the layer, a wrapper function that is using 
% @li obj.labels.clearLayer, for core.MibLabels63
% @li obj.(layer).clearLayer, for other types
%
% Parameters:
% layer: a string with the target layer, can be []
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
% blockModeSwitch: [@em optional, logical] enable/disable the block mode 
%   @li [] - use the currently selected value "obj.blockModeSwitch"
%   @li true - enable the block mode switch, clear only the shown area of the dataset
%   @li false - disable the block mode switch, clear the full dataset
%
% Return values:
% 

%| 
% Examples:
% @code obj.mibModel.I{obj.mibModel.Id}.clearLayer('selection'); // call from mibController, clear the Selection layer completely @endcode

if nargin < 7; blockModeSwitch = obj.blockModeSwitch; end
if nargin < 6; t = []; end
if nargin < 5; z = []; end
if nargin < 4; x = []; end
if nargin < 3; y = '4D'; end
if nargin < 2; layer = 'selection'; end

% find the currently visible limits
if blockModeSwitch == 1
    x = ceil(obj.axesX);
    y = ceil(obj.axesY);
end

if isa(obj.labels, 'core.MibLabels63') && ~strcmp(layer, 'image')
    obj.labels.clearLayer(layer, y, x, z, t);
else
    obj.(layer).clearLayer([], y, x, z, t);
end