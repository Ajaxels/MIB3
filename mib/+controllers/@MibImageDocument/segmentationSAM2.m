function segmentationSAM2(obj, extraOptions, BatchOptIn)
% SEGMENTATIONSAM2 - Perform segmentation using Segment Anything Model 2 (SAM2).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.segmentationSAM2()
%      obj.segmentationSAM2(extraOptions)
%      obj.segmentationSAM2(extraOptions, BatchOptIn)
%
% Perform segmentation using Segment Anything Model 2. See https://github.com/facebookresearch/segment-anything-2
%
% Input Arguments:
%   - **extraOptions** *(optional)* — [struct] structure with additional options:
%
%     - ``.addNextMaterial`` — [logical] switch to add next material for "add, +next material" mode
%
%   - **BatchOptIn** *(optional)* — [struct|NaN] batch processing mode;
%     when ``NaN``, returns default structure via "syncBatch" event.
%     See Declaration of BatchOpt structure below for details; function
%     variables are preferred over BatchOptIn variables:
%
%     - ``.Method`` — [char] specify how SAM2 should execute:
%
%       - ``'Interactive'`` — add points interactively
%       - ``'Interactive 3D'`` — add points for 3D video segmentation
%       - ``'Landmarks'`` — process placed points all at once
%       - ``'Automatic everything'`` — automatically segment all objects on image
%
%     - ``.Dataset`` — [char] segment current slice (``'2D, Slice'``), stack (``'3D, Stack'``), or whole dataset (``'4D, Dataset'``)
%     - ``.Destination`` — [char] MIB layer for results: ``'selection'``, ``'mask'``, or ``'labels'``
%     - ``.showWaitbar`` — [logical] show progress bar during execution
%
% Output Arguments:
%   (none)
%
% **Example** — perform segmentation:
%
%   .. code-block:: matlab
%
%      obj.segmentationSAM2(extraOptions);
%

if nargin < 2; extraOptions = []; end

if isempty(extraOptions); extraOptions = struct(); end
if ~isfield(extraOptions, 'addNextMaterial'); extraOptions.addNextMaterial = true; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();   % optional, id
BatchOpt.Method = {obj.mibController.cSegmentation.handles.samMethod.Value};
BatchOpt.Method{2} = {'Interactive', 'Interactive 3D', 'Landmarks', 'Automatic everything'};
BatchOpt.Dataset = {obj.mibController.cSegmentation.handles.samDataset.Value};
BatchOpt.Dataset{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
BatchOpt.Destination = {obj.mibController.cSegmentation.handles.samDestination.Value};
BatchOpt.Destination{2} = {'selection', 'mask', 'labels'};
BatchOpt.Mode = {obj.mibController.cSegmentation.handles.samMode.Value};
BatchOpt.Mode{2} = {'replace', 'add', 'subtract'};
BatchOpt.showWaitbar = true;   % show or not the waitbar

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';    % section name for the Batch
BatchOpt.mibBatchActionName = 'Segment-anything model';

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.Method = sprintf('Specify method how SAM should be executed');
BatchOpt.mibBatchTooltip.Dataset = sprintf('Apply SAM for the current slice (2D, Slice), current stack (3D, Stack) or the whole dataset(4D, Dataset)');
BatchOpt.mibBatchTooltip.Destination = sprintf('Destination layer for the results');

% do backup of the current state
doBackup = true;

%% Batch mode check actions
if nargin == 3  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when varargin{3} == NaN return possible settings
            % trigger syncBatch event to send BatchOptInOut to mibBatchController
            BatchOpt = rmfield(BatchOpt, 'id');     % remove id field
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, sprintf('A structure as the 3rd parameter is required!'), 'Error');
        end
        return;
    else
        % add/update BatchOpt with the provided fields in BatchOptIn
        % combine fields from input and default structures
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
    if ismember(BatchOpt.Method{1}, {'Interactive'})
        dlgOpt.MsgBoxOnly = true;
        header = sprintf('"%s" mode is not available in the batch processing mode!', BatchOpt.Method{1});
        dlgOpt.HeaderLines = 2;
        utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'Error', dlgOpt);
        return;
    end
end

dataset = obj.mibModel.I{BatchOpt.id};

% check for the virtual stacking mode and return
if strcmp(dataset.datasetType, 'Virtual')
    toolname = 'segment-everything-2 model is';
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    header = sprintf('The %s not yet available in the virtual stacking mode!\nPlease switch to the memory-resident mode and try again', toolname);
    dlgOpt.HeaderLines = 3;
    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'Not implemented', dlgOpt);
    return;
end

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

methodToUse = find(ismember(BatchOpt.Method{2}, BatchOpt.Method{1})); % 1, 2, 3, 4: ['Interactive', 'Interactive 3D', 'Landmarks', 'Automatic everything'
% create a new model. if needed
switch BatchOpt.Method{1}
    case 'Automatic everything'
        if dataset.modelExist
            if dataset.labels.maxMaterials == 65353
                obj.mibModel.createModel(65535);
            elseif (~strcmp(BatchOpt.Dataset{1}, '2D, Slice') && dataset.image.depth > 1) || ...
                    (strcmp(BatchOpt.Dataset{1}, '2D, Slice') && dataset.image.depth == 1)
                obj.mibModel.createModel(65535);
            end
        else
            obj.mibModel.createModel(65535);
        end
    otherwise
        if strcmp(BatchOpt.Destination{1}, 'labels')
            if numel(dataset.labels.materialNames) == 0
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                header = sprintf('Please create the Model and add there a material first!\n\nPress the "+" in the Segmentation panel');
                dlgOpt.HeaderLines = 3;
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'The model is missing!', dlgOpt);
                return;
            end
            if dataset.selectedMaterial < 2; return; end
        end
