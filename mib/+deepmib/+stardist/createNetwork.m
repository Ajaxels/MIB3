function net = createNetwork(config, weights)
% CREATENETWORK - Build the StarDist 2D network (U-Net with probability and ray-distance heads).
%
% Syntax:
%   .. code-block:: matlab
%
%      net = deepmib.stardist.createNetwork(config)
%      net = deepmib.stardist.createNetwork(config, weights)
%
% Reproduces ``StarDist2D._build`` and csbdeep ``unet_block`` of StarDist 0.9.2, layer for
% layer, so that weights converted from a Keras model load by name:
%
% 1. grid pre-stage, only when ``grid > 1``: for each factor 2 of the grid,
%    ``unetConvPerDepth`` 3x3 convolutions with ``unetFilterBase`` filters and ReLU, then a 2x2
%    max pooling (Keras names ``conv2d``, ``conv2d_1``, ... and ``max_pooling2d``);
% 2. U-Net of ``unetDepth`` levels: per level ``unetConvPerDepth`` convolutions with
%    ``unetFilterBase * unetExpansion^level`` filters, then max pooling (``down_level_L_no_i``,
%    ``max_L``); the middle block (``middle_i``); and per level on the way up a nearest-neighbour
%    2x upsampling, concatenation **upsampled first, skip second**, and convolutions
%    (``up_level_L_no_i``); the last up convolution of each level has the filter count of the
%    level below;
% 3. ``features``: 3x3 convolution with ``netConvAfterUnet`` filters and ReLU (skipped when 0);
% 4. heads: ``prob`` 1x1 convolution with 1 filter and sigmoid, ``dist`` 1x1 convolution with
%    ``nRays`` filters and no activation, concatenated into one output so that ``trainnet`` sees
%    a single output and a single target.
%
% All convolutions use ``'same'`` padding and a bias, without batch normalisation or dropout,
% as in every StarDist 2D model (StarDist 0.9.2, ``stardist/models/model2d.py``).
%
% The input layer is an ``imageInputLayer`` of ``[patchSize nChannelIn]`` without
% normalisation. It fixes the size used by ``trainnet``; ``predict`` accepts any other size
% divisible by ``2^unetDepth * grid`` (see deepmib.stardist.predictMaps).
%
% Input Arguments:
%   - **config** - [struct] configuration, see deepmib.stardist.defaultConfig; missing fields
%     take the defaults
%   - **weights** *(optional)* - [struct] trained weights by Keras layer name:
%     ``weights.(layerName).kernel`` in Keras ``[height width in out]`` (HWIO) layout, which is
%     also the MATLAB layout, and ``weights.(layerName).bias``. Singleton dimensions dropped by a
%     ``.mat`` round trip are restored. Layers without an entry are initialised randomly
%     (Glorot uniform, as Keras).
%
% Output Arguments:
%   - **net** - [dlnetwork] initialised network; output ``[H/g W/g 1+nRays]`` with the
%     probability in channel 1 and the ray distances in channels ``2:nRays+1``
%
% **Example** - network for a fresh model and its output size:
%
%   .. code-block:: matlab
%
%      config = deepmib.stardist.defaultConfig(struct('grid', [2 2]));
%      net = deepmib.stardist.createNetwork(config);
%      Y = predict(net, dlarray(zeros(256, 256, 1, 'single'), 'SSCB'));
%      size(Y)   % 128 128 33

if nargin < 2; weights = struct(); end
config = deepmib.stardist.defaultConfig(config);

grid = config.grid;
if any(grid < 1) || any(bitand(grid, grid - 1) ~= 0)
    error('stardist:createNetwork:grid', 'grid values must be powers of 2, got %s', mat2str(grid));
end
divisor = 2^config.unetDepth * grid;
if any(mod(config.patchSize, divisor) ~= 0)
    error('stardist:createNetwork:patchSize', ...
        'Patch size %s must be divisible by 2^unetDepth * grid = %s', mat2str(config.patchSize), mat2str(divisor));
end

kernelSize = config.unetKernelSize;
nConv = config.unetConvPerDepth;
filterBase = config.unetFilterBase;
expansion = config.unetExpansion;
depth = config.unetDepth;

net = dlnetwork;
net = addLayers(net, imageInputLayer([config.patchSize config.nChannelIn], 'Normalization', 'none', 'Name', 'input'));
lastName = 'input';

