function segmentationObjectPicker(obj, yxzCoordinate, modifier)
% SEGMENTATIONOBJECTPICKER - Select 2D/3D objects from the Mask or Model layers.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.segmentationObjectPicker(yxzCoordinate, modifier)
%
% Picks connected objects from the Mask or Model layer and copies them
% to the Selection layer. Supports multiple sub-modes: Click (direct
% object selection), Lasso/Rectangle/Ellipse/Polyline (ROI-based), and
% Mask within Selection (AND operation).
%
% Input Arguments:
%   - **yxzCoordinate** — [vector] ``[y, x, z]`` coordinates of starting point;
%     ``[y, x]`` is sufficient for 2D case
%   - **modifier** — [char] specify action with generated selection:
%
%     - ``''`` — make new selection (add to existing)
%     - ``'control'`` — remove selection from existing
%     - ``'shift'`` — used for 3D mode in Mask within Selection; returns union of mask and selection
%
% Output Arguments:
%   (none)
%
% **Example 1** — select object at [y,x,z]=50,75,1:
%
%   .. code-block:: matlab
%
%      obj.segmentationObjectPicker([50, 75, 1], '');
%
% **Example 2** — subtract object from selection:
%
%   .. code-block:: matlab
%
%      obj.segmentationObjectPicker([50, 75, 1], 'control');
%

% Updates
%

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

id = obj.mibModel.getActiveId();
switch3d = obj.mibModel.applySegmentationIn3D;
options.blockModeSwitch = obj.mibModel.I{id}.blockModeSwitch;

% determine whether to pick from mask or model
colchannel = obj.mibModel.I{id}.getSelectedMaterialIndex();
if colchannel == -1
    type = 'mask';
    if ~obj.mibModel.I{id}.maskExist
        dlgOpt.MsgBoxOnly = true;
        header = sprintf('No mask found!\nGenerate the mask layer first');
        dlgOpt.HeaderLines = 2;
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Object picker error', dlgOpt);
        return;
    end
    colchannel = 0;
else
    type = 'labels';
    if ~obj.mibModel.I{id}.modelExist
        dlgOpt.MsgBoxOnly = true;
        header = sprintf('Model was not found!\nPlease create a model first...');
        dlgOpt.HeaderLines = 2;
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Object picker error', dlgOpt);
        return;
    end
    if obj.mibModel.I{id}.labels.maxMaterials > 255
        colchannel = [];    % get all materials
    end
end

if switch3d
    h = yxzCoordinate(1);
    w = yxzCoordinate(2);
    z = yxzCoordinate(3);
else
    yCrop = yxzCoordinate(1);
    xCrop = yxzCoordinate(2);
end

[axesX, axesY] = obj.mibModel.getAxesLimits();
orientation = obj.mibModel.I{id}.orientation;

% get the sub-tool from lassoType dropdown
segmHandles = obj.mibController.cSegmentation.handles;
subTool = segmHandles.lassoType.Value;

% update modifier for ROI-based modes from lassoMode dropdown
if ismember(subTool, {'Lasso', 'Rectangle', 'Ellipse', 'Polyline'})
    lassoMode = segmHandles.lassoMode.Value;
    if strcmp(lassoMode, 'Subtract')
        modifier = 'control';
    else
        modifier = '';
    end
end

