function img = Filter(obj, img, batchModeSwitch)
% FILTER - Apply the currently selected image filter to the dataset or a supplied image.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.Filter()              % reads data from model, applies filter, writes back
%       img = obj.Filter(img)     % applies filter to supplied image (used by preview/thumbnail)
%
% Input Arguments:
%   - **img** — *(optional)* image to filter; when empty the filter reads/writes via MibModel
%   - **batchModeSwitch** — *(optional)* ``1`` in batch mode (skips reading parameters from GUI)

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageFilters.Filter: triggered\n');
end
if nargin < 3; batchModeSwitch = 0; end
if nargin < 2; img = []; end

% build BatchOptOut — merge filter-specific parameters into a flat struct
BatchOptOut = obj.BatchOpt;

if batchModeSwitch == 0     % GUI mode: read current filter parameters
    ImageFiltersFields = fieldnames(obj.imageFiltersParams.(BatchOptOut.FilterName{1}));
    for i = 1:numel(ImageFiltersFields)
        if strcmp(ImageFiltersFields{i}, 'mibBatchTooltip'); continue; end
        BatchOptOut.(ImageFiltersFields{i}) = obj.imageFiltersParams.(BatchOptOut.FilterName{1}).(ImageFiltersFields{i});
    end
end

obj.imageFiltersParams.DesiredFilterName = BatchOptOut.FilterName{1};

% validate DistanceMap parameters
if strcmp(BatchOptOut.FilterName{1}, 'DistanceMap')
    errorMessage = [];
    if BatchOptOut.Mode3D == 1 && ~strcmp(BatchOptOut.Method{1}, 'euclidean')
        errorMessage = sprintf('DistanceMap in the 3D mode is implemented only for the "euclidean" method!\nPlease change the Method field to "euclidean" or switch off 3D and try again');
    end
    if strcmp(BatchOptOut.SourceLayer{1}, 'image')
        errorMessage = sprintf('The source layer for the DistanceMap filter should be one of these: "selection", "mask", or "labels"');
    end
    if ~isempty(errorMessage)
        utils.dlgs.showErrorDialog(obj.view.gui, errorMessage, 'Wrong parameters!');
        return;
    end
end

% define parent window
if isempty(obj.view)   % headless batch mode
    parentFigure = obj.mibModel.mibGUI;
else
    parentFigure = obj.view.gui;
end

returnBatchSettings = 0;
if isempty(img)
    % check for virtual stacking mode
    if isprop(obj.mibModel.I{obj.BatchOpt.id}, 'Virtual') && obj.mibModel.I{obj.BatchOpt.id}.Virtual.virtual == 1
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
            {sprintf('This tool is not compatible with the virtual stacking mode!\nPlease switch to the memory-resident mode and try again')}, ...
            'Not implemented', dlgOpt);
        notify(obj.mibModel, 'StopProtocol');
        obj.closeWindow();
        return;
    end

    id = obj.BatchOpt.id;
    if obj.mibModel.I{id}.roiShow
        getDataOptions.roiId = 0;   % restrict to all shown ROIs
    else
        getDataOptions.roiId = -1;  % no ROI restriction
    end
    getDataOptions.id = id;

    if strcmp(BatchOptOut.FilterGroup{1}, 'Image Binarization')
        backupLayer = BatchOptOut.DestinationLayer{1};
    else
        backupLayer = BatchOptOut.SourceLayer{1};
    end

    if strcmp(BatchOptOut.FilterName{1}, 'ElasticDistortion') && BatchOptOut.DistortAllLAyers
        backupLayer = 'image';
    end
    if strcmp(BatchOptOut.FilterName{1}, 'DistanceMap')
        backupLayer = 'image';
    end

    switch obj.BatchOpt.DatasetType{1}
        case '2D, Slice'
            if batchModeSwitch == 0; obj.mibModel.backup(backupLayer, 0, getDataOptions); end
            timeVector = [obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint(), obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint()];
        case '3D, Stack'
            if batchModeSwitch == 0; obj.mibModel.backup(backupLayer, 1, getDataOptions); end
            timeVector = [obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint(), obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint()];
        case '4D, Dataset'
            timeVector = [1, obj.mibModel.I{obj.BatchOpt.id}.image.time];
    end
    returnBatchSettings = 1;
end

% validate 3D mode compatibility
if BatchOptOut.Mode3D == 1 && ~ismember(BatchOptOut.FilterName{1}, obj.Filters3D)
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('The selected filter (%s) is only available in 2D mode!\nPlease change Mode3D parameter to false', BatchOptOut.FilterName{1}), ...
        'Error');
    return;