% grid pre-stage; Keras numbers unnamed layers conv2d, conv2d_1, ... and max_pooling2d, ...
pooled = [1 1];
convIndex = 0;
poolIndex = 0;
while any(pooled ~= grid)
    pool = 1 + (grid > pooled);
    pooled = pooled .* pool;
    for convId = 1:nConv
        layerName = kerasAutoName('conv2d', convIndex);
        convIndex = convIndex + 1;
        [net, lastName] = addConvRelu(net, lastName, layerName, kernelSize, filterBase, weights);
    end
    layerName = kerasAutoName('max_pooling2d', poolIndex);
    poolIndex = poolIndex + 1;
    net = addLayers(net, maxPooling2dLayer(pool, 'Stride', pool, 'Name', layerName));
    net = connectLayers(net, lastName, layerName);
    lastName = layerName;
end

% U-Net, down
skipNames = cell(depth, 1);
for level = 0:depth-1
    for convId = 0:nConv-1
        [net, lastName] = addConvRelu(net, lastName, sprintf('down_level_%d_no_%d', level, convId), ...
            kernelSize, filterBase * expansion^level, weights);
    end
    skipNames{level+1} = lastName;
    layerName = sprintf('max_%d', level);
    net = addLayers(net, maxPooling2dLayer(2, 'Stride', 2, 'Name', layerName));
    net = connectLayers(net, lastName, layerName);
    lastName = layerName;
end

% U-Net, middle; csbdeep names the last middle convolution middle_<nConv>
for convId = 0:nConv-2
    [net, lastName] = addConvRelu(net, lastName, sprintf('middle_%d', convId), ...
        kernelSize, filterBase * expansion^depth, weights);
end
[net, lastName] = addConvRelu(net, lastName, sprintf('middle_%d', nConv), ...
    kernelSize, filterBase * expansion^max(0, depth-1), weights);

% U-Net, up: nearest upsampling, concatenation [upsampled, skip]
for level = depth-1:-1:0
    upName = sprintf('up_sampling_%d', level);
    concatName = sprintf('concatenate_%d', level);
    net = addLayers(net, resize2dLayer('Scale', 2, 'Method', 'nearest', 'Name', upName));
    net = addLayers(net, concatenationLayer(3, 2, 'Name', concatName));
    net = connectLayers(net, lastName, upName);
    net = connectLayers(net, upName, [concatName '/in1']);
    net = connectLayers(net, skipNames{level+1}, [concatName '/in2']);
    lastName = concatName;
    for convId = 0:nConv-2
        [net, lastName] = addConvRelu(net, lastName, sprintf('up_level_%d_no_%d', level, convId), ...
            kernelSize, filterBase * expansion^level, weights);
    end
    [net, lastName] = addConvRelu(net, lastName, sprintf('up_level_%d_no_%d', level, nConv), ...
        kernelSize, filterBase * expansion^max(0, level-1), weights);
end

if config.netConvAfterUnet > 0
    [net, lastName] = addConvRelu(net, lastName, 'features', kernelSize, config.netConvAfterUnet, weights);
end

% heads, concatenated into a single [prob, dist] output
net = addLayers(net, [makeConv('prob', [1 1], 1, weights), sigmoidLayer('Name', 'prob_sigmoid')]);
net = addLayers(net, makeConv('dist', [1 1], config.nRays, weights));
net = addLayers(net, concatenationLayer(3, 2, 'Name', 'output'));
net = connectLayers(net, lastName, 'prob');
net = connectLayers(net, lastName, 'dist');
net = connectLayers(net, 'prob_sigmoid', 'output/in1');
net = connectLayers(net, 'dist', 'output/in2');

net = initialize(net);
end

function layerName = kerasAutoName(baseName, index)
% Keras names the first unnamed layer of a type 'conv2d', the next ones 'conv2d_1', 'conv2d_2'
if index == 0
    layerName = baseName;
else
    layerName = sprintf('%s_%d', baseName, index);
end
end

function [net, outputName] = addConvRelu(net, inputName, layerName, kernelSize, nFilters, weights)
net = addLayers(net, [makeConv(layerName, kernelSize, nFilters, weights), reluLayer('Name', [layerName '_relu'])]);
net = connectLayers(net, inputName, layerName);
outputName = [layerName '_relu'];
end

function layer = makeConv(layerName, kernelSize, nFilters, weights)
% Keras convolutions are cross-correlations with HWIO kernels, the same as MATLAB's
% convolution2dLayer [h w in out]; no flip or permutation is needed
layer = convolution2dLayer(kernelSize, nFilters, 'Padding', 'same', 'Name', layerName);
if isfield(weights, layerName)
    layer.Weights = reshape(single(weights.(layerName).kernel), kernelSize(1), kernelSize(2), [], nFilters);
    layer.Bias = reshape(single(weights.(layerName).bias), 1, 1, nFilters);
end
end
