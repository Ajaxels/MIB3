function measureLength(obj, type)
% function measureLength(obj, type)
% Quick measurement tool: open the Measure Tool or interactively measure a
% straight-line or freehand path length on the currently displayed image.
% Converted from MIB2 @mibController/menuToolsMeasure_Callback.m
%
% Parameters:
% type: a string selecting the measurement mode
% @li 'tool'     - open the full interactive Measure Tool controller
% @li 'line'     - draw a straight line and report its length
% @li 'freehand' - draw a freehand path and report its length
%
% Return values:
%   none
%
% Updates
%

switch type
    case 'tool'
        obj.startController('mibMeasureToolController', obj);     % start the Measure Tool
        obj.view.handles.panels.selection.handles.showAnnotations
        obj.cSelection.handles.showAnnotations.Value = true;
        obj.mibModel.showAnnotations = true;
        return;
    case 'line'
        cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
        savedWBDF = cImageDoc.UIFigure.WindowButtonDownFcn;
        cImageDoc.UIFigure.WindowButtonDownFcn = [];
        roi = drawline(cImageDoc.handles.imViewAxes);
    case 'freehand'
        cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
        savedWBDF = cImageDoc.UIFigure.WindowButtonDownFcn;
        cImageDoc.UIFigure.WindowButtonDownFcn = [];
        roi = drawfreehand(cImageDoc.handles.imViewAxes, 'Closed', false);
end

% Compute coordinate-system parameters before setting up listeners so they
% are available inside the callbacks via anonymous-function capture.
magFactor = obj.mibModel.getMagFactor();
[axesX, axesY] = obj.mibModel.getAxesLimits();
dataset = obj.mibModel.I{obj.mibModel.id};
switch dataset.orientation
    case 3;  coef_z = dataset.pixSize.x / dataset.pixSize.y;
    case 1;  coef_z = dataset.pixSize.z / dataset.pixSize.x;
    otherwise; coef_z = dataset.pixSize.z / dataset.pixSize.y;
end
pixSize     = dataset.pixSize;
orientation = dataset.orientation;

