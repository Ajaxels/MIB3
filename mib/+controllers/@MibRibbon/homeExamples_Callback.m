function homeExamples_Callback(obj, BatchOptIn)
% HOMEEXAMPLES_CALLBACK - callback on press of the Examples buttons in the Home ribbon; imports an example dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.homeExamples_Callback(BatchOptIn)
%
% Input Arguments:
%   - **BatchOptIn** - a structure for batch processing mode, when NaN return
%     a structure with default options via "syncBatch" event
%     .Dataset [cell] dataset name
%     .DirectoryName [cell] output directory, only for DeepMIB projects
%     .showWaitbar [logical] show or not the waitbar
%
% .. note::
%    With the waitbar shown, every download can be cancelled while it runs
%    (``core.DownloadProgressMonitor``). A cancel returns before anything is
%    unzipped or the active dataset is replaced. Unzipping itself is not
%    cancelable, so the Cancel button is removed for that step.
%

BatchOpt = struct();
BatchOpt.Dataset = {'Huh7 and model'};
BatchOpt.Dataset{2} = {'Synthetic 2D Large spots', 'Synthetic 2D small spots', 'Synthetic 2.5D large spots', 'Synthetic 2D patch-wise', ...
    '2D EM membranes', '2D LM nuclei', '2D LM nuclei StarDist', '3D EM mitochondria', '3D LM hair cells', ...
    'LM 3D SIM ER', 'LM 3D STED', 'LM WF ER photobleaching', ...
    'Huh7 and model', 'Trypanosoma and model', 'MATLAB Brain and model'};
BatchOpt.DirectoryName = {'Current MIB path'};
BatchOpt.DirectoryName{2} = {'Current MIB path', 'Inherit from Directory/File loop', obj.mibModel.currentDirectory};
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
BatchOpt.mibBatchActionName = 'Example datasets';
BatchOpt.mibBatchTooltip.Dataset = sprintf('Select dataset or a DeepMIB project to import');
BatchOpt.mibBatchTooltip.DirectoryName = sprintf('Output directory for importing of DeepMIB projects');
BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not the waitbar');

batchMode = false; % switch to indicate the batch mode usage

if nargin == 2
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), 'A structure as the 2nd parameter is required!', 'BatchOpt Error');
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
        if strcmp(BatchOpt.DirectoryName{1}, 'Current MIB path')
            BatchOpt.DirectoryName{1} = obj.mibModel.currentDirectory;
        end
    end
    if isfield(BatchOptIn, 'showWaitbar');batchMode = true; end
else
    if strcmp(BatchOpt.DirectoryName{1}, 'Current MIB path')
        BatchOpt.DirectoryName{1} = obj.mibModel.currentDirectory;
    end
end

if ismember(BatchOpt.Dataset{1}, {'Synthetic 2D Large spots', 'Synthetic 2D small spots', 'Synthetic 2.5D large spots', 'Synthetic 2D patch-wise', ...
        '2D EM membranes', '2D LM nuclei', '2D LM nuclei StarDist', '3D EM mitochondria', '3D LM hair cells'}) && ~batchMode
    BatchOpt.DirectoryName{1} = uigetdir(BatchOpt.DirectoryName{1}, 'Select directory to unzip the project');
    if BatchOpt.DirectoryName{1} == 0; return; end
end

% developer check
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeExamples_Callback: pressed -> %s\n', BatchOpt.Dataset{1});
end


wb = [];    % stays empty without the waitbar: downloads then run without progress or cancel
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.mibModel.getProgressBarParent(), 'Value', 0, ...
        'Message', sprintf('Importing %s dataset\nPlease wait...', BatchOpt.Dataset{1}), ...
        'Title', 'Example dataset', 'Indeterminate', 'on', 'Cancelable', 'on');
end

id = obj.mibModel.getActiveId();

