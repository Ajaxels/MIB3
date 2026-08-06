function result = loadMask(obj, filenames, options)
% LOADMASK - Load a binary mask into this dataset from files or a raw array.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.loadMask(filenames, options)
%
% Dataset-level orchestrator for mask loading. Called by MibModel.loadMask
% after BatchOpt processing, virtual-mode guarding, and file browsing are done.
%
% FILE PATH  - filenames is a cell array of full file paths.
%   ``.mask`` files are loaded with ``load()``; other formats use LoaderFactory.
%   Multiple files are stacked slice-by-slice into a 3D volume.
%
% IMPORT PATH - options.mask contains the raw array. filenames is empty (``[]``).
%
% After the array is obtained the method validates dimensions against the open
% image, binarises the data, rebuilds ``obj.mask`` as a new ``MibLabels``
% instance, and sets ``obj.maskExist = true``.
%
% Input Arguments:
%   - **filenames** - cell array of full file paths, or ``[]`` for the import path
%   - **options** - struct with loading parameters
%
%     - ``.mask`` - raw array to import (import path only)
%     - ``.loaderType`` - ``'matlab_mask'`` when loading ``.mask`` MAT files
%     - ``.loaderInfo`` - struct from ExtensionRegistryLoad.resolveLoader
%       (required for non-mask image formats)
%     - ``.batchModeSwitch`` - [logical, ``false``] suppress interactive dialogs
%     - ``.preferences`` - MIB preferences struct
%     - ``.ParentFigure`` - parent figure handle for dialogs
%     - ``.mibPath`` - path to MIB installation directory
%     - ``.showWaitbar`` - [logical, ``true``] show progress dialog
%
% Output Arguments:
%   - **result** - struct (non-empty) on success; ``[]`` on error or user cancel
%
% Usage:
%   **Example 1** - file path
%
%   .. code-block:: matlab
%
%      dsOpts.loaderType   = 'matlab_mask';
%      dsOpts.showWaitbar  = true;
%      dsOpts.ParentFigure = obj.mibGUI;
%      result = obj.mibModel.I{id}.loadMask({'C:\data\Mask_stack.mask'}, dsOpts);
%
%   **Example 2** - import path
%
%   .. code-block:: matlab
%
%      dsOpts.mask = myBinaryVolume;
%      result = obj.mibModel.I{id}.loadMask([], dsOpts);
%

% Updates

result = [];

if nargin < 3; options = struct(); end
if nargin < 2; filenames = {}; end

if ~isfield(options, 'batchModeSwitch'); options.batchModeSwitch = false; end
if ~isfield(options, 'showWaitbar');     options.showWaitbar = true; end
if ~isfield(options, 'mask');            options.mask = []; end

imgH = obj.image.height;
imgW = obj.image.width;
imgD = obj.image.depth;

%% Get raw mask array

maskArray = [];
maskFilename = '';

if ~isempty(options.mask)
    % ---- IMPORT PATH --------------------------------------------------------
    maskArray    = options.mask;
    maskFilename = '';

elseif isfield(options, 'loaderType') && strcmp(options.loaderType, 'matlab_mask')
    % ---- .mask MAT FILE PATH ------------------------------------------------
    if isempty(filenames)
        warning('MibDataset:loadMask', 'No filenames provided for matlab_mask loader');
        return;
    end

    waitbarHandle = [];
    if options.showWaitbar && isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
        try
            if isvalid(options.ParentFigure)
                waitbarHandle = uiprogressdlg(options.ParentFigure, ...
                    'Title', 'Loading mask', 'Message', 'Reading file...', ...
                    'Indeterminate', 'on');
            end
        catch
        end
    end

    if numel(filenames) == 1
        data = load(filenames{1}, '-mat');
        fields = fieldnames(data);
        maskArray = logical(data.(fields{1}));
    else
        % Multiple files → stack as 2D slices
        slices = cell(numel(filenames), 1);
        for fileIndex = 1:numel(filenames)
            data = load(filenames{fileIndex}, '-mat');
            fields = fieldnames(data);
            slices{fileIndex} = logical(data.(fields{1}));
        end
        maskArray = cat(3, slices{:});
    end
    maskFilename = filenames{1};

    if ~isempty(waitbarHandle); delete(waitbarHandle); end

