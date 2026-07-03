function loadConfig(obj, configName)
% LOADCONFIG - load config file with Deep MIB settings.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.loadConfig(configName)
%
% Input Arguments:
%   - **configName** — full filename for the config file to load
%

if nargin < 2
    [file, projectPath] = utils.dlgs.mibUiGetFile({'*.mibCfg;', 'Deep MIB config files (*.mibCfg)';
        '*.mat', 'Mat files (*.mat)'}, 'Open network file', ...
        obj.BatchOpt.NetworkFilename);
    if isequal(file, 0); return; end
    file = file{1};
    configName = fullfile(projectPath, file);
else
    projectPath = fileparts(configName);
end

% remove slash from the end of the path
if strcmp(projectPath(end), filesep); projectPath = projectPath(1:end-1); end

obj.wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Loading config file\nPlease wait...'), 'Title', 'Load config');

res = load(configName, '-mat');
obj.wb.Value = 0.2;

% correct the slash characters depending on OS
if ispc
    res.BatchOpt.NetworkFilename = strrep(res.BatchOpt.NetworkFilename, '/', filesep);
    res.BatchOpt.OriginalTrainingImagesDir = strrep(res.BatchOpt.OriginalTrainingImagesDir, '/', filesep);
    res.BatchOpt.OriginalPredictionImagesDir = strrep(res.BatchOpt.OriginalPredictionImagesDir, '/', filesep);
    res.BatchOpt.ResultingImagesDir = strrep(res.BatchOpt.ResultingImagesDir, '/', filesep);