% All downloads below go through core.DownloadProgressMonitor.download instead of
% webread / unzip(url): the bytes are streamed while wb shows the received /
% total MB and the speed, and its Cancel button stops the transfer at once.
%   - raw datasets: [bytes, cancelled] = download(url, wb, message) returns the
%     file as a uint8 column, the same as webread(url, weboptions('ContentType', 'raw'))
%   - zip projects: download(url, wb, message, zipFilename) writes a temporary file
% After each call:
%   - Cancel pressed: cancelled = true and no error; close the dialog and return
%     before the active dataset is replaced or anything is unzipped
%   - download failed: an error is thrown, as webread / unzip(url) did before
% Huh7 and Trypanosoma download two files (image, model); each is checked.
switch BatchOpt.Dataset{1}
    case {'Synthetic 2D Large spots', 'Synthetic 2D small spots', 'Synthetic 2.5D large spots', 'Synthetic 2D patch-wise', ...
            '2D EM membranes', '2D LM nuclei', '2D LM nuclei StarDist', '3D EM mitochondria', '3D LM hair cells'}
        switch BatchOpt.Dataset{1}
            case 'Synthetic 2D small spots'
                url = 'http://mib.helsinki.fi/tutorials/datasets/2D_SmallSpots_3cl_Unet.zip';
            case 'Synthetic 2D Large spots'
                url = 'http://mib.helsinki.fi/tutorials/datasets/2D_LargeSpots_2cl_DeepLabV3.zip';
            case 'Synthetic 2.5D large spots'
                url = 'http://mib.helsinki.fi/tutorials/datasets/25D_LargeSpots.zip';
            case 'Synthetic 2D patch-wise'
                url = 'http://mib.helsinki.fi/tutorials/datasets/2D_LargeSpots_Patchwise_DeepLabV3.zip';
            case '2D EM membranes'
                url = 'http://mib.helsinki.fi/tutorials/deepmib/1_2DEM_Files.zip';
            case '2D LM nuclei'
                url = 'http://mib.helsinki.fi/tutorials/deepmib/2_2DLM_Files.zip';
            case '2D LM nuclei StarDist'
                url = 'http://mib.helsinki.fi/tutorials/deepmib/2D_Nuclei_StarDist.zip';
            case '3D EM mitochondria'
                url = 'http://mib.helsinki.fi/tutorials/deepmib/3_3DEM_Files.zip';
            case '3D LM hair cells'
                url = 'http://mib.helsinki.fi/tutorials/deepmib/4_3DLM_Files.zip';
        end
        % download to a temporary file first and unzip it only after a complete
        % download, so a cancel leaves nothing in the output directory
        zipFilename = [tempname '.zip'];
        [~, cancelled] = core.DownloadProgressMonitor.download(url, wb, ...
            sprintf('Downloading %s...', BatchOpt.Dataset{1}), zipFilename);
        if cancelled; delete(wb); return; end
        if ~isempty(wb)
            wb.Cancelable = 'off';      % unzip cannot be interrupted
            wb.Indeterminate = 'on';    % and reports no progress
            wb.Message = sprintf('Unzipping to\n%s', BatchOpt.DirectoryName{1});
        end
        unzip(zipFilename, BatchOpt.DirectoryName{1});
        delete(zipFilename);
        obj.mibModel.currentDirectory = BatchOpt.DirectoryName{1};
        
        % update list of files
        obj.mibController.cDirContents.updateFileList_Callback();

    case 'LM 3D SIM ER'
        [vol, cancelled] = core.DownloadProgressMonitor.download( ...
            'http://mib.helsinki.fi/tutorials/datasets/LM_SIM_ER.raw', wb, 'Downloading LM 3D SIM ER...');
        if cancelled; delete(wb); return; end
        vol = reshape(vol, [1024 1024 20 1]);
        obj.mibModel.I{id} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
        obj.mibModel.I{id}.image.sliceName = {fullfile(obj.mibModel.currentDirectory, 'LM_SIM_ER.tif')};
        obj.mibModel.I{id}.image.pixSize.x = 0.04;
        obj.mibModel.I{id}.image.pixSize.y = 0.04;
        obj.mibModel.I{id}.image.pixSize.z = 0.125;
        obj.mibModel.I{id}.updateBoundingBox([], [0 0 0]);
        [~, obj.mibModel.I{id}.image.pixSize] = utils.updatePixSizeAndResolution([], obj.mibModel.I{id}.image.pixSize);
        obj.mibModel.I{id}.image.updateActionLog('MIB demo dataset, LM SIM, ER', 'insert', 2);
        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');

    case 'LM 3D STED'
        [vol, cancelled] = core.DownloadProgressMonitor.download( ...
            'http://mib.helsinki.fi/tutorials/datasets/LM_STED.raw', wb, 'Downloading LM 3D STED...');
        if cancelled; delete(wb); return; end
        vol = reshape(vol, [1024 1024 2 13]);
        vol = permute(vol, [1 2 4 3]);
        obj.mibModel.I{id} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
        obj.mibModel.I{id}.image.sliceName = {fullfile(obj.mibModel.currentDirectory, 'LM_STED.tif')};
        obj.mibModel.I{id}.image.pixSize.x = 0.0329059;
        obj.mibModel.I{id}.image.pixSize.y = 0.0329059;
        obj.mibModel.I{id}.image.pixSize.z = 0.335694;
        obj.mibModel.I{id}.updateBoundingBox([], [0 0 0]);
        [~, obj.mibModel.I{id}.image.pixSize] = utils.updatePixSizeAndResolution([], obj.mibModel.I{id}.image.pixSize);
        obj.mibModel.I{id}.image.updateActionLog('MIB demo dataset, LM STED', 'insert', 2);
        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');

    case 'LM WF ER photobleaching'
        [vol, cancelled] = core.DownloadProgressMonitor.download( ...
            'http://mib.helsinki.fi/tutorials/datasets/LM_WF_timelapse_ER_Photobleaching.raw', wb, ...
            'Downloading LM WF ER photobleaching...');
        if cancelled; delete(wb); return; end
        vol = typecast(vol, 'uint16');
        vol = reshape(vol, [301 383 250 1]);
        obj.mibModel.I{id} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
        obj.mibModel.I{id}.image.sliceName = {fullfile(obj.mibModel.currentDirectory, 'LM_WF_timelapse_ER_Photobleaching.tif')};
        obj.mibModel.I{id}.image.pixSize.x = 0.157142;
        obj.mibModel.I{id}.image.pixSize.y = 0.157142;
        obj.mibModel.I{id}.image.pixSize.z = 1;
        obj.mibModel.I{id}.updateBoundingBox([], [0 0 0]);
        [~, obj.mibModel.I{id}.image.pixSize] = utils.updatePixSizeAndResolution([], obj.mibModel.I{id}.image.pixSize);
        obj.mibModel.I{id}.image.updateActionLog('MIB demo dataset, LM wide-field time-lapse, ER', 'insert', 2);
        obj.mibModel.I{id}.image.viewPort.min = 96;
        obj.mibModel.I{id}.image.viewPort.max = 423;
        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');

    case 'Huh7 and model'
        modelMaterialColors = [0.6510 0.2627 0.1294;
                               0.3098 0.4196 0.6706;
                               1.0000 0.8000 0.4000;
                               0.2784 0.6980 0.4941;
                               0.1020 0.2000 0.4353;
                               0.5882 0.6627 0.8353];
        [vol, cancelled] = core.DownloadProgressMonitor.download( ...
            'http://mib.helsinki.fi/tutorials/datasets/SBEM_Huh7.raw', wb, 'Downloading Huh7 image (1/2)...');
        if cancelled; delete(wb); return; end
        vol = reshape(vol, [372 521 75 1]);
        [label, cancelled] = core.DownloadProgressMonitor.download( ...
            'http://mib.helsinki.fi/tutorials/datasets/Labels_SBEM_Huh7.raw', wb, 'Downloading Huh7 model (2/2)...');
        if cancelled; delete(wb); return; end
        label = reshape(label, [372 521 75]);
        obj.mibModel.I{id} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
        obj.mibModel.I{id}.image.sliceName = {fullfile(obj.mibModel.currentDirectory, 'SBEM_Huh7.tif')};
        obj.mibModel.I{id}.image.pixSize.x = 0.013;
        obj.mibModel.I{id}.image.pixSize.y = 0.013;
        obj.mibModel.I{id}.image.pixSize.z = 0.030;
        obj.mibModel.I{id}.updateBoundingBox([], [0 0 0]);
        [~, obj.mibModel.I{id}.image.pixSize] = utils.updatePixSizeAndResolution([], obj.mibModel.I{id}.image.pixSize);
        obj.mibModel.I{id}.image.updateActionLog('MIB demo dataset, Huh7 SBEM', 'insert', 2);
        obj.mibModel.setData3D(label, 'labels');
        obj.mibModel.I{id}.labels.materialNames = [{'LD'}; {'NE'}; {'ER'}; {'Mito'}];
        obj.mibModel.I{id}.labels.materialColors = modelMaterialColors;
        notify(obj.mibModel, 'NewDataset');
        obj.mibModel.showModel = true;
        notify(obj.mibModel, 'ShowImage');

    case 'Trypanosoma and model'
        modelMaterialColors = [0.3098 0.4196 0.6706;
                               0.2784 0.6980 0.4941;
                               0.6510 0.2627 0.1294;
                               0.4902 0.1804 0.5608;
                               1.0000 0.8000 0.4000;
                               0.9686 0.9176 0.7961];
        [vol, cancelled] = core.DownloadProgressMonitor.download( ...
            'http://mib.helsinki.fi/tutorials/datasets/SBEM_Trypanosoma.raw', wb, 'Downloading Trypanosoma image (1/2)...');
        if cancelled; delete(wb); return; end
        vol = reshape(vol, [887 813 171 1]);
        [label, cancelled] = core.DownloadProgressMonitor.download( ...
            'http://mib.helsinki.fi/tutorials/datasets/Labels_SBEM_Trypanosoma.raw', wb, 'Downloading Trypanosoma model (2/2)...');
        if cancelled; delete(wb); return; end
        label = reshape(label, [887 813 171]);
        obj.mibModel.I{id} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
        obj.mibModel.I{id}.image.sliceName = {fullfile(obj.mibModel.currentDirectory, 'SBEM_Trypanosoma.tif')};
        obj.mibModel.I{id}.image.pixSize.x = 0.0140193;
        obj.mibModel.I{id}.image.pixSize.y = 0.0140193;
        obj.mibModel.I{id}.image.pixSize.z = 0.03;
        obj.mibModel.I{id}.updateBoundingBox([], [0 0 0]);
        [~, obj.mibModel.I{id}.image.pixSize] = utils.updatePixSizeAndResolution([], obj.mibModel.I{id}.image.pixSize);
        obj.mibModel.I{id}.image.updateActionLog('MIB demo dataset, Trypanosoma, SBEM', 'insert', 2);
        obj.mibModel.setData3D(label, 'labels');
        obj.mibModel.I{id}.labels.materialNames = [{'Nuclei'}; {'Mito'}; {'Vesicles'}; {'LD'}; {'ER'}; {'Cytoplasm'}];
        obj.mibModel.I{id}.labels.materialColors = modelMaterialColors;
        notify(obj.mibModel, 'NewDataset');
        obj.mibModel.showModel = true;
        notify(obj.mibModel, 'ShowImage');

    case 'MATLAB Brain and model'
        if isdeployed
            delete(wb);
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                'MATLAB brain dataset is only available in MIB for MATLAB!', 'Not available');
            return;
        end
        dataDir = fullfile(toolboxdir('images'), 'imdata', 'BrainMRILabeled');
        load(fullfile(dataDir, 'images', 'vol_003.mat'));
        load(fullfile(dataDir, 'labels', 'label_003.mat'));
        %vol = permute(vol, [1 2 3 4]);
        vol = uint8(vol * 0.1469);
        obj.mibModel.I{id} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
        obj.mibModel.I{id}.image.sliceName = {fullfile(obj.mibModel.currentDirectory, 'brainMRI_MATLAB_Example.tif')};
        obj.mibModel.I{id}.updateBoundingBox([], [0 0 0]);
        [~, obj.mibModel.I{id}.image.pixSize] = utils.updatePixSizeAndResolution([], obj.mibModel.I{id}.image.pixSize);
        obj.mibModel.I{id}.image.updateActionLog('MATLAB Brain MRI demo dataset', 'insert', 2);
        obj.mibModel.setData3D(label, 'labels'); %#ok<NODEF>
        obj.mibModel.I{id}.modelExist = true;
        obj.mibModel.I{id}.labels.materialNames = [{'Mat1'}; {'Mat2'}; {'Mat3'}];
        notify(obj.mibModel, 'NewDataset');
        obj.mibModel.showModel = true;
        notify(obj.mibModel, 'ShowImage');
end

delete(wb);

eventdata = core.ToggleEventData(BatchOpt);
notify(obj.mibModel, 'SyncBatch', eventdata);
end
