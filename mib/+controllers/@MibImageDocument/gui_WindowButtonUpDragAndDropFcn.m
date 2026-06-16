function gui_WindowButtonUpDragAndDropFcn(obj, mode, diffX, diffY, BatchOptIn)
% GUI_WINDOWBUTTONUPDRAGANDDROPFCN - Commit the drag-and-drop shift on mouse button release.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_WindowButtonUpDragAndDropFcn(mode)
%      obj.gui_WindowButtonUpDragAndDropFcn(mode, diffX, diffY)
%      obj.gui_WindowButtonUpDragAndDropFcn(mode, diffX, diffY, BatchOptIn)
%
% Input Arguments:
%   - **mode** — [char] mode for drag-and-drop action:
%
%     - ``'2D, Slice'`` — drag all selection on current slice
%     - ``'Object2D'`` — drag selected object only on current slice
%     - ``'3D, Stack'`` — drag all selection for all slices
%     - ``'Object3D'`` — drag selected 3D object
%
%   - **diffX** *(optional)* — [double] shift in X direction (pixels); when empty, calculated from mouse position
%   - **diffY** *(optional)* — [double] shift in Y direction (pixels); when empty, calculated from mouse position
%   - **BatchOptIn** *(optional)* — [struct] batch processing mode:
%
%     - ``.Target`` — [char] layer to be moved
%     - ``.Mode`` — [char] part of dataset to be moved
%     - ``.shiftX`` — [numeric] X-shift in pixels
%     - ``.shiftY`` — [numeric] Y-shift in pixels
%     - ``.showWaitbar`` — [logical] show progress bar
%
% Output Arguments:
%   (none)
%
% **Example** — shift 5px right, 3px up:
%
%   .. code-block:: matlab
%
%      obj.gui_WindowButtonUpDragAndDropFcn('2D, Slice', 5, -3);
%

% Updates
%

if nargin < 4; diffY = []; end
if nargin < 3; diffX = []; end
if nargin < 2; mode = '2D, Slice'; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();
targetLayer = obj.mibController.cSegmentation.handles.dragLayer.Value;
if strcmp(targetLayer, 'model'); targetLayer = 'labels'; end
BatchOpt.Target = {targetLayer};
BatchOpt.Target{2} = {'selection', 'mask', 'labels'};
BatchOpt.Mode = {'2D, Slice'};
BatchOpt.Mode{2} = {'2D, Slice', '3D, Stack'};
if ~isempty(mode) && ismember(mode, BatchOpt.Mode{2})
    BatchOpt.Mode{1} = mode;
end
BatchOpt.shiftX = '0';
if ~isempty(diffX); BatchOpt.shiftX = num2str(diffX); end
BatchOpt.shiftY = '0';
if ~isempty(diffY); BatchOpt.shiftY = num2str(diffY); end
BatchOpt.showWaitbar = true;
BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = 'Drag & Drop materials';
BatchOpt.mibBatchTooltip.Target = 'Layer to be moved';
BatchOpt.mibBatchTooltip.Mode = 'Part of the dataset to be moved';
BatchOpt.mibBatchTooltip.shiftX = 'X-shift in pixels';
BatchOpt.mibBatchTooltip.shiftY = 'Y-shift in pixels';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 5  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_error';
            header = 'A structure as the 5th parameter is required!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
    diffX = str2double(BatchOpt.shiftX);
    diffY = str2double(BatchOpt.shiftY);
    mode = BatchOpt.Mode{1};
else
    if nargin < 3
        pos = obj.handles.imViewAxes.CurrentPoint;
        XLim = size(obj.mibModel.Ishown, 2);
        YLim = size(obj.mibModel.Ishown, 1);
        pos = round(pos);

        if pos(1,1) <= 0; pos(1,1) = 1; end
        if pos(1,1) > XLim; pos(1,1) = XLim; end
        if pos(1,2) <= 0; pos(1,2) = 1; end
        if pos(1,2) > YLim; pos(1,2) = YLim; end

        % calculate shift for the selection layer
        diffX = pos(1,1) - obj.brushPrevXY(1);
        diffY = pos(1,2) - obj.brushPrevXY(2);

        magFactor = obj.mibModel.getMagFactor();
        diffX = round(diffX * magFactor);
        diffY = round(diffY * magFactor);
    end
end

getDataOptions.blockModeSwitch = 0;
getDataOptions.id = BatchOpt.id;
% Pyramidal (BigData/Virtual) datasets: read/write the layer at FULL resolution so
% the shift (diffX/diffY are full-res) and the array indexing line up.
if any(obj.mibModel.I{BatchOpt.id}.datasetType(1) == ['V' 'B'])
    getDataOptions.magFactor = 1;