else
    res.BatchOpt.NetworkFilename = strrep(res.BatchOpt.NetworkFilename, '\', filesep);
    res.BatchOpt.OriginalTrainingImagesDir = strrep(res.BatchOpt.OriginalTrainingImagesDir, '\', filesep);
    res.BatchOpt.OriginalPredictionImagesDir = strrep(res.BatchOpt.OriginalPredictionImagesDir, '\', filesep);
    res.BatchOpt.ResultingImagesDir = strrep(res.BatchOpt.ResultingImagesDir, '\', filesep);
end

% restore full paths from relative
if isempty(strfind(res.BatchOpt.NetworkFilename, '[RELATIVE]\'))
    % older version of configs, where the relative path encoded
    % as "[RELATIVE]subdir", i.e. without slash
    res.BatchOpt.NetworkFilename = strrep(res.BatchOpt.NetworkFilename, '[RELATIVE]', [projectPath filesep]); %#ok<*PROP>
    res.BatchOpt.OriginalTrainingImagesDir = strrep(res.BatchOpt.OriginalTrainingImagesDir, '[RELATIVE]', [projectPath filesep]);
    res.BatchOpt.OriginalPredictionImagesDir = strrep(res.BatchOpt.OriginalPredictionImagesDir, '[RELATIVE]', [projectPath filesep]);
    res.BatchOpt.ResultingImagesDir = strrep(res.BatchOpt.ResultingImagesDir, '[RELATIVE]', [projectPath filesep]);
else
    % newer version of configs, where the relative path encoded
    % as "[RELATIVE]\subdir", i.e. with slash
    res.BatchOpt.NetworkFilename = deepmib.convertRelativeToAbsolutePath(res.BatchOpt.NetworkFilename, projectPath, '[RELATIVE]'); %#ok<*PROP>
    res.BatchOpt.OriginalTrainingImagesDir = deepmib.convertRelativeToAbsolutePath(res.BatchOpt.OriginalTrainingImagesDir, projectPath, '[RELATIVE]');
    res.BatchOpt.OriginalPredictionImagesDir = deepmib.convertRelativeToAbsolutePath(res.BatchOpt.OriginalPredictionImagesDir, projectPath, '[RELATIVE]');
    res.BatchOpt.ResultingImagesDir = deepmib.convertRelativeToAbsolutePath(res.BatchOpt.ResultingImagesDir, projectPath, '[RELATIVE]');
end

if ~isfield(res.BatchOpt, 'T_ActivationLayer')
    res.BatchOpt.T_ActivationLayer = {'reluLayer'};
    res.BatchOpt.T_ActivationLayer{2} = {'clippedReluLayer', 'eluLayer', 'leakyReluLayer', 'reluLayer', 'swishLayer', 'tanhLayer'};
end

% update res.BatchOpt to be compatible with DeepMIB v2.83
res = obj.correctBatchOpt(res);
if isempty(res); delete(obj.wb); return; end
obj.wb.Value = 0.4;

% remove ImageNoise that may somehow sneak when importing old projects
if isfield(res.AugOpt2DStruct, 'ImageNoise');  res.AugOpt2DStruct = rmfield(res.AugOpt2DStruct, 'ImageNoise'); end
%if strcmp(res.BatchOpt.Architecture{1}, 'U-net') && strcmp(res.BatchOpt.Workflow{1}, '2D Semantic')
%    delete(obj.wb); return;
%end



% compare current vs the loaded workflow
if ~strcmp(obj.BatchOpt.Workflow{1}, res.BatchOpt.Workflow{1})
    obj.view.handles.Workflow.Value = res.BatchOpt.Workflow{1};
    obj.selectWorkflow();
end
% compare current vs the loaded architecture
if ~strcmp(obj.BatchOpt.Architecture{1}, res.BatchOpt.Architecture{1})
    if strcmp(res.BatchOpt.Architecture{1}, 'U-net')
        errText = sprintf('Unfortunately, this type of U-net architecture is not supported in MIB3!\nPlease use "U-net +Encoder" option, we will try to restore all used parameters...\nYou will need to retrain the network, alternatively use MIB2');
        utils.dlgs.showErrorDialog(obj.view.gui, errText, 'The architecture is not supported')
        res.BatchOpt.Architecture{1} = 'U-net +Encoder';
        res.BatchOpt.T_EncoderNetwork{1} = 'Classic';
    end
    obj.view.handles.Architecture.Value = res.BatchOpt.Architecture{1};
    obj.selectArchitecture();
end

% add/update BatchOpt with the provided fields in BatchOptIn
% combine fields from input and default structures
obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, res.BatchOpt);
if ~strcmp(obj.view.handles.T_EncoderNetwork.Value, obj.BatchOpt.T_EncoderNetwork{1})
    obj.view.handles.T_EncoderNetwork.Value = obj.BatchOpt.T_EncoderNetwork{1};
    event.Source = obj.view.handles.T_EncoderNetwork;
    obj.updateBatchOptFromGUI(event);
end
obj.wb.Value = 0.8;

try
    if isstruct(obj.AugOpt2D.RandScale)
        obj.AugOpt2D = utils.concatenateStructures(obj.AugOpt2D, res.AugOpt2DStruct);
        obj.AugOpt3D = utils.concatenateStructures(obj.AugOpt3D, res.AugOpt3DStruct);
    else
        % the current obj.AugOpt2D is in the old format, thus
        % overwrite it with settings from the config file
        obj.AugOpt2D = res.AugOpt2DStruct;
        obj.AugOpt3D = res.AugOpt3DStruct;
    end
    obj.TrainingOpt = utils.concatenateStructures(obj.TrainingOpt, res.TrainingOptStruct);
    % fix an old parameter that is no longer in use
    if strcmp(obj.TrainingOpt.Plots, 'training-progress-Matlab'); obj.TrainingOpt.Plots = 'training-progress'; end
    obj.InputLayerOpt = utils.concatenateStructures(obj.InputLayerOpt, res.InputLayerOpt);

    if isfield(res, 'ActivationLayerOpt')   % new in MIB 2.71
        obj.ActivationLayerOpt = utils.concatenateStructures(obj.ActivationLayerOpt, res.ActivationLayerOpt);
        obj.SegmentationLayerOpt = utils.concatenateStructures(obj.SegmentationLayerOpt, res.SegmentationLayerOpt);
    end
    if isfield(res, 'DynamicMaskOpt')   % new in MIB 2.83
        obj.DynamicMaskOpt = utils.concatenateStructures(obj.DynamicMaskOpt, res.DynamicMaskOpt);
    end
    if isfield(res, 'ScoreExportOpt')   % new in MIB 2.9113
        obj.ScoreExportOpt = utils.concatenateStructures(obj.ScoreExportOpt, res.ScoreExportOpt);
    end
    if isfield(res, 'OverlapInstancesOpt')   % new in MIB3, 2D Instance workflow
        obj.OverlapInstancesOpt = utils.concatenateStructures(obj.OverlapInstancesOpt, res.OverlapInstancesOpt);
    end
catch err
    % when the training was stopped before finish,
    % those structures are not stored
end

obj.updateWidgets();

obj.wb.Value = 1;
delete(obj.wb);

% the two following commands are fix of sending the DeepMIB
% window behind main MIB window
drawnow;
figure(obj.view.gui);
end

