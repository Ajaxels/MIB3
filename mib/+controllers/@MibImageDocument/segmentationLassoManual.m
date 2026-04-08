function segmentationLassoManual(obj, BatchOptIn)
% function segmentationLassoManual(obj, BatchOptIn)
% Do manual segmentation using the lasso tool in the manual mode
%
% Uses coordinate values from the lasso panel edit fields (X1, Y1, Width,
% Height) to define a rectangular or elliptical selection area. Lasso and
% Polyline types are not supported in manual mode.
%
% Parameters:
% BatchOptIn: [@em optional] a structure for batch processing mode, when NaN return
%   a structure with default options via "syncBatch" event, or a char modifier
%   ('control' to subtract, empty to add) for interactive calls
% @li .Shape - Shape type for the manual selection: Rectangle or Ellipse
% @li .Mode - Apply selection for the current slice (2D, Slice) or the whole stack (3D, Stack)
% @li .X1 - X coordinate: top-left corner for Rectangle, center for Ellipse
% @li .Y1 - Y coordinate: top-left corner for Rectangle, center for Ellipse
% @li .Width - Half-width of the selection area (semi-axis for Ellipse)
% @li .Height - Half-height of the selection area (semi-axis for Ellipse)
% @li .Action - Action to perform with the generated selection: Add or Subtract
% @li .FixSelectionToMask - Apply selection only to the masked area
% @li .FixSelectionToMaterial - Apply selection only to the area of the selected material
% @li .showWaitbar - Show or not the progress bar during execution
%
% Return values:
%   (none)
%
%|
% @b Examples:
% @code obj.segmentationLassoManual();             // select area and add to selection @endcode
% @code obj.segmentationLassoManual('control');    // select area and subtract from selection @endcode
% @code obj.segmentationLassoManual(BatchOpt);     // batch mode with provided options @endcode

% Updates
%

% get handles alias for segmentation panel widgets
segmHandles = obj.mibController.cSegmentation.handles;

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();

BatchOpt.Shape = {segmHandles.lassoType.Value};
BatchOpt.Shape{2} = segmHandles.lassoType.Items;

BatchOpt.Mode = {'2D, Slice'};
if obj.mibModel.applySegmentationIn3D; BatchOpt.Mode = {'3D, Stack'}; end
BatchOpt.Mode{2} = {'2D, Slice', '3D, Stack'};

BatchOpt.X1 = num2str(segmHandles.lassoX1.Value);
BatchOpt.Y1 = num2str(segmHandles.lassoY1.Value);
BatchOpt.Width = num2str(segmHandles.lassoWidth.Value);
BatchOpt.Height = num2str(segmHandles.lassoHeight.Value);

BatchOpt.Action = {'Add'};
BatchOpt.Action{2} = {'Add', 'Subtract'};

BatchOpt.FixSelectionToMask = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMask);
BatchOpt.FixSelectionToMaterial = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMaterial);
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = 'Lasso manual selection';

% tooltips
BatchOpt.mibBatchTooltip.Shape = 'Shape type for the manual selection';
BatchOpt.mibBatchTooltip.Mode = 'Apply selection for the current slice (2D) or the whole stack (3D)';
BatchOpt.mibBatchTooltip.X1 = 'X coordinate: top-left corner for Rectangle, center for Ellipse';
BatchOpt.mibBatchTooltip.Y1 = 'Y coordinate: top-left corner for Rectangle, center for Ellipse';
BatchOpt.mibBatchTooltip.Width = 'Half-width of the selection area (semi-axis for Ellipse)';
BatchOpt.mibBatchTooltip.Height = 'Half-height of the selection area (semi-axis for Ellipse)';
BatchOpt.mibBatchTooltip.Action = 'Action to perform: Add to or Subtract from current selection';
BatchOpt.mibBatchTooltip.FixSelectionToMask = 'Apply selection only to the masked area';
BatchOpt.mibBatchTooltip.FixSelectionToMaterial = 'Apply selection only to the area of the selected material';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 2
    if ischar(BatchOptIn)
        % interactive call with modifier string
        if strcmp(BatchOptIn, 'control')
            BatchOpt.Action{1} = 'Subtract';
        end
    elseif isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            % return possible settings via syncBatch
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_error';
            header = 'A structure as the 2nd parameter is required!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
        end
        return;
    else
        % batch mode with provided structure
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

% validate shape type
type = BatchOpt.Shape{1};
if ~ismember(type, {'Rectangle', 'Ellipse'})
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    header = sprintf('The manual mode is not available for the "%s" type!\nPlease use Rectangle or Ellipse instead', type);
    dlgOpt.HeaderLines = 2;
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Lasso manual mode', dlgOpt);
    notify(obj.mibModel, 'stopProtocol');
    return;