end

% init python environment
if isempty(obj.mibModel.pythonEnv)
    % check python requirements
    status = obj.segmentationSAM_requirements('SAM2');
    if ~status; return; end

    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
            sprintf('Initializing Python environment\n%s\nPlease wait...', obj.mibModel.preferences.SegmTools.SAM2.backbone), ...
            'Title', 'SAM2 segmentation');
    end

    checkpointFilename = obj.mibModel.sessionSettings.SAMsegmenter.Links.checkpointFilename;
    modelCfgFilename = obj.mibModel.sessionSettings.SAMsegmenter.Links.modelCfgFilename;
    if ~ispc; modelCfgFilename = strrep(modelCfgFilename, '%2B', '+'); end % swap %2B with + for Linux

    % path to segment-anything package from github
    samPath = obj.mibModel.preferences.SegmTools.SAM2.sam_installation_path;

    if ispc() % for PC the full absolute path is used
        model_cfg = fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, modelCfgFilename);
    else
        % for linux it is important to copy *.yaml configs to sam2
        % subfolder of segment-anything-2
        % in this case only modelCfgFilename is used to initalize it
        model_cfg = modelCfgFilename;
    end
    checkpoint = fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, checkpointFilename);

    try
        obj.mibModel.pythonEnv = pyenv( ...
            'Version', obj.mibModel.preferences.ExternalDirs.PythonInstallationPath, ...
            'ExecutionMode', 'OutOfProcess');     % InProcess or OutOfProcess
    catch err
        if strcmp(err.identifier, 'MATLAB:Pyenv:PythonLoaded')
            terminate(pyenv);
            obj.mibModel.pythonEnv = pyenv( ...
                'Version', obj.mibModel.preferences.ExternalDirs.PythonInstallationPath, ...
                'ExecutionMode', 'OutOfProcess');     % InProcess or OutOfProcess
        end
    end

    if BatchOpt.showWaitbar; wb.Value = 0.5; end
    % Add the SAM folder to the Python search path
    pyPath = py.sys.path;
    if count(pyPath, samPath) == 0     % add to path
        insert(py.sys.path, int64(0), samPath);
    end

    % import required modules
    pyrun('import torch');
    if BatchOpt.showWaitbar; wb.Value = 0.7; end
    pyrun('import numpy as np');
    pyrun('from sam2.build_sam import build_sam2');
    if BatchOpt.showWaitbar; wb.Value = 0.8; end
    pyrun('from sam2.sam2_image_predictor import SAM2ImagePredictor');
    pyrun('from sam2.automatic_mask_generator import SAM2AutomaticMaskGenerator');
    pyrun('from sam2.build_sam import build_sam2_video_predictor');
    if BatchOpt.showWaitbar; wb.Value = 0.9; end

    pyrun(sprintf('torch.autocast(device_type="%s", dtype=torch.bfloat16).__enter__()', ...
        obj.mibModel.preferences.SegmTools.SAM2.environment));

    % turn on tfloat32 for Ampere GPUs
    pyrun(sprintf(['' ...
        'if torch.cuda.get_device_properties(0).major >= 8:\n' ...
        '   torch.backends.cuda.matmul.allow_tf32 = True\n' ...
        '   torch.backends.cudnn.allow_tf32 = True']));

    pyrun(sprintf('checkpoint = "%s"', strrep(checkpoint, '\', '/'))); % checkpoint = "./checkpoints/sam2_hiera_large.pt"
    pyrun(sprintf('model_cfg = "%s"', strrep(model_cfg, '\', '/')));  % model_cfg = "sam2_hiera_tiny.yaml"

    % set predictor status in false state
    pyrun('predictor2D = 0');
    pyrun('predictor3D = 0');
    pyrun('predictorMasks = 0');

    if BatchOpt.showWaitbar; wb.Value = 1; end
    close(wb);
end

% init predictors
try
    switch BatchOpt.Method{1}
        case {'Interactive', 'Landmarks'}
            notInitStatus = pyrun('notInitStatus = predictor2D==0', 'notInitStatus');
            if notInitStatus
                if BatchOpt.showWaitbar
                    wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
                        sprintf('Initializing SAM2 predictor for %s\n%s\nPlease wait...', BatchOpt.Method{1}, obj.mibModel.preferences.SegmTools.SAM2.backbone), ...
                        'Title', 'SAM2 segmentation');
                    drawnow;
                end
                pyrun(sprintf('sam2_model = build_sam2(model_cfg, checkpoint, device="%s")', obj.mibModel.preferences.SegmTools.SAM2.environment));
                % init predictor for the interactive mode for images
                pyrun('predictor2D = SAM2ImagePredictor(sam2_model)');
            end
        case 'Interactive 3D'
            notInitStatus = pyrun('notInitStatus = predictor3D==0', 'notInitStatus');
            if notInitStatus
                if BatchOpt.showWaitbar
                    wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
                        sprintf('Initializing SAM2 predictor for %s\n%s\nPlease wait...', BatchOpt.Method{1}, obj.mibModel.preferences.SegmTools.SAM2.backbone), ...
                        'Title', 'SAM2 segmentation');
                    drawnow;
                end
                % init predictor for the interactive mode for video
                pyrun(sprintf('predictor3D = build_sam2_video_predictor(model_cfg, checkpoint, device="%s")', obj.mibModel.preferences.SegmTools.SAM2.environment));
            end
        case 'Automatic everything'
            notInitStatus = pyrun('notInitStatus = predictorMasks==0', 'notInitStatus');
            if notInitStatus
                if BatchOpt.showWaitbar
                    wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
                        sprintf('Initializing SAM2 predictor for %s\n%s\nPlease wait...', BatchOpt.Method{1}, obj.mibModel.preferences.SegmTools.SAM2.backbone), ...
                        'Title', 'SAM2 segmentation');
                    drawnow;
                end
                % init mask generator for automatic mode
                pyrun(sprintf('sam2_model = build_sam2(model_cfg, checkpoint, device="%s", apply_postprocessing=False)', obj.mibModel.preferences.SegmTools.SAM2.environment));
                pyrun(['predictorMasks = SAM2AutomaticMaskGenerator(' ...
                    'model = sam2_model, ' ...
                    'points_per_side = pnts_p_side, ' ...
                    'points_per_batch = pnts_p_batch, ' ...
                    'pred_iou_thresh = pred_iou_th, ' ...
                    'stability_score_thresh = st_sco_th, ' ...
                    'stability_score_offset = st_sco_offset, ' ...
                    'crop_n_layers = crop_n_l, ' ...
                    'box_nms_thresh = box_nms_thresh, ' ...
                    'crop_n_points_downscale_factor = crop_n_pnts_downsc_f, ' ...
                    'min_mask_region_area = min_mask_reg_area,' ...
                    'use_m2m = bool(use_m2m),)'], ...
                    pnts_p_side = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM2.points_per_side), ...
                    pnts_p_batch = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM2.points_per_batch), ...
                    pred_iou_th = py.numpy.float16(obj.mibModel.preferences.SegmTools.SAM2.pred_iou_thresh), ...
                    st_sco_th = py.numpy.float16(obj.mibModel.preferences.SegmTools.SAM2.stability_score_thresh), ...
                    st_sco_offset = py.numpy.float16(obj.mibModel.preferences.SegmTools.SAM2.stability_score_offset), ...
                    crop_n_l = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM2.crop_n_layers), ...
                    box_nms_thresh = py.numpy.float16(obj.mibModel.preferences.SegmTools.SAM2.box_nms_thresh), ...
                    crop_n_pnts_downsc_f = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM2.crop_n_points_downscale_factor), ...
                    min_mask_reg_area = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM2.min_mask_region_area), ...
                    use_m2m = obj.mibModel.preferences.SegmTools.SAM2.use_m2m);
            end
    end
    if BatchOpt.showWaitbar && exist('wb', 'var'); wb.Value = 1; close(wb); end
