function saveConfig(obj, configName)
% SAVECONFIG - save Deep MIB configuration to a file.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.saveConfig(configName)
%
% Input Arguments:
%   - **configName** - [optional] string, full filename to the config file
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.saveConfig: triggered\n');
end

    if nargin < 2
        [projectPath, file] = fileparts(obj.BatchOpt.NetworkFilename);
        [file, projectPath]  = uiputfile({'*.mibCfg', 'mibDeep config files (*.mibCfg)';
            '*.mat', 'Mat files (*.mat)'}, 'Select config file', ...
            fullfile(projectPath, file));
        if file == 0; return; end

        configName = fullfile(projectPath, file);
    else
        projectPath = fileparts(configName);
    end
    % if ~strcmp(path(end), filesep)   % remove the ending slash
    %     path = [path filesep];
    % end

    if strcmp(projectPath(end), filesep)   % remove the ending slash
        projectPath = projectPath(1:end-1);
    end

    BatchOpt = obj.BatchOpt; %#ok<*PROPLC>
    % generate TrainingOptStruct, because TrainingOptions is
    % 'TrainingOptionsADAM' class
    AugOpt2DStruct = obj.AugOpt2D;
    AugOpt3DStruct = obj.AugOpt3D;
    InputLayerOpt = obj.InputLayerOpt;
    TrainingOptStruct = obj.TrainingOpt;
    ActivationLayerOpt = obj.ActivationLayerOpt;
    SegmentationLayerOpt = obj.SegmentationLayerOpt;
    DynamicMaskOpt = obj.DynamicMaskOpt;
    ScoreExportOpt = obj.ScoreExportOpt;
    OverlapInstancesOpt = obj.OverlapInstancesOpt;
    StartingWeightsOpt = obj.StartingWeightsOpt;

    % try to export path as relatives
    BatchOpt.NetworkFilename = deepmib.convertAbsoluteToRelativePath(BatchOpt.NetworkFilename, projectPath, '[RELATIVE]');
    BatchOpt.OriginalTrainingImagesDir = deepmib.convertAbsoluteToRelativePath(BatchOpt.OriginalTrainingImagesDir, projectPath, '[RELATIVE]');
    BatchOpt.OriginalPredictionImagesDir = deepmib.convertAbsoluteToRelativePath(BatchOpt.OriginalPredictionImagesDir, projectPath, '[RELATIVE]');
    BatchOpt.ResultingImagesDir = deepmib.convertAbsoluteToRelativePath(BatchOpt.ResultingImagesDir, projectPath, '[RELATIVE]');

    % add MIB version to the saved config
    mibVersion.mibVersion = obj.mibController.mibVersion;
    mibVersion.mibVersionNumeric = obj.mibController.mibVersionNumeric;

    % generate config file; the config file is the same as *.mibDeep but without 'net' field
    save(configName, ...
        'TrainingOptStruct', 'AugOpt2DStruct', 'AugOpt3DStruct', ...
        'SegmentationLayerOpt', 'ActivationLayerOpt', 'DynamicMaskOpt', 'ScoreExportOpt', ...
        'OverlapInstancesOpt', 'StartingWeightsOpt', ...
        'InputLayerOpt', 'BatchOpt', 'mibVersion', '-mat', '-v7.3');
end

