function segmentBlackWhiteThreshold(obj, BatchOptIn)
% SEGMENTBLACKWHITETHRESHOLD - Perform black and white thresholding for the BW Threshold tool.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.segmentBlackWhiteThreshold()
%      obj.segmentBlackWhiteThreshold(BatchOptIn)
%
% Tool from the Segmentation panel.
%
% Input Arguments:
%   - **BatchOptIn** *(optional)* - [struct|NaN] batch processing mode;
%     when ``NaN``, returns default structure via "syncBatch" event:
%
%     - ``.Mode`` - [char] ``'2D'``, ``'3D'``, or ``'4D'`` - apply thresholding for current slice, stack, or whole dataset
%     - ``.MinValue`` - [numeric] minimum intensity or Sensitivity value for thresholding
%     - ``.MaxValue`` - [numeric] maximum intensity or Width value for thresholding
%     - ``.ColorChannel`` - [numeric] color channel for thresholding
%     - ``.FixSelectionToMask`` - [logical] apply thresholding only to masked area
%     - ``.FixSelectionToMaterial`` - [logical] apply thresholding only to selected material area
%     - ``.Adaptive`` - [logical] enable adaptive thresholding (use ``MinValue`` for Sensitivity, ``MaxValue`` for Width)
%     - ``.AdaptiveInvert`` - [logical, adaptive only] invert dataset before adaptive thresholding
%     - ``.AdaptiveForegroundPolarity`` - [char, adaptive only] determine which pixels are foreground
%     - ``.Target`` - [char] ``'selection'`` or ``'mask'`` - destination layer for thresholding
%     - ``.showWaitbar`` - [logical] show progress bar during execution
%
% Output Arguments:
%   (none)
%
% **Example 1** - apply thresholding with current widget settings:
%
%   .. code-block:: matlab
%
%      obj.segmentBlackWhiteThreshold();
%
% **Example 2** - batch mode with provided options:
%
%   .. code-block:: matlab
%
%      obj.segmentBlackWhiteThreshold(BatchOpt);
%

% Updates
%

% get handles alias for segmentation panel widgets
segmHandles = obj.mibController.cSegmentation.handles;

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();

% check and correct the selected color channel
if obj.mibModel.I{BatchOpt.id}.selectedColorChannel == 0
    if obj.mibModel.I{BatchOpt.id}.colors == 1
        obj.mibModel.I{BatchOpt.id}.selectedColorChannel = 1;
    else
        dlgOpt.MsgBoxOnly = true;
        header = 'Please select the active color channel for the thresholding!\nSelection panel -> Color channel:';
        dlgOpt.HeaderLines = 3;
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong color channel', dlgOpt);
        notify(obj.mibModel, 'stopProtocol');
        return;
    end
end

BatchOpt.Mode = {'2D, Slice'};
if segmHandles.threshold3D.Value; BatchOpt.Mode = {'3D, Stack'}; end
if segmHandles.threshold4D.Value; BatchOpt.Mode = {'4D, Dataset'}; end
BatchOpt.Mode{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};

BatchOpt.ColorChannel{2} = arrayfun(@(x) sprintf('ColCh %d', x), 1:obj.mibModel.I{BatchOpt.id}.image.colors, 'UniformOutput', false);
BatchOpt.ColorChannel{1} = BatchOpt.ColorChannel{2}{obj.mibModel.I{BatchOpt.id}.selectedColorChannel};

% read from the numeric edit fields, not the sliders - during ValueChangingFcn
% the slider .Value is stale, but the edit field is already updated by the callback
BatchOpt.MinValue = num2str(round(segmHandles.thresholdLowValue.Value));
BatchOpt.MaxValue = num2str(round(segmHandles.thresholdHighValue.Value));

BatchOpt.FixSelectionToMask = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMask);
BatchOpt.FixSelectionToMaterial = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMaterial);
BatchOpt.Adaptive = logical(segmHandles.thresholdAdaptive.Value);
BatchOpt.AdaptiveInvert = logical(segmHandles.thresholdInvert.Value);
BatchOpt.AdaptiveForegroundPolarity = {segmHandles.thresholdType.Value};
BatchOpt.AdaptiveForegroundPolarity{2} = segmHandles.thresholdType.Items;

BatchOpt.Target = {'selection'};
BatchOpt.Target{2} = {'selection', 'mask'};
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = 'Black and white thresholding';

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.Mode = sprintf('Apply thresholding for the current slice (2D), current stack (3D) or the whole dataset(4D)');
BatchOpt.mibBatchTooltip.MinValue = 'Minimum intensity or Sensitivity value for thresholding';
BatchOpt.mibBatchTooltip.MaxValue = 'Maximum intensity or Width value for thresholding';
BatchOpt.mibBatchTooltip.ColorChannel = 'Color channel to be used for thresholding';
BatchOpt.mibBatchTooltip.FixSelectionToMask = 'Apply thresholding only to the masked area';
BatchOpt.mibBatchTooltip.FixSelectionToMaterial = 'Apply thresholding only to the area of the selected material; use Modify checkboxes to update the selected material';
BatchOpt.mibBatchTooltip.Adaptive = 'Enable the adaptive thresholding; use MinValue to specify Sensitivity and MaxValue to specify Width';
BatchOpt.mibBatchTooltip.AdaptiveInvert = '[Adaptive only] invert dataset before adaptive thresholding';
BatchOpt.mibBatchTooltip.AdaptiveForegroundPolarity = '[Adaptive only] determine which pixels are considered foreground pixels';
BatchOpt.mibBatchTooltip.Target = 'Destination layer for the thresholding';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