end

% filter a supplied image directly (preview/thumbnail path)
t1 = tic;
if ~isempty(img)
    BatchOptOut.ColorChannel{1} = 1;
    BatchOptOut.Mode3D = false;
    if isfield(BatchOptOut, 'useRGB') && BatchOptOut.useRGB == 1
        if size(img,3) ~= 3; return; end
    end

    switch BatchOptOut.ActionToResult{1}
        case 'Fitler image'
            img = utils.doImageFiltering(img, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
        case 'Filter and add'
            imgOut = utils.doImageFiltering(img, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
            img = img + imgOut;
        case 'Filter and subtract'
            imgOut = utils.doImageFiltering(img, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
            img = img - imgOut;
    end
    if size(img, 4)+size(img, 3) > 2; toc; end
    return;
end

% resolve color channel
switch BatchOptOut.ColorChannel{1}
    case 'All';      colChannel = NaN;  % MIB3: NaN = all channels
    case 'Displayed'; colChannel = [];
    otherwise;       colChannel = str2double(BatchOptOut.ColorChannel{1});
end
if strcmp(BatchOptOut.SourceLayer{1}, 'labels')
    colChannel = str2double(BatchOptOut.MaterialIndex);
end

% determine which layers to process (ElasticDistortion can distort all)
if strcmp(BatchOptOut.FilterName{1}, 'ElasticDistortion') && BatchOptOut.DistortAllLAyers
    if obj.mibModel.I{obj.BatchOpt.id}.labels.maxMaterials == 63
        sourceLayersList = {'image', 'everything'};
    else
        sourceLayersList = {'image', 'labels', 'mask'};
    end
else
    sourceLayersList = BatchOptOut.SourceLayer(1);
end

for sourceLayerId = 1:numel(sourceLayersList)
    BatchOptOut.SourceLayer(1) = sourceLayersList(sourceLayerId);
    for t = timeVector(1):timeVector(2)
        if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
            img = obj.mibModel.getData3D(sourceLayersList{sourceLayerId}, t, [], colChannel, getDataOptions);
        else
            getDataOptions.t = [t t];
            img = obj.mibModel.getData2D(sourceLayersList{sourceLayerId}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], colChannel, getDataOptions);
        end

        if strcmp(BatchOptOut.FilterGroup{1}, 'Image Binarization') && size(img{1}, 4) > 1
            utils.dlgs.showErrorDialog(obj.view.gui, 'Please select a single color channel before binarization', 'Too many color channels');
            return;
        end

        for roi = 1:numel(img)
            % adjust image for SLIC/Watershed clustering (needs uint8)
            % img{roi} is in MIB3 format [H,W,Z,C] for 3D or [H,W,C] for 2D
            if ismember(BatchOptOut.FilterName{1}, {'SlicClustering', 'WatershedClustering'})
                id = obj.mibModel.getActiveId();
                viewPort = obj.mibModel.I{id}.image.viewPort;
                if isempty(colChannel)
                    col_channel = obj.mibModel.I{obj.BatchOpt.id}.slices{4};
                elseif isnan(colChannel)
                    col_channel = 1;
                else
                    col_channel = colChannel;
                end
                if isa(img{roi}, 'uint16')
                    if obj.mibModel.onFlyImageStretch
                        for sliceId = 1:size(img{roi}, 3)
                            img{roi}(:,:,sliceId,1) = imadjust(img{roi}(:,:,sliceId,1), stretchlim(img{roi}(:,:,sliceId,1),[0 1]),[]);
                        end
                    else
                        for sliceId = 1:size(img{roi}, 3)
                            img{roi}(:,:,sliceId,1) = imadjust(img{roi}(:,:,sliceId,1), [viewPort.min(col_channel)/65535 viewPort.max(col_channel)/65535],[0 1],viewPort.gamma(col_channel));
                        end
                    end
                    img{roi} = uint8(img{roi}/255);
                else
                    if viewPort.min(col_channel) > 1 || viewPort.max(col_channel) < 255
                        for sliceId = 1:size(img{roi}, 3)
                            img{roi}(:,:,sliceId,1) = imadjust(img{roi}(:,:,sliceId,1), [viewPort.min(col_channel)/255 viewPort.max(col_channel)/255],[0 1],viewPort.gamma(col_channel));
                        end
                    end
                end
            end

            switch BatchOptOut.ActionToResult{1}
                case 'Fitler image'
                    [img{roi}, log_text] = utils.doImageFiltering(img{roi}, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
                case 'Filter and add'
                    [imgOut, log_text] = utils.doImageFiltering(img{roi}, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
                    img{roi} = img{roi}+imgOut;
                case 'Filter and subtract'
                    [imgOut, log_text] = utils.doImageFiltering(img{roi}, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
                    img{roi} = img{roi}-imgOut;
            end

            % Normalize output: doImageFiltering normalizes to [H,W,Z,C] internally.
            % For 2D-slice image data it adds a Z=1 dim ([H,W,C]→[H,W,1,C]); squeeze it back.
            % For non-image layers, squeeze [H,W,Z,1] → [H,W,Z] (or [H,W] for 2D).
            if strcmp(sourceLayersList{sourceLayerId}, 'image') && strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                img{roi} = squeeze(img{roi});  % [H,W,1,C] → [H,W,C] for setData2D
            elseif ~strcmp(sourceLayersList{sourceLayerId}, 'image') && ~ismember(BatchOptOut.FilterName{1}, {'DistanceMap'})
                img{roi} = squeeze(img{roi});  % [H,W,Z,1] → [H,W,Z] for setData3D non-image
            end
        end

        if ismember(BatchOptOut.FilterName{1}, {'DistanceMap'})
            % apply result to image layer; convert class if needed
            id = obj.mibModel.getActiveId();
            if ~strcmp(obj.mibModel.I{id}.image.dataClass, class(img{1}(1)))
                convertOpt.showWaitbar = true;
                obj.mibModel.I{id}.image.convertImage(class(img{1}(1)), convertOpt);
                notify(obj.mibModel, 'NewDataset');
            end
            if strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                obj.mibModel.setData2D(img, 'image', obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], 1, getDataOptions);
            else
                obj.mibModel.setData3D(img, 'image', t, [], 1, getDataOptions);
            end
        elseif ~ismember(BatchOptOut.FilterName{1}, obj.BinarizationFiltersList)
            id = obj.mibModel.getActiveId();
            if strcmp(BatchOptOut.FilterName{1}, 'MathOps')
                if ~strcmp(class(img{1}), obj.mibModel.I{id}.image.dataClass)
                    obj.mibModel.I{id}.image.convertImage(class(img{1}));
                end
            end
            if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                obj.mibModel.setData3D(img, sourceLayersList{sourceLayerId}, t, [], colChannel, getDataOptions);
            else
                obj.mibModel.setData2D(img, sourceLayersList{sourceLayerId}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], colChannel, getDataOptions);
            end
        else    % binarization filters
            if strcmp(BatchOptOut.DestinationLayer{1}, 'labels')
                if isa(img{1}, 'uint16'); ModelType = 65535; else; ModelType = 4294967295; end
                if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                    obj.mibModel.createModel(ModelType);
                    obj.mibModel.setData3D(img, BatchOptOut.DestinationLayer{1}, t, [], [], getDataOptions);
                else
                    id = obj.mibModel.getActiveId();
                    if obj.mibModel.I{id}.labels.maxMaterials ~= ModelType
                        obj.mibModel.createModel(ModelType);
                    end
                    obj.mibModel.setData2D(img, BatchOptOut.DestinationLayer{1}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], [], getDataOptions);
                end
                obj.mibModel.showModel = true;
                notify(obj.mibModel, 'ShowImage');
            else
                if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                    obj.mibModel.setData3D(img, BatchOptOut.DestinationLayer{1}, t, [], [], getDataOptions);
                else
                    obj.mibModel.setData2D(img, BatchOptOut.DestinationLayer{1}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], [], getDataOptions);
                end
                if strcmp(BatchOptOut.DestinationLayer{1}, 'mask')
                    obj.mibModel.showMask = true;
                    notify(obj.mibModel, 'ShowImage');
                end
            end
        end
    end
end

if strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
    log_text = [log_text ', slice=' num2str(obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber())];
end
if isnan(log_text); return; end
if ~strcmp(BatchOptOut.FilterGroup{1}, 'Image Binarization') && ~ismember(BatchOptOut.SourceLayer{1}, {'selection', 'mask', 'labels'})
    obj.mibModel.I{obj.mibModel.getActiveId()}.image.updateActionLog(log_text);
end
toc(t1);

% count user points
obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings = obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings + 1;
eventdata = core.ToggleEventData(2);
notify(obj.mibModel, 'UpdateUserScore', eventdata);

% redraw image
notify(obj.mibModel, 'ShowImage');

% send BatchOpt to macro recorder
if returnBatchSettings; obj.returnBatchOpt(BatchOptOut); end
end
