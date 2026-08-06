function measureLength(obj, type)
% MEASURELENGTH - Quick measurement tool: open the Measure Tool or interactively measure a.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.measureLength(type)
%
% straight-line or freehand path length on the currently displayed image.
% Converted from MIB2 @mibController/menuToolsMeasure_Callback.m
%
% Input Arguments:
%   - **type** - a string selecting the measurement mode
%     - 'tool'     - open the full interactive Measure Tool controller
%     - 'line'     - draw a straight line and report its length
%     - 'freehand' - draw a freehand path and report its length
%
% Output Arguments:
%   (none)
%

switch type
    case 'tool'
        obj.startController('controllers.MeasureTool', obj);     % start the Measure Tool
        obj.cSelection.handles.showAnnotations.Value = true;
        obj.mibModel.showAnnotations = true;
        return;
    case 'line'
        obj.mibModel.disableSegmentation = true;
        cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
        % Only one measurement ROI per document at a time.
        % Placeholder set BEFORE drawline so a second button press while
        % drawline is blocking (waiting for point placement) is ignored.
        if ~isempty(cImageDoc.quickMeasure); return; end
        cImageDoc.quickMeasure = struct('roi',[],'textH',[],'pending',true);
        savedWBDF = cImageDoc.UIFigure.WindowButtonDownFcn;
        cImageDoc.UIFigure.WindowButtonDownFcn = [];
        roi = drawline(cImageDoc.handles.imViewAxes);
    case 'freehand'
        obj.mibModel.disableSegmentation = true;

        cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
        if ~isempty(cImageDoc.quickMeasure); return; end
        cImageDoc.quickMeasure = struct('roi',[],'textH',[],'pending',true);
        savedWBDF = cImageDoc.UIFigure.WindowButtonDownFcn;
        cImageDoc.UIFigure.WindowButtonDownFcn = [];
        roi = drawfreehand(cImageDoc.handles.imViewAxes, 'Closed', false);
end

% Restore WindowButtonDownFcn immediately so pan/zoom work during
% interactive adjustment (vertex dragging before finalisation).
cImageDoc.UIFigure.WindowButtonDownFcn = savedWBDF;

% If the ROI was cancelled during initial placement (Escape before placing
% points), drawline/drawfreehand returns an invalid handle - clean up and bail.
if ~isvalid(roi)
    cImageDoc.quickMeasure = [];
    obj.mibModel.disableSegmentation = false;
    return;
end

