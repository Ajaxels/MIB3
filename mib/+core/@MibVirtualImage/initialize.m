function initialize(obj, data, meta)
% INITIALIZE - Initialize MibVirtualImage with a dummy placeholder or provided file paths.
%
% Syntax:
%   function initialize(obj, data, meta)
%
% Overrides MibImage.initialize for virtual (disk-resident) datasets.
% Unlike the base class, dimensions are derived from 'meta' rather than
% from the data array, and obj.data{} stores file-path strings rather
% than pixel arrays.
%
% Input Arguments:
%   - **data** — *(optional)*:
%
%     - ``[]`` *(default)* — placeholders are set using ``assets/images/default.h5``
%     - **cell** array of file-path strings — stored directly in ``obj.data{}``
%     - **numeric** array — treated as a standard image (unusual; calls parent)
%   - **meta** — *(optional)*, a dictionary with dataset metadata (same fields as MibImage.initialize)
%
% Output Arguments:
%   (none — modifies obj in place)
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.initialize();% blank virtual placeholder
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.initialize({'/data/file.h5'}, meta);% load file paths
%

%% Updates
%
if nargin < 3; meta = []; end
if nargin < 2; data = []; end

if isempty(meta); meta = core.MibImage.initializeImgInfo(); end

% --- close any previously open virtual readers and loader objects --------
if iscell(obj.data) && ~isempty(obj.data)
    obj.closeVirtualDataset();
end
obj.loaders = {};

% --- set up data storage and dimensions ----------------------------------
if isempty(data)
    % placeholder: store the dummy .h5 path but mark as not yet loaded
    persistent mibInstallPath
    if isempty(mibInstallPath)
        mibInstallPath = utils.getInstallationPath('mib3');
        if isempty(mibInstallPath)
            % fallback: derive from this file's location (@MibVirtualImage → mib root)
            mibInstallPath = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        end
    end
    obj.data{1} = fullfile(mibInstallPath, 'assets', 'images', 'default.h5');
    obj.exists   = false;

    % dimensions: use meta if populated, otherwise fall back to 1
    obj.height   = max([1, double(meta{'Height'})]);
    obj.width    = max([1, double(meta{'Width'})]);
    obj.depth    = max([1, double(meta{'Depth'})]);
    obj.colors   = max([1, double(meta{'Colors'})]);
    obj.time     = 1;   % time is rarely stored in meta at this stage

elseif iscell(data)
    % caller is providing the actual file paths (e.g. after user selects files)
    obj.data   = data;
    obj.exists = true;

    % dimensions must come from meta (set by the loader before calling initialize)
    obj.height = max([1, double(meta{'Height'})]);
    obj.width  = max([1, double(meta{'Width'})]);
    obj.depth  = max([1, double(meta{'Depth'})]);
    obj.colors = max([1, double(meta{'Colors'})]);
    obj.time   = 1;
    if isKey(meta, 'Time') && ~isempty(meta{'Time'}); obj.time = double(meta{'Time'}); end

else
    % numeric array passed — delegate to base class (unusual for virtual)
    obj.initialize@core.MibImage(data, meta);
    return;
end

% --- shared properties derived from meta ---------------------------------
imgClass        = meta{'imgClass'};
if isempty(imgClass); imgClass = 'uint8'; end
obj.dataClass   = imgClass;
obj.maxInt      = double(intmax(imgClass));
obj.dim_yxzct   = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

if isempty(meta{'Filename'}); meta{'Filename'} = 'none.tif'; end
obj.filename = meta{'Filename'};

if ~isKey(meta, 'lutColors')
    meta{'lutColors'} = utils.defaults.generateLUT(obj.colors);
end
obj.lutColors = meta{'lutColors'};

if isempty(meta{'viewPort'})
    meta{'viewPort'} = obj.getDefaultViewPort();
end
obj.viewPort = meta{'viewPort'};

% update other parameters
obj.colormap  = meta{'Colormap'};
obj.sliceName = meta{'SliceName'};

if ~isempty(meta{'ColorType'})
    obj.colorType = meta{'ColorType'};
else
    if obj.colors == 1
        obj.colorType = 'grayscale';
    else
        obj.colorType = 'multichannel';
    end
end

% --- pyramid (virtual datasets may carry full pyramid via meta) ----------
obj.pyramid                        = struct();
obj.pyramid.levelNames             = {};
obj.pyramid.levelImageSizes        = [obj.height, obj.width, obj.colors, obj.depth, obj.time];
obj.pyramid.levelImageTranslations = [0 0 0 0 0];
obj.pyramid.levelScaleFactors      = [1 1 1];
obj.pyramid.levelVoxelSizes        = [meta{'pixSize'}.y, meta{'pixSize'}.x, meta{'pixSize'}.z];
obj.pyramid.chunkSizes             = [];
obj.pyramid.shardSizes             = [];
if isKey(meta, 'Pyramid')
    obj.pyramid = utils.concatenateStructures(obj.pyramid, meta{'Pyramid'});
    meta = remove(meta, 'Pyramid'); %#ok<NASGU>
end

% Apply Virtual struct populated by HDF5VirtualSetupLoader.loadImages
% (mirrors the Pyramid pattern above)
if isKey(meta, "Virtual")
    virtualInfo = meta{"Virtual"};
    obj.Virtual.objectType    = virtualInfo.objectType;
    obj.Virtual.seriesName    = virtualInfo.seriesName;
    obj.Virtual.slicesPerFile = virtualInfo.slicesPerFile;
    obj.Virtual.filenames     = virtualInfo.filenames;
    obj.Virtual.readerId      = virtualInfo.readerId;
    if isfield(virtualInfo, 'transMatrix')
        obj.Virtual.transMatrix = virtualInfo.transMatrix;
    else
        obj.Virtual.transMatrix = cell(1, numel(virtualInfo.filenames));
    end
    meta = remove(meta, "Virtual"); %#ok<NASGU>
end
end
