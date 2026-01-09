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

coreImgInfoKeys = [ ...
    "Filename" ...
    "Height" ...
    "Width" ...
    "Colors" ...
    "Depth" ...
    "Time" ...
    "imgClass" ...
    "ColorType" ...
    "ImageDescription" ...
    "MaxInt" ...
    "SliceName" ...
    "pixSize" ...
    ];
coreImgInfoValues = repmat({[]}, size(coreImgInfoKeys));
imginfo = dictionary(coreImgInfoKeys, coreImgInfoValues);
% update pixSize
imginfo{"pixSize"} = utils.defaults.initializePixSize();
end