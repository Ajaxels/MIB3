function [prob, dist, cancelled] = predictMaps(net, img, config, options)
% PREDICTMAPS - Tiled StarDist forward pass returning whole-image probability and ray-distance maps.
%
% Syntax:
%   .. code-block:: matlab
%
%      [prob, dist] = deepmib.stardist.predictMaps(net, img, config)
%      [prob, dist, cancelled] = deepmib.stardist.predictMaps(net, img, config, options)
%
% Predicts the dense maps of one normalised image (see deepmib.stardist.normalizeImage). The
% maps are what deepmib.stardist.nms turns into objects; tiling happens here, on the maps, so
% no instance ever has to be stitched across tiles.
%
% Input handling follows StarDist 0.9.2 (``StarDistPadAndCropResizer``): the image is padded
% only at the bottom and right to a multiple of ``d = 2^unetDepth * grid``, with numpy
% ``'reflect'`` mode (mirror without repeating the edge pixel; MATLAB ``'symmetric'`` repeats
% it), and the outputs are cropped back to ``ceil([H W] ./ grid)``. Predicted distances are
% clamped to at least ``1e-3`` (``models/base.py:521``); the raw output is negative in much of
% the background.
%
% Tiling: the padded image is cut into cores of ``options.tileSize`` (rounded down to a multiple
% of ``d``), each predicted with a context margin on every side that is not at the image
% border. The margin is the receptive field of the network, computed from ``config`` as an upper
% bound (107 px for ``2D_versatile_fluo``; StarDist measures 94) and rounded up to a multiple of
% ``d``. Because every window starts and ends on a multiple of ``d``, the pooling grid of each
% window coincides with that of the whole image and the tiled maps equal the untiled ones up to
% floating-point summation order. Only the core of each window is written to the output.
%
% Input Arguments:
%   - **net** - [dlnetwork] StarDist network, see deepmib.stardist.createNetwork
%   - **img** - [numeric] normalised image ``[height, width]`` or ``[height, width, nChannelIn]``
%   - **config** - [struct] configuration, see deepmib.stardist.defaultConfig
%   - **options** *(optional)* - struct with fields:
%
%     - ``.tileSize`` - [1x2 numeric] core size ``[rows cols]`` of a tile in pixels; ``[Inf Inf]``
%       predicts the whole image in one pass (default: ``[1024 1024]``)
%     - ``.executionEnvironment`` - [char] ``'auto'`` (GPU when available), ``'gpu'`` or ``'cpu'``
%       (default: ``'auto'``)
%     - ``.progressDlg`` - [uiprogressdlg] dialog whose ``Value`` follows the tiles and whose
%       ``CancelRequested`` is checked before every tile; ``[]`` for none (default: ``[]``)
%
% Output Arguments:
%   - **prob** - [single] object probability ``[ceil(H/gRow), ceil(W/gCol)]``
%   - **dist** - [single] ray distances in pixels ``[ceil(H/gRow), ceil(W/gCol), nRays]``
%   - **cancelled** - [logical] ``true`` when the user pressed Cancel; **prob** and **dist** are
%     then empty
%
% **Example** - maps of a 2D image on the GPU in tiles of 2048 px:
%
%   .. code-block:: matlab
%
%      x = deepmib.stardist.normalizeImage(img, config.normalizePercentiles);
%      opt = struct('tileSize', [2048 2048], 'executionEnvironment', 'gpu');
%      [prob, dist] = deepmib.stardist.predictMaps(net, x, config, opt);

if nargin < 4; options = struct(); end
if ~isfield(options, 'tileSize'); options.tileSize = [1024 1024]; end
if ~isfield(options, 'executionEnvironment'); options.executionEnvironment = 'auto'; end
if ~isfield(options, 'progressDlg'); options.progressDlg = []; end
dlg = options.progressDlg;
config = deepmib.stardist.defaultConfig(config);

cancelled = false;
grid = config.grid;
divisor = 2^config.unetDepth * grid;
useGpu = strcmp(options.executionEnvironment, 'gpu') || ...
    (strcmp(options.executionEnvironment, 'auto') && canUseGPU);