end

% BigData single-object drag (WSI-safe): bound the read/write to the visible∪shifted
% window at full resolution instead of the whole layer. The object can't be dragged
% more than ~one screen, so this window always contains both its source and
% destination. Only the YX orientation is bounded; ZX/ZY fall back to whole-layer.
is3D = any(strcmp(mode, {'3D, Stack', 'Object3D'}));
isBoundedDrag = false;
winXoff = 0; winYoff = 0;
if obj.mibModel.I{BatchOpt.id}.datasetType(1) == 'B' && ...
        any(strcmp(mode, {'Object2D', 'Object3D'})) && ...
        obj.mibModel.I{BatchOpt.id}.orientation == 3
    [axesX, axesY] = obj.mibModel.getAxesLimits(BatchOpt.id);
    fullW = obj.mibModel.I{BatchOpt.id}.image.width;
    fullH = obj.mibModel.I{BatchOpt.id}.image.height;
    vx = [ceil(axesX(1)), ceil(axesX(2))];
    vy = [ceil(axesY(1)), ceil(axesY(2))];
    winX = [max(1, min(vx(1), vx(1)+diffX)), min(fullW, max(vx(2), vx(2)+diffX))];
    winY = [max(1, min(vy(1), vy(1)+diffY)), min(fullH, max(vy(2), vy(2)+diffY))];
    getDataOptions.x = winX;
    getDataOptions.y = winY;
    winXoff = winX(1) - 1;
    winYoff = winY(1) - 1;
    isBoundedDrag = true;
end

% Undo backup for BigData (the interactive setup skipped it so it can be bounded
% here): windowed when bounded, otherwise a full backup (+ warn) for ZX/ZY.
if obj.mibModel.I{BatchOpt.id}.datasetType(1) == 'B'
    if isBoundedDrag
        obj.mibModel.backup(BatchOpt.Target{1}, double(is3D), ...
            struct('id', BatchOpt.id, 'x', winX, 'y', winY, 'magFactor', 1));
    else
        utils.warnLargeFullResRead(obj.mibModel.I{BatchOpt.id}.image.height, ...
            obj.mibModel.I{BatchOpt.id}.image.width);
        obj.mibModel.backup(BatchOpt.Target{1}, double(is3D), ...
            struct('id', BatchOpt.id, 'magFactor', 1));
    end
end

if isBoundedDrag
    width  = winX(2) - winX(1) + 1;
    height = winY(2) - winY(1) + 1;
else
    [height, width] = obj.mibModel.I{BatchOpt.id}.getDatasetDimensions('image', [], getDataOptions);
end

