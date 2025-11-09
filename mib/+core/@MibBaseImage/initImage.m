function initImage(obj, img, meta)
% function initImage(obj, img, meta)
% initialize the class using default or provided values
%
% Parameters:
% img: matrix with the image to initialize the class, can be empty
% meta: a structure with default settings for the class, can be empty; the
% following fields are used:
% .filename -> full path to the dataset
% .sliceName -> cell array with slice names, can be empty
% .lutColors -> matrix with LUT colors to use (colChannel, R G B) in range 0-1
% .pixSize -> structure with
%   @li .x - physical width of a pixel
%   @li .y - physical height of a pixel
%   @li .z - physical thickness of a pixel
%   @li .t - time between the frames for 2D movies
%   @li .tunits - time units
%   @li .units - physical units for x, y, z. Possible values: [m, cm, mm, um, nm]


if nargin < 3; meta = struct(); end
if nargin < 2; img = []; end

% init img with an empty matrix
if isempty(img)
    obj.img{1} = zeros([256 256], 'uint8');  
else
    obj.img{1} = img;
end

% update default properties of the class
[y, x, z, c, t] = size(obj.img{1});
obj.width = x;  % width of the dataset
obj.height = y; % height of the dataset
obj.depth = z;  % depth of the dataset
obj.colors = c; % number of colors of the dataset
obj.time = t;   % number of time points of the dataset
obj.maxInt = double(intmax(class(obj.img{1}))); % max value that is possible to store in the dataset
obj.imgClass = class(obj.img{1}); % image class

% fix the missing properties in the provided meta class
if isfield(meta, 'filename'); meta.filename = 'none.tif'; end
if isfield(meta, 'sliceName'); meta.sliceName = []; end
if isfield(meta, 'lutColors'); meta.lutColors = utils.defaults.generateLUT(obj.colors); end
if isfield(meta, 'pixSize'); meta.pixSize = struct('x', 1, 'y', 1, 'z', 1, 't', 1, 'units', 'pixels', 'tunits', 's');

% update additional properties
obj.filename = meta.filename;
obj.sliceName = meta.sliceName;
obj.lutColors = meta.lutColors;
obj.pixSize = meta.pixSize;

end