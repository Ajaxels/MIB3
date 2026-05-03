function segmentationSAM(obj, extraOptions, BatchOptIn)
% SEGMENTATIONSAM - Perform segmentation using Segment Anything Model (SAM).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.segmentationSAM()
%      obj.segmentationSAM(extraOptions)
%      obj.segmentationSAM(extraOptions, BatchOptIn)
%
% Perform segmentation using Segment Anything Model. See https://segment-anything.com
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
%     - ``.Method`` — [char] specify how SAM should execute:
%
%       - ``'Interactive'`` — add points interactively
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
%      obj.segmentationSAM(extraOptions);
%

if nargin < 2; extraOptions = []; end

if isempty(extraOptions); extraOptions = struct(); end
if ~isfield(extraOptions, 'addNextMaterial'); extraOptions.addNextMaterial = true; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();   % optional, id
BatchOpt.Method = {obj.mibController.cSegmentation.handles.samMethod.Value};
BatchOpt.Method{2} = {'Interactive', 'Landmarks', 'Automatic everything'};
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
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, sprintf('A structure as the 2nd parameter is required!'), 'Error');
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
    toolname = 'segment-everything model is';
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    header = sprintf('The %s not yet available in the virtual stacking mode!\nPlease switch to the memory-resident mode and try again', toolname);
    dlgOpt.HeaderLines = 3;
    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'Not implemented', dlgOpt);
    return;
end

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

