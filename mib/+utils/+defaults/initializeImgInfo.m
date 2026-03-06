function imginfo = initializeImgInfo(~)
% function imginfo = initializeImgInfo(~)
% Initialize imginfo dictionary with standard keys
%
% This method creates a dictionary with all standard metadata fields
% initialized to empty values. This ensures consistent structure across
% all loaders and prevents missing key errors.
%
% Parameters:
%   none
%
% Return values:
%   imginfo: dictionary with standard image metadata keys
%       @li "Filename" - [char] source filename
%       @li "Height" - [numeric] image height in pixels
%       @li "Width" - [numeric] image width in pixels
%       @li "Colors" - [numeric] number of color channels
%       @li "Colormap" - [numeric] colormap for indexed images
%       @li "Depth" - [numeric] number of z-slices
%       @li "Time" - [numeric] number of time points
%       @li "imgClass" - [char] image class (uint8, uint16, etc.)
%       @li "ColorType" - [char] 'grayscale', 'truecolor', or 'indexed'
%       @li "ImageDescription" - [char] description with BoundingBox
%       @li "MaxInt" - [numeric] maximum intensity value
%       @li "SliceName" - [cell] slice names
%       @li "pixSize" - structure with voxel dimensions
%           @li .x - [numeric] pixel width, default = 1
%           @li .y - [numeric] pixel height, default = 1
%           @li .z - [numeric] slice thickness, default = 1
%           @li .units - [char] physical units, default = 'um'
%           @li .t - [numeric] time between frames, default = 1
%           @li .tunits - [char] time units, default = 's'
%
% Example:
%   @code
%   imginfo = utils.defaults.initializeImgInfo();
%   imginfo{"Width"} = 1024;
%   imginfo{"Height"} = 768;
%   @endcode

imginfo = dictionary( ...
    "Filename",          {'none.tif'},          ...
    "Height",            {512},         ...
    "Width",             {512},         ...
    "Colors",            {1},           ...
    "Colormap",          {[]},          ...
    "Depth",             {1},           ...
    "Time",              {1},           ...
    "imgClass",          {'uint8'},     ...
    "ColorType",         {'grayscale'}, ...
    "ImageDescription",  {sprintf('|')},          ...
    "MaxInt",            {255},         ...
    "SliceName",         {[]},          ...
    "pixSize",           {utils.defaults.initializePixSize},     ...
    "viewPort",          {struct('min', 0, 'max', 255, 'gamma', 1)}      ...
);
end