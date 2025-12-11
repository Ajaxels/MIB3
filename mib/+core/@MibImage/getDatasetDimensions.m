function varargout = getDatasetDimensions(obj, orient, splitDims)
% function varargout = getDatasetDimensions(obj, orient, splitDims)
% Get dimensions of the dataset as [height, width, depth, colors, time] or
% combined vector
%
% Parameters:
% orient: [@em optional], can be @em [] 
% @li when @b 1 returns dimensions of the transposed dataset to the zx configuration: [y,x,z,c,t] -> [x,z,y,c,t]
% @li when @b 2 returns dimensions of the transposed dataset to the zy configuration: [y,x,z,c,t] -> [y,z,x,c,t]
% @li when @b 3 returns dimensions of the original dataset to the yx configuration: [y,x,z,c,t]
% splitDims: logical
% .true -> [@em default] split dimensions into individual variables as height, width, depth, color, time; 
% .false -> return a single array where each of this dimensions is reported - [height, width, depth, color, time]
%
% Return values:
% height: height of the dataset
% width: width of the dataset
% depth: number of z-layers of the dataset
% colors: vector of colors of the dataset
% time: number of time points
% or vector with all those numbers when splitDims == true

% define missing parameters
if nargin < 3; splitDims = true; end  
if nargin < 2; orient = []; end  

% update default settings
if isempty(orient); orient = 3; end % YX-plane

%| 
% @b Examples:
% @code [height, width, depth, colors, time] = MibBaseImage.getDatasetDimensions()      // get dimensions of the complete dataset  @endcode

dim_yxzct = size(obj.data{1});
if numel(dim_yxzct) < 4; dim_yxzct(4:5) = [1 1]; end
if numel(dim_yxzct) < 5; dim_yxzct(5) = 1; end

colors = dim_yxzct(4);
time = dim_yxzct(5);

if orient == 3 % yx
    height = dim_yxzct(1);
    width = dim_yxzct(2);
    depth = dim_yxzct(3);
elseif orient==1     % xz
    height = dim_yxzct(2);
    width = dim_yxzct(3);
    depth = dim_yxzct(1);
elseif orient==2 % yz
    height = dim_yxzct(1);
    width = dim_yxzct(3);
    depth = dim_yxzct(2);
end

% Return based on outputMode
if splitDims
    varargout{1} = height;
    varargout{2} = width;
    varargout{3} = depth;
    varargout{4} = colors;
    varargout{5} = time;
else
    varargout{1} = dim_yxzct;
end

end