catch err
    utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, err, 'Problem', '', ...
        'Try to copy yaml configs to the specified SAM2 directory');
    obj.mibModel.pythonEnv = [];
    if BatchOpt.showWaitbar && exist('wb', 'var'); close(wb); end
    return;
end

% define limits
if strcmp(BatchOpt.Dataset{1}, '4D, Dataset')
    % process all time points
    t1 = 1;
    t2 = dataset.image.time;
else
    t1 = dataset.getCurrentTimePoint();
    t2 = t1;
end

if strcmp(BatchOpt.Dataset{1}, '2D, Slice') && methodToUse ~= 2  % not for Interactive 3D
    z1 = dataset.getCurrentSliceNumber();
    z2 = z1;
else
    switch BatchOpt.Method{1}
        case {'Interactive', 'Interactive 3D'}
            % when click is done on the same slice or when a new click is
            % done with a different value, make 2D segmentation
            if numel(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3)) > 1 && ...
                    (obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end,3)-obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end-1,3) == 0 || ...
                    abs(diff(obj.mibModel.sessionSettings.SAMsegmenter.Points.Value(end-1:end))) == 1)
                z1 = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end,3);
                z2 = z1;
            else
                z1 = min(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3));
                z2 = max(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3));
            end
        case 'Landmarks'
            z1 = dataset.annotations.getMinValueZ();
            z2 = dataset.annotations.getMaxValueZ();
        otherwise
            z1 = 1;
            z2 = dataset.image.depth;
    end
end
noImages = (z2-z1+1)*(t2-t1+1);

% redefine showing of the progress bar
localWaitbar = BatchOpt.showWaitbar;
if ismember(BatchOpt.Method{1}, {'Interactive', 'Interactive 3D'}) && ~obj.mibModel.preferences.SegmTools.SAM2.showProgressBar && noImages == 1
    localWaitbar = false;
end

if localWaitbar; wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', sprintf('%s\nPlease wait...', BatchOpt.Method{1}), 'Title', 'Segment anything'); end

getDataOpt.id = BatchOpt.id;

% enable blocked mode switch
getLabelsOpt = struct();
if ismember(BatchOpt.Method{1}, {'Interactive', 'Interactive 3D'})
    getDataOpt.blockModeSwitch = true;

    getLabelsOpt.blockModeSwitch = true;
    getLabelsOpt.shiftCoordinates = true;
    if ismember(BatchOpt.Mode{1}, {'add', 'add, +next material'}) % && methodToUse ~= 2
        % first click in non-Interactive-3D 'add' mode: gui_WindowButtonDownFcn already stored backup
        doBackup = false;
    end
    if numel(obj.mibModel.sessionSettings.SAMsegmenter.Points.Value) > 1 && z1 == z2
        % same-slice refinement (ctrl-click, or shift-click on same slice): no new backup needed;
        % the backup was already made on the first click or the first shift-click to a new slice
        doBackup = false;
    end
