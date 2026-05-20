function imginfo = initializeImgInfo(varargin)
% INITIALIZEIMGINFO - Create the standard MibImage metadata dictionary, optionally overriding defaults via Name-Value pairs.
%
% Syntax:
%   .. code-block:: matlab
%
%       imginfo = initializeImgInfo(varargin)
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
% The full ImageDescription string stored in TIFF and other formats has
% the structure:
%
% 'BoundingBox x1 x2 y1 y2 z1 z2|LogEntry1|LogEntry2|...'
%
% MIB3 stores the two parts separately inside the dictionary:
% - "ImageDescription" BoundingBox string only (before first '|')
% - "ActionLog" cell array of log entries (after first '|')
%
% When a loader reads the raw combined string from a file it should call
% core.MibImage.splitImageDescription() and pass the two parts as
% separate Name-Value pairs to this function.
%
% Input Arguments:
%   - **varargin** — optional Name-Value pairs overriding any subset of the default keys.
%     Unrecognised keys are stored in the dictionary unchanged, allowing format-specific
%     metadata (e.g. TIFF tags) to be carried through without special-casing.
%
%     Supported keys (with defaults):
%
%     - ``'Filename'`` — (char) full path to the source file; default ``'none.tif'``
%     - ``'Height'`` — (double) image height in pixels; default ``512``
%     - ``'Width'`` — (double) image width in pixels; default ``512``
%     - ``'Colors'`` — (double) number of colour channels; default ``1``
%     - ``'Colormap'`` — (double[]) colormap for indexed images; default ``[]``
%     - ``'Depth'`` — (double) number of z-slices; default ``1``
%     - ``'Time'`` — (double) number of time points; default ``1``
%     - ``'imgClass'`` — (char) MATLAB image class; default ``'uint8'``
%     - ``'ColorType'`` — (char) ``'grayscale'`` | ``'multichannel'`` | ``'hsvcolor'`` | ``'indexed'``; default ``'grayscale'``
%     - ``'ImageDescription'`` — (char) BoundingBox string (part before the first ``'|'``); default ``''``
%     - ``'ActionLog'`` — (cell) per-operation log entries (parts after the first ``'|'``); default ``{}``
%     - ``'MaxInt'`` — (double) maximum representable intensity; default ``255``
%     - ``'SliceName'`` — (cell) per-slice source filenames; default ``{}``
%     - ``'SliceSize'`` — (double[N×2]) per-slice original ``[height, width]`` as rows; default ``[]``
%     - ``'pixSize'`` — (struct) voxel/time-step sizes from ``utils.defaults.initializePixSize()``:
%
%       - ``.x`` — pixel width [µm]; default ``1``
%       - ``.y`` — pixel height [µm]; default ``1``
%       - ``.z`` — slice thickness [µm]; default ``1``
%       - ``.t`` — time step [s]; default ``1``
%       - ``.units`` — spatial units; default ``'um'``
%       - ``.tunits`` — time units; default ``'s'``
%
%     - ``'viewPort'`` — (struct) display stretch parameters:
%
%       - ``.min`` — default ``0``
%       - ``.max`` — default ``255``
%       - ``.gamma`` — default ``1``
%
%     - ``'lutColors'`` — (double Nx3) LUT colours, values 0..1, one row per colour channel
%
% Output Arguments:
%   - **imginfo** — dictionary with all standard MibImage metadata fields.
%     Caller-supplied Name-Value pairs override the defaults.
%
% Usage:
%   **Example 1** — Empty dictionary with all defaults
%
%   .. code-block:: matlab
%
%
%       imginfo = core.MibImage.initializeImgInfo();
%
%   **Example 2** — Provide filename and physical voxel size only
%
%   .. code-block:: matlab
%
%
%       pixSz = struct('x',0.013,'y',0.013,'z',0.025,'t',1,'units','um','tunits','s');
%       imginfo = core.MibImage.initializeImgInfo( ...
%           'Filename', '/data/em_volume.tif', ...
%           'pixSize',  pixSz);
%
%   **Example 3** — Loader workflow: split the raw ImageDescription tag first
%
%   .. code-block:: matlab
%
%
%       rawDesc = 'BoundingBox 0 511.5 0 511.5 0 49.5|MIB(2601041823): opened|MIB(2603131934): filtered';
%       [imgDesc, actionLog] = core.MibImage.splitImageDescription(rawDesc);
%
%       imginfo = core.MibImage.initializeImgInfo( ...
%           'Filename',         '/data/stack.tif', ...
%           'ImageDescription', imgDesc, ...
%           'ActionLog',        actionLog, ...
%           'pixSize',          struct('x',0.013,'y',0.013,'z',0.025, ...
%                                     't',1,'units','um','tunits','s'));
%
%   **Example 4** — Full dimension metadata (useful in custom loaders)
%
%   .. code-block:: matlab
%
%
%       imginfo = core.MibImage.initializeImgInfo( ...
%           'Filename',   '/data/multichannel.tif', ...
%           'Height',     1024, ...
%           'Width',      1024, ...
%           'Depth',      50,   ...
%           'Colors',     3,    ...
%           'ColorType',  'multichannel', ...
%           'imgClass',   'uint16', ...
%           'MaxInt',     65535);
%
%   **Example 5** — Add a format-specific tag (stored as-is, no error)
%
%   .. code-block:: matlab
%
%
%       imginfo = core.MibImage.initializeImgInfo( ...
%           'Filename',          '/data/scan.tif', ...
%           'TiffBitsPerSample', 16);
%
% See also:
%   core.MibImage.splitImageDescription, core.MibImage.buildImageDescription, utils.defaults.initializePixSize, core.MibDataset.initialize, core.MibImage.initialize
%

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
    "SliceSize",        {[]},                                     ...
    "pixSize",          {utils.defaults.initializePixSize()},     ...
    "viewPort",         {struct('min', 0, 'max', 255, 'gamma', 1)} ...
);

% --- apply caller overrides ---
for k = 1:2:numel(varargin)
    imginfo{varargin{k}} = varargin{k+1};
end
end
