function varargout = getDatasetDimensions(obj, orient, splitDims, blockModeSwitch)
% function varargout = getDatasetDimensions(obj, orient, splitDims, blockModeSwitch)
% Get dimensions of the dataset as [height, width, depth, colors, time] or
% combined vector
%
% Parameters:
% orient: [@em optional], can be @em [] 
% @li when @b [] -> default "3"
% @li when @b 1 returns dimensions of the transposed dataset to the zx configuration: [y,x,z,c,t] -> [x,z,y,c,t]
% @li when @b 2 returns dimensions of the transposed dataset to the zy configuration: [y,x,z,c,t] -> [y,z,x,c,t]
% @li when @b 3 returns dimensions of the original dataset to the yx configuration: [y,x,z,c,t]
% splitDims: logical
% .true -> [@em default] split dimensions into individual variables as height, width, depth, color, time; 
% .false -> return a single array where each of this dimensions is reported - [height, width, depth, color, time]
% blockModeSwitch: [@em logical] return dimensions of the shown or full dataset, @em default == false
% @li @b false - return dimensions of the full dataset
% @li @b true - return dimensions of the shown part only

% Return values:
% height: height of the dataset
% width: width of the dataset
% depth: number of z-layers of the dataset
% colors: vector of colors of the dataset
% time: number of time points
% or vector with all those numbers when splitDims == true

% define missing parameters
if nargin < 4; blockModeSwitch = false; end  
if nargin < 3; splitDims = []; end  
if nargin < 2; orient = []; end  

% update default settings
if isempty(splitDims); splitDims = true; end % split dimensions
if isempty(orient); orient = 3; end % YX-plane

%| 
% @b Examples:
% @code [height, width, depth, colors, time] = MibBaseImage.getDatasetDimensions()      // get dimensions of the complete dataset  @endcode

dim_yxz = [obj.height, obj.width, obj.depth];
colors = obj.colors;
time = obj.time;

if blockModeSwitch
    if orient == 3 % yx
        height = obj.slices{1}(2)-obj.slices{1}(1)+1;
        width = obj.slices{2}(2)-obj.slices{2}(1)+1;
        depth = dim_yxz(3);
    elseif orient==1     % xz
        depth = dim_yxz(1);
        height = obj.slices{2}(2)-obj.slices{2}(1)+1;
        width = obj.slices{3}(2)-obj.slices{3}(1)+1;
    elseif orient==2 % yz
        height = obj.slices{1}(2)-obj.slices{1}(1)+1;
        width = obj.slices{3}(2)-obj.slices{3}(1)+1;
        depth = dim_yxz(2);
    end
else % block mode
    if orient == 3 % yx
        height = dim_yxz(1);
        width = dim_yxz(2);
        depth = dim_yxz(3);
    elseif orient==1     % xz
        height = dim_yxz(2);
        width = dim_yxz(3);
        depth = dim_yxz(1);
    elseif orient==2 % yz
        height = dim_yxz(1);
        width = dim_yxz(3);
        depth = dim_yxz(2);
    end
end

% Return based on outputMode
if splitDims
    varargout{1} = height;
    varargout{2} = width;
    varargout{3} = depth;
    varargout{4} = colors;
    varargout{5} = time;
else
    varargout{1} = [height, width, depth, colors, time];
end

end