switch mode
    case {'2D, Slice', 'Object2D'}
        selarea = cell2mat(obj.mibModel.getData2D(BatchOpt.Target{1}, [], [], [], getDataOptions));
        if strcmp(mode, 'Object2D')
            [xOut, yOut] = obj.mibModel.convertMouseToDataCoordinates(obj.brushPrevXY(1), obj.brushPrevXY(2), 'shown', 1);
            xOut = xOut - winXoff; yOut = yOut - winYoff;   % offset to the read window (0 unless bounded)

            if strcmp(BatchOpt.Target{1}, 'labels')
                materialId = selarea(ceil(yOut), ceil(xOut));
                currSelArea = selarea;
                selarea2 = zeros(size(selarea), 'uint8');
                selarea2(selarea == materialId) = 1;
                selarea = bwselect(selarea2, xOut, yOut);
                currSelArea(selarea == 1) = 0;
            else
                materialId = 1;
                selarea2 = bwselect(selarea, xOut, yOut);
                currSelArea = selarea;
                currSelArea(selarea2 == 1) = 0;
                selarea = selarea2;
            end
        end

        selAreaOut = zeros(size(selarea), 'uint8');
        w2 = width - abs(diffX);
        h2 = height - abs(diffY);
        if diffY > 0 && diffX > 0
            selAreaOut(diffY+1:end, diffX+1:end) = selarea(1:h2, 1:w2);
        elseif diffY > 0 && diffX <= 0
            selAreaOut(diffY+1:end, 1:w2) = selarea(1:h2, abs(diffX)+1:end);
        elseif diffY <= 0 && diffX > 0
            selAreaOut(1:h2, diffX+1:end) = selarea(abs(diffY)+1:end, 1:w2);
        elseif diffY <= 0 && diffX <= 0
            selAreaOut(1:h2, 1:w2) = selarea(abs(diffY)+1:end, abs(diffX)+1:end);
        end

        if strcmp(mode, 'Object2D')
            currSelArea(selAreaOut == 1) = materialId;
            obj.mibModel.setData2D(currSelArea, BatchOpt.Target{1}, [], [], [], getDataOptions);
        else
            obj.mibModel.setData2D(selAreaOut, BatchOpt.Target{1}, [], [], [], getDataOptions);
        end
    case {'3D, Stack', 'Object3D'}
        if BatchOpt.showWaitbar
            wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait', 'Title', 'Drag & Drop materials');
        end
        selarea = cell2mat(obj.mibModel.getData3D(BatchOpt.Target{1}, [], [], [], getDataOptions));
        if strcmp(mode, 'Object3D')
            [xOut, yOut] = obj.mibModel.convertMouseToDataCoordinates(obj.brushPrevXY(1), obj.brushPrevXY(2), 'shown', 1);
            xOut = xOut - winXoff; yOut = yOut - winYoff;   % offset to the read window (0 unless bounded)
            zOut = obj.mibModel.I{BatchOpt.id}.getCurrentSliceNumber();
            if strcmp(BatchOpt.Target{1}, 'labels')
                materialId = selarea(ceil(yOut), ceil(xOut), zOut);
                currSelArea = selarea;
                selarea2 = zeros(size(selarea), 'uint8');
                selarea2(selarea == materialId) = 1;
                selarea = bwselect3(selarea2, ceil(xOut), ceil(yOut), zOut);
                currSelArea(selarea == 1) = 0;
            else
                materialId = 1;
                selarea2 = bwselect3(selarea, ceil(xOut), ceil(yOut), zOut);
                currSelArea = selarea;
                currSelArea(selarea2 == 1) = 0;
                selarea = selarea2;
            end
        end
        if BatchOpt.showWaitbar; wb.Value = 0.5; end
        selAreaOut = zeros(size(selarea), 'uint8');
        w2 = width - abs(diffX);
        h2 = height - abs(diffY);
        if diffY > 0 && diffX > 0
            selAreaOut(diffY+1:end, diffX+1:end, :) = selarea(1:h2, 1:w2, :);
        elseif diffY > 0 && diffX <= 0
            selAreaOut(diffY+1:end, 1:w2, :) = selarea(1:h2, abs(diffX)+1:end, :);
        elseif diffY <= 0 && diffX > 0
            selAreaOut(1:h2, diffX+1:end, :) = selarea(abs(diffY)+1:end, 1:w2, :);
        elseif diffY <= 0 && diffX <= 0
            selAreaOut(1:h2, 1:w2, :) = selarea(abs(diffY)+1:end, abs(diffX)+1:end, :);
        end
        if BatchOpt.showWaitbar; wb.Value = 0.9; end
        if strcmp(mode, 'Object3D')
            currSelArea(selAreaOut == 1) = materialId;
            obj.mibModel.setData3D(currSelArea, BatchOpt.Target{1}, [], [], [], getDataOptions);
        else
            obj.mibModel.setData3D(selAreaOut, BatchOpt.Target{1}, [], [], [], getDataOptions);
        end
        if BatchOpt.showWaitbar; close(wb); end
end

obj.brushSelection = [];
obj.brushPrevXY = [];

%% Restore figure callbacks and pointer
hFig = obj.UIFigure;

if nargin < 3; hFig.Pointer = 'crosshair'; end
hFig.WindowButtonUpFcn = [];
hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();

% restore key press callback
if ~isempty(obj.quickMeasure) && isfield(obj.quickMeasure, 'measureKPF') && ...
        ~isempty(obj.quickMeasure.measureKPF)
    hFig.WindowKeyPressFcn = obj.quickMeasure.measureKPF;
else
    hFig.WindowKeyPressFcn = @(hWidget, hData) obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
end

% re-show the center marker if it was hidden
if ~isempty(obj.centralMarker)
    obj.centralMarker.Visible = 'on';
end

notify(obj.mibModel, 'ShowImage');

hFig.WindowScrollWheelFcn = @(~, eventdata) obj.gui_ScrollWheelFcn(eventdata);
hFig.WindowButtonMotionFcn = @(~, ~) obj.gui_WinMouseMotionFcn();

% notify the batch mode
if strcmp(mode, '2D, Slice') || strcmp(mode, '3D, Stack')
    BatchOpt = rmfield(BatchOpt, 'id');
    eventdata = core.ToggleEventData(BatchOpt);
    notify(obj.mibModel, 'SyncBatch', eventdata);
end

end
