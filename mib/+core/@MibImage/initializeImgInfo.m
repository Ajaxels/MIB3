function imginfo = initializeImgInfo(varargin)
% function imginfo = initializeImgInfo(varargin)
% Create the standard MibImage metadata dictionary, optionally overriding
% defaults via Name-Value pairs.
%
% This is the CANONICAL factory for the imginfo dictionary used throughout
% MIB3 to carry image metadata between loaders, core data classes, and
% savers.  Ownership of the schema lives here because MibImage is the class
% that ultimately consumes every field.  All other components — loaders,
% MibDataset, savers — must call this method rather than constructing the
% dictionary by hand.  This guarantees that every key is always present
% with a well-defined default, regardless of which component creates the dict.
%
% IMAGEDESCRPTION / ACTIONLOG SPLIT
%   The full ImageDescription string stored in TIFF and other formats has
%   the structure:
%
%       'BoundingBox x1 x2 y1 y2 z1 z2|LogEntry1|LogEntry2|...'
%
%   MIB3 stores the two parts separately inside the dictionary:
%     - "ImageDescription"  ->  BoundingBox string only (before first '|')
%     - "ActionLog"         ->  cell array of log entries (after first '|')
%
%   When a loader reads the raw combined string from a file it should call
%   core.MibImage.splitImageDescription() and pass the two parts as
%   separate Name-Value pairs to this function.
%
% Parameters:
%   varargin — optional Name-Value pairs overriding any subset of the keys
%              listed below.  Unrecognised keys are stored in the dictionary
%              unchanged, so format-specific metadata (e.g. TIFF tags) can
%              be carried through without special-casing.
%
%   Key                  Type        Default          Description
%   ---                  ----        -------          -----------
%   'Filename'           char        'none.tif'       Full path to the source file
%   'Height'             double      512              Image height in pixels
%   'Width'              double      512              Image width in pixels
%   'Colors'             double      1                Number of colour channels
%   'Colormap'           double[]    []               Colormap for indexed images
%   'Depth'              double      1                Number of z-slices
%   'Time'               double      1                Number of time points
%   'imgClass'           char        'uint8'          MATLAB image class
%   'ColorType'          char        'grayscale'      'grayscale'|'multichannel'|
%                                                     'hsvcolor'|'indexed'
%   'ImageDescription'   char        ''               BoundingBox string only
%                                                     (part BEFORE the first '|')
%   'ActionLog'          cell        {}               Per-operation log entries
%                                                     (parts AFTER the first '|',
%                                                     one entry per cell)
%   'MaxInt'             double      255              Maximum representable intensity
%   'SliceName'          cell        {}               Per-slice source filenames
%   'pixSize'            struct                       Voxel / time-step sizes
%                                                     (from utils.defaults.initializePixSize):
%                                                       .x      pixel width  [um]  = 1
%                                                       .y      pixel height [um]  = 1
%                                                       .z      slice thickness [um] = 1
%                                                       .t      time step [s]      = 1
%                                                       .units  spatial units      = 'um'
%                                                       .tunits time units         = 's'
%   'viewPort'           struct                       Display stretch parameters:
%                                                       .min    = 0
%                                                       .max    = 255
%                                                       .gamma  = 1
%   'lutColors'          double Nx3  (auto)           LUT colours, values 0..1,
%                                                     one row per colour channel
%
% Return values:
%   imginfo — dictionary with all standard MibImage metadata fields.
%             Caller-supplied Name-Value pairs override the defaults.
%
% USAGE EXAMPLES
%   @code
%   %% 1. Empty dictionary with all defaults
%   imginfo = core.MibImage.initializeImgInfo();
%   @endcode
%
%   @code
%   %% 2. Provide filename and physical voxel size only
%   pixSz = struct('x',0.013,'y',0.013,'z',0.025,'t',1,'units','um','tunits','s');
%   imginfo = core.MibImage.initializeImgInfo( ...
%       'Filename', '/data/em_volume.tif', ...
%       'pixSize',  pixSz);
%   @endcode
%
%   @code
%   %% 3. Loader workflow: split the raw ImageDescription tag first
%   rawDesc = 'BoundingBox 0 511.5 0 511.5 0 49.5|MIB(2601041823): opened|MIB(2603131934): filtered';
%   [imgDesc, actionLog] = core.MibImage.splitImageDescription(rawDesc);
%
%   imginfo = core.MibImage.initializeImgInfo( ...
%       'Filename',         '/data/stack.tif', ...
%       'ImageDescription', imgDesc, ...
%       'ActionLog',        actionLog, ...
%       'pixSize',          struct('x',0.013,'y',0.013,'z',0.025, ...
%                                 't',1,'units','um','tunits','s'));
%   @endcode
%
%   @code
%   %% 4. Full dimension metadata (useful in custom loaders)
%   imginfo = core.MibImage.initializeImgInfo( ...
%       'Filename',   '/data/multichannel.tif', ...
%       'Height',     1024, ...
%       'Width',      1024, ...
%       'Depth',      50,   ...
%       'Colors',     3,    ...
%       'ColorType',  'multichannel', ...
%       'imgClass',   'uint16', ...
%       'MaxInt',     65535);
%   @endcode
%
%   @code
%   %% 5. Add a format-specific tag (stored as-is, no error)
%   imginfo = core.MibImage.initializeImgInfo( ...
%       'Filename',          '/data/scan.tif', ...
%       'TiffBitsPerSample', 16);
%   @endcode
%
% SEE ALSO
%   core.MibImage.splitImageDescription, core.MibImage.buildImageDescription,
%   utils.defaults.initializePixSize, core.MibDataset.initialize,
%   core.MibImage.initialize

% --- build the default dictionary ---
imginfo = dictionary( ...
    "Filename",         {'none.tif'},                             ...
    "Height",           {512},                                    ...
    "Width",            {512},                                    ...
    "Colors",           {1},                                      ...
    "Colormap",         {[]},                                     ...
    "Depth",            {1},                                      ...
    "Time",             {1},                                      ...
    "imgClass",         {'uint8'},                                ...
    "ColorType",        {'grayscale'},                            ...
    "ImageDescription", {''},                                     ...
    "ActionLog",        {{}},                                     ...
    "MaxInt",           {255},                                    ...
    "SliceName",        {[]},                                     ...
    "pixSize",          {utils.defaults.initializePixSize()},     ...
    "viewPort",         {struct('min', 0, 'max', 255, 'gamma', 1)} ...
);

% --- apply caller overrides ---
for k = 1:2:numel(varargin)
    imginfo{varargin{k}} = varargin{k+1};
end
end
