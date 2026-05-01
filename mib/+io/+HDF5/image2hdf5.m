function result = image2hdf5(filename, imageS, options)
% IMAGE2HDF5 - Save image into hdf5 format.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = io.HDF5.image2hdf5(filename, imageS)
%      result = io.HDF5.image2hdf5(filename, imageS, options)
%
% Input Arguments:
%   - **filename** — filename for the HDF5 file
%   - **imageS** — dataset [height, width, colors, depth] or [height, width, depth]
%   - **options** — *(optional)* struct with additional parameters:
%
%     - ``.ChunkSize`` — [y, x, z] matrix of chunk size
%     - ``.Deflate`` — [numeric] gzip compression level 0–9 (default: ``0``)
%     - ``.overwrite`` — ``1`` = do not check whether file already exists
%     - ``.showWaitbar`` — ``1`` = show the progress bar, ``0`` = hide it
%     - ``.ParentFigure`` — *(optional)* handle to the main MIB UIFigure; when provided,
%       the progress bar is shown as a ``uiprogressdlg`` attached to that window;
%       when absent or empty, the legacy ``waitbar`` is used as a fallback
%     - ``.lutColors`` — not yet implemented
%     - ``.pixSize`` — not yet implemented
%     - ``.ImageDescription`` — cell string with dataset description
%     - ``.DatasetName`` — cell string or dictionary with metadata
%     - ``.order`` — (char) axis order string, e.g. ``'yxzct'`` (default) or ``'yxczt'``
%     - ``.height`` — height of the full dataset (required for initialisation, i.e. when ``options.t == 1``)
%     - ``.width`` — width of the full dataset (required for initialisation)
%     - ``.colors`` — number of colour channels (required for initialisation)
%     - ``.depth`` — depth of the full dataset (required for initialisation)
%     - ``.time`` — number of time points (required for initialisation)
%     - ``.x`` — minimal X coordinate for data to store
%     - ``.y`` — minimal Y coordinate for data to store
%     - ``.z`` — minimal Z coordinate for data to store
%     - ``.t`` — minimal T index for data to store
%     - ``.DatasetType`` — (char) type of the dataset: ``'image'``, ``'model'``, or ``'mask'``
%     - ``.DatasetClass`` — (char) image class of the dataset, e.g. ``'uint8'``, ``'uint16'``
%
% Output Arguments:
%   - **result** — ``1`` = success, ``0`` = failure
%

% Updates
% 

% **Example 1** — standalone use (no GUI parent):
%
%   .. code-block:: matlab
%
%      opts.showWaitbar = false;
%      opts.overwrite   = 1;
%      io.HDF5.image2hdf5('saveme.h5', image_var, opts);
%
% **Example 2** — GUI use (attach progress dialog to MIB window):
%
%   .. code-block:: matlab
%
%      opts.showWaitbar  = true;
%      opts.overwrite    = 1;
%      opts.ParentFigure = obj.mibModel.mibGUI;
%      io.HDF5.image2hdf5('saveme.h5', image_var, opts);

result = 0;
if nargin < 3; options = struct(); end
if nargin < 2; error('Please provide filename and image!'); end

if ~isfield(options, 'ChunkSize'); options.ChunkSize = [];    end
if ~isfield(options, 'Deflate'); options.Deflate = 0;    end
if ~isfield(options, 'overwrite'); options.overwrite = 0;    end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = 1;    end
% Dimension order must be set first — other defaults depend on it.
% Default 'yxzct' matches MIB3 native layout [H, W, D, C, T].
% Use 'yxczt' for legacy MIB2 / Ilastik-compatible layout [H, W, C, D, T].
if ~isfield(options, 'order'); options.order = 'yxzct'; end

if ~isfield(options, 'height'); options.height = size(imageS, 1); end
if ~isfield(options, 'width');  options.width  = size(imageS, 2); end
% Derive colors/depth positions from order so defaults are order-aware
if ~isfield(options, 'colors'); options.colors = size(imageS, strfind(options.order,'c')); end
if ~isfield(options, 'depth');  options.depth  = size(imageS, strfind(options.order,'z')); end
if ~isfield(options, 'time');   options.time   = size(imageS, strfind(options.order,'t')); end
if ~isfield(options, 'x'); options.x = 1; end
if ~isfield(options, 'y'); options.y = 1; end
if ~isfield(options, 'z'); options.z = 1; end
if ~isfield(options, 't'); options.t = 1; end
if ~isfield(options, 'DatasetName')    % Set dataset name and check for the leading slash
    options.DatasetName = '/MIB_Export';
else
    if options.DatasetName(1) ~= '/'
        options.DatasetName = ['/' options.DatasetName];
    end
end
if ~isfield(options, 'ImageDescription'); options.ImageDescription = ''; end
if ~isfield(options, 'DatasetType');      options.DatasetType = 'image'; end
if ~isfield(options, 'DatasetClass');     options.DatasetClass = class(imageS); end

if options.overwrite == 0
    if exist(filename,'file') == 2
        reply = questdlg(sprintf('!!! Warning !!!\n\nThe file exists!\nOverwrite?'),'Overwrite','Overwrite','Cancel','Cancel');
        if strcmp(reply,'Cancel'); return; end
    end
end

% % permute the matrix to make it yxczt
% if isempty(strfind(options.order,'c')) && ndims(imageS) < 5
%     imageS = reshape(imageS, size(imageS,1), size(imageS,2), 1, size(imageS,3),size(imageS,4));
% end

