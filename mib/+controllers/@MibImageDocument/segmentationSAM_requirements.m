function status = segmentationSAM_requirements(obj, samVersionName)
% SEGMENTATIONSAM_REQUIREMENTS - Check for files required to run SAM segmentation.
%
% Syntax:
%   .. code-block:: matlab
%
%      status = obj.segmentationSAM_requirements()
%      status = obj.segmentationSAM_requirements(samVersionName)
%
% Check for files required to run segmentation using Segment Anything Model.
% See https://segment-anything.com and https://github.com/facebookresearch/segment-anything-2
%
% Input Arguments:
%   - **samVersionName** *(optional)* — [numeric|char] SAM version to check:
%
%     - ``1`` or ``'SAM1'`` — first version SAM (https://segment-anything.com)
%     - ``2`` or ``'SAM2'`` — second version SAM-2 (default; https://github.com/facebookresearch/segment-anything-2)
%
% Output Arguments:
%   - **status** — [logical] indicates success of the function
%
% **Example** — check SAM requirements:
%
%   .. code-block:: matlab
%
%      status = obj.segmentationSAM_requirements('SAM1');  % check SAM1 requirements
%      status = obj.segmentationSAM_requirements('SAM2');  % check SAM2 requirements
%      status = obj.segmentationSAM_requirements(2);  % check SAM2 requirements
%

if nargin < 2; samVersionName = 'SAM2'; end
if ~ischar(samVersionName)
    % define proper field name in obj.mibModel.preferences.SegmTools structure
    samVersionName = 'SAM1';
    if samVersionName==2; samVersionName = 'SAM2'; end
end

status = false;

if isempty(obj.mibModel.preferences.ExternalDirs.PythonInstallationPath) || ~isfile(obj.mibModel.preferences.ExternalDirs.PythonInstallationPath)
    dlgOpt.MsgBoxOnly = true;
    header = 'Location of python interpreter (python.exe) is not specified or python.exe is missing!';
    dlgOpt.HeaderLines = 2;
    dlgOpt.WindowHeight = 190;
    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {''}, {sprintf('<html><p style="font-size:10pt">Specify Python location using<br>Menu->File->Preferences->External dirs...')}, 'Missing Python location', dlgOpt);
    return;
end

if isempty(obj.mibModel.preferences.SegmTools.(samVersionName).sam_installation_path) || ...
        ~isfolder(obj.mibModel.preferences.SegmTools.(samVersionName).sam_installation_path)
    dlgOpt.MsgBoxOnly = true;
    header = sprintf('Location of segment-anything is not specified!\nSpecify its location using SAM settings dialog');
    dlgOpt.HeaderLines = 2;
    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'Missing SAM location', dlgOpt);
    return;
end

% get settings file with links to SAM backbones
linksFile = fullfile(obj.mibModel.mibPath, obj.mibModel.preferences.SegmTools.(samVersionName).linksFile);
if exist(linksFile, 'file') == 0
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    header = sprintf(['Location of "sam_links.json" (or "sam2_links.json" for SAM2) with links to SAM backbones is not specified!\n\n' ...
        'Specify its location using SAM settings dialog, ' ...
        'the default location in Resources directory under MIB installation']);
    dlgOpt.HeaderLines = 4;
    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'Missing sam_links.json location', dlgOpt);
    return;
end
% read links with backbones
linksJSON = fileread(linksFile);
linksStruct = jsondecode(linksJSON);

% get index of the selected backbone
selectedBackboneIndex = find(ismember({linksStruct.name}, obj.mibModel.preferences.SegmTools.(samVersionName).backbone));
checkpointFilename = linksStruct(selectedBackboneIndex).checkpointFilename;
checkpointLink = linksStruct(selectedBackboneIndex).checkpointLink_url_1;
checkpointLink2 = linksStruct(selectedBackboneIndex).checkpointLink_url_2;
onnxFilename = '*** not used ***';
modelCfgFilename = '*** not used ***';
switch samVersionName
    case 'SAM1'
        onnxFilename = linksStruct(selectedBackboneIndex).onnxFilename;
        onnxLink = linksStruct(selectedBackboneIndex).onnxLink;
    case 'SAM2'
        % for SAM2 links to model configs are needed
        modelCfgLink = linksStruct(selectedBackboneIndex).modelCfgLink_url_1;
        modelCfgLink2 = linksStruct(selectedBackboneIndex).modelCfgLink_url_2;
        [~, modelCfgFilename] = fileparts(modelCfgLink);
        modelCfgFilename = [modelCfgFilename '.yaml'];
