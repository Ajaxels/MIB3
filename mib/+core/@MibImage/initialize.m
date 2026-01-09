function initialize(obj, data, meta)
% function initialize(obj, data, meta)
% initialize the class using default or provided values
%
% Parameters:
% data: matrix with the image to initialize the class, can be empty
% meta: a dictionary with default settings for the class, can be empty;
%       the following fields are used,
%       .filename -> full path to the dataset
%       .SliceName -> cell array with slice names, can be empty
%       .lutColors -> matrix with LUT colors to use (colChannel, R G B) in range 0-1
%       .pixSize -> structure with
%           @li .x - physical width of a pixel
%           @li .y - physical height of a pixel
%           @li .z - physical thickness of a pixel
%           @li .t - time between the frames for 2D movies
%           @li .tunits - time units
%           @li .units - physical units for x, y, z. Possible values: [m, cm, mm, um, nm]
%       .viewPort -> structure with viewing parameters:
%           @li .min - a vector with minimal value for intensity stretching for each color channel
%           @li .max - a vector with maximal value for intensity stretching for each color channel
%           @li .gamma a vector with gamma factor for contrast adjustment for each color channel

if nargin < 3; meta = []; end
if nargin < 2; data = []; end

% init meta as empty dictionary
if isempty(meta); meta = dictionary(); end

% init data with an empty matrix
if isempty(data)
    if strcmp(obj.type, 'image')
        obj.data{1} = uint8(randi(255, [256 256]));
        obj.exists = true;
    else
        obj.data = [];      % default for labels and other types
        obj.exists = false;
    end
else
    obj.data{1} = data;
    obj.exists = true;
end

% define data type: image, the other types: 'labels' used in MibLabels and 'labels63' in MibLabels63
%obj.type = 'image';

% update default properties of the class
[y, x, z, c, t] = size(obj.data{1});
obj.width = x;      % width of the dataset
obj.height = y;     % height of the dataset
obj.depth = z;      % depth of the dataset
obj.colors = c;     % number of colors of the dataset
obj.time = t;       % number of time points of the dataset
obj.maxInt = double(intmax(class(obj.data{1})));    % max value that is possible to store in the dataset
obj.dataClass = class(obj.data{1});                 % image class
obj.dim_yxzct = [obj.height obj.width obj.depth obj.colors obj.time];
% a matrix with dimensions of the dataset [height, width, depth, colors, time]
% equal to size obj.data{1} for non-virtual datasets

% fix the missing properties in the provided meta class
if ~isKey(meta, 'Filename'); meta{'Filename'} = 'none.tif'; end
if ~isKey(meta, 'SliceName'); meta{'SliceName'} = []; end
if ~isKey(meta, 'lutColors'); meta{'lutColors'} = utils.defaults.generateLUT(obj.colors); end
if ~isKey(meta, 'viewPort')
    viewPort = struct();
    viewPort.min = zeros([obj.colors, 1]);
    viewPort.max = zeros([obj.colors, 1]) + obj.maxInt;
    viewPort.gamma = zeros([obj.colors, 1]) + 1;
    if strcmp(obj.dataClass, 'uint32')
        obj.viewPort.min = zeros([obj.colors, 1]) + double(min(min(min(obj.data{1}(:,:,1,:,1)))));
        obj.viewPort.max = zeros([obj.colors, 1]) + double(max(max(max(obj.data{1}(:,:,1,:,1)))));
    end
    meta{'viewPort'} = viewPort;
end

% update additional properties
obj.filename = meta{'Filename'};
obj.sliceName = meta{'SliceName'};
obj.lutColors = meta{'lutColors'};
obj.viewPort = meta{'viewPort'};
end
