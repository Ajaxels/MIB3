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
%   - **samVersionName** *(optional)* - [numeric|char] SAM version to check:
%
%     - ``1`` or ``'SAM1'`` - first version SAM (https://segment-anything.com)
%     - ``2`` or ``'SAM2'`` - second version SAM-2 (default; https://github.com/facebookresearch/segment-anything-2)
%
% Output Arguments:
%   - **status** - [logical] indicates success of the function
%
% .. note::
%    Missing files are downloaded into ``preferences.ExternalDirs.DeepMIBDir``
%    in one progress dialog that shows the size, speed and step, and can be
%    cancelled while a file downloads (``core.DownloadProgressMonitor``). A cancel
%    returns ``status = false`` without updating
%    ``sessionSettings.SAMsegmenter.Links``; a file cancelled part-way is deleted,
%    files already completed are kept and are not downloaded again. The
%    checkpoint and model config are tried from ``*_url_2`` when ``*_url_1``
%    fails; a cancel never falls through to the second link. The SAM1 onnx zip
%    goes to a temporary file first, and Cancel is off while it is unzipped.
%
% **Example** - check SAM requirements:
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
    if samVersionName == 2
        samVersionName = 'SAM2';
    else
        samVersionName = 'SAM1';
    end
end

status = false;

if isempty(obj.mibModel.preferences.ExternalDirs.PythonInstallationPath) || ~isfile(obj.mibModel.preferences.ExternalDirs.PythonInstallationPath)
    dlgOpt.MsgBoxOnly = true;
    header = 'Location of python interpreter (python.exe) is not specified or python.exe is missing!';
    dlgOpt.HeaderLines = 2;
    dlgOpt.WindowHeight = 190;
    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), header, {''}, {sprintf('<html><p style="font-size:10pt">Specify Python location using<br>Menu->File->Preferences->External dirs...')}, 'Missing Python location', dlgOpt);
    return;
end

if isempty(obj.mibModel.preferences.SegmTools.(samVersionName).sam_installation_path) || ...
        ~isfolder(obj.mibModel.preferences.SegmTools.(samVersionName).sam_installation_path)
    dlgOpt.MsgBoxOnly = true;
    header = sprintf('Location of segment-anything is not specified!\nSpecify its location using SAM settings dialog');
    dlgOpt.HeaderLines = 2;
    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), header, {}, {}, 'Missing SAM location', dlgOpt);
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
    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), header, {}, {}, 'Missing sam_links.json location', dlgOpt);
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
        answer = utils.dlgs.inputQuestDlg(obj.mibModel.getProgressBarParent(), ...
            sprintf(['The following files were not found and will be downloaded\n' ...
                '  - checkpoint:    %s\n' ...
                '  - onnx (SAM1):   %s\n' ...
                '  - yaml (SAM2):   %s\n\n' ...
                'The destination directory is\n' ...
                '%s\n\n' ...
                'Before download, you can update the destination directory'], ...
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

% ---- download the missing files ----
% core.DownloadProgressMonitor.download streams each file into one cancelable
% progress dialog that shows the step, the received / total MB and the speed.
% How its outcomes are handled here:
%   - {link, link2}: link2 (mirror) is tried only when link fails with an error
%   - Cancel pressed: it returns cancelled = true WITHOUT an error and has already
%     deleted the partly written file, so the isfile() checks above stay reliable:
%     files completed before the cancel are kept and the next call downloads only
%     what is still missing. status stays false and sessionSettings is not updated.
%   - every address of a file failed: it throws; the catch below closes the
%     dialog and passes the error on to the caller
deepMibDir = obj.mibModel.preferences.ExternalDirs.DeepMIBDir;
backbone = obj.mibModel.preferences.SegmTools.(samVersionName).backbone;
numFiles = nnz(~[checkpointExists, onnxExists, modelCfgExists]);
stepIndex = 0;
wb = [];
if numFiles > 0
    wb = uiprogressdlg(obj.mibModel.getProgressBarParent(), 'Message', 'Connecting...', ...
        'Title', sprintf('Downloading %s', backbone), 'Indeterminate', 'on', 'Cancelable', 'on');
end

try
    if checkpointExists == 0
        stepIndex = stepIndex + 1;
        message = sprintf('Checkpoint %s (%d/%d)', checkpointFilename, stepIndex, numFiles);
        [~, cancelled] = core.DownloadProgressMonitor.download({checkpointLink, checkpointLink2}, wb, message, ...
            fullfile(deepMibDir, checkpointFilename));
        if cancelled; delete(wb); return; end
        fprintf('The checkpoint file %s was downloaded to %s\n', checkpointFilename, deepMibDir);
    end

    if onnxExists == 0
        stepIndex = stepIndex + 1;
        message = sprintf('Onnx for %s (%d/%d)', backbone, stepIndex, numFiles);
        % the onnx comes zipped: download it to a temporary file, so a cancel leaves
        % nothing in deepMibDir, and unzip it only after a complete download
        zipFilename = [tempname '.zip'];
        [~, cancelled] = core.DownloadProgressMonitor.download(onnxLink, wb, message, zipFilename);
        if cancelled; delete(wb); return; end
        wb.Cancelable = 'off';      % unzip cannot be interrupted
        wb.Message = sprintf('Unzipping onnx for %s...', backbone);
        unzip(zipFilename, deepMibDir);
        delete(zipFilename);
        wb.Cancelable = 'on';
        fprintf('The onnx file %s was downloaded to %s\n', onnxFilename, deepMibDir);
    end

    if modelCfgExists == 0
        stepIndex = stepIndex + 1;
        message = sprintf('Model config %s (%d/%d)', modelCfgFilename, stepIndex, numFiles);
        [~, cancelled] = core.DownloadProgressMonitor.download({modelCfgLink, modelCfgLink2}, wb, message, ...
            fullfile(deepMibDir, modelCfgFilename));
        if cancelled; delete(wb); return; end
        fprintf('The model config file %s was downloaded to %s\n', modelCfgFilename, deepMibDir);
    end
catch err
    % every address of a file failed (or the unzip failed): close the dialog and
    % pass the error on; nothing partial is left in deepMibDir
    if ~isempty(wb) && isvalid(wb); delete(wb); end
    rethrow(err);
end
delete(wb);

% update sessionSettings with the selected backbone
obj.mibModel.sessionSettings.SAMsegmenter.Links.checkpointFilename = checkpointFilename;
obj.mibModel.sessionSettings.SAMsegmenter.Links.onnxFilename = onnxFilename;
obj.mibModel.sessionSettings.SAMsegmenter.Links.modelCfgFilename = modelCfgFilename;
obj.mibModel.sessionSettings.SAMsegmenter.Links.backbone = linksStruct(selectedBackboneIndex).backbone;

status = true;
end