% Create a live text label that follows the ROI midpoint
axH   = cImageDoc.handles.imViewAxes;
midPt = mean(roi.Position, 1);
textH = text(axH, midPt(1), midPt(2), '', ...
    'Color', 'yellow', 'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [0 0 0], 'HitTest', 'off', 'PickableParts', 'none');

% Store last-known ROI position in appdata immediately so it is never empty
% when wait() unblocks (covers both double-click and Escape exits).
setappdata(axH, 'measurePos',  roi.Position);
setappdata(axH, 'measureTextH', textH);

% Listeners:
%  MovingROI  — keeps measurePos current AND updates the live length label
%  ROIClicked — double-click: clean up text then delete ROI (unblocks wait)
% Note: Enter/Escape are handled natively by MATLAB's ROI wait() machinery;
% do NOT intercept WindowKeyPressFcn as it conflicts with ROI internals.
addlistener(roi, 'MovingROI',   @(src, evt) onMovingROI( ...
    evt.CurrentPosition, axH, magFactor, coef_z, pixSize, orientation, axesX, axesY));
addlistener(roi, 'ROIClicked',  @(src, evt) handleDoubleClick(src, evt, axH));

% Populate the text for the position drawn initially
onMovingROI(roi.Position, axH, magFactor, coef_z, pixSize, orientation, axesX, axesY);

wait(roi);   % blocks until ROI is deleted (double-click) or Enter/Escape (MATLAB native)

% Always clean up the text label first
cleanupText(axH);

% After wait(): ROI may still be valid (Enter keeps it) or already deleted (Escape/double-click).
% Capture position then delete if still alive.
if isvalid(roi)
    setappdata(axH, 'measurePos', roi.Position);
    delete(roi);
end

% Restore the button-down callback
cImageDoc.UIFigure.WindowButtonDownFcn = savedWBDF;

% Use the last position stored before deletion (always valid after initial draw)
pos = getappdata(axH, 'measurePos');
if isappdata(axH, 'measurePos'); rmappdata(axH, 'measurePos'); end
if isempty(pos); return; end

% Convert captured physical (XData) coordinates to data-pixel coordinates.
% Mirrors the two-branch formula in convertMouseToDataCoordinates('shown').
if magFactor >= 1   % full-image: XLim is absolute, no axesX offset
    pos(:,1) = pos(:,1) * magFactor / coef_z;
    pos(:,2) = pos(:,2) * magFactor;
else                % block mode: XLim viewport-relative, add axesX(1) offset
    pos(:,1) = pos(:,1) * magFactor / coef_z + max([0 floor(axesX(1))]);
    pos(:,2) = pos(:,2) * magFactor           + max([0 floor(axesY(1))]);
end

% Physical pixel sizes along the two displayed axes
if orientation == 3;       xSz = pixSize.x; ySz = pixSize.y;   % YX plane
elseif orientation == 1;   xSz = pixSize.z; ySz = pixSize.x;   % XZ plane
else;                      xSz = pixSize.z; ySz = pixSize.y;   % YZ plane
end

% Accumulate Euclidean path length (in physical units)
distance = 0;
for i = 2:size(pos, 1)
    distance = distance + sqrt(((pos(i,1)-pos(i-1,1))*xSz)^2 + ((pos(i,2)-pos(i-1,2))*ySz)^2);
end

str2 = ['Distance = ' num2str(distance) ' ' pixSize.units];

if ~isfield(obj.mibModel.sessionSettings.DoNotShowDialogs, 'MeasureLength') || ~obj.mibModel.sessionSettings.DoNotShowDialogs.MeasureLength
    str3 = sprintf('Hints!\n- Hold the Shift to make the line snap to 15 degree angles\n- Close the line with Esc, Enter or double click');
    htmlContent = sprintf('%s\nThe measured length has been also copied to the system clipboard\n\n%s', str2, str3);
    dlgTitle = 'Quick measurement';
    options.MsgBoxOnly = true;
    options.OkBtnText = 'OK';
    options.Icon = 'puffin_measure';
    options.IconWidth = 96;
    options.WindowHeight = 146;
    options.ParentFigure = obj.view.gui;
    options.DoNotShowAgain = true;
    [~, ~, obj.mibModel.sessionSettings.DoNotShowDialogs.MeasureLength] = utils.dlgs.mibInputUniversalDlg(obj.mibPath, {htmlContent}, {htmlContent}, dlgTitle, options);
end

disp(str2);
clipboard('copy', [num2str(distance) ' ' pixSize.units]);
obj.showImage();

end

% -------------------------------------------------------------------------
function handleDoubleClick(src, evt, axH)
% Double-click: clean up text first, then delete the ROI (unblocks wait).
    if strcmp(evt.SelectionType, 'double') && isvalid(src)
        cleanupText(axH);
        delete(src);
    end
end

% -------------------------------------------------------------------------
function cleanupText(axH)
% Remove the live text label (called from double-click and DeletingROI).
    if isappdata(axH, 'measureTextH')
        textH = getappdata(axH, 'measureTextH');
        if ~isempty(textH) && isvalid(textH); delete(textH); end
        rmappdata(axH, 'measureTextH');
    end
end

% -------------------------------------------------------------------------
function onMovingROI(pos, axH, magFactor, coef_z, pixSize, orientation, axesX, axesY)
% Keep measurePos current and refresh the live length text label.
    setappdata(axH, 'measurePos', pos);   % always save latest position
    if magFactor >= 1
        px = pos(:,1) * magFactor / coef_z;
        py = pos(:,2) * magFactor;
    else
        px = pos(:,1) * magFactor / coef_z + max([0 floor(axesX(1))]);
        py = pos(:,2) * magFactor           + max([0 floor(axesY(1))]);
    end
    if orientation == 3;      xSz = pixSize.x; ySz = pixSize.y;
    elseif orientation == 1;  xSz = pixSize.z; ySz = pixSize.x;
    else;                     xSz = pixSize.z; ySz = pixSize.y;
    end
    dist = 0;
    for i = 2:size(px, 1)
        dist = dist + sqrt(((px(i)-px(i-1))*xSz)^2 + ((py(i)-py(i-1))*ySz)^2);
    end
    if isappdata(axH, 'measureTextH')
        textH = getappdata(axH, 'measureTextH');
        if ~isempty(textH) && isvalid(textH)
            midPt = mean(pos, 1);
            textH.Position = [midPt(1), midPt(2)];
            textH.String = sprintf('%.4g %s', dist, pixSize.units);
        end
    end
end