% get max intensity value
maxVal = obj.mibModel.I{BatchOpt.id}.image.maxInt;

%% Batch mode check actions
if nargin == 2  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when BatchOptIn == NaN return possible settings
            % trigger syncBatch event to send BatchOpt to mibBatchController
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            dlgOpt.MsgBoxOnly = true;
            header = 'A structure as the 2nd parameter is required!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
        end
        return;
    else
        % add/update BatchOpt with the provided fields in BatchOptIn
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

% check for the virtual stacking mode and return
if any(obj.mibModel.I{BatchOpt.id}.datasetType(1) == ['V' 'B'])
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.WindowStyle = 'modal';
    header = sprintf('The black-and-white thresholding is not yet available in the virtual or BigData mode!\nPlease switch to the memory-resident mode and try again');
    dlgOpt.HeaderLines = 4;
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Black and white thresholding', dlgOpt);
    return;
end

% update button appearance during processing
buttonBackgroundColor = segmHandles.threshold.BackgroundColor;
segmHandles.threshold.BackgroundColor = [1.00,0.53,0.10];
segmHandles.threshold.Text = 'Thresholding...';
drawnow;

val1 = str2double(BatchOpt.MinValue);
val2 = str2double(BatchOpt.MaxValue);
model_id = obj.mibModel.I{BatchOpt.id}.getSelectedMaterialIndex();
color_channel = find(ismember(BatchOpt.ColorChannel{2}, BatchOpt.ColorChannel{1}));

if BatchOpt.Adaptive
    val1 = val1 / double(maxVal);
    height = obj.mibModel.I{BatchOpt.id}.getDatasetDimensions('image');
    val2 = 2 * ceil(height * val2 / double(maxVal)) + 1;
    polarity = 'dark';
    if strcmp(BatchOpt.AdaptiveForegroundPolarity{1}, 'white-on-black'); polarity = 'bright'; end
end
if model_id < 0 && BatchOpt.FixSelectionToMaterial == 1; BatchOpt.FixSelectionToMask = 1; end