end

% parse parameters
id = BatchOpt.id;
x1 = str2double(BatchOpt.X1);
y1 = str2double(BatchOpt.Y1);
halfW = str2double(BatchOpt.Width);
halfH = str2double(BatchOpt.Height);

if strcmp(type, 'Ellipse')
    % X1, Y1 are center of the ellipse; Width, Height are semi-axes
    bb = [x1 - halfW, y1 - halfH, halfW * 2, halfH * 2];
else
    % X1, Y1 are top-left corner; Width, Height are half-dimensions
    bb = [x1, y1, halfW * 2, halfH * 2];
end

selcontour = obj.mibModel.I{id}.getSelectedMaterialIndex();

orientation = obj.mibModel.I{id}.orientation;
if orientation == 3      % XY
    backupOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.x = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
elseif orientation == 1  % ZX
    backupOptions.x = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.z = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
elseif orientation == 2  % ZY
    backupOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
    backupOptions.z = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
end

getDataOptions.y = [ceil(bb(2)) ceil(bb(2))+floor(bb(4))-1];
getDataOptions.x = [ceil(bb(1)) ceil(bb(1))+floor(bb(3))-1];
getDataOptions.id = id;

% generate the shape mask within the bounding box
roiHeight = floor(bb(4));
roiWidth = floor(bb(3));
if strcmp(type, 'Ellipse')
    % create elliptical mask using meshgrid
    cx = (roiWidth + 1) / 2;
    cy = (roiHeight + 1) / 2;
    rx = roiWidth / 2;
    ry = roiHeight / 2;
    [xx, yy] = meshgrid(1:roiWidth, 1:roiHeight);
    shapeMask = uint8(((xx - cx).^2 / rx^2 + (yy - cy).^2 / ry^2) <= 1);
else
    % rectangle: fill entire bounding box
    shapeMask = ones(roiHeight, roiWidth, 'uint8');
end

subtractMode = strcmp(BatchOpt.Action{1}, 'Subtract');

if strcmp(BatchOpt.Mode{1}, '3D, Stack')
    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait', 'Title', 'Lasso manual selection');
    end
    obj.mibModel.backup('selection', 1, backupOptions);
    currSelection = cell2mat(obj.mibModel.getData3D('selection', [], [], [], getDataOptions));
    selarea = repmat(shapeMask, [1 1 size(currSelection, 3)]);
    if BatchOpt.showWaitbar; wb.Value = 0.3; end

    % limit to the selected material of the model
    if BatchOpt.FixSelectionToMaterial && selcontour >= 0
        currModel = cell2mat(obj.mibModel.getData3D('labels', [], [], selcontour, getDataOptions));
        selarea = bitand(selarea, currModel);
    end

    % limit selection to the masked area
    if BatchOpt.FixSelectionToMask && obj.mibModel.I{id}.maskExist
        currModel = cell2mat(obj.mibModel.getData3D('mask', [], 3, [], getDataOptions));
        selarea = bitand(selarea, currModel);
    end
    if BatchOpt.showWaitbar; wb.Value = 0.7; end

    if subtractMode
        currSelection(selarea==1) = 0;
        obj.mibModel.setData3D({currSelection}, 'selection', [], [], [], getDataOptions);
    else
        obj.mibModel.setData3D({bitor(selarea, currSelection)}, 'selection', [], [], [], getDataOptions);
    end
    if BatchOpt.showWaitbar; close(wb); end
else    % 2D case
    obj.mibModel.backup('selection', 0, getDataOptions);
    currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], getDataOptions));
    selarea = shapeMask;

    % limit to the selected material of the model
    if BatchOpt.FixSelectionToMaterial && selcontour >= 0
        currModel = cell2mat(obj.mibModel.getData2D('labels', [], [], selcontour, getDataOptions));
        selarea = bitand(selarea, currModel);
    end

    % limit selection to the masked area
    if BatchOpt.FixSelectionToMask && obj.mibModel.I{id}.maskExist
        currModel = cell2mat(obj.mibModel.getData2D('mask', [], [], selcontour, getDataOptions));
        selarea = bitand(selarea, currModel);
    end

    if subtractMode
        currSelection(selarea==1) = 0;
        obj.mibModel.setData2D({currSelection}, 'selection', [], [], selcontour, getDataOptions);
    else
        obj.mibModel.setData2D({bitor(currSelection, selarea)}, 'selection', [], [], selcontour, getDataOptions);
    end
end

notify(obj.mibModel, 'ShowImage');

% notify the batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj.mibModel, 'SyncBatch', eventdata);

end