switch subTool
    case 'Click'
        % selection with mouse button click
        if switch3d
            if isempty(obj.mibModel.I{id}.maskStats)
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.HeaderLines = 1;
                header = sprintf('Stats for the objects were not yet calculated!');
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {'Press the "Recalculate stats for 3D objects" button and try again.'}, 'Object picker error', dlgOpt);
                return;
            end

            if isfield(obj.mibModel.I{id}.maskStats, 'PixelIdxList')
                % fast path using pre-computed PixelIdxList
                convertPixelOpt.y = [1, obj.mibModel.I{id}.image.height];
                convertPixelOpt.x = [1, obj.mibModel.I{id}.image.width];
                convertPixelOpt.z = [z, z];
                linearInd = sub2ind([obj.mibModel.I{id}.image.height, obj.mibModel.I{id}.image.width], h, w);
                linearInd = obj.mibModel.I{id}.convertPixelIdxListCrop2Full(linearInd, convertPixelOpt);
                obj_id = obj.mibModel.I{id}.getPixelIdxList(type, linearInd);
                if obj_id == 0; return; end
                dataset = ones([numel(obj.mibModel.I{id}.maskStats(obj_id).PixelIdxList), 1]);

                % limit to the selected material of the model
                if obj.mibModel.I{id}.restrictSelectionToMaterial && strcmp(type, 'mask')
                    % placeholder — not implemented in MIB2 either
                end
                % limit selection to the masked area
                if obj.mibModel.I{id}.restrictSelectionToMask && obj.mibModel.I{id}.maskExist && strcmp(type, 'labels')
                    datasetImage = obj.mibModel.I{id}.getPixelIdxList('mask', obj.mibModel.I{id}.maskStats(obj_id).PixelIdxList);
                    dataset = dataset & datasetImage;
                end

                if isempty(modifier) % add to selection
                    obj.mibModel.I{id}.setPixelIdxList('selection', dataset, obj.mibModel.I{id}.maskStats(obj_id).PixelIdxList);
                elseif strcmp(modifier, 'control')  % subtract from selection
                    datasetImage = obj.mibModel.I{id}.getPixelIdxList('selection', obj.mibModel.I{id}.maskStats(obj_id).PixelIdxList);
                    datasetImage(dataset==1) = 0;
                    obj.mibModel.I{id}.setPixelIdxList('selection', datasetImage, obj.mibModel.I{id}.maskStats(obj_id).PixelIdxList);
                end

                notify(obj.mibModel, 'ShowImage');
                obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers = obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers + 1;
                notify(obj.mibModel, 'UpdateUserScore');
                return;
            else
                % label matrix approach
                options.blockModeSwitch = 0;
                orient = 3;
                obj_id = obj.mibModel.I{id}.maskStats.L(h, w, z);
                if obj_id == 0; return; end

                % define subset of data for selection
                bb = obj.mibModel.I{id}.maskStats.bb(obj_id).BoundingBox;
                options.y = [ceil(bb(2)), ceil(bb(2))+floor(bb(5))-1];
                options.x = [ceil(bb(1)), ceil(bb(1))+floor(bb(4))-1];
                options.z = [ceil(bb(3)), ceil(bb(3))+floor(bb(6))-1];
                options.id = id;

                obj.mibModel.backup('selection', 1, options);

                currSelection = cell2mat(obj.mibModel.getData3D('selection', [], orient, [], options));
                objSelection = zeros(size(currSelection), 'uint8');
                objSelection(obj.mibModel.I{id}.maskStats.L(options.y(1):options.y(2), ...
                    options.x(1):options.x(2), options.z(1):options.z(2)) == obj_id) = 1;

                % limit to the selected material of the model
                if obj.mibModel.I{id}.restrictSelectionToMaterial && strcmp(type, 'mask')
                    selcontour = obj.mibModel.I{id}.getSelectedMaterialIndex();
                    datasetImage = cell2mat(obj.mibModel.getData3D('labels', [], orient, selcontour, options));
                    objSelection(datasetImage ~= 1) = 0;
                end

                % limit selection to the masked area
                if obj.mibModel.I{id}.restrictSelectionToMask && obj.mibModel.I{id}.maskExist && strcmp(type, 'labels')
                    datasetImage = cell2mat(obj.mibModel.getData3D('mask', [], orient, [], options));
                    objSelection(datasetImage ~= 1) = 0;
                end

                if isempty(modifier)
                    currSelection(objSelection==1) = 1;
                    obj.mibModel.setData3D(currSelection, 'selection', [], orient, [], options);
                elseif strcmp(modifier, 'control')
                    currSelection(objSelection==1) = 0;
                    obj.mibModel.setData3D(currSelection, 'selection', [], orient, [], options);
                end

                notify(obj.mibModel, 'ShowImage');
                obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers = obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers + 1;
                notify(obj.mibModel, 'UpdateUserScore');
                return;
            end
        else
            % 2D click mode
            obj.mibModel.backup('selection', 0);
            options.id = id;
            if strcmp(type, 'labels') && obj.mibModel.I{id}.restrictSelectionToMaterial
                selarea = cell2mat(obj.mibModel.getData2D(type, [], [], colchannel, options));
            elseif strcmp(type, 'labels')
                mask = cell2mat(obj.mibModel.getData2D(type, [], [], [], options));
                colchannel = mask(yCrop, xCrop);
                if colchannel == 0; return; end
                selarea = zeros(size(mask), 'uint8');
                selarea(mask == colchannel) = 1;
            else
                selarea = cell2mat(obj.mibModel.getData2D(type, [], [], [], options));
            end
            selarea = uint8(bwselect(selarea, xCrop, yCrop, 4));
        end

    case {'Lasso', 'Rectangle', 'Ellipse', 'Polyline'}
        % ROI-based object picking
        [selected_mask, cancelled] = drawROIAndCreateMask(obj, subTool);
        if cancelled; return; end

        options.blockModeSwitch = 1;
        options.id = id;
        currMask = cell2mat(obj.mibModel.getData2D(type, [], [], colchannel, options));
        selected_mask = imresize(selected_mask, [size(currMask, 1), size(currMask, 2)], 'method', 'nearest');

        CC = regionprops(selected_mask, 'BoundingBox');
        if isempty(CC); return; end
        bb = CC.BoundingBox;
        bb(1) = bb(1) + max([1, ceil(axesX(1))]) - 1;
        bb(2) = bb(2) + max([1, ceil(axesY(1))]) - 1;

        if orientation == 3      % XY
            backupOptions.y = [ceil(bb(2)), ceil(bb(2))+floor(bb(4))-1];
            backupOptions.x = [ceil(bb(1)), ceil(bb(1))+floor(bb(3))-1];
        elseif orientation == 1  % ZX
            backupOptions.x = [ceil(bb(2)), ceil(bb(2))+floor(bb(4))-1];
            backupOptions.z = [ceil(bb(1)), ceil(bb(1))+floor(bb(3))-1];
        elseif orientation == 2  % ZY
            backupOptions.y = [ceil(bb(2)), ceil(bb(2))+floor(bb(4))-1];
            backupOptions.z = [ceil(bb(1)), ceil(bb(1))+floor(bb(3))-1];
        end

        if switch3d
            obj.mibModel.backup('selection', 1, backupOptions);
            maskDataset = cell2mat(obj.mibModel.getData3D(type, [], [], colchannel, options));
            selarea = zeros(size(maskDataset), 'uint8');
            for layer_id = 1:size(selarea, 3)
                selarea(:,:,layer_id) = bitand(selected_mask, maskDataset(:,:,layer_id));
            end
        else
            obj.mibModel.backup('selection', 0);
            selarea = bitand(selected_mask, currMask);
        end

    case 'Mask within Selection'
        % AND the mask/model with current selection — handle fully here and return
        options.id = id;
        useVolume = switch3d || (iscell(modifier) && any(strcmp(modifier, 'shift'))) || (ischar(modifier) && strcmp(modifier, 'shift'));
        if useVolume
            obj.mibModel.backup('selection', 1);
            mask = cell2mat(obj.mibModel.getData3D(type, [], 3, colchannel, options));
            sel = cell2mat(obj.mibModel.getData3D('selection', [], 3, [], options));
            obj.mibModel.setData3D(bitand(mask, sel), 'selection', [], 3, [], options);
        else
            obj.mibModel.backup('selection', 0);
            currMask = cell2mat(obj.mibModel.getData2D(type, [], [], colchannel, options));
            currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
            obj.mibModel.setData2D(bitand(currMask, currSelection), 'selection', [], [], [], options);
        end
        notify(obj.mibModel, 'ShowImage');
        obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers = obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers + 1;
        notify(obj.mibModel, 'UpdateUserScore');
        return;

    otherwise
        return;
