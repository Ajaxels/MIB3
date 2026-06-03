function roiToSelection(obj)
% ROITOSELECTION - Highlight the area under the selected ROI(s) in the Selection layer.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.roiToSelection()
%
% Rasterises the currently selected ROI(s) into the Selection layer. With
% ``Shift`` held or the *Apply segmentation in 3D* checkbox enabled, the
% mask is propagated to all z-slices; otherwise only the current slice is
% updated. Respects *Restrict to material* and *Restrict to mask* flags.
%
% Input Arguments:
%   - **obj** — [controllers.MibRoi] the ROI panel controller
%
% Return values: none
%

dataset = obj.mibModel.I{obj.mibModel.id};

% get index/indices of the selected ROI(s)
roiNo = dataset.selectedROI;
if roiNo(1) < 0
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.UIFigure, ...
        '!!! Warning !!!', {''}, {'No ROIs were detected!\nAdd a new ROI area and try again.'}, ...
        'ROI is missing', dlgOpt);
    return;
end

% define whether the selection should be expanded to 3D space
mode3D = false;
modifier = obj.mibController.currentModifier;
if ismember('shift', modifier)
    mode3D = true;
elseif obj.view.handles.panels.selection.handles.applySegmentationIn3D.Value
    mode3D = true;
end

backupOptions.blockModeSwitch = 0;
[height, width, ~, ~] = dataset.getDatasetDimensions('image', [], backupOptions);

% build a combined mask from all selected ROIs
for roiIndex = 1:numel(roiNo)
    roiId = roiNo(roiIndex);
    roiMask = dataset.hROI.returnMask(roiId, height, width, NaN, backupOptions.blockModeSwitch);
    if roiIndex == 1
        selectedMask = roiMask;
    else
        selectedMask = bitor(selectedMask, roiMask);
    end
end

selectedMask = uint8(selectedMask);

% calculate bounding box for the backup (crop to the ROI extent)
CC = regionprops(selectedMask, 'BoundingBox');
bb = CC.BoundingBox;

if dataset.orientation == 3         % XY plane (default)
    backupOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.x = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
elseif dataset.orientation == 1     % ZX plane
    backupOptions.x = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.z = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
elseif dataset.orientation == 2     % ZY plane
    backupOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.z = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
end
selectedMask = selectedMask(backupOptions.y(1):backupOptions.y(2), backupOptions.x(1):backupOptions.x(2));

if mode3D
    obj.mibModel.backup('selection', 1, backupOptions);
    currentSelection = cell2mat(obj.mibModel.getData3D('selection', [], [], [], backupOptions));
    selectionArea = zeros(size(currentSelection), 'uint8');
    for sliceIndex = 1:size(selectionArea, 3)
        selectionArea(:,:,sliceIndex) = selectedMask;
    end

    % restrict to the selected material
    if dataset.restrictSelectionToMaterial
        materialIndex = dataset.getSelectedMaterialIndex();
        materialData = cell2mat(obj.mibModel.getData3D('labels', [], [], materialIndex, backupOptions));
        selectionArea = bitand(selectionArea, materialData);
    end

    % restrict to the masked area
    if dataset.restrictSelectionToMask && dataset.maskExist
        maskData = cell2mat(obj.mibModel.getData3D('mask', [], 3, [], backupOptions));
        selectionArea = bitand(selectionArea, maskData);
    end

    obj.mibModel.setData3D(bitor(selectionArea, currentSelection), 'selection', [], [], [], backupOptions);
else
    obj.mibModel.backup('selection', 0);
    currentSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], backupOptions));

    % restrict to the selected material
    if dataset.restrictSelectionToMaterial
        materialIndex = dataset.getSelectedMaterialIndex();
        materialData = cell2mat(obj.mibModel.getData2D('labels', [], [], materialIndex, backupOptions));
        selectedMask = bitand(selectedMask, materialData);
    end

    % restrict to the masked area
    if dataset.restrictSelectionToMask && dataset.maskExist
        maskData = cell2mat(obj.mibModel.getData2D('mask', [], [], [], backupOptions));
        selectedMask = bitand(selectedMask, maskData);
    end

    obj.mibModel.setData2D(bitor(currentSelection, selectedMask), 'selection', [], [], [], backupOptions);
end

obj.mibController.showImage();
end