% Create a live text label at the ROI midpoint
datasetId = obj.mibModel.id;
axH   = cImageDoc.handles.imViewAxes;
midPt = mean(roi.Position, 1);
textH = text(axH, midPt(1), midPt(2), '', ...
    'Color', 'yellow', 'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [0 0 0], 'HitTest', 'off', 'PickableParts', 'none');

% Register the active measurement in the document (one per document).
% savedKPF is stored here so clearQuickMeasure can restore it on any exit.
cImageDoc.quickMeasure.roi = roi;
cImageDoc.quickMeasure.textH = textH;
cImageDoc.quickMeasure.datasetId = datasetId;
cImageDoc.quickMeasure.lastPos = roi.Position;
cImageDoc.quickMeasure.savedKPF = cImageDoc.UIFigure.WindowKeyPressFcn;
cImageDoc.quickMeasure.mibController = obj;

% Populate text label immediately
cImageDoc.updateMeasureText(roi.Position);

% Intercept Escape (silent delete) and Enter (finalise with distance report).
% Safe without wait() - no conflict with MATLAB's internal ROI key machinery.
measureKPF = @(~, evt) handleMeasureKey(evt, obj, cImageDoc);
cImageDoc.quickMeasure.measureKPF = measureKPF;   % stored so gui_WindowButtonUpFcn can restore it
cImageDoc.UIFigure.WindowKeyPressFcn = measureKPF;

% ----- Fully event-driven - no wait(), function returns now -----
%
%  MovingROI   -> update live text while dragging vertices
%  ROIClicked  -> double-click finalises: compute distance, show dialog
%  DeletingROI -> cleanup if ROI is removed externally (dataset change)

addlistener(roi, 'MovingROI',   @(src, evt) cImageDoc.updateMeasureText(evt.CurrentPosition));
addlistener(roi, 'ROIClicked',  @(src, evt) onROIClicked(src, evt, obj, cImageDoc));
addlistener(roi, 'DeletingROI', @(src, ~)   cImageDoc.clearQuickMeasure());

end

% -------------------------------------------------------------------------
function handleMeasureKey(evt, obj, cImageDoc)
% HANDLEMEASUREKEY - Temporary WindowKeyPressFcn active while a measurement ROI is alive.
%
% Syntax:
%   function handleMeasureKey(evt, obj, cImageDoc)
%
    if isempty(cImageDoc.quickMeasure)
        % ROI already gone - just forward to the normal handler
        obj.gui_WindowKeyPressFcn(cImageDoc.UIFigure, evt);
        return;
    end
    switch evt.Key
        case 'escape'
            % Silent removal - no distance report
            cImageDoc.clearQuickMeasure();
        case 'return'
            % Finalise with distance report (same as double-click)
            if isvalid(cImageDoc.quickMeasure.roi)
                doFinalize(cImageDoc.quickMeasure.roi.Position, ...
                    cImageDoc.quickMeasure.datasetId, obj, cImageDoc);
                cImageDoc.clearQuickMeasure();
            end
        otherwise
            % Pass all other keys to the normal handler
            obj.gui_WindowKeyPressFcn(cImageDoc.UIFigure, evt);
    end
end

% -------------------------------------------------------------------------
function onROIClicked(roi, evt, obj, cImageDoc)
% ONROICLICKED - ROIClicked fires on every click; only act on double-click.
%
% Syntax:
%   function onROIClicked(roi, evt, obj, cImageDoc)
%
    if ~strcmp(evt.SelectionType, 'double'); return; end
    if ~isvalid(roi) || isempty(cImageDoc.quickMeasure); return; end
    pos       = roi.Position;
    datasetId = cImageDoc.quickMeasure.datasetId;
    cImageDoc.clearQuickMeasure();
    doFinalize(pos, datasetId, obj, cImageDoc);
end

% -------------------------------------------------------------------------
function doFinalize(pos, datasetId, obj, cImageDoc)
% DOFINALIZE - Compute path length and show the result dialog.
%
% Syntax:
%   function doFinalize(pos, datasetId, obj, cImageDoc)
%
    dataset     = obj.mibModel.I{datasetId};
    magFactor   = dataset.magFactor;
    [axesX, axesY] = dataset.getAxesLimits();
    pixSize     = dataset.image.pixSize;
    orientation = dataset.orientation;

    % Convert physical (XData) coords to data-pixel coords
    switch orientation
        case 3;  coef_z = pixSize.x / pixSize.y;
        case 1;  coef_z = pixSize.z / pixSize.x;
        otherwise; coef_z = pixSize.z / pixSize.y;
    end
    if magFactor >= 1
        pos(:,1) = pos(:,1) * magFactor / coef_z;
        pos(:,2) = pos(:,2) * magFactor;
    else
        pos(:,1) = pos(:,1) * magFactor / coef_z + max([0 floor(axesX(1))]);
        pos(:,2) = pos(:,2) * magFactor           + max([0 floor(axesY(1))]);
    end

    % Physical pixel sizes along the displayed axes
    if orientation == 3;       xSz = pixSize.x; ySz = pixSize.y;
    elseif orientation == 1;   xSz = pixSize.z; ySz = pixSize.x;
    else;                      xSz = pixSize.z; ySz = pixSize.y;
    end

    % Accumulate Euclidean path length
    distance = 0;
    for i = 2:size(pos, 1)
        distance = distance + sqrt(((pos(i,1)-pos(i-1,1))*xSz)^2 + ((pos(i,2)-pos(i-1,2))*ySz)^2);
    end

    str2 = ['Distance = ' num2str(distance) ' ' pixSize.units];

    if ~isfield(obj.mibModel.preferences, 'DoNotShowDialogs') || ~isstruct(obj.mibModel.preferences.DoNotShowDialogs)
        obj.mibModel.preferences.DoNotShowDialogs = struct();
    end
    if ~isfield(obj.mibModel.preferences.DoNotShowDialogs, 'MeasureLength') || ...
            ~obj.mibModel.preferences.DoNotShowDialogs.MeasureLength
        str3 = 'Hints: hold Shift to snap line to 15-degree angles; finalise with double-click or Enter';
        htmlContent = sprintf('%s\nThe measured length has been also copied to the system clipboard\n\n%s', str2, str3);
        dlgTitle = 'Quick measurement';
        options = struct();
        options.MsgBoxOnly     = true;
        options.OkBtnText      = 'OK';
        options.Icon           = 'puffin_measure';
        options.IconWidth      = 96;
        options.WindowHeight   = 180;
        options.mibPath        = obj.mibPath;
        options.DoNotShowAgain = true;
        [~, ~, obj.mibModel.preferences.DoNotShowDialogs.MeasureLength] = ...
            utils.dlgs.inputUniversalDlg(obj.view.gui, '', {htmlContent}, {htmlContent}, dlgTitle, options);
    end

    disp(str2);
    clipboard('copy', [num2str(distance) ' ' pixSize.units]);
    obj.showImage();
end