end

%% Apply restrictions and write selection
selcontour = obj.mibModel.I{id}.getSelectedMaterialIndex();
options.id = id;

if switch3d
    % limit to the selected material of the model
    if obj.mibModel.I{id}.restrictSelectionToMaterial && strcmp(type, 'mask')
        datasetImage = cell2mat(obj.mibModel.getData3D('labels', [], 3, selcontour, options));
        selarea(datasetImage ~= 1) = 0;
    end

    % limit selection to the masked area
    if obj.mibModel.I{id}.restrictSelectionToMask && obj.mibModel.I{id}.maskExist && strcmp(type, 'labels')
        datasetImage = cell2mat(obj.mibModel.getData3D('mask', [], 3, [], options));
        selarea(datasetImage ~= 1) = 0;
    end

    if isempty(modifier)
        currSelection = cell2mat(obj.mibModel.getData3D('selection', [], 3, [], options));
        obj.mibModel.setData3D(bitor(currSelection, selarea), 'selection', [], 3, [], options);
    elseif strcmp(modifier, 'control')
        currSelection = cell2mat(obj.mibModel.getData3D('selection', [], 3, [], options));
        currSelection(selarea==1) = 0;
        obj.mibModel.setData3D(currSelection, 'selection', [], 3, [], options);
    elseif strcmp(modifier, 'new')
        obj.mibModel.setData3D(selarea, 'selection', [], 3, [], options);
    end