wb = [];
if options.showWaitbar
    if isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
        try
            wb = uiprogressdlg(options.ParentFigure, 'Title', 'Saving images as hdf5...', ...
                'Message', sprintf('%s\nPlease wait...', filename));
        catch; wb = []; end
    else
        curInt = get(0, 'DefaulttextInterpreter');
        set(0, 'DefaulttextInterpreter', 'none');
        wb = waitbar(0, sprintf('%s\nPlease wait...', filename), 'Name', 'Saving images as hdf5...', 'WindowStyle', 'modal');
    end
end

if exist(filename,'file') && options.t == 1  % for overwrite
    fileNameDelete = filename;
    delete(fileNameDelete);
end

% Build order-aware size/start/chunk helpers.
% dimSizeMap:  named dimension → its extent
% dimStartMap: named dimension → write start index (1-based)
% chunkSzMap:  named dimension → chunk size (spatial: from ChunkSize; c,t: 1)
dimSizeMap  = struct('y',options.height,'x',options.width, ...
                     'z',options.depth, 'c',options.colors,'t',options.time);
dimStartMap = struct('y',options.y,     'x',options.x, ...
                     'z',options.z,     'c',1,          't',options.t);

if isempty(options.ChunkSize)
    % default: chunk along y/x/z only (spatial), c and t unchunked
    options.ChunkSize = [options.height, options.width, options.depth];
end
chunkSzMap = struct('y',options.ChunkSize(1),'x',options.ChunkSize(2), ...
                    'z',options.ChunkSize(3),'c',1,'t',1);

% Derive the 5-element vectors in the caller's chosen order
datasetSize  = cellfun(@(d) dimSizeMap.(d),  num2cell(options.order));
chunkVec     = cellfun(@(d) chunkSzMap.(d),  num2cell(options.order));
writeStart   = cellfun(@(d) dimStartMap.(d), num2cell(options.order));

% create dataset
if options.t == 1
    if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=0.05; wb.Message=sprintf('%s\nCreate file container...',filename); else; waitbar(0.05,wb,sprintf('%s\nCreate file container...',filename)); end; end
    h5create(filename, options.DatasetName, datasetSize, ...
            'Datatype', options.DatasetClass, 'Deflate', options.Deflate, ...
            'ChunkSize', chunkVec);
end

if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=0.1; wb.Message=sprintf('%s\nSaving images...',filename); else; waitbar(0.1,wb,sprintf('%s\nSaving images...',filename)); end; end
getDataOpt.showWaitbar = 0;     % do not show waitbar in getDataVirt
maxIndex = options.time*ceil(options.depth/options.ChunkSize(3));

counterIndex = 1;
if isfield(options, 'mibImage')     % tweak to save HDF5 in the virtual mode, without loaded imageS
    for t=1:options.time
        getDataOpt.t = t;
        for z=1:ceil(options.depth/options.ChunkSize(3))
            getDataOpt.z = [(z-1)*options.ChunkSize(3)+1, z*options.ChunkSize(3)];
            for x=1:ceil(options.width/options.ChunkSize(2))
                getDataOpt.x = [(x-1)*options.ChunkSize(2)+1, x*options.ChunkSize(2)];
                for y=1:ceil(options.height/options.ChunkSize(1))
                    getDataOpt.y = [(y-1)*options.ChunkSize(1)+1, y*options.ChunkSize(1)];
                    img2 = options.mibImage.getDataVirt(options.DatasetType, 4, 0, getDataOpt);
                    chunkStartMap = struct('y',getDataOpt.y(1),'x',getDataOpt.x(1), ...
                                          'z',getDataOpt.z(1),'c',1,'t',getDataOpt.t(1));
                    chunkStart = cellfun(@(d) chunkStartMap.(d), num2cell(options.order));
                    h5write(filename, options.DatasetName, img2, chunkStart, size(img2, 1:5));
                end
            end
            if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=counterIndex/maxIndex; else; waitbar(counterIndex/maxIndex,wb); end; end
            counterIndex = counterIndex + 1;
        end
    end
else
    h5write(filename, options.DatasetName, imageS, writeStart, size(imageS, 1:5));
end

if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=0.9; wb.Message=sprintf('%s\nSaving metadata...',filename); else; waitbar(0.9,wb,sprintf('%s\nSaving metadata...',filename)); end; end

% generate axistags to be compatible with Ilastik
% see more here:
% https://ukoethe.github.io/vigra/doc-release/vigranumpy/#vigra.AxisInfo

axistags = sprintf('{\n"axes": [\n');
% should be in reverse order
for i=numel(options.order):-1:1
    % identify the typeFlag
    switch options.order(i)
        case 't'
            typeFlag = '8';
        case 'c'
            typeFlag = '1';
        otherwise
            typeFlag = '2';
    end

    axistags = sprintf('%s {\n  "key": "%s",\n', axistags, options.order(i));
    axistags = sprintf('%s  "typeFlags": %s,\n', axistags, typeFlag);
    axistags = sprintf('%s  "resolution": 0,\n', axistags);
    axistags = sprintf('%s  "description": "%s"\n', axistags, options.ImageDescription);
    axistags = sprintf('%s },\n', axistags);
end
axistags(end-1) = []; % remove comma
axistags = sprintf('%s]\n', axistags); % close axes field
axistags = sprintf('%s}', axistags); % close axistags

h5writeatt(filename, options.DatasetName, 'axistags', axistags);

% metaFields = keys(ImageDescription);
%
% for index=1:numel(metaFields)
%     h5writeatt(filename,ImageDescription('DatasetName'), metaFields{index}, ImageDescription(metaFields{index}));
% end

if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=1; else; waitbar(1,wb); end; end
%disp(['image2hdf5: ' filename ' was created!']);
if ~isempty(wb)
    if ~isa(wb, 'matlab.ui.dialog.ProgressDialog'); set(0, 'DefaulttextInterpreter', curInt); end
    delete(wb);
end
result = 1;
end