else
    if dataset.blockModeSwitch
        getLabelsOpt.blockModeSwitch = true;
        getLabelsOpt.shiftCoordinates = true;
    end
end

counter = 0;
tic;

% do backup
if t2-t1 == 0 && doBackup
    getDatasetDimensionsOpt.blockModeSwitch = 0;
    [blockHeight, blockWidth] = dataset.getDatasetDimensions('image', [], getDatasetDimensionsOpt);
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    backupOptions.x(1) = max([1 ceil(axesX(1))]);
    backupOptions.x(2) = min([ceil(axesX(2)), blockWidth]);
    backupOptions.y(1) = max([1 ceil(axesY(1))]);
    backupOptions.y(2) = min([ceil(axesY(2)), blockHeight]);
    backupOptions.z(1) = z1;
    backupOptions.z(2) = z2;
    if numel(obj.mibModel.sessionSettings.SAMsegmenter.Points.Value) == 1 %#ok<ISCL>
        backupOptions.LinkedData.Points.Position = [];
        backupOptions.LinkedData.Points.Value = [];
    else
        backupOptions.LinkedData.Points.Position = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(1:end-1,:);
        backupOptions.LinkedData.Points.Value = obj.mibModel.sessionSettings.SAMsegmenter.Points.Value(1:end-1);
    end
    % MibModel.undo, restores the sessionSettings relative to itself so "obj" is used instead of obj.mibModel
    backupOptions.LinkedVariable.Points = 'obj.sessionSettings.SAMsegmenter.Points'; 
    obj.mibModel.backup(BatchOpt.Destination{1}, 1, backupOptions);  % do backup
end

% define default output data type when generating data by pointsSAM and pointsVideoSAM
castDataType = 'uint8';

% get current contrast
currViewPort = dataset.image.viewPort;
liveStretch = obj.mibModel.onFlyImageStretch;
colCh = dataset.selectedColorChannel;