methodToUse = find(ismember(BatchOpt.Method{2}, BatchOpt.Method{1})); % 1, 2, 3: ['Interactive', 'Landmarks', 'Automatic everything']
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
    status = obj.segmentationSAM_requirements();
    if ~status; return; end
    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', ...
            sprintf('Initializing Python environment\n%s\nPlease wait...', obj.mibModel.preferences.SegmTools.SAM1.backbone), ...
            'Title', 'SAM segmentation');
    end

    checkpointFilename = obj.mibModel.sessionSettings.SAMsegmenter.Links.checkpointFilename;
    onnxFilename = obj.mibModel.sessionSettings.SAMsegmenter.Links.onnxFilename;
    model_type = obj.mibModel.sessionSettings.SAMsegmenter.Links.backbone;

    % path to segment-anything package from github
    samPath = obj.mibModel.preferences.SegmTools.SAM1.sam_installation_path;

    onnx_model_path = fullfile(obj.mibModel.preferences.ExternalDirs.DeepMIBDir, onnxFilename);
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

    if BatchOpt.showWaitbar; wb.Value = 0.1; end
    % Add the SAM folder to the Python search path
    pyPath = py.sys.path;
    if count(pyPath, samPath) == 0     % add to path
        insert(py.sys.path, int64(0), samPath);
    end

    % import required modules
    pyrun('import cv2');
    pyrun('import numpy as np')
    pyrun('from segment_anything import sam_model_registry, SamPredictor, SamAutomaticMaskGenerator');
    pyrun('import onnxruntime');
    pyrun(sprintf('onnx_model_path = "%s"', strrep(onnx_model_path, '\', '/')));
    if BatchOpt.showWaitbar; wb.Value = 0.3; end

    if strcmp(obj.mibModel.preferences.SegmTools.SAM1.environment, 'cuda')
        pyrun('ort_session = onnxruntime.InferenceSession(onnx_model_path, providers=["CUDAExecutionProvider", "CPUExecutionProvider"])');
    else
        pyrun('ort_session = onnxruntime.InferenceSession(onnx_model_path, providers=["CPUExecutionProvider"])');
    end
    if BatchOpt.showWaitbar; wb.Value = 0.5; end
    % define checkpoint and model type
    pyrun(sprintf('checkpoint = "%s"', strrep(checkpoint, '\', '/')));
    pyrun(sprintf('model_type = "%s"', model_type));

    pyrun('sam = sam_model_registry[model_type](checkpoint=checkpoint)')
    if BatchOpt.showWaitbar; wb.Value = 0.7; end

    if strcmp(obj.mibModel.preferences.SegmTools.SAM1.environment, 'cuda')
        pyrun('sam.to(device="cuda")');
    else
        pyrun('sam.to(device="cpu")');
    end
    if BatchOpt.showWaitbar; wb.Value = 0.8; end
    pyrun('predictor = SamPredictor(sam)');
    if BatchOpt.showWaitbar; wb.Value = 0.9; end

    pyrun(['mask_generator = SamAutomaticMaskGenerator(' ...
        'model = sam, ' ...
        'points_per_side = pnts_p_side, ' ...
        'points_per_batch = pnts_p_batch, ' ...
        'pred_iou_thresh = pred_iou_th, ' ...
        'stability_score_thresh = st_sco_th, ' ...
        'crop_n_layers = crop_n_l, ' ...
        'crop_nms_thresh = crop_n_th, ' ...
        'crop_overlap_ratio = crop_ovl_rto, ' ...
        'crop_n_points_downscale_factor = crop_n_pnts_downsc_f, ' ...
        'min_mask_region_area = min_mask_reg_area)'], ...
        pnts_p_side = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM1.points_per_side), ...
        pnts_p_batch = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM1.points_per_batch), ...
        pred_iou_th = py.numpy.float16(obj.mibModel.preferences.SegmTools.SAM1.pred_iou_thresh), ...
        st_sco_th = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM1.stability_score_thresh), ...
        crop_n_l = py.numpy.int32(obj.mibModel.preferences.SegmTools.SAM1.crop_n_layers), ...
        crop_n_th = py.numpy.float16(obj.mibModel.preferences.SegmTools.SAM1.crop_nms_thresh), ...
        crop_ovl_rto = py.numpy.float16(obj.mibModel.preferences.SegmTools.SAM1.crop_overlap_ratio), ...
        crop_n_pnts_downsc_f = obj.mibModel.preferences.SegmTools.SAM1.crop_n_points_downscale_factor, ...
        min_mask_reg_area = obj.mibModel.preferences.SegmTools.SAM1.min_mask_region_area);

    if BatchOpt.showWaitbar; wb.Value = 1; end
    close(wb);
end

% define limits
t1 = 1;
t2 = dataset.image.time;
if strcmp(BatchOpt.Dataset{1}, '2D, Slice') || ...
        strcmp(BatchOpt.Method{1}, 'Interactive')
    z1 = dataset.getCurrentSliceNumber();
    z2 = z1;
else
    z1 = 1;
    z2 = dataset.image.depth;
end
noImages = (z2-z1+1)*(t2-t1+1);

% redefine showing of the progress bar
localWaitbar = BatchOpt.showWaitbar;
if strcmp(BatchOpt.Method{1}, 'Interactive') && ~obj.mibModel.preferences.SegmTools.SAM1.showProgressBar
    localWaitbar = false;
end

if localWaitbar; wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, 'Message', sprintf('%s\nPlease wait...', BatchOpt.Method{1}), 'Title', 'Segment anything'); end

currViewPort = dataset.image.viewPort;
max_int = double(dataset.image.maxInt);
getDataOpt.id = BatchOpt.id;
% enable blocked mode switch
getLabelsOpt = struct();
if strcmp(BatchOpt.Method{1}, 'Interactive')
    getDataOpt.blockModeSwitch = true;

    getLabelsOpt.blockModeSwitch = true;
    getLabelsOpt.shiftCoordinates = true;
    if ismember(BatchOpt.Mode{1}, {'add',  'add, +next material'})
        % do not make backup in this mode
        % as it has already been made in gui_WindowButtonDownFcn
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
    [blockHeight, blockWidth] = dataset.getDatasetDimensions('image', NaN, NaN, getDatasetDimensionsOpt);
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    backupOptions.x(1) = max([1 ceil(axesX(1))]);
    backupOptions.x(2) = min([ceil(axesX(2)), blockWidth]);
    backupOptions.y(1) = max([1 ceil(axesY(1))]);
    backupOptions.y(2) = min([ceil(axesY(2)), blockHeight]);
    backupOptions.z(1) = z1;
    backupOptions.z(2) = z2;
    if numel(obj.mibModel.sessionSettings.SAMsegmenter.Points.Value) == 1
        backupOptions.LinkedData.Points.Position = [];
        backupOptions.LinkedData.Points.Value = [];
    else
        backupOptions.LinkedData.Points.Position = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(1:end-1,:);
        backupOptions.LinkedData.Points.Value = obj.mibModel.sessionSettings.SAMsegmenter.Points.Value(1:end-1);
    end
    % MibModel.undo, restores the sessionSettings relative to itself so "obj" is used instead of obj.mibModel
    backupOptions.LinkedVariable.Points = 'obj.sessionSettings.SAMsegmenter.Points';
    obj.mibModel.backup(BatchOpt.Destination{1}, 0, backupOptions);  % do backup
end

try
    for t=t1:t2
        getDataOpt.t = [t, t];

        for z=z1:z2
            if methodToUse == 2 % landmark mode
                [labelsList, labelValues, labelPositions, indices] = dataset.getSliceLabels(z, t, getLabelsOpt);
                if isempty(labelsList)
                    counter = counter + 1;
                    if localWaitbar && mod(counter, 10); wb.Value = counter/noImages; end
                    continue;
                end
            end

            % get image
            imgIn = cell2mat(obj.mibModel.getData2D('image', z, dataset.orientation, NaN, getDataOpt));

            if size(imgIn, 3) ~= 1 && size(imgIn, 3) ~= 3
                dlgOpt.MsgBoxOnly = true;
                header = sprintf('Segmentation using segment-everything model is only available for grayscale and RGB images\nFor multi-channel images select a single channel in the Colors table and try again!');
                dlgOpt.HeaderLines = 3;
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'SAM segmentation error', dlgOpt);
                if localWaitbar; close(wb); end
                return;
            end

            % convert to 8bit
            if ~isa(imgIn, 'uint8')
                if obj.mibModel.onFlyImageStretch
                    for i=1:size(imgIn,3)
                        imgIn(:,:,i) = imadjust(imgIn(:,:,i), stretchlim(imgIn(:,:,i),[0 1]),[]);
                    end
                    imgIn = uint8(imgIn/256);
                else
                    % convert to the 8bit image
                    if size(imgIn, 3) == 1
                        colCh = dataset.selectedColorChannel;
                        if currViewPort.min(colCh) ~= 0 || currViewPort.max(colCh) ~= max_int || currViewPort.gamma(colCh) ~= 1
                            imgIn = imadjust(imgIn, [currViewPort.min(colCh)/max_int currViewPort.max(colCh)/max_int], [0 1], currViewPort.gamma(colCh));
                        end
                    else
                        if max(currViewPort.min) > 0 || min(currViewPort.max) ~= max_int || sum(currViewPort.gamma) ~= 3
                            for colCh=1:3
                                imgIn(:,:,colCh) = imadjust(imgIn(:,:,colCh), [currViewPort.min(colCh)/max_int currViewPort.max(colCh)/max_int], [0 1], currViewPort.gamma(colCh));
                            end
                        end
                    end
                    imgIn = uint8(imgIn/256);
                end
            end

            % add padding to minimize edge artefacts
            if methodToUse == 1
                padSize = ceil(size(imgIn, 2)/256);
                imgIn = padarray(imgIn, [padSize padSize], 'symmetric', 'both');
            end
            % convert to RGB
            if size(imgIn, 3) == 1 %#ok<ISMAT>
                imgIn = repmat(imgIn, [1 1 3]);
            end
            switch methodToUse
                case 1  % Interactive in-view points
                    % check for points from different slices and remove points
                    % that do not belong to the current slice
                    currZ = dataset.getCurrentSliceNumber();
                    % get indices of the points on the current slice
                    pntIndices = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3) == currZ;
                    % keep only the points on the current slice
                    obj.mibModel.sessionSettings.SAMsegmenter.Points.Position = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(pntIndices, :);
                    obj.mibModel.sessionSettings.SAMsegmenter.Points.Value = obj.mibModel.sessionSettings.SAMsegmenter.Points.Value(pntIndices);
                    % remove z-coordinate
                    labelPositions = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:, 1:2);
                    % shift coordinates
                    labelPositions(:,1) = ceil((labelPositions(:,1) - max([0 floor(dataset.axesX(1))])) );
                    labelPositions(:,2) = ceil((labelPositions(:,2) - max([0 floor(dataset.axesY(1))])) );
                    imgOut = pointsSAM(imgIn, labelPositions, obj.mibModel.sessionSettings.SAMsegmenter.Points.Value);
                    imgOut = imgOut(padSize+1:end-padSize, padSize+1:end-padSize);    % remove padding

                    % limit to the selected material of the model
                    if dataset.restrictSelectionToMaterial == 1
                        imgOut = bitand(imgOut, obj.mibModel.sessionSettings.SAMsegmenter.initialImageSelected);
                    end

                    switch BatchOpt.Mode{1}
                        case 'replace'
                            obj.mibModel.setData2D({imgOut}, BatchOpt.Destination{1}, NaN, NaN, dataset.selectedAddToMaterial-2, getDataOpt);
                        case 'add'
                            obj.mibModel.setData2D({bitor(obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo, imgOut)}, BatchOpt.Destination{1}, NaN, NaN, dataset.selectedAddToMaterial-2, getDataOpt);
                        case 'subtract'
                            currLayer = cell2mat(obj.mibModel.getData2D(BatchOpt.Destination{1}, NaN, NaN, dataset.selectedAddToMaterial-2, getDataOpt));
                            obj.mibModel.setData2D({currLayer - imgOut}, BatchOpt.Destination{1}, NaN, NaN, dataset.selectedAddToMaterial-2, getDataOpt);
                        case 'add, +next material'
                            selMaterialIndex = dataset.getSelectedMaterialIndex('AddTo');

                            obj.mibModel.setData2D({bitor(obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo, imgOut)}, BatchOpt.Destination{1}, NaN, NaN, selMaterialIndex, getDataOpt);

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
                case 2  % Landmarks
                    % keep only x,y
                    labelPositions = labelPositions(:,2:3);
                    imgOut = pointsSAM(imgIn, labelPositions, labelValues);
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
                case 3  % Automatic everything
                    masks = pyrun('masks = mask_generator.generate(image)', 'masks', image=py.numpy.array(imgIn));
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
catch err
    utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, err, 'Problem', '', ...
        'You might be running out of GPU memory; try to decrease "Set the number of points run simultaneously by the model in SAM settings"');
    if localWaitbar; close(wb); end
    return;
