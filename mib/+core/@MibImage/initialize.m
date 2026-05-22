function initialize(obj, data, meta)
% INITIALIZE - initialize the class using default or provided values.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.initialize(data, meta)
%
% Input Arguments:
%   - **data** — matrix with the image to initialize the class, can be empty
%   - **meta** — a dictionary with default settings for the class, can be empty;
%     the following fields are used,
%     .filename full path to the dataset
%     .SliceName cell array with slice names, can be empty
%     .lutColors matrix with LUT colors to use (colChannel, R G B) in range 0-1
%     .pixSize structure with
%
%     - ``.x`` — physical width of a pixel
%     - ``.y`` — physical height of a pixel
%     - ``.z`` — physical thickness of a pixel
%     - ``.t`` — time between the frames for 2D movies
%     - ``.tunits`` — time units
%     - ``.units`` — physical units for x, y, z. Possible values: [m, cm, mm, um, nm]
%       .viewPort structure with viewing parameters:
%     - ``.min`` — a vector with minimal value for intensity stretching for each color channel
%     - ``.max`` — a vector with maximal value for intensity stretching for each color channel
%     - ``.gamma`` a vector with gamma factor for contrast adjustment for each color channel
%

if nargin < 3; meta = []; end
if nargin < 2; data = []; end

% init meta as empty dictionary or combine with the provided
if isempty(meta); meta = core.MibImage.initializeImgInfo(); end

% init data with an empty matrix
if isempty(data)
    if strcmp(obj.type, 'image')
        obj.data{1} = uint8(randi(255, [512 512]));
        obj.exists = true;
    elseif strcmp(obj.type, 'virtual')
        obj.data{1} = uint8(1);  % 1x1 placeholder; replaced by MibVirtualImage.initialize
        obj.exists = false;
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
if ~isempty(obj.data)
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
    if isempty(meta{'Filename'}); meta{'Filename'} = 'none.tif'; end
    if ~isKey(meta, 'lutColors'); meta{'lutColors'} = utils.defaults.generateLUT(obj.colors); end
    if isempty(meta{'viewPort'}) || numel(meta{'viewPort'}.min) ~= obj.colors
        viewPort = obj.getDefaultViewPort();
        meta{'viewPort'} = viewPort;
    end
    obj.viewPort = meta{'viewPort'};

    obj.colormap =  meta{'Colormap'};

    % update additional properties
    obj.filename = meta{'Filename'};
    obj.sliceName = meta{'SliceName'};
    obj.sliceSize = meta{'SliceSize'};
    obj.lutColors = meta{'lutColors'};

    % ---- parse ImageDescription → boundingBox + actionLog ----------------
    % Compute a default bounding box from image dimensions × voxel size.
    % This is used whenever the file has no BoundingBox tag (e.g. plain PNG).
    pixSize = meta{'pixSize'};
    obj.pixSize = pixSize;
    defaultBB = [ 0, (max([obj.width,  2]) - 1) * pixSize.x, ...
                  0, (max([obj.height, 2]) - 1) * pixSize.y, ...
                  0, (max([obj.depth,  2]) - 1) * pixSize.z ];

    % Split the raw ImageDescription string (as stored in the file) into:
    %   imgDesc   — the 'BoundingBox x1 x2 y1 y2 z1 z2' prefix
    %   parsedLog — cell array of pipe-separated operation log entries
    [imgDesc, parsedLog] = core.MibImage.splitImageDescription(meta{'ImageDescription'});

    % Try to parse numeric coordinates from the BoundingBox prefix.
    coords = sscanf(imgDesc, 'BoundingBox %f %f %f %f %f %f');
    if numel(coords) == 6
        obj.boundingBox = coords(:)';
    else
        obj.boundingBox = defaultBB;
    end

    % Prefer a pre-split ActionLog already stored in meta by a loader that
    % called splitImageDescription itself; fall back to what we parsed above.
    if isKey(meta, 'ActionLog') && ~isempty(meta{'ActionLog'})
        obj.actionLog = meta{'ActionLog'};
    else
        obj.actionLog = parsedLog;
    end
    % ----------------------------------------------------------------------
    % update color type
    if ~isempty(meta{'ColorType'})
        obj.colorType = meta{'ColorType'};
    else
        if size(obj.data{1}, 4) == 1
            obj.colorType = 'grayscale';
        else
            obj.colorType = 'multichannel';
        end
    end
    % ensure colorType is consistent with actual data: 'grayscale' is only
    % valid for single-channel data; upgrade to 'multichannel' otherwise
    if strcmp(obj.colorType, 'grayscale') && obj.colors > 1
        obj.colorType = 'multichannel';
    end

    % capture custom metadata from loaders (e.g. BioFormats XML struct)
    if isKey(meta, 'meta') && isstruct(meta{'meta'})
        obj.customMeta = meta{'meta'};
    else
        obj.customMeta = struct();
    end

    % update obj.pyramid
    obj.pyramid = struct(); % structure to keep pyramid organization of data, convert axes to MIB order
    obj.pyramid.levelNames = {};
    obj.pyramid.levelImageSizes = [obj.height, obj.width obj.colors obj.depth obj.time];
    obj.pyramid.levelImageTranslations = [0 0 0 0 0];
    obj.pyramid.levelScaleFactors = [1 1 1];
    obj.pyramid.levelVoxelSizes = [meta{'pixSize'}.y meta{'pixSize'}.x meta{'pixSize'}.z];
    obj.pyramid.chunkSizes = [];
    obj.pyramid.shardSizes = [];
    if isKey(meta, 'Pyramid')
        obj.pyramid = utils.concatenateStructures(obj.pyramid, meta{'Pyramid'});
        % Remove Pyramid from obj.meta
        meta = remove(meta, 'Pyramid'); %#ok<NASGU>
    end
    
end
end
