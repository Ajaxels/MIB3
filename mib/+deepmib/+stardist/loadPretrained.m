function [model, cancelled] = loadPretrained(modelName, folder, progressDlg)
% LOADPRETRAINED - Load a converted pretrained StarDist 2D model, downloading it on first use.
%
% Syntax:
%   .. code-block:: matlab
%
%      model = deepmib.stardist.loadPretrained(modelName, folder)
%      [model, cancelled] = deepmib.stardist.loadPretrained(modelName, folder, progressDlg)
%
% Looks for ``<folder>/<modelName>.mat``. When it is missing, ``<modelName>.zip`` is downloaded
% from ``http://mib.helsinki.fi/web-update/stardist/`` (HTTPS when HTTP fails) with
% core.DownloadProgressMonitor into a temporary file and unzipped into **folder** only after a
% complete download, so a cancelled or failed download leaves nothing behind. **folder** is
% normally ``mibModel.preferences.ExternalDirs.DeepMIBDir``, where DeepMIB keeps its downloaded
% encoders.
%
% The ``.mat`` file is converted from the StarDist release (``stardist-models``) and holds the Keras weights by layer name, the model's
% ``config.json`` and ``thresholds.json`` verbatim, the source and the licence text. The
% configuration is translated into a deepmib.stardist.defaultConfig struct, and the network is
% built by deepmib.stardist.createNetwork. Settings that ``createNetwork`` cannot reproduce
% (multi-class models, batch normalisation, dropout, a backbone other than the U-Net, pooling
% other than 2, activations other than ReLU, a distance loss other than ``'mae'``) raise an
% error instead of silently producing a different network.
%
% Input Arguments:
%   - **modelName** - [char] pretrained model:
%
%     - ``'2D_versatile_fluo'`` - fluorescent nuclei, 1 channel, 32 rays, grid ``[2 2]``
%
%   - **folder** - [char] folder holding the converted models
%   - **progressDlg** *(optional)* - [uiprogressdlg] cancelable dialog for the download;
%     ``[]`` downloads without progress or cancel (default: ``[]``)
%
% Output Arguments:
%   - **model** - [struct] ``[]`` when cancelled, otherwise with fields:
%
%     - ``.net`` - [dlnetwork] network with the pretrained weights
%     - ``.config`` - [struct] configuration incl. the model's ``probThresh`` and ``nmsThresh``
%     - ``.modelName`` - [char] model name
%     - ``.sourceUrl`` - [char] where the original model is published
%     - ``.stardistVersion`` - [char] StarDist release used for the conversion
%     - ``.licence`` - [char] licence text of the model
%
%   - **cancelled** - [logical] ``true`` when the user pressed Cancel during the download
%
% **Example** - segment one image with the pretrained fluorescence model:
%
%   .. code-block:: matlab
%
%      model = deepmib.stardist.loadPretrained('2D_versatile_fluo', obj.mibModel.preferences.ExternalDirs.DeepMIBDir);
%      x = deepmib.stardist.normalizeImage(img, model.config.normalizePercentiles);
%      [prob, dist] = deepmib.stardist.predictMaps(model.net, x, model.config);
%      [points, scores, rayDist] = deepmib.stardist.nms(prob, dist, model.config.grid, model.config.probThresh, model.config.nmsThresh);
%      labels = deepmib.stardist.polygonsToLabel(points, rayDist, scores, size(img, [1 2]));

if nargin < 3; progressDlg = []; end
model = [];
cancelled = false;

availableModels = {'2D_versatile_fluo'};
if ~ismember(modelName, availableModels)
    error('stardist:loadPretrained:unknownModel', 'Unknown pretrained StarDist model "%s"; available: %s', ...
        modelName, strjoin(availableModels, ', '));
end