end
if localWaitbar; close(wb); end
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

end

function imgOut = pointsSAM(imgIn, labelPositions, labelIndices)
% POINTSSAM - do interactive prediction of 2D image using ONNX runtime.
%
% Syntax:
%   function imgOut = pointsSAM(imgIn, labelPositions, labelIndices)
%
% Input Arguments:
%   - **imgIn** — image to segment (height, width, colors)
%   - **labelPositions** — matrix of coordinates for seeds ([seedId; x,y])
%   - **labelIndices** — matrix positive (1) and negative seeds (0)
%
% Output Arguments:
%   - **imgOut** — results of the segmentation, 2D image (height, width)
%

pyrun('predictor.set_image(image)', image=py.numpy.array(imgIn))
pyrun('image_embedding = predictor.get_image_embedding().cpu().numpy()')

% duplicate the coordinate to preserve dimension
if size(labelPositions,1) == 1
    labelPositions = [labelPositions; labelPositions];
    labelIndices = [labelIndices labelIndices];
end

labelPositions = py.numpy.array(labelPositions);
pyrun('input_point = np.array(pointCoordinates)', pointCoordinates=labelPositions);
labelIndices = py.numpy.array(labelIndices);
pyrun('input_label = np.array(labelIndices)', labelIndices=labelIndices);