try
    for t=t1:t2
        getDataOpt.t = [t, t];
        if methodToUse == 2   % 'Interactive 3D'
            % code below is an adapation of video segmentation from SAM2 for 3D microscopy datasets
            % it requires addition of init_state_from_array function into sam2_video_predictor.py in order to work

            if localWaitbar && t1==t2
                wb.Value = 0.05; wb.Message = sprintf('%s: preparing data\nPlease wait...', BatchOpt.Method{1});
                drawnow;
            end

            getDataOpt.z = [z1 z2];
            imgDataset = cell2mat(obj.mibModel.getData3D('image', t, dataset.orientation, NaN, getDataOpt));
            % check for correct number of color channels, adjust contast, do image padding and convert to RGB
            [imgDataset, padSize] = checkAndPreprocessImage(imgDataset, methodToUse, currViewPort, colCh, liveStretch, true);
            if isnan(imgDataset(1))
                if localWaitbar; close(wb); end
                return;
            end

            % get positions, x,y,z
            labelPositions = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:, 1:3);
            labelValues = obj.mibModel.sessionSettings.SAMsegmenter.Points.Value;

            % shift coordinates
            labelPositions(:,1) = ceil((labelPositions(:,1) - max([0 floor(dataset.axesX(1))])) +padSize);
            labelPositions(:,2) = ceil((labelPositions(:,2) - max([0 floor(dataset.axesY(1))])) +padSize);
            labelPositions(:,3) = labelPositions(:,3) - z1;

            % do SAM2 segmentation using the provided list of points using predictor for video

            [h1, w1, d1, c1] = size(imgDataset);
            % use pre-resizing when h1 or w1 > 1024
            % to minimize data exchange between MATLAB and Python
            useResize = false;
            if h1 > 1024 || w1 > 1024; useResize = true; end
            useResize = false;
            if useResize
                dataset2 = zeros([1024 1024 d1 c1], class(imgDataset));
                scaleH = 1024/h1;
                scaleW = 1024/w1;
                % scale coordinates of seeds
                labelPositions(:,2) = labelPositions(:,2)*scaleH;
                labelPositions(:,1) = labelPositions(:,1)*scaleW;
                for z=1:d1
                    dataset2(:,:,z,:) = imresize(imgDataset(:,:,z,:), [1024 1024], 'bicubic');
                end
                if localWaitbar && t1==t2
                    wb.Value = 0.15; wb.Message = sprintf('%s: starting SAM\nPlease wait...', BatchOpt.Method{1});
                end
                dataset2 = pointsVideoSAM(dataset2, labelPositions, labelValues, castDataType);
                if localWaitbar && t1==t2
                    wb.Value = 0.9; wb.Message = sprintf('%s: upsampling results\nPlease wait...', BatchOpt.Method{1});
                end
                imgDataset = zeros([h1 w1 d1], class(dataset2));
                sigma = 1/min([scaleH scaleW]);
                for z=1:d1
                    mask = imresize(dataset2(:,:,z), [h1, w1], 'nearest');
                    imgDataset(:,:,z) = imgaussfilt(mask, sigma);
                end
            else
                if localWaitbar && t1==t2
                    wb.Value = 0.15; wb.Message = sprintf('%s: starting SAM\nPlease wait...', BatchOpt.Method{1});
                    drawnow;
                end
                imgDataset = pointsVideoSAM(imgDataset, labelPositions, labelValues, castDataType);
                if localWaitbar && t1==t2
                    wb.Value = 0.9; wb.Message = sprintf('%s: finalizing\nPlease wait...', BatchOpt.Method{1});
                end
            end

            imgDataset = imgDataset(padSize+1:end-padSize, padSize+1:end-padSize, :, :);    % remove padding

            % auto fill the shape when auto fill is checked
            if obj.mibModel.autoFillSelection
                for z=1:size(imgDataset, 3)
                    imgDataset(:,:,z) = imfill(imgDataset(:,:,z));
                end
            end

            % limit to the selected material of the model
            if dataset.restrictSelectionToMaterial == true
                imgDataset = bitand(imgDataset, obj.mibModel.sessionSettings.SAMsegmenter.initialImageSelected);
            end

            selMaterialIndex = dataset.getSelectedMaterialIndex('AddTo');
            switch BatchOpt.Mode{1}
                case 'replace'
                    obj.mibModel.setData3D(imgDataset, BatchOpt.Destination{1}, t, dataset.orientation, selMaterialIndex, getDataOpt);
                case 'add'
                    obj.mibModel.setData3D({bitor(obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo, imgDataset)}, BatchOpt.Destination{1}, t, dataset.orientation, selMaterialIndex, getDataOpt);
                case 'subtract'
                    currLayer = cell2mat(obj.mibModel.getData3D(BatchOpt.Destination{1}, t, NaN, selMaterialIndex, getDataOpt));
                    obj.mibModel.setData3D({currLayer - imgDataset}, BatchOpt.Destination{1}, t, NaN, selMaterialIndex, getDataOpt);
                case 'add, +next material'
                    obj.mibModel.setData3D({bitor(obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo, imgDataset)}, BatchOpt.Destination{1}, t, NaN, selMaterialIndex, getDataOpt);

                    % add next material
                    if extraOptions.addNextMaterial
                        dataset.labels.materialNames = {num2str(selMaterialIndex), num2str(selMaterialIndex+1) };
                        if size(dataset.labels.materialColors, 1) < selMaterialIndex+1  % generate a random color
                            dataset.labels.materialColors(selMaterialIndex+1, :) = rand(1,3);
                        end
                        obj.mibController.cSegmentation.updateMaterialsTable();
                        eventdata2.Indices = [dataset.selectedAddToMaterial, 3];
                        obj.mibController.cSegmentation.materialsTable_CellSelectionCallback(eventdata2.Indices);
                    end
            end
        else   % 'Interactive', 'Landmarks', 'Automatic everything'
            for z=z1:z2
                if methodToUse == 3 % landmark mode
                    [labelsList, labelValues, labelPositions, indices] = dataset.getSliceLabels(z, t, getLabelsOpt);
                    if isempty(labelsList)
                        counter = counter + 1;
                        if localWaitbar && mod(counter, 10); wb.Value = counter/noImages; end
                        continue;
                    end
                end

                % get image
                imgIn = cell2mat(obj.mibModel.getData2D('image', z, dataset.orientation, NaN, getDataOpt));
                % check for correct number of color channels, adjust contast, do image padding and convert to RGB
                [imgIn, padSize] = checkAndPreprocessImage(imgIn, methodToUse, currViewPort, colCh, liveStretch);
                imgIn = squeeze(imgIn);  % restore [H,W,C] for 2D processing
                if isnan(imgIn(1))
                    if localWaitbar; close(wb); end
                    return;
                end

                switch methodToUse
                    case 1  % Interactive in-view points
                        % get indices of the points on the current slice
                        pntIndices = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3) == z;
                        % get positions, keep only x,y
                        labelPositions = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(pntIndices, 1:2);
                        labelValues = obj.mibModel.sessionSettings.SAMsegmenter.Points.Value(pntIndices);

                        % shift coordinates
                        labelPositions(:,1) = ceil((labelPositions(:,1) - max([0 floor(dataset.axesX(1))])) +padSize);
                        labelPositions(:,2) = ceil((labelPositions(:,2) - max([0 floor(dataset.axesY(1))])) +padSize);

                        % do SAM2 segmentation using the provided list of points
                        [h1, w1, ~] = size(imgIn);
                        % use pre-resizing when h1 or w1 > 1024
                        useResize = false;
                        if h1 > 1024 || w1 > 1024; useResize = true; end
                        if useResize
                            scaleH = 1024/h1;
                            scaleW = 1024/w1;
                            % scale coordinates of seeds
                            labelPositions(:,2) = labelPositions(:,2)*scaleH;
                            labelPositions(:,1) = labelPositions(:,1)*scaleW;

                            imgIn = imresize(imgIn, [1024 1024], 'bicubic');

                            imgOut = pointsSAM(imgIn, labelPositions, labelValues, castDataType);
                            sigma = 1/min([scaleH scaleW]);
                            imgOut = imresize(imgOut, [h1, w1], 'nearest');
                            imgOut = imgaussfilt(imgOut, sigma);
                        else
                            imgOut = pointsSAM(imgIn, labelPositions, labelValues, castDataType);
                        end

                        imgOut = imgOut(padSize+1:end-padSize, padSize+1:end-padSize);    % remove padding

                        % auto fill the shape when auto fill is checked
                        if obj.mibModel.autoFillSelection
                            imgOut = imfill(imgOut);
                        end

                        % limit to the selected material of the model
                        if dataset.restrictSelectionToMaterial == 1
                            imgOut = bitand(imgOut, obj.mibModel.sessionSettings.SAMsegmenter.initialImageSelected);
                        end
                        selMaterialIndex = dataset.getSelectedMaterialIndex('AddTo');
                        switch BatchOpt.Mode{1}
                            case 'replace'
                                obj.mibModel.setData2D({imgOut}, BatchOpt.Destination{1}, z, NaN, selMaterialIndex, getDataOpt);
                            case 'add'
                                obj.mibModel.setData2D({bitor(obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo, imgOut)}, BatchOpt.Destination{1}, z, NaN, selMaterialIndex, getDataOpt);
                            case 'subtract'
                                currLayer = cell2mat(obj.mibModel.getData2D(BatchOpt.Destination{1}, z, NaN, selMaterialIndex, getDataOpt));
                                obj.mibModel.setData2D({currLayer - imgOut}, BatchOpt.Destination{1}, z, NaN, selMaterialIndex, getDataOpt);
                            case 'add, +next material'
                                obj.mibModel.setData2D({bitor(obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo(:,:,z-z1+1), imgOut)}, BatchOpt.Destination{1}, z, NaN, selMaterialIndex, getDataOpt);

                                % add next material
                                if extraOptions.addNextMaterial
                                    dataset.labels.materialNames = {num2str(selMaterialIndex), num2str(selMaterialIndex+1) };
                                    if size(dataset.labels.materialColors, 1) < selMaterialIndex+1  % generate a random color
                                        dataset.labels.materialColors(selMaterialIndex+1, :) = rand(1,3);
                                    end
                                    obj.mibController.cSegmentation.updateMaterialsTable();
                                    eventdata2.Indices = [dataset.selectedAddToMaterial, 3];
                                    obj.mibController.cSegmentation.materialsTable_CellSelectionCallback(eventdata2.Indices);
                                end
                        end
                    case 3  % Landmarks
                        % get labels, keep only x,y
                        labelPositions = labelPositions(:,2:3);
                        imgOut = pointsSAM(imgIn, labelPositions, labelValues);
                        % auto fill the shape when auto fill is checked
                        if obj.mibModel.autoFillSelection
                            imgOut = imfill(imgOut);
                        end

                        switch BatchOpt.Mode{1}
                            case 'replace'
                                obj.mibModel.setData2D({imgOut}, BatchOpt.Destination{1}, z, NaN, dataset.selectedAddToMaterial-2, getDataOpt);
                            case 'add'
                                currLayer = cell2mat(obj.mibModel.getData2D(BatchOpt.Destination{1}, z, NaN, dataset.selectedAddToMaterial-2, getDataOpt));
                                obj.mibModel.setData2D({bitor(currLayer, imgOut)}, BatchOpt.Destination{1}, z, NaN, dataset.selectedAddToMaterial-2, getDataOpt);
                            case 'subtract'
                                currLayer = cell2mat(obj.mibModel.getData2D(BatchOpt.Destination{1}, z, NaN, dataset.selectedAddToMaterial-2, getDataOpt));
                                obj.mibModel.setData2D({currLayer - imgOut}, BatchOpt.Destination{1}, z, NaN, dataset.selectedAddToMaterial-2, getDataOpt);
                        end
                    case 4  % Automatic everything
                        masks = pyrun('masks = predictorMasks.generate(image)', 'masks', image=py.numpy.array(imgIn));
                        for maskId=1:double(py.len(masks))
                            currentMask = uint8(masks{maskId}{'segmentation'});
                            if maskId==1; modelOut = zeros(size(currentMask), 'uint16'); end
                            modelOut(currentMask==1) = maskId;
                        end
                        obj.mibModel.setData2D({modelOut}, 'labels', z, NaN, NaN, getDataOpt);
                end
                counter = counter + 1;
                if localWaitbar && mod(counter, 10); wb.Value = counter/noImages; end
            end
        end
    end