% pad at the end only, numpy 'reflect'
[height, width, ~] = size(img);
paddedHeight = ceil(height / divisor(1)) * divisor(1);
paddedWidth = ceil(width / divisor(2)) * divisor(2);
padded = single(img(reflectIndex(paddedHeight, height), reflectIndex(paddedWidth, width), :));

margin = ceil(receptiveField(config) ./ divisor) .* divisor;
coreSize = min(floor(options.tileSize(:)' ./ divisor) .* divisor, [paddedHeight paddedWidth]);
coreSize = max(coreSize, divisor);
rowStarts = 0:coreSize(1):paddedHeight-1;
colStarts = 0:coreSize(2):paddedWidth-1;
nTiles = numel(rowStarts) * numel(colStarts);

output = zeros(paddedHeight / grid(1), paddedWidth / grid(2), 1 + config.nRays, 'single');
tileId = 0;
for rowStart = rowStarts
    for colStart = colStarts
        if ~isempty(dlg)
            if dlg.CancelRequested
                prob = []; dist = []; cancelled = true;
                return;
            end
            dlg.Value = tileId / nTiles;
        end
        tileId = tileId + 1;
        coreRows = [rowStart, min(rowStart + coreSize(1), paddedHeight)];     % 0-based, end exclusive
        coreCols = [colStart, min(colStart + coreSize(2), paddedWidth)];
        windowRows = [max(0, coreRows(1) - margin(1)), min(paddedHeight, coreRows(2) + margin(1))];
        windowCols = [max(0, coreCols(1) - margin(2)), min(paddedWidth, coreCols(2) + margin(2))];

        window = dlarray(padded(windowRows(1)+1:windowRows(2), windowCols(1)+1:windowCols(2), :), 'SSCB');
        if useGpu; window = gpuArray(window); end
        prediction = gather(extractdata(predict(net, window)));

        sourceRows = (coreRows(1) - windowRows(1)) / grid(1) + 1 : (coreRows(2) - windowRows(1)) / grid(1);
        sourceCols = (coreCols(1) - windowCols(1)) / grid(2) + 1 : (coreCols(2) - windowCols(1)) / grid(2);
        output(coreRows(1)/grid(1)+1 : coreRows(2)/grid(1), coreCols(1)/grid(2)+1 : coreCols(2)/grid(2), :) = ...
            prediction(sourceRows, sourceCols, :);
    end
end
if ~isempty(dlg); dlg.Value = 1; end

outputRows = ceil(height / grid(1));
outputCols = ceil(width / grid(2));
prob = output(1:outputRows, 1:outputCols, 1);
dist = max(output(1:outputRows, 1:outputCols, 2:end), single(1e-3));
end

function index = reflectIndex(paddedLength, length)
% 1-based source indices of numpy np.pad(..., mode='reflect') at the end of an axis
index = 0:paddedLength-1;
if length > 1
    period = 2 * (length - 1);
    index = mod(index, period);
    index(index >= length) = period - index(index >= length);
else
    index(:) = 0;
end
index = index + 1;
end

function radius = receptiveField(config)
% Upper bound of the receptive field radius in input pixels: sum of the kernel half-widths of
% every convolution on the deepest path, plus one pixel per pooling step, at the scale of the
% layer
halfKernel = floor(config.unetKernelSize / 2);
nConv = config.unetConvPerDepth;
radius = [0 0];
scale = [1 1];
pooled = [1 1];
while any(pooled ~= config.grid)
    pool = 1 + (config.grid > pooled);
    pooled = pooled .* pool;
    radius = radius + nConv * halfKernel .* scale + (pool - 1) .* scale;
    scale = scale .* pool;
end
for level = 1:config.unetDepth
    radius = radius + nConv * halfKernel .* scale + scale;
    scale = scale * 2;
end
radius = radius + nConv * halfKernel .* scale;                 % middle block
for level = 1:config.unetDepth
    scale = scale / 2;
    radius = radius + nConv * halfKernel .* scale;
end
if config.netConvAfterUnet > 0
    radius = radius + halfKernel .* scale;
end
end
