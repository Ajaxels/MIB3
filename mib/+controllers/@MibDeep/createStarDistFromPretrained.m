function createStarDistFromPretrained(obj)
% CREATESTARDISTFROMPRETRAINED - Write a network file and its config from a pretrained StarDist model, for prediction without training.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.createStarDistFromPretrained()
%
% Turns the pretrained StarDist model ``2D_versatile_fluo`` (fluorescent nuclei) into a DeepMIB
% network file, so it can be used in the Predict tab straight away, without preprocessing or
% training. Offered when StarDist is selected in the Architecture dropdown (see
% :func:`selectArchitecture`) and from the StarDist settings (:func:`setStarDistSettings`).
%
% Steps:
%
% 1. the user picks the ``.mibDeep`` filename (default ``2D_versatile_fluo.mibDeep`` in the
%    folder of the current network file); the save dialog confirms an overwrite;
% 2. deepmib.stardist.loadPretrained loads the converted model from
%    ``preferences.ExternalDirs.DeepMIBDir``, downloading it on first use (cancelable);
% 3. :func:`saveStarDistNetwork` writes the network file and :func:`saveConfig` the ``.mibCfg``
%    next to it, and the file becomes the current "Network filename".
%
% The stored ``StarDistConfig`` is the model's own configuration (32 rays, grid 2, one input
% channel, patch size 256 x 256) with the detection thresholds that StarDist tuned for it
% (``thresholds.json``), ``pretrainedModel`` set to the model name and the normalisation
% percentiles of ``obj.StarDistOpt``. ``inputPatchSize`` is ``[patchSize 1 nChannelIn]``; the
% ``BatchOpt`` and option structs are the current DeepMIB settings, as after training. The file
% is therefore read as any trained StarDist network: prediction with the stored or custom
% thresholds, Check network, and "Continue training" to fine-tune it later.
%
% The final message, as the offer in :func:`selectArchitecture`, gives the nucleus size of the
% model's training data (about 20 px in diameter, see :func:`startPredictionInstances`), so
% the user can set "Downsample factor for images" (``BatchOpt.P_ImageDownsamplingFactor``) for
% nuclei of another size.
%
% On cancel or error nothing is written and "Network filename" is not changed.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.createStarDistFromPretrained: triggered\n');
end

modelName = '2D_versatile_fluo';    % the only converted model, as in updateStartingWeightsList

networkPath = fileparts(obj.BatchOpt.NetworkFilename);
if isempty(networkPath) || ~isfolder(networkPath); networkPath = obj.mibModel.currentDirectory; end
[file, path] = uiputfile({'*.mibDeep', 'mibDeep files (*.mibDeep)'}, ...
    'Save the pretrained StarDist network', fullfile(networkPath, [modelName '.mibDeep']));
% the two following commands are fix of sending the DeepMIB window behind main MIB window
drawnow;
figure(obj.view.gui);
if isequal(file, 0); return; end
networkFilename = fullfile(path, file);
[~, networkName] = fileparts(networkFilename);
configFilename = fullfile(path, [networkName '.mibCfg']);

progressDlg = uiprogressdlg(obj.view.gui, 'Message', sprintf('Loading %s...', modelName), ...
    'Title', 'StarDist pretrained network', 'Cancelable', 'on', 'Indeterminate', 'on');
cleanupDlg = onCleanup(@() localDeleteDialog(progressDlg));
try
    [model, cancelled] = deepmib.stardist.loadPretrained(modelName, ...
        obj.mibModel.preferences.ExternalDirs.DeepMIBDir, progressDlg);
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'StarDist pretrained network');
    return;
end
if cancelled; return; end

config = model.config;
config.normalizePercentiles = obj.StarDistOpt.NormalizePercentiles;
config.pretrainedModel = modelName;
config = deepmib.stardist.defaultConfig(config);
inputPatchSize = [config.patchSize, 1, config.nChannelIn];

progressDlg.Cancelable = 'off';     % the two files are written together
progressDlg.Message = 'Saving the network...';
previousNetworkFilename = obj.BatchOpt.NetworkFilename;
obj.BatchOpt.NetworkFilename = networkFilename;    % stored in BatchOpt of both files
try
    obj.saveStarDistNetwork(networkFilename, model.net, config, inputPatchSize);
    obj.saveConfig(configFilename);
catch err
    obj.BatchOpt.NetworkFilename = previousNetworkFilename;
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Saving the network failed');
    return;
end
obj.view.Figure.NetworkFilename.Value = obj.BatchOpt.NetworkFilename;
delete(progressDlg);

msgOpt.MsgBoxOnly = true;
msgOpt.Icon = 'puffin_info';
msgOpt.HeaderLines = 1;
msgOpt.WindowWidth = 520;
msgOpt.WindowHeight = 400;
utils.dlgs.inputUniversalDlg(obj.view.gui, 'StarDist network created', {''}, ...
    {sprintf(['%s was saved as\n%s\nwith its config file %s.mibCfg\n\n' ...
    'Detection thresholds: probability %.3f, NMS overlap %.2f (tuned by StarDist)\n\n' ...
    'The network is ready for prediction: open the Predict tab, select the directory with images ' ...
    'and press Predict. It expects fluorescence images of nuclei with %d color channel(s).\n\n' ...
    'It was trained on nuclei of about 20 pixels in diameter. For other sizes set "Downsample factor ' ...
    'for images" on the Predict tab to about diameter of your nuclei / 20.'], ...
    modelName, [networkName '.mibDeep'], networkName, config.probThresh, config.nmsThresh, config.nChannelIn)}, ...
    'StarDist network created', msgOpt);
end

% -------------------------------------------------------------------------------------
function localDeleteDialog(dialogHandle)
if ~isempty(dialogHandle) && isvalid(dialogHandle); delete(dialogHandle); end
end
