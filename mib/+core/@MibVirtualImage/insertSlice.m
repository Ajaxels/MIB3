function insertSlice(obj, img, insertPosition, dim, virtMeta, options)
% INSERTSLICE - Insert virtual file references into the virtual dataset along the depth dimension.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertSlice(img, insertPosition, dim, virtMeta, options)
%
% Overrides MibImage.insertSlice for virtual (MibVirtualImage) datasets.
% Instead of manipulating pixel arrays, this method splices cell arrays of
% file paths (obj.data) and the Virtual metadata struct (obj.Virtual).
%
% Input Arguments:
%   - **img** — cell array of file-path strings to insert (one entry per slice)
%   - **insertPosition** — 1-based insertion index; 0 or NaN means append to the end
%   - **dim** — 'depth' (default); 'time' is not supported for virtual datasets
%   - **virtMeta** — struct with fields matching obj.Virtual:
%
%     - ``.filenames``, ``.objectType``, ``.readerId``, ``.seriesName``, ``.slicesPerFile``
%   - **options** — *(optional)* struct with fields:
%
%     - ``.sliceNames`` — cell array of names for the inserted slices (default {})
%
% Output Arguments:
%   none
%
%   After the call the following properties are updated:
%   obj.data, obj.Virtual, obj.depth, obj.dim_yxzct, obj.sliceName (when applicable)
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.image.insertSlice(newFilePaths, 1, 'depth', meta{'Virtual'});
%

% Updates
%

if nargin < 6; options = struct; end
if nargin < 4; dim = 'depth'; end
if ~isfield(options, 'sliceNames'); options.sliceNames = {}; end

if ~strcmp(dim, 'depth')
    error('core:MibVirtualImage:insertSlice:unsupportedDim', ...
        'Inserting along the time dimension is not supported for virtual datasets.');
end

D1_z = obj.depth;
nNew = numel(img);

% clamp insertPosition
if isnan(insertPosition) || insertPosition == 0; insertPosition = D1_z + 1; end

if insertPosition == 1
    obj.data = [img; obj.data];
    obj.Virtual.filenames     = [virtMeta.filenames;    obj.Virtual.filenames];
    obj.Virtual.objectType    = [virtMeta.objectType;   obj.Virtual.objectType];
    obj.Virtual.readerId      = [virtMeta.readerId;     obj.Virtual.readerId + max(virtMeta.readerId)];
    obj.Virtual.seriesName    = [virtMeta.seriesName;   obj.Virtual.seriesName];
    obj.Virtual.slicesPerFile = [virtMeta.slicesPerFile; obj.Virtual.slicesPerFile];
elseif insertPosition == D1_z+1
    obj.data = [obj.data; img];
    obj.Virtual.filenames     = [obj.Virtual.filenames;    virtMeta.filenames];
    obj.Virtual.objectType    = [obj.Virtual.objectType;   virtMeta.objectType];
    obj.Virtual.readerId      = [obj.Virtual.readerId;     virtMeta.readerId + max(obj.Virtual.readerId)];
    obj.Virtual.seriesName    = [obj.Virtual.seriesName;   virtMeta.seriesName];
    obj.Virtual.slicesPerFile = [obj.Virtual.slicesPerFile; virtMeta.slicesPerFile];
else
    obj.data = [obj.data(1:insertPosition-1); img; obj.data(insertPosition:end)];
    obj.Virtual.filenames     = [obj.Virtual.filenames(1:insertPosition-1);    virtMeta.filenames;    obj.Virtual.filenames(insertPosition:end)];
    obj.Virtual.objectType    = [obj.Virtual.objectType(1:insertPosition-1);   virtMeta.objectType;   obj.Virtual.objectType(insertPosition:end)];
    obj.Virtual.readerId      = [obj.Virtual.readerId(1:insertPosition-1); ...
                                 virtMeta.readerId + max(obj.Virtual.readerId(1:insertPosition-1)); ...
                                 obj.Virtual.readerId(insertPosition:end) + max(virtMeta.readerId)];
    obj.Virtual.seriesName    = [obj.Virtual.seriesName(1:insertPosition-1);   virtMeta.seriesName;   obj.Virtual.seriesName(insertPosition:end)];
    obj.Virtual.slicesPerFile = [obj.Virtual.slicesPerFile(1:insertPosition-1); virtMeta.slicesPerFile; obj.Virtual.slicesPerFile(insertPosition:end)];
end

obj.depth = D1_z + nNew;
obj.dim_yxzct(3) = obj.depth;

% ---- update sliceName ----
if ~isempty(obj.sliceName)
    sliceNames = obj.sliceName;
    if numel(sliceNames) == 1; sliceNames = repmat(sliceNames, [D1_z 1]); end %#ok<ISCL>

    sliceNamesNew = options.sliceNames;
    if isempty(sliceNamesNew); sliceNamesNew = {''}; end
    if numel(sliceNamesNew) == 1; sliceNamesNew = repmat(sliceNamesNew, [nNew 1]); end %#ok<ISCL>

    if insertPosition == D1_z+1
        sliceNames = [sliceNames; sliceNamesNew];
    elseif insertPosition == 1
        sliceNames = [sliceNamesNew; sliceNames];
    else
        sliceNames = [sliceNames(1:insertPosition-1); sliceNamesNew; sliceNames(insertPosition:end)];
    end
    obj.sliceName = sliceNames;
end

end