modelFilename = fullfile(folder, [modelName '.mat']);
if ~isfile(modelFilename)
    zipFilename = [tempname '.zip'];
    [~, cancelled] = core.DownloadProgressMonitor.download( ...
        {sprintf('http://mib.helsinki.fi/web-update/stardist/%s.zip', modelName), ...
         sprintf('https://mib.helsinki.fi/web-update/stardist/%s.zip', modelName)}, ...
        progressDlg, sprintf('Downloading StarDist model %s...', modelName), zipFilename);
    if cancelled; return; end
    if ~isempty(progressDlg)
        progressDlg.Cancelable = 'off';     % unzip cannot be interrupted
        progressDlg.Indeterminate = 'on';
        progressDlg.Message = 'Unzipping...';
    end
    if ~isfolder(folder); mkdir(folder); end
    unzip(zipFilename, folder);
    delete(zipFilename);
end

saved = load(modelFilename);
kerasConfig = jsondecode(saved.configJson);
thresholds = jsondecode(saved.thresholdsJson);
config = configFromKeras(kerasConfig, thresholds);
model.net = deepmib.stardist.createNetwork(config, saved.weights);
model.config = config;
model.modelName = char(saved.modelName);
model.sourceUrl = char(saved.sourceUrl);
model.stardistVersion = char(saved.stardistVersion);
model.licence = char(saved.licence);

% every Keras layer must have found its MATLAB counterpart
kerasLayers = cellstr(saved.layerOrder);
matlabLayers = unique(model.net.Learnables.Layer);
if ~isempty(setxor(kerasLayers, matlabLayers))
    error('stardist:loadPretrained:layerMismatch', 'Layers of %s do not match the StarDist network: %s', ...
        modelName, strjoin(setxor(kerasLayers, matlabLayers), ', '));
end
end

function config = configFromKeras(kerasConfig, thresholds)
% translate StarDist Config2D (config.json) into the deepmib.stardist configuration
unsupported = {};
if ~isequal(kerasConfig.n_dim, 2); unsupported{end+1} = 'n_dim'; end
if ~strcmp(kerasConfig.backbone, 'unet'); unsupported{end+1} = 'backbone'; end
if isfield(kerasConfig, 'n_classes') && ~isempty(kerasConfig.n_classes); unsupported{end+1} = 'n_classes'; end
if kerasConfig.unet_batch_norm; unsupported{end+1} = 'unet_batch_norm'; end
if kerasConfig.unet_dropout ~= 0; unsupported{end+1} = 'unet_dropout'; end
if ~isequal(kerasConfig.unet_pool(:)', [2 2]); unsupported{end+1} = 'unet_pool'; end
if ~strcmp(kerasConfig.unet_activation, 'relu'); unsupported{end+1} = 'unet_activation'; end
if ~strcmp(kerasConfig.unet_last_activation, 'relu'); unsupported{end+1} = 'unet_last_activation'; end
if ~strcmp(kerasConfig.train_dist_loss, 'mae'); unsupported{end+1} = 'train_dist_loss'; end
if ~isempty(unsupported)
    error('stardist:loadPretrained:unsupported', 'Unsupported StarDist settings: %s', strjoin(unsupported, ', '));
end

config = struct( ...
    'nRays', kerasConfig.n_rays, ...
    'grid', kerasConfig.grid(:)', ...
    'nChannelIn', kerasConfig.n_channel_in, ...
    'patchSize', kerasConfig.train_patch_size(:)', ...
    'unetDepth', kerasConfig.unet_n_depth, ...
    'unetFilterBase', kerasConfig.unet_n_filter_base, ...
    'unetKernelSize', kerasConfig.unet_kernel_size(:)', ...
    'unetConvPerDepth', kerasConfig.unet_n_conv_per_depth, ...
    'netConvAfterUnet', kerasConfig.net_conv_after_unet, ...
    'probThresh', thresholds.prob, ...
    'nmsThresh', thresholds.nms, ...
    'trainLossWeights', kerasConfig.train_loss_weights(:)', ...
    'trainBackgroundReg', kerasConfig.train_background_reg);
if isfield(kerasConfig, 'unet_expansion'); config.unetExpansion = kerasConfig.unet_expansion; end
if isfield(kerasConfig, 'train_foreground_only'); config.trainForegroundOnly = kerasConfig.train_foreground_only; end
config = deepmib.stardist.defaultConfig(config);
end
