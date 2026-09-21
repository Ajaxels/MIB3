function result = cropToBigData(obj, cropF, options)
% CROPTOBIGDATA - Crop a BigData dataset and write the result to a new Zarr pyramid.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.cropToBigData(cropF, options)
%
% Reads the cropped image region from the source BigData (on-demand, only
% the crop footprint is loaded into memory), writes it as a new OME-Zarr v3
% pyramid at ``options.outputPath`` via ``io.savers.Zarr3Saver``, and copies
% the BigData model pyramid (if one exists) to a sibling file whose name is
% the same as the image output but with a ``Labels_`` prefix:
%
%   - image  → ``options.outputPath``          (e.g. ``crop.zarr3``)
%   - model  → ``<dir>/Labels_<stem><ext>``    (e.g. ``Labels_crop.zarr3``)
%
% Input Arguments:
%   - **cropF** - a vector ``[x1, y1, dx, dy, z1, dz, t1, dt]`` in pixels
%
%     - *x1,* *y1* - top-left corner of the crop region
%     - *dx,* *dy* - width and height of the crop region
%     - *z1,* *dz* - first slice index and number of slices
%     - *t1,* *dt* - first time point and number of time points
%     - when ``numel(cropF)`` < 7, *t1* and *dt* default to ``[1, obj.image.time]``
%
%   - **options** - *(optional)* structure with additional parameters
%
%     - ``.outputPath`` - [char] path to the destination zarr folder (required)
%     - ``.showWaitbar`` - logical, show a progress dialog (default: **true**)
%     - ``.UIFigure`` - handle to the parent UIFigure for the progress dialog
%
%   The progress dialog is cancelable up to the point where the output store
%   starts being written; past that the operation runs to the end rather than
%   leaving a partial pyramid on disk. The region read is a single
%   uninterruptible call, so a cancel pressed during it takes effect when it
%   returns.
%
% Output Arguments:
%   - **result** - **1** on success, **0** on cancel or error
%
% Usage:
%   **Example**
%
%   .. code-block:: matlab
%
%
%     opts.outputPath  = 'C:\data\crop.zarr3';
%     opts.showWaitbar = true;
%     opts.UIFigure    = obj.view.gui;
%     result = obj.mibModel.I{id}.cropToBigData(crop_factor, opts);
%

% Updates
% 2026-06-26 created

result = 0;

if nargin < 3; options = struct(); end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = true; end
if ~isfield(options, 'UIFigure');    options.UIFigure    = [];   end
if ~isfield(options, 'outputPath') || isempty(options.outputPath)
    error('core:MibDataset:cropToBigData', 'options.outputPath is required');
end

if numel(cropF) < 7; cropF(7:8) = [1, obj.image.time]; end
x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);

% Cancel is honoured only before the output store is written; once Zarr3Saver
% has started writing, the operation runs to the end rather than leaving a
% partial pyramid on disk.
wb = [];
if options.showWaitbar && ~isempty(options.UIFigure)
    wb = uiprogressdlg(options.UIFigure, ...
        'Value', 0.05, 'Message', 'Reading image crop...', 'Title', 'Crop to BigData', ...
        'Cancelable', 'on');
end

% =========================================================================
%  1. Read the cropped image region at full resolution (pyramid level 1)
% =========================================================================
readOpts.x            = [x1, x1+dx-1];
readOpts.y            = [y1, y1+dy-1];
readOpts.z            = [z1, z1+dz-1];
readOpts.t            = [t1, t1+dt-1];
readOpts.pyramidLevel = 1;

% Only the requested region is read - a remote store serves just the chunks it
% touches - but that single call cannot be interrupted, so the cancel check
% below fires when it returns.
if ~isempty(wb) && wb.CancelRequested; delete(wb); return; end
if ~isempty(wb)
    wb.Message = sprintf('Reading a %d x %d x %d region from the dataset...', dx, dy, dz);
end
imageData = obj.image.getData('image', 3, [], readOpts);
if ~isempty(wb) && wb.CancelRequested; delete(wb); return; end
% imageData is [dy, dx, dz, colors, dt]

if isempty(imageData)
    if ~isempty(wb); delete(wb); end
    utils.dlgs.showErrorDialog(options.UIFigure, ...
        'Failed to read image crop from the source BigData.', 'Crop to BigData error');
    return;
end

if ~isempty(wb); wb.Value = 0.3; wb.Message = 'Writing image pyramid...'; end

% =========================================================================
%  2. Write the cropped image as a new Zarr pyramid
% =========================================================================
meta = struct('pixSize', obj.image.pixSize);
saverOpts.silent    = true;   % bypass the interactive export-settings dialog
saverOpts.ChunkSize = [256, 256, 16];

fnOut = io.savers.Zarr3Saver().save(imageData, meta, options.outputPath, saverOpts);
if isempty(fnOut)
    if ~isempty(wb); delete(wb); end
    return;
end

if ~isempty(wb); wb.Value = 0.65; wb.Message = 'Copying model...'; end

% =========================================================================
%  3. Copy BigData model pyramid (if present) to Labels_<stem><ext>
% =========================================================================
if isa(obj.labels, 'core.MibBigDataLabels') && obj.labels.exists

    % Derive model store path: same directory, Labels_ prefix, same extension
    [parentDir, stem, ext] = fileparts(options.outputPath);
    modelStorePath = fullfile(parentDir, ['Labels_' stem ext]);

    % Build a pyramid struct for the new model store.
    % Level sizes are the crop dimensions divided by the source scale factors.
    % Scale factors come from the source image pyramid (unchanged by the crop).
    srcSF    = obj.image.pyramid.levelScaleFactors;   % [nLevels x 3] [sfY sfX sfZ]
    nLevels  = size(srcSF, 1);
    newLevelSizes = zeros(nLevels, 3);
    for levelIdx = 1:nLevels
        sf = srcSF(levelIdx, :);
        newLevelSizes(levelIdx, :) = max(1, round([dy, dx, dz] ./ sf));
    end

    newPyramid = struct();
    newPyramid.levelImageSizes   = newLevelSizes;
    newPyramid.levelScaleFactors = srcSF;
    newPyramid.chunkSizes        = obj.image.pyramid.chunkSizes;
    newPyramid.axisOrder         = obj.image.pyramid.axisOrder;

    % Create the new disk-backed model store
    newLabels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
    newLabels.createStore([dy, dx, dz], modelStorePath, newPyramid);

    % Copy full-resolution packed uint8 model from the source crop region
    srcOpts.pyramidLevel = 1;
    srcOpts.x = [x1, x1+dx-1];
    srcOpts.y = [y1, y1+dy-1];
    srcOpts.z = [z1, z1+dz-1];
    packedData = obj.labels.getData63('everything', 3, [], srcOpts);

    if ~isempty(packedData)
        dstOpts.pyramidLevel = 1;
        newLabels.setData63(packedData, 'everything', 3, [], dstOpts);
        newLabels.materializeAll();
    end
    newLabels.closeStore();
end

if ~isempty(wb); wb.Value = 1; delete(wb); end
result = 1;
end
