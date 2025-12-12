function varargout = getDatasetDimensions(obj, type, orient, options)
% function [height, width, depth, color, time] = getDatasetDimensions(obj, type, orient, options)
% Get dimensions of the dataset
%
% Parameters:
% type:  type of the dataset to retrieve dimensions, 'image' (@b default), 'model', 'mask', 'selection'
% orient: [@em optional], can be @em [] 
% @li when @b 1 returns dimensions of the transposed dataset to the zx configuration: [y,x,z,c,t] -> [x,z,y,c,t]
% @li when @b 2 returns dimensions of the transposed dataset to the zy configuration: [y,x,z,c,t] -> [y,z,x,c,t]
% @li when @b 3 returns dimensions of the original dataset to the yx configuration: [y,x,z,c,t]
% options: [@em optional], a structure with extra parameters
% @li .blockModeSwitch -> @b 0 - return dimensions of the full dataset, @b 1 - return dimensions of the shown part only
% @li .splitDims -> logical
% .true -> [@em default] split dimensions into individual variables as height, width, depth, color, time; 
% .false -> return a single array where each of this dimensions is reported - [height, width, depth, color, time]
%
% Return values:
% height: height of the dataset
% width: width of the dataset
% depth: number of z-layers of the dataset
% colors: vector of colors of the dataset
% time: number of time points
% or vector with all those numbers when options.splitDims == true

%| 
% @b Examples:
% @code [height width color depth] = obj.mibModel.I{obj.mibModel.id}.getDatasetDimensions('image')      // get dimensions of the complete dataset  @endcode
% @code [height width color depth] = obj.mibModel.I{obj.mibModel.id}.getDatasetDimensions('image', 1)      // get dimensions of the transposed dataset  @endcode
% @attention @b not @b sensitive to the shown ROI

% Updates
% 

if nargin < 4; options = struct(); end
if nargin < 3; orient = []; end
if nargin < 2; type = []; end

if ~isfield(options, 'blockModeSwitch'); options.blockModeSwitch = obj.blockModeSwitch; end
if ~isfield(options, 'splitDims'); options.splitDims = true; end

if isempty(orient); orient = obj.orientation; end
if isempty(type); type = 'image'; end
time = obj.image.time;

if options.blockModeSwitch == 0     % get the full size dataset
    if strcmp(type, 'image')
        [height, width, depth, colors, time] = obj.image.getDatasetDimensions(orient);
    elseif isa(obj.labels, 'core.MibLabels63')
        [height, width, depth, colors, time] = obj.labels.getDatasetDimensions(orient);
    else
        [height, width, depth, colors, time] = obj.(type).getDatasetDimensions(orient);
    end
else        % get the shown block
    switch orient
        case 3  % yx configuration: [y,x,z,c,t]
            height = obj.slices{1}(2)-obj.slices{1}(1)+1;
            width = obj.slices{2}(2)-obj.slices{2}(1)+1;
            depth = obj.image.depth;
        case 2  % yz configuration: [y,x,z,c,t] -> [y,z,x,c,t]
            height = obj.slices{1}(2)-obj.slices{1}(1)+1;
            width = obj.slices{3}(2)-obj.slices{3}(1)+1;
            depth = obj.width;
        case 1  % xz configuration: [y,x,z,c,t] -> [x,z,y,c,t]
            height = obj.slices{2}(2)-obj.slices{2}(1)+1;
            width = obj.slices{3}(2)-obj.slices{3}(1)+1;
            depth = obj.height;
    end
    if strcmp(type, 'image')
        colors = numel(obj.slices{4});
    else
        colors = 1;
    end
end

% Return based on outputMode
if options.splitDims
    varargout{1} = height;
    varargout{2} = width;
    varargout{3} = depth;
    varargout{4} = colors;
    varargout{5} = time;
else
    varargout{1} = dim_yxzct;
end

end