end

checkpointIsMissing = true;
while checkpointIsMissing
    checkpointExists = isfile(fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, checkpointFilename));
    switch samVersionName
        case 'SAM1'
            modelCfgExists = true; % yaml is not used in SAM1
            onnxExists = isfile(fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, onnxFilename));
        case 'SAM2'
            modelCfgExists = isfile(fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, modelCfgFilename));
            onnxExists = true; % onnx is not used in SAM2
    end

    if checkpointExists == 0 || onnxExists == 0 || modelCfgExists == 0
        questDlgOpt.WindowHeight = 300;
        questDlgOpt.WindowWidth = 500;
        answer = utils.dlgs.inputQuestDlg(obj.mibModel.mibGUI, ...
            sprintf(['The following files were not found and will be downloaded\n' ...
                '  - checkpoint:    %s\n' ...
                '  - onnx (SAM1):   %s\n' ...
                '  - yaml (SAM2):   %s\n\n' ...
                'The destination directory is\n' ...
                '%s\n\n' ...
                'Before download, you can update the destination directory\n\n' ...
                'Please note that the progress bar won''t be updated during the process and it may take a while...'], ...
                checkpointFilename, onnxFilename, modelCfgFilename, obj.mibModel.preferences.ExternalDirs.DeepMIBDir), ...
            'Download checkpoint', ...
            'Continue with download', 'Update directory', 'Cancel', 'Cancel',questDlgOpt);

        switch answer
            case 'Update directory'
                selpath = uigetdir(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, 'Directory for trainined models');
                if selpath == 0; return; end

                obj.mibModel.preferences.ExternalDirs.DeepMIBDir = selpath;
                checkpointIsMissing = false;
            case 'Cancel'
                return;
            case 'Continue with download'
                checkpointIsMissing = false;
        end
    else
        checkpointIsMissing = false;
    end
end

% download checkpoint file
if checkpointExists == 0
    wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
        sprintf('Downloading checkpoint %s...\nNote that the progress bar won''t be updated', obj.mibModel.preferences.SegmTools.(samVersionName).backbone), ...
        'Title', 'Downloading checkpoint file', 'Indeterminate', true);
    drawnow;
    try
        websave(fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, checkpointFilename), checkpointLink);
    catch err
        websave(fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, checkpointFilename), checkpointLink2);
    end
    wb.Value = 1;
    fprintf('The checkpoint file %s was downloaded to %s\n', checkpointFilename, obj.mibModel.preferences.ExternalDirs.DeepMIBDir);
    close(wb);
end

if onnxExists == 0
    wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
        sprintf('Downloading onnx %s...\nNote that the progress bar won''t be updated', obj.mibModel.preferences.SegmTools.(samVersionName).backbone), ...
        'Title', 'Downloading onnx file', 'Indeterminate', true);
    drawnow;
    unzip(onnxLink, obj.mibModel.preferences.ExternalDirs.DeepMIBDir);
    wb.Value = 1;
    fprintf('The onnx file %s was downloaded to %s\n', onnxFilename, obj.mibModel.preferences.ExternalDirs.DeepMIBDir);
    close(wb);
end

if modelCfgExists == 0
    wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
        sprintf('Downloading model config for "%s"\nNote that the progress bar won''t be updated', obj.mibModel.preferences.SegmTools.(samVersionName).backbone), ...
        'Title', 'Downloading yaml file', 'Indeterminate', true);
    drawnow;
    try
        websave(fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, modelCfgFilename), modelCfgLink);
    catch err
        websave(fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, modelCfgFilename), modelCfgLink2);
    end
    wb.Value = 1;
    fprintf('The model config file %s was downloaded to %s\n', modelCfgFilename, obj.mibModel.preferences.ExternalDirs.DeepMIBDir);
    close(wb);
end

% update sessionSettings with the selected backbone
obj.mibModel.sessionSettings.SAMsegmenter.Links.checkpointFilename = checkpointFilename;
obj.mibModel.sessionSettings.SAMsegmenter.Links.onnxFilename = onnxFilename;
obj.mibModel.sessionSettings.SAMsegmenter.Links.modelCfgFilename = modelCfgFilename;
obj.mibModel.sessionSettings.SAMsegmenter.Links.backbone = linksStruct(selectedBackboneIndex).backbone;

status = true;
end