catch err
    utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, err, 'Problem', '', ...
        'You might be running out of GPU memory; try to decrease "Set the number of points run simultaneously by the model in SAM settings"');
    if localWaitbar; close(wb); end
    return;
end
toc

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfSAMclicks = obj.mibModel.preferences.Users.Tiers.numberOfSAMclicks+1;
eventdata = core.ToggleEventData(2);    % scale scoring by factor 2
notify(obj.mibModel, 'UpdateUserScore', eventdata);

% notify the batch mode
BatchOpt = rmfield(BatchOpt, 'id');     % remove id field
eventdata = core.ToggleEventData(BatchOpt);
notify(obj.mibModel, 'SyncBatch', eventdata);
if strcmp(BatchOpt.Destination{1}, 'mask')
    obj.mibModel.showMask = true;
    notify(obj.mibModel, 'ShowImage');
end

notify(obj.mibModel, 'ShowImage');
if localWaitbar; close(wb); end

end

function [imgIn, padSize] = checkAndPreprocessImage(imgIn, methodToUse, currViewPort, colCh, liveStretch, is3Ddata)
% CHECKANDPREPROCESSIMAGE - check for correct number of color channels, adjust.
%
% Syntax:
%   function [imgIn, padSize] = checkAndPreprocessImage(imgIn, methodToUse, currViewPort, colCh, liveStretch, is3Ddata)
%
% contast, do image padding and convert to RGB
%
% Input Arguments:
%   - **imgIn** — matrix [height, width, depth, colors] to check and process
%   - **methodToUse** — index of the SAM2 method that was used, 1-Interactive, 2-Interactive 3D, 3-Landmarks, 4-Automatic
%   - **currViewPort** — current viewport settings, comes from dataset.image.viewPort as
%     .min
%     .max
%     .gamma
%   - **colCh** — selected color channels
%   - **liveStretch** — [logical] switch to automatically stretch the contrast
%   - **is3Ddata** — *(optional)* logical, when true the input is a 3D dataset
%     where dim3=depth; when false (default) dim3=colors (2D image)
%
% Output Arguments:
%   - **imgIn** — converted image as [height, width, depth, colors]
%   - **padSize** — size of padding used for the Interactive mode
%

