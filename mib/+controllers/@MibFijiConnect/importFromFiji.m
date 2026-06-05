function importFromFiji(obj)
% IMPORTFROMFIJI - Import a dataset from Fiji/ImageJ into MIB.
%
% Prompts the user to select one of the images open in Fiji and the
% destination layer type, then imports the data. Fiji must be running;
% the function starts it automatically if needed.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.importFromFiji()
%
% Updates
%

id = obj.mibModel.getActiveId();

% ensure Fiji/MIJ is running
if exist('MIJ', 'class') == 8
    if ~isempty(ij.gui.Toolbar.getInstance)
        ijInstance = char(ij.gui.Toolbar.getInstance.toString);
        if contains(ijInstance, 'invalid')  % instance exists but window was closed
            utils.fiji.Miji_wrapper(true);
        end
    else
        utils.fiji.Miji_wrapper(true);
    end
else
    utils.fiji.Miji_wrapper(true);
end

% build list of datasets open in Fiji
if exist('MIJ', 'class') ~= 8
    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
        sprintf('Miji was not started!\n\nPress the Start Fiji button in the Fiji Connect panel.'), ...
        'Missing Miji!');
    return;
end

try
    fijiImageList = MIJ.getListImages;
catch
    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
        'Nothing is available for import — please open a dataset in Fiji and try again.', ...
        'Nothing to import');
    return;
end

if isempty(fijiImageList)
    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
        'No images are open in Fiji — please open a dataset there and try again.', ...
        'Nothing to import');
    return;
end

datasetItems = cell(1, numel(fijiImageList));
for i = 1:numel(fijiImageList)
    datasetItems{i} = char(fijiImageList(i));
end

% default destination type = currently selected imageType in the panel
imageTypeItems = {'image', 'labels', 'mask', 'selection'};
defaultTypeIndex = find(strcmp(imageTypeItems, obj.handles.imageType.Value), 1);
if isempty(defaultTypeIndex); defaultTypeIndex = 1; end

selectOpt.WindowHeight = 200;
selectOpt.WindowType = 'modal';
answer = utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', ...
    {'Select dataset from Fiji:', 'Destination layer in MIB:'}, ...
    {[datasetItems, {1}], [imageTypeItems, {defaultTypeIndex}]}, ...
    'Select Fiji dataset', selectOpt);
if isempty(answer); return; end
datasetName  = answer{1};
datasetType  = answer{2};   % 'image' | 'labels' | 'mask' | 'selection'

% virtual stacking mode is not supported for any layer import
if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', ...
        {}, {sprintf('Switch to memory-resident mode before importing "%s"!\nUse the Active Dataset panel to change the mode.', datasetType)}, ...
        'Virtual mode', dlgOpt);
    return;
end

roiNo = obj.mibModel.I{id}.selectedROI;
if ~obj.mibModel.I{id}.roiShow
    roiNo = -1;  % ROI overlay is off; ignore stale selectedROI and use full dataset
end
% roiNo == 0  → "All ROIs" mode (multiple patches)
% numel > 1   → several specific ROIs selected
if (roiNo == 0 && obj.mibModel.I{id}.roiShow) || numel(roiNo) > 1
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), ...
        'Please select a single ROI from the ROI list or disable the ROI mode!', ...
        {}, {}, 'Select ROI!', dlgOpt);
    return;
end

progressDlg = uiprogressdlg(obj.mibModel.getProgressBarParent(), ...
    'Title', 'Import from Fiji', 'Message', 'Retrieving image from Fiji...', 'Value', 0.1);

% retrieve image data; MIJ returns [h,w,d] for grayscale or [h,w,c,d] for multichannel
imageData = MIJ.getImage(datasetName);

% MIJ returns multichannel stacks as [h,w,c,d]; swap to MIB3's [h,w,d,c]
if ndims(imageData) == 4
    imageData = permute(imageData, [1 2 4 3]);
end

progressDlg.Value = 0.4; progressDlg.Message = 'Converting image data...';

% shift data to non-negative range if needed, then convert to uint type
minVal = double(min(imageData(:)));
maxVal = double(max(imageData(:)));
if minVal < 0
    imageData = double(imageData);
    for colorChannel = 1:size(imageData, 4)
        imageData(:,:,:,colorChannel) = imageData(:,:,:,colorChannel) - minVal;
    end
end

if maxVal - minVal < 256
    imageData = uint8(imageData);
elseif maxVal - minVal < 65536
    imageData = uint16(imageData);
elseif maxVal - minVal < 4294967296
    imageData = uint32(imageData);
else
    delete(progressDlg);
    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), 'Dataset format problem!', 'Import error');
    return;
end

options.blockModeSwitch = 0;
options.roiId = roiNo;

progressDlg.Value = 0.7; progressDlg.Message = 'Writing data to MIB...';

if strcmp(datasetType, 'image')
    % for a grayscale Z-stack [h,w,d]: reshape to [h,w,d,1] (MIB3 [h,w,d,c] format)
    if ndims(imageData) == 3 && size(imageData, 3) ~= 3
        imageData = reshape(imageData, size(imageData,1), size(imageData,2), size(imageData,3), 1);
    end
    obj.mibModel.setData3D(imageData, 'image', [], 3, NaN, options);
    if roiNo == -1
        obj.mibModel.I{id}.image.filename = datasetName;
    end
else
    % for labels, mask, selection: verify dimensions match the current dataset
    if roiNo == -1
        currentHeight = obj.mibModel.I{id}.image.height;
        currentWidth  = obj.mibModel.I{id}.image.width;
        currentDepth  = obj.mibModel.I{id}.image.depth;
        if size(imageData,1) ~= currentHeight || ...
                size(imageData,2) ~= currentWidth || ...
                size(imageData,3) ~= currentDepth
            delete(progressDlg);
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                sprintf('Dimensions mismatch!\nFiji image (HxWxZ) = %d x %d x %d pixels\nCurrent dataset (HxWxZ) = %d x %d x %d pixels', ...
                    size(imageData,1), size(imageData,2), size(imageData,3), ...
                    currentHeight, currentWidth, currentDepth), ...
                'Dimensions mismatch!');
            return;
        end
    end

    if strcmp(datasetType, 'labels')
        if roiNo == -1
            obj.mibModel.I{id}.createModel();
            obj.mibModel.setData3D(imageData, 'labels', [], 3, NaN, options);
            numMaterials = double(max(imageData(:)));  % max label index = required colormap rows
            materialNames = cell(numMaterials, 1);
            for i = 1:numMaterials
                materialNames{i} = num2str(i);
            end
            obj.mibModel.I{id}.labels.materialNames = materialNames;
            obj.mibModel.I{id}.labels.materialColors = rand(numMaterials, 3);
        else
            obj.mibModel.setData3D(imageData, 'labels', [], 3, NaN, options);
        end
        obj.mibModel.showModel = true;

    elseif strcmp(datasetType, 'mask')
        imageData(imageData > 1) = 1;   % clamp to binary
        if roiNo == -1
            obj.mibModel.clearMask('4D, Dataset');
        end
        obj.mibModel.setData3D(imageData, 'mask', [], 3, NaN, options);
        obj.mibModel.I{id}.maskExist = true;
        obj.mibModel.showMask = true;

    elseif strcmp(datasetType, 'selection')
        imageData(imageData > 1) = 1;   % clamp to binary
        obj.mibModel.setData3D(imageData, 'selection', [], 3, NaN, options);
    end
end

delete(progressDlg);
notify(obj.mibModel, 'UpdateGuiWidgets');
notify(obj.mibModel, 'ShowImage');
end
