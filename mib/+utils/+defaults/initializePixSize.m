function pixSize = initializePixSize(~)
% function pixSize = initializePixSize(~)
% Initialize pixSize structure with default values
%
% This method creates a structure with default voxel dimensions.
% Physical units default to micrometers and temporal units to seconds.
%
% Parameters:
%   none
%
% Return values:
%   pixSize: structure with voxel dimensions
%       @li .x - [numeric] pixel width, default = 1
%       @li .y - [numeric] pixel height, default = 1
%       @li .z - [numeric] slice thickness, default = 1
%       @li .units - [char] physical units, default = 'um'
%       @li .t - [numeric] time between frames, default = 1
%       @li .tunits - [char] time units, default = 's'
%
% Example:
%   @code
%   pixSize = utils.defaults.initializePixSize();
%   pixSize.x = 0.065;  % 65 nm pixel size
%   pixSize.units = 'um';
%   @endcode

pixSize.x = 1;
pixSize.y = 1;
pixSize.z = 1;
pixSize.units = 'um';
pixSize.t = 1;
pixSize.tunits = 's';
end