if nargin < 6; is3Ddata = false; end

padSize = 0;
% ensure 4D [H,W,D,C] layout for uniform processing
% 2D input [H,W,C]: dim3 is colors  -> reshape to [H,W,1,C]
% 3D input [H,W,D]: dim3 is depth   -> reshape to [H,W,D,1]
% 2D input [H,W]:   no colors/depth -> reshape to [H,W,1,1]
if ndims(imgIn) <= 3
    if is3Ddata
        % [H,W,D] grayscale volume -> [H,W,D,1]
        imgIn = reshape(imgIn, size(imgIn,1), size(imgIn,2), size(imgIn,3), 1);
    else
        % [H,W,C] or [H,W] 2D image -> [H,W,1,C]
        imgIn = reshape(imgIn, size(imgIn,1), size(imgIn,2), 1, size(imgIn,3));
    end
end

if size(imgIn, 4) ~= 1 && size(imgIn, 4) ~= 3
    errorOpts.WindowHeight = 150;
    utils.dlgs.showErrorDialog([], sprintf('Segmentation using segment-everything model is only available for grayscale and RGB images\nFor multi-channel images select a single channel in the Colors table and try again!'), ...
        'Error', 'SAM segmentation error', '', errorOpts);
    imgIn = NaN;
    return;
end

% convert to 8bit
if ~isa(imgIn, 'uint8')
    max_int = double(intmax(class(imgIn)));
    if liveStretch
        for z=1:size(imgIn, 3)
            for i=1:size(imgIn, 4)
                imgIn(:,:,z,i) = imadjust(imgIn(:,:,z,i), stretchlim(imgIn(:,:,z,i), [0 1]), []);
            end
        end
        imgIn = uint8(imgIn/256);
    else
        % convert to the 8bit image
        if size(imgIn, 4) == 1
            if currViewPort.min(colCh) ~= 0 || currViewPort.max(colCh) ~= max_int || currViewPort.gamma(colCh) ~= 1
                for z=1:size(imgIn, 3)
                    imgIn(:,:,z) = imadjust(imgIn(:,:,z), [currViewPort.min(colCh)/max_int currViewPort.max(colCh)/max_int], [0 1], currViewPort.gamma(colCh));
                end
            end
        else
            if max(currViewPort.min) > 0 || min(currViewPort.max) ~= max_int || sum(currViewPort.gamma) ~= 3
                for z=1:size(imgIn, 3)
                    for colCh2=1:3
                        imgIn(:,:,z,colCh2) = imadjust(imgIn(:,:,z,colCh2), [currViewPort.min(colCh2)/max_int currViewPort.max(colCh2)/max_int], [0 1], currViewPort.gamma(colCh2));
                    end
                end
            end
        end
        imgIn = uint8(imgIn/256);
    end
end

% add padding to minimize edge artefacts
if methodToUse == 1 || methodToUse == 2  % 'Interactive', 'Interactive 3D'
    padSize = ceil(size(imgIn, 2)/256);
    imgIn = padarray(imgIn, [padSize padSize], 'symmetric', 'both');
end

% convert to RGB
if size(imgIn, 4) == 1 %#ok<ISMAT>
    imgIn = repmat(imgIn, [1 1 1 3]);
end
end

function imgOut = pointsSAM(imgIn, labelPositions, labelIndices, castDataType)
% POINTSSAM - do interactive prediction of 2D image in imgIn using seeds in.
%
% Syntax:
%   function imgOut = pointsSAM(imgIn, labelPositions, labelIndices, castDataType)
%
% labelPositions and labelIndices
%
% Input Arguments:
%   - **imgIn** — image to segment (height, width, colors)
%   - **labelPositions** — matrix of coordinates for seeds ([seedId; x,y])
%   - **labelIndices** — matrix positive (1) and negative seeds (0)
%   - **castDataType** — string with class to cast output imgOut
%
% Output Arguments:
%   - **imgOut** — results of the segmentation, 2D image (height, width)
%

if nargin < 4; castDataType = 'uint8'; end

% send image to predictor
pyrun('predictor2D.set_image(image)', image=py.numpy.array(imgIn))

% duplicate the coordinate to preserve dimension
if size(labelPositions,1) == 1
    labelPositions = [labelPositions; labelPositions];
    labelIndices = [labelIndices labelIndices];
end

labelPositions = py.numpy.array(labelPositions);
pyrun('input_point = np.array(pointCoordinates)', pointCoordinates=labelPositions);
%  transpose to have labelIndices in a row:
if size(labelIndices,1)>size(labelIndices,2); labelIndices = labelIndices'; end
labelIndices = py.numpy.array(labelIndices);
pyrun('input_label = np.array(labelIndices)', labelIndices=labelIndices);