else
    % limit to the selected material of the model
    if obj.mibModel.I{id}.restrictSelectionToMaterial && strcmp(type, 'mask')
        currModel = cell2mat(obj.mibModel.getData2D('labels', [], [], selcontour, options));
        selarea = bitand(selarea, currModel);
    end

    % limit selection to the masked area
    if obj.mibModel.I{id}.restrictSelectionToMask && obj.mibModel.I{id}.maskExist && strcmp(type, 'labels')
        currModel = cell2mat(obj.mibModel.getData2D('mask', [], [], [], options));
        selarea = bitand(selarea, currModel);
    end

    if isempty(modifier)
        currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
        obj.mibModel.setData2D(bitor(currSelection, selarea), 'selection', [], [], [], options);
    elseif strcmp(modifier, 'control')
        currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
        currSelection(selarea==1) = 0;
        obj.mibModel.setData2D(currSelection, 'selection', [], [], [], options);
    elseif strcmp(modifier, 'new')
        obj.mibModel.setData2D(selarea, 'selection', [], [], [], options);
    end
end

notify(obj.mibModel, 'ShowImage');

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers = obj.mibModel.preferences.Users.Tiers.numberOfObjectPickers + 1;
notify(obj.mibModel, 'UpdateUserScore');

end

%% Local helper: draw ROI interactively and return a binary mask
function [selected_mask, cancelled] = drawROIAndCreateMask(obj, subTool)
% DRAWROIANDCREATEMASK - Draw an interactive ROI on the image axes and return the binary mask.
%
% Syntax:
%   function [selected_mask, cancelled] = drawROIAndCreateMask(obj, subTool)
%
% Input Arguments:
%   - **subTool** — char, one of 'Lasso', 'Rectangle', 'Ellipse', 'Polyline'
%
% Output Arguments:
%   - **selected_mask** — uint8 binary mask (size of displayed image)
%   - **cancelled** — logical, true if the user cancelled
%

cancelled = true;
selected_mask = [];

hFig = obj.UIFigure;
axH = obj.handles.imViewAxes;

% disable segmentation and set cursor
obj.mibModel.disableSegmentation = true;
hFig.WindowButtonDownFcn = [];
hFig.Pointer = 'cross';

try
    switch subTool
        case 'Lasso'
            roi = drawfreehand(axH, 'Closed', true);
        case 'Rectangle'
            roi = drawrectangle(axH);
        case 'Ellipse'
            roi = drawellipse(axH);
        case 'Polyline'
            roi = drawpolygon(axH);
    end
    wait(roi);
catch
    obj.mibModel.disableSegmentation = false;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end

if ~isvalid(roi)
    obj.mibModel.disableSegmentation = false;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end

try
    selected_mask = uint8(createMask(roi, obj.imageHandle));
catch
    delete(roi);
    obj.mibModel.disableSegmentation = false;
    hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
    hFig.Pointer = 'crosshair';
    return;
end
delete(roi);

% restore callbacks and pointer
hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
hFig.Pointer = 'crosshair';
obj.mibModel.disableSegmentation = false;

cancelled = false;
end