getDataOptions.id = BatchOpt.id;
if strcmp(BatchOpt.Mode{1}, '3D, Stack') || strcmp(BatchOpt.Mode{1}, '4D, Dataset')
    % do segmentation for the whole stack or dataset
    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait...', 'Title', 'Black and white thresholding');
    end
    if strcmp(BatchOpt.Mode{1}, '4D, Dataset')
        t1 = 1;
        t2 = obj.mibModel.I{BatchOpt.id}.time;
    else
        slices = obj.mibModel.I{BatchOpt.id}.slices;
        t1 = slices{5}(1);
        t2 = slices{5}(1);
        obj.mibModel.backup(BatchOpt.Target{1}, 1, getDataOptions);
    end

    orientation = obj.mibModel.I{BatchOpt.id}.orientation;
    [axesX, axesY] = obj.mibModel.getAxesLimits(BatchOpt.id);

    for t = t1:t2
        img = squeeze(cell2mat(obj.mibModel.getData3D('image', t, 3, color_channel, getDataOptions)));

        if BatchOpt.FixSelectionToMask == 1
            selection = zeros(size(img), 'uint8');

            mask = cell2mat(obj.mibModel.getData3D('mask', t, 3, [], getDataOptions));
            STATS = regionprops(uint8(mask), 'BoundingBox');
            if numel(STATS) == 0; continue; end

            BBox = round(STATS.BoundingBox);
            if numel(BBox) == 4
                BBox = [BBox(1) BBox(2) 1 BBox(3) BBox(4) 1];
            end

            indeces(1,:) = [BBox(2), BBox(2)+BBox(5)-1];
            indeces(2,:) = [BBox(1), BBox(1)+BBox(4)-1];
            indeces(3,:) = [BBox(3), BBox(3)+BBox(6)-1];
            % crop image to the masked area
            img = img(indeces(1,1):indeces(1,2), indeces(2,1):indeces(2,2), indeces(3,1):indeces(3,2));
            % crop the mask
            mask = mask(indeces(1,1):indeces(1,2), indeces(2,1):indeces(2,2), indeces(3,1):indeces(3,2));

            % generate cropped selection
            selection2 = zeros(size(img), 'uint8') + 1;
            if BatchOpt.Adaptive
                for sliceId = 1:size(img, 3)
                    T = adaptthresh(img(:,:,sliceId), val1, 'ForegroundPolarity', polarity, 'NeighborhoodSize', val2);
                    selection2(:,:,sliceId) = uint8(imbinarize(img(:,:,sliceId), T));
                    if BatchOpt.AdaptiveInvert
                        selection2(:,:,sliceId) = 1 - selection2(:,:,sliceId);
                    end
                end
            else
                selection2(img < val1 | img > val2) = 0;
            end

            selection2 = selection2 & mask;

            if BatchOpt.FixSelectionToMaterial && model_id >= 0
                if obj.mibModel.I{BatchOpt.id}.blockModeSwitch
                    if orientation == 1     % ZX: horizontal X, vertical Z
                        shiftX = max([ceil(axesX(1)) 0]);
                        shiftY = 0;
                        shiftZ = max([ceil(axesY(1)) 0]);
                    elseif orientation == 2 % ZY
                        shiftX = 0;
                        shiftY = max([ceil(axesY(1)) 0]);
                        shiftZ = max([ceil(axesX(1)) 0]);
                    elseif orientation == 3 % XY
                        shiftX = max([ceil(axesX(1)) 0]);
                        shiftY = max([ceil(axesY(1)) 0]);
                        shiftZ = 0;
                    end
                else
                    shiftX = 0;
                    shiftY = 0;
                    shiftZ = 0;
                end
                getDataOptions.x = [indeces(2,1), indeces(2,2)] + shiftX;
                getDataOptions.y = [indeces(1,1), indeces(1,2)] + shiftY;
                getDataOptions.z = [indeces(3,1), indeces(3,2)] + shiftZ;
                model = cell2mat(obj.mibModel.getData3D('labels', [], 3, model_id, getDataOptions));
                selection2(model ~= 1) = 0;
            end
            selection(indeces(1,1):indeces(1,2), indeces(2,1):indeces(2,2), indeces(3,1):indeces(3,2)) = selection2;
        else
            selection = zeros(size(img), 'uint8') + 1;
            if BatchOpt.Adaptive
                for sliceId = 1:size(img, 3)
                    T = adaptthresh(img(:,:,sliceId), val1, 'ForegroundPolarity', polarity, 'NeighborhoodSize', val2);
                    selection(:,:,sliceId) = uint8(imbinarize(img(:,:,sliceId), T));
                    if BatchOpt.AdaptiveInvert
                        selection(:,:,sliceId) = 1 - selection(:,:,sliceId);
                    end
                end
            else
                selection(img < val1 | img > val2) = 0;
            end

            if BatchOpt.FixSelectionToMaterial && model_id >= 0
                model = cell2mat(obj.mibModel.getData3D('labels', t, 3, model_id, getDataOptions));
                selection = selection & model;
            end
        end
        setDataOptions = struct();
        setDataOptions.id = getDataOptions.id;
        obj.mibModel.setData3D({selection}, BatchOpt.Target{1}, t, 3, [], setDataOptions);
        if BatchOpt.showWaitbar; wb.Value = t / (t2 - t1 + 1); end
    end
    if BatchOpt.showWaitbar; close(wb); end

    % count user's points
    obj.mibModel.preferences.Users.Tiers.numberOfBWThresholdings = obj.mibModel.preferences.Users.Tiers.numberOfBWThresholdings + 1;
    eventdata = core.ToggleEventData(2);    % scale scoring by factor 2
    notify(obj.mibModel, 'UpdateUserScore', eventdata);
else
    % do segmentation for the current slice only
    obj.mibModel.backup(BatchOpt.Target{1}, 0, getDataOptions);
    img = squeeze(cell2mat(obj.mibModel.getData2D('image', [], [], color_channel, getDataOptions)));
    if BatchOpt.Adaptive
        T = adaptthresh(img, val1, 'ForegroundPolarity', polarity, 'NeighborhoodSize', val2);
        selection = uint8(imbinarize(img, T));
        if BatchOpt.AdaptiveInvert
            selection = 1 - selection;
        end
    else
        selection = zeros(size(img), 'uint8') + 1;
        selection(img < val1 | img > val2) = 0;
    end

    if BatchOpt.FixSelectionToMask == 1
        mask = cell2mat(obj.mibModel.getData2D('mask', [], [], [], getDataOptions));
        selection(mask ~= 1) = 0;
    end
    if BatchOpt.FixSelectionToMaterial && model_id >= 0
        model = cell2mat(obj.mibModel.getData2D('labels', [], [], [], getDataOptions));
        selection(model ~= model_id) = 0;
    end
    obj.mibModel.setData2D({selection}, BatchOpt.Target{1}, [], [], [], getDataOptions);
end

% restore button appearance
segmHandles.threshold.BackgroundColor = segmHandles.addMaterial.BackgroundColor;
segmHandles.threshold.Text = 'Threshold';

notify(obj.mibModel, 'ShowImage');

% notify the batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj.mibModel, 'SyncBatch', eventdata);

end
