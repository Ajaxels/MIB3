function config = defaultConfig(config)
% DEFAULTCONFIG - StarDist 2D configuration with defaults for every missing field.
%
% Syntax:
%   .. code-block:: matlab
%
%      config = deepmib.stardist.defaultConfig()
%      config = deepmib.stardist.defaultConfig(config)
%
% Returns the configuration struct shared by all ``deepmib.stardist`` functions. When a
% partial struct is given, only its missing fields are filled in, so a configuration stored in an
% older network file keeps working after new fields are added.
%
% The defaults are those of StarDist 0.9.2 ``Config2D`` with ``grid = (1,1)``. The pretrained
% models use ``grid = [2 2]``; their configuration comes from their own ``config.json`` (see
% deepmib.stardist.loadPretrained) and must not be replaced by these defaults.
%
% Input Arguments:
%   - **config** *(optional)* - [struct] partial configuration; fields already present are kept
%
% Output Arguments:
%   - **config** - [struct] configuration with fields:
%
%     - ``.nRays`` - [numeric] number of rays per polygon (default: ``32``)
%     - ``.grid`` - [1x2 numeric] output subsampling ``[rows cols]``, powers of 2; the network
%       predicts at ``1/grid`` resolution (default: ``[1 1]``)
%     - ``.nChannelIn`` - [numeric] number of image channels (default: ``1``)
%     - ``.patchSize`` - [1x2 numeric] training patch ``[height width]``, also the size of the
%       network input layer; must be divisible by ``2^unetDepth * grid`` (default: ``[256 256]``)
%     - ``.unetDepth`` - [numeric] number of U-Net pooling levels (default: ``3``)
%     - ``.unetFilterBase`` - [numeric] filters of the first U-Net level (default: ``32``)
%     - ``.unetKernelSize`` - [1x2 numeric] convolution kernel size (default: ``[3 3]``)
%     - ``.unetConvPerDepth`` - [numeric] convolutions per U-Net level (default: ``2``)
%     - ``.unetExpansion`` - [numeric] filter multiplier per level (default: ``2``)
%     - ``.netConvAfterUnet`` - [numeric] filters of the 3x3 convolution between the U-Net and
%       the output heads, ``0`` to skip it (default: ``128``)
%     - ``.normalizePercentiles`` - [1x2 numeric] lower and upper percentile of the intensity
%       normalisation, see deepmib.stardist.normalizeImage (default: ``[1 99.8]``)
%     - ``.probThresh`` - [numeric] object probability threshold for prediction (default: ``0.5``)
%     - ``.nmsThresh`` - [numeric] overlap threshold of the non-maximum suppression (default: ``0.4``)
%     - ``.trainLossWeights`` - [1x2 numeric] weights of the probability and distance losses
%       (default: ``[1 0.2]``)
%     - ``.trainBackgroundReg`` - [numeric] weight of the penalty on distances predicted in the
%       background (default: ``1e-4``)
%     - ``.trainForegroundOnly`` - [numeric] fraction of training patches that must contain an
%       object (default: ``0.9``)
%
% **Example** - configuration for a 3-channel model with grid 2:
%
%   .. code-block:: matlab
%
%      config = deepmib.stardist.defaultConfig(struct('nChannelIn', 3, 'grid', [2 2]));

if nargin < 1; config = struct(); end

defaults = struct( ...
    'nRays', 32, ...
    'grid', [1 1], ...
    'nChannelIn', 1, ...
    'patchSize', [256 256], ...
    'unetDepth', 3, ...
    'unetFilterBase', 32, ...
    'unetKernelSize', [3 3], ...
    'unetConvPerDepth', 2, ...
    'unetExpansion', 2, ...
    'netConvAfterUnet', 128, ...
    'normalizePercentiles', [1 99.8], ...
    'probThresh', 0.5, ...
    'nmsThresh', 0.4, ...
    'trainLossWeights', [1 0.2], ...
    'trainBackgroundReg', 1e-4, ...
    'trainForegroundOnly', 0.9);

fieldNames = fieldnames(defaults);
for fieldId = 1:numel(fieldNames)
    if ~isfield(config, fieldNames{fieldId})
        config.(fieldNames{fieldId}) = defaults.(fieldNames{fieldId});
    end
end
config.grid = reshape(config.grid, 1, []);
config.patchSize = reshape(config.patchSize, 1, []);
config.unetKernelSize = reshape(config.unetKernelSize, 1, []);
end