else
    % ---- OTHER FORMAT PATH (via LoaderFactory) -------------------------------
    if isempty(filenames)
        warning('MibDataset:loadMask', 'No filenames provided');
        return;
    end
    if ~isfield(options, 'loaderInfo') || ~isstruct(options.loaderInfo)
        warning('MibDataset:loadMask', 'options.loaderInfo required for non-mask formats');
        return;
    end

    loaderOpts = struct();
    if isfield(options, 'ParentFigure'); loaderOpts.ParentFigure = options.ParentFigure; end
    if isfield(options, 'mibPath');      loaderOpts.mibPath      = options.mibPath; end
    loaderOpts.showWaitbar = options.showWaitbar;

    try
        loader = io.LoaderFactory.create(options.loaderInfo, loaderOpts);
    catch ME
        warning('MibDataset:loadMask', 'Failed to create loader: %s', ME.message);
        return;
    end

    [imginfo, files] = loader.loadMetadata(filenames, loaderOpts);
    if ~isKey(imginfo, 'numEntries') || imginfo{"numEntries"} == 0
        warning('MibDataset:loadMask', 'Loader returned no entries for: %s', filenames{1});
        return;
    end

    [rawData, ~] = loader.loadImages(files, imginfo, loaderOpts);
    maskArray    = uint8(squeeze(rawData) > 0);
    maskFilename = filenames{1};
end

if isempty(maskArray)
    warning('MibDataset:loadMask', 'No mask data returned');
    return;
end

%% Dimension validation (mirrors MibDataset.loadModel logic)

maskArray = squeeze(maskArray);
sz = size(maskArray);
maskH = sz(1);
maskW = sz(2);
maskD = 1;
if numel(sz) >= 3; maskD = sz(3); end

% H×W mismatch
if maskH ~= imgH || maskW ~= imgW
    if ~options.batchModeSwitch && isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
        choice = obj.promptSizeMismatch('Mask', maskH, maskW, imgH, imgW, [], options);
        if choice.cancelled; return; end
        if strcmp(choice.action, 'Resize'); action = 'Resize'; else; action = 'Crop'; end
    else
        % unattended (batch / no parent figure): keep the previous silent
        % top-left crop/pad fallback
        action = 'Crop';
        choice = struct('offsetY', 0, 'offsetX', 0);
    end
    maskArray = core.MibDataset.applySizeMismatch(maskArray, imgH, imgW, action, choice.offsetY, choice.offsetX);
    maskH = imgH;  %#ok<NASGU>
    maskW = imgW;  %#ok<NASGU>
end

% Depth adjustment
if maskD > imgD
    maskArray = maskArray(:, :, 1:imgD);
    maskD = imgD;
elseif maskD < imgD
    padded = zeros(imgH, imgW, imgD, 'uint8');
    padded(:, :, 1:maskD) = maskArray;
    maskArray = padded;
    maskD = imgD;  %#ok<NASGU>
end

% Ensure binary uint8 [H, W, D, 1, 1]
maskArray = reshape(uint8(maskArray > 0), [imgH, imgW, imgD, 1, 1]);

%% Store mask

if obj.labels.maxMaterials < 64
    % MibLabels63: mask bits are packed inside obj.labels - write via setData3D
    % so the packing logic inside MibLabels63 is applied correctly.
    obj.setData3D(squeeze(maskArray), 'mask', [], 3, NaN);
    obj.maskExist = true;

    % Filename lives on labels.maskFilename for MibLabels63
    if ~isempty(maskFilename)
        resolvedFilename = maskFilename;
    else
        [pathStr, fn] = fileparts(obj.image.filename);
        resolvedFilename = fullfile(pathStr, ['Mask_' fn '.mask']);
    end
    obj.labels.maskFilename = resolvedFilename;
    obj.image.maskFilename  = resolvedFilename;
else
    % Standalone MibLabels mask - rebuild the object so all dimension
    % properties (height, width, depth, …) are derived from actual data.
    maskMeta = core.MibImage.initializeImgInfo( ...
        'pixSize', obj.image.pixSize, ...
        'Height',  imgH, 'Width', imgW, 'Depth', imgD, 'Time', 1, 'Colors', 1);
    obj.mask = core.MibLabels(maskArray, maskMeta);
    obj.mask.materialNames  = {'Mask'};
    obj.mask.materialColors = [1 0 1];
    obj.maskExist = true;

    if ~isempty(maskFilename)
        obj.image.maskFilename = maskFilename;
        obj.mask.filename      = maskFilename;
    else
        [pathStr, fn] = fileparts(obj.image.filename);
        obj.image.maskFilename = fullfile(pathStr, ['Mask_' fn '.mask']);
        obj.mask.filename      = obj.image.maskFilename;
    end
end

result = struct('maskFilename', obj.image.maskFilename);
end