multipleMasks = false;
if multipleMasks
    pyrun(['masks, scores, logits = predictor2D.predict(', ...
        'point_coords=input_point,', ...
        'point_labels=input_label,', ...
        'multimask_output=True)']);
    pyrun('sorted_ind = np.argsort(scores)[::-1]');
    imgOut = pyrun('masks = masks[sorted_ind]', 'masks');
    pyrun('scores = scores[sorted_ind]');
    pyrun('logits = logits[sorted_ind]');
else
    imgOut = pyrun([...
        ['with torch.no_grad():' ...
        '   masks, scores, logits = predictor2D.predict('], ...
        '   point_coords=input_point,', ...
        '   point_labels=input_label,', ...
        '   multimask_output=False)'] ...
    , 'masks');
end
imgOut = cast(squeeze(imgOut), castDataType);

% clear GPU memory
pyrun([
    "import torch", ...
    "import gc", ...
    "torch.cuda.empty_cache()", ...
    "torch.cuda.synchronize()", ...
    "gc.collect()"
]);

end

function dataset = pointsVideoSAM(dataset, labelPositions, labelValues, castDataType)
% POINTSVIDEOSAM - do SAM2 segmentation using the provided list of points using predictor for video.
%
% Syntax:
%   function dataset = pointsVideoSAM(dataset, labelPositions, labelValues, castDataType)
%
% Input Arguments:
%   - **dataset** — 3D dataset to predict as [height, width, depth, colors]
%   - **labelPositions** — list of seeds from the first slice of the dataset
%   - **labelValues** — values of the seeds: 1-positiva, 0-negative
%   - **castDataType** — string with class to cast output imgOut
%
% Output Arguments:
%   - **dataset** — results of the segmentation, 3D image (height, width, depth)
%

[height, width, depth, colors] = size(dataset);

% permute from [height, width, depth, colors] to [depth, height, width, colors]
dataset = permute(dataset, [3 1 2 4]);

% get indices of the points on the slice where seeds were placed
pntIndices = ~isnan(labelValues);
start_frame_idx = labelPositions(pntIndices, 3);
% flip z of the dataset as the propagation of slices goes forward
use_reverse = false; % reverse the dataset for propagation backwards
if start_frame_idx ~= 0
    use_reverse = true;
    dataset = flip(dataset, 1);
end
% get positions, keep only x,y,z
labelPositions = labelPositions(pntIndices, 1:2);
labelValues = labelValues(pntIndices);

% initialize predictor with dataset
pyrun('inference_state = predictor3D.init_state_from_array(image_array=image)', image=py.numpy.array(dataset))
% reset the state of the predictor
pyrun('predictor3D.reset_state(inference_state)')
% get dimensions of the dataset to allocate space for output
pyrun('num_frames, height, width = image.shape[0], image.shape[1], image.shape[2]')

pyrun('ann_frame_idx = 0');
pyrun('ann_obj_id = 1')  % give a unique id to each object we interact with
pyrun('reverse_mode = use_reverse', 'use_reverse', use_reverse);

% duplicate the coordinate to preserve dimension
if size(labelPositions, 1) == 1
    labelPositions = [labelPositions; labelPositions];
    labelValues = [labelValues labelValues];
end

% send coordinates to python
pyrun('points = np.array(pointCoordinates, dtype=np.float32)', pointCoordinates=labelPositions);
% send seeds to python, '1' means positive click and '0' means negative click
pyrun('labels = np.array(labelValues, np.int32)', labelValues=labelValues);

if depth == 1  % when only a single slice provided
    pyrun(['with torch.no_grad():' ...
           '    _, out_obj_ids, out_mask_logits = predictor3D.add_new_points_or_box(', ...
           '        inference_state=inference_state,', ...
           '        frame_idx=ann_frame_idx,', ...
           '        obj_id=ann_obj_id,', ...
           '        points=points,', ...
           '        labels=labels)'   ]);

    dataset = pyrun('mask = (out_mask_logits[0] > 0.0).cpu().numpy()', 'mask');
    dataset = squeeze(dataset); % squeeze dimensions
else
    % propagate the prompts to get the masklet across the video
    pyrun(['with torch.no_grad():' ...
           '    predictor3D.add_new_points_or_box(', ...
           '        inference_state=inference_state,', ...
           '        frame_idx=ann_frame_idx,', ...
           '        obj_id=ann_obj_id, ', ...
           '        points=points,', ...
           '        labels=labels,', ...
           '        clear_old_points=True)']);

    % allocate space for the output
    pyrun('video_masks = np.zeros((height, width, num_frames), dtype=np.bool_)');
    pyrun(sprintf([...
        'for out_frame_idx, out_obj_ids, out_mask_logits in predictor3D.propagate_in_video(inference_state):\n' ...
        '   masks = (out_mask_logits > 0.0).cpu().numpy()\n' ...
        '   masks = masks.squeeze(1)\n' ...
        '   if reverse_mode:\n' ...
        '       video_masks[:, :, num_frames - 1 - out_frame_idx] = masks[0, :, :]\n' ...
        '   else:\n' ...
        '       video_masks[:, :, out_frame_idx] = masks[0, :, :]\n' ...
        ]));

    % Retrieve the numpy matrix and convert to MATLAB array
    dataset = pyrun('video_masks', 'video_masks');
end
dataset = cast(dataset, castDataType); % Shape: [height, width, depth]

% clear GPU memory
pyrun([
    "del inference_state", ...
    "import torch", ...
    "import gc", ...
    "gc.collect()", ...
    "torch.cuda.empty_cache()", ...
    "torch.cuda.synchronize()" ...
]);

end