% Add a batch index, concatenate a padding point, and transform.
pyrun('onnx_coord = np.concatenate([input_point, np.array([[0.0, 0.0]])], axis=0)[None, :, :]');
pyrun('onnx_label = np.concatenate([input_label, np.array([-1])], axis=0)[None, :].astype(np.float32)');
pyrun('onnx_coord = predictor.transform.apply_coords(onnx_coord, image.shape[:2]).astype(np.float32)');

% Create an empty mask input and an indicator for no mask.
pyrun('onnx_mask_input = np.zeros((1, 1, 256, 256), dtype=np.float32)')
pyrun('onnx_has_mask_input = np.zeros(1, dtype=np.float32)')

pyrun(['ort_inputs = {' ...
    '"image_embeddings": image_embedding, ' ...
    '"point_coords": onnx_coord, ' ...
    '"point_labels": onnx_label, ' ...
    '"mask_input": onnx_mask_input, ' ...
    '"has_mask_input": onnx_has_mask_input, ' ...
    '"orig_im_size": np.array(image.shape[:2], dtype=np.float32)' ...
    '}'])

pyrun('masks, _, low_res_logits = ort_session.run(None, ort_inputs)');
imgOut = pyrun('masks = masks > predictor.model.mask_threshold', 'masks');   % do not remove ";", it hangs matlab
imgOut = uint8(squeeze(imgOut));

% clear GPU memory
pyrun([
    "import torch", ...
    "import gc", ...
    "torch.cuda.empty_cache()", ...
    "torch.cuda.synchronize()", ...
    "gc.collect()"
]);

% this pause is required to clear the sticky key modifier states
pause(0.1);

end
