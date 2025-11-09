function dataset = getData(obj, orient, col_channel, options) % get complete 4D dataset
% function dataset = getData(obj, type, orient, col_channel, options)
% Get dataset from MibBaseImage class
%
% Parameters:
% orient: [@em optional], can be @em [] 
% @li when @b 1 returns dimensions of the transposed dataset to the zx configuration: [y,x,z,c,t] -> [x,z,y,c,t]
% @li when @b 2 returns dimensions of the transposed dataset to the zy configuration: [y,x,z,c,t] -> [y,z,x,c,t]
% @li when @b 3 returns dimensions of the original dataset to the yx configuration: [y,x,z,c,t]
% col_channel: [@em optional],
% @li when @b type is 'image', @b col_channel is a vector with color numbers to take, when @b NaN [@e default] take the colors
% selected in the imageData.slices{3} variable, when @b 0 - take all colors of the dataset.
% @li when @b type is 'model' @b col_channel may be @em NaN - to take all materials of the model or an integer to take specific material. 
% In the later case the selected material will have index = 1.
% options: [@em optional], a structure with extra parameters
% @li .y -> [@em optional], [ymin, ymax] coordinates of the dataset to take
% after transpose for level=1, when @b 0 takes 1:obj.height; can be a single number
% @li .x -> [@em optional], [xmin, xmax] coordinates of the dataset to take
% after transpose for level=1, when @b 0 takes 1:obj.width; can be a single number
% @li .z -> [@em optional], [zmin, zmax] coordinates of the dataset to take
% after transpose, when @b 0 takes 1:obj.depth; can be a single number
% @li .t -> [@em optional], [tmin, tmax] coordinates of the dataset to take after transpose, when @b 0 takes 1:obj.time; can be a single number
% @li .level -> [@em optional], index of image level from the image pyramid
% custom_img: get dataset from a provided custom image stack, not implemented
%
% Return values:
% dataset: 4D or 5D stack. For the 'image' type: [1:height, 1:width, 1:colors, 1:depth, 1:time]; for all other types: [1:height, 1:width, 1:thickness, 1:time]

%|
% @b Examples:
% @code dataset = obj.getData('image');      // get the complete dataset in the shown orientation @endcode
% @code dataset = obj.getData('image', 4, 2); // get complete dataset in the XY orientation with only second color channel @endcode

% Updates
%