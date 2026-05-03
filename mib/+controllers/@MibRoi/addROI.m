function addROI(obj)
% ADDROI - Interactively add a new ROI or create one from manual coordinates.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.addROI()
%
% Reads the selected ROI type from obj.handles.roiType dropdown
% ('Rectangle', 'Ellipse', 'Polyline', 'Lasso') and either places the
% ROI interactively on the current image axes or builds it from the
% coordinate spinners when obj.handles.roiManually is checked.
%
% After successful placement the ROI data struct is stored via
% core.RoiRegion.storeROI, the ROI list is refreshed, and a ShowImage
% event is fired to repaint the overlay.
%
% Input Arguments:
%   - **obj** — controllers.MibRoi — the ROI panel controller
%
%   Return values: none
%
% Usage:
%   Example 1::
%
%     // called from gui_Callbacks when roiAdd button is pressed
%     obj.addROI();
%

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.addROI: pressed\n');
end

dataset  = obj.mibModel.I{obj.mibModel.id};        % current MibDataset
hROI     = dataset.hROI;                            % core.RoiRegion
newIndex = hROI.getNumberOfROI(0) + 1;              % append position

roiType = obj.handles.roiType.Value;                % 'Rectangle','Ellipse','Polyline','Lasso'
manual  = obj.handles.roiManually.Value;            % logical

% remember current selection in the list
prevListVal = obj.handles.roiList.Value;

% --- Manual mode: build ROI from coordinate spinners ---
if manual && ~strcmp(roiType, 'Polyline') && ~strcmp(roiType, 'Lasso')
    x1     = obj.handles.roiX1.Value;
    y1     = obj.handles.roiY1.Value;
    roiW   = obj.handles.roiWidth.Value;
    roiH   = obj.handles.roiHeight.Value;

    switch roiType
        case 'Rectangle'
            X = [x1; x1 + roiW - 1];
            Y = [y1; y1 + roiH - 1];
            newData.type  = cellstr('rectangle');
        case 'Ellipse'
            % generate ellipse vertices from center+radii
            cx = x1 + roiW/2;  cy = y1 + roiH/2;
            if obj.handles.roiFixAspect.Value
                r = min(roiW, roiH) / 2;
                rx = r;  ry = r;
            else
                rx = roiW/2;  ry = roiH/2;
            end
            theta = linspace(0, 2*pi, 64)';
            X = cx + rx * cos(theta);
            Y = cy + ry * sin(theta);
            newData.type  = cellstr('ellipse');
    end

    newData.label       = cellstr(sprintf('%d', newIndex));
    newData.X           = X;
    newData.Y           = Y;
    newData.orientation = dataset.orientation;
    newData.BoundingBox.x = [max([floor(min(X)) 1]); min([ceil(max(X)) dataset.image.width])];
    newData.BoundingBox.y = [max([floor(min(Y)) 1]); min([ceil(max(Y)) dataset.image.height])];

    hROI.storeROI(newData, newIndex);
    obj.refreshROIList([]);
    obj.handles.roiList.Value = 'All';
    dataset.selectedROI = 0;

    % ensure the "Show ROI" checkbox is on
    obj.handles.roiShowROI.Value = true;
    obj.mibController.cQuickAccessBar.handles.roiMode.Value = true;
    notify(obj.mibModel, 'ShowImage');
    return;
end

% --- Interactive mode: draw on axes ---
cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
axH       = cImageDoc.handles.imViewAxes;

% switch cursor for drawing
cImageDoc.UIFigure.Pointer = 'cross';

% disable segmentation callbacks (pan remains active via WindowButtonDownFcn)
obj.mibModel.disableSegmentation = true;

try
    switch roiType
        case 'Rectangle'
            if obj.handles.roiFixAspect.Value
                roi = drawrectangle(axH, 'FixedAspectRatio', true);
            else
                roi = drawrectangle(axH);
            end
        case 'Ellipse'
            if obj.handles.roiFixAspect.Value
                roi = drawellipse(axH, 'AspectRatio', 1, 'FixedAspectRatio', true);
            else
                roi = drawellipse(axH);
            end
        case 'Polyline'
            roi = drawpolygon(axH);
        case 'Lasso'
            roi = drawfreehand(axH, 'Closed', true);
    end
catch ME
    obj.mibModel.disableSegmentation = false;
    obj.drawingROI.active = false;
    cImageDoc.UIFigure.Pointer = 'cross';
    rethrow(ME);
end

% user cancelled (Escape before completing)
if ~isvalid(roi)
    obj.mibModel.disableSegmentation = false;
    obj.drawingROI.active = false;
    cImageDoc.UIFigure.Pointer = 'cross';
    return;
end

% --- Set up live position tracking (data coords) for zoom/pan repositioning ---
obj.drawingROI.roi          = roi;
obj.drawingROI.type         = roiType;
obj.drawingROI.dataPos      = [];
obj.drawingROI.repositioning = false;
obj.drawingROI.active       = true;
%fprintf('[addROI] drawingROI.active set to %d\n', obj.drawingROI.active);

    function captureDataPos()
        % CAPTUREDATAPOS - Convert current axes-space position to data pixels and cache it.
        %
        % Syntax:
        %   function captureDataPos()
        %
        if ~isvalid(roi) || obj.drawingROI.repositioning; return; end
        try
            switch roiType
                case 'Rectangle'
                    p = roi.Position;   % [x y w h] in axes coords
                    [X, Y] = obj.mibModel.convertMouseToDataCoordinates([p(1); p(1)+p(3)], [p(2); p(2)+p(4)], 'shown');
                    obj.drawingROI.dataPos = [X(:), Y(:)];   % [xmin ymin; xmax ymax]
                case 'Ellipse'
                    c  = roi.Center;    % [cx cy] in axes coords
                    sa = roi.SemiAxes;  % [rx ry] in axes coords
                    [cx, cy] = obj.mibModel.convertMouseToDataCoordinates(c(1),       c(2),       'shown');
                    [ex, ~]  = obj.mibModel.convertMouseToDataCoordinates(c(1)+sa(1), c(2),       'shown');
                    [~,  ey] = obj.mibModel.convertMouseToDataCoordinates(c(1),       c(2)+sa(2), 'shown');
                    obj.drawingROI.dataPos = [cx, cy, ex-cx, ey-cy];  % [cx cy rx ry]
                otherwise
                    verts = roi.Position;   % Nx2 axes coords
                    [X, Y] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
                    obj.drawingROI.dataPos = [X(:), Y(:)];
            end
        catch
        end
    end

% Listen for position changes while the user drags the ROI
movingLsn = addlistener(roi, 'MovingROI', @(~,~) captureDataPos());
movedLsn  = addlistener(roi, 'ROIMoved',  @(~,~) captureDataPos());

% Capture the initial placement position once the tool is on the axes
captureDataPos();

% wait for user to finalize the ROI (double-click)
try
    wait(roi);
catch
    % ROI was deleted during wait
    delete(movingLsn); delete(movedLsn);
    obj.mibModel.disableSegmentation = false;
    obj.drawingROI.active = false;
    cImageDoc.UIFigure.Pointer = 'cross';
    return;
end

% clean up listeners and drawing state
delete(movingLsn); delete(movedLsn);
obj.mibModel.disableSegmentation = false;
obj.drawingROI.active = false;

if ~isvalid(roi)
    cImageDoc.UIFigure.Pointer = 'cross';
    return;
end

% Guard against incomplete ROI (Esc pressed before confirming —
% roi.Position/Vertices may be empty or undersized)
roiCancelled = false;
switch roiType
    case 'Rectangle'
        roiCancelled = numel(roi.Position) < 4;
    case 'Ellipse'
        roiCancelled = size(roi.Vertices, 2) < 2 || isempty(roi.Vertices);
    case {'Polyline', 'Lasso'}
        roiCancelled = size(roi.Position, 2) < 2 || size(roi.Position, 1) < 2;
end
if roiCancelled
    delete(roi);
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

% --- Convert final axes-space position to data coordinates ---
switch roiType
    case 'Rectangle'
        p = roi.Position;
        screenX = [p(1); p(1) + p(3)];
        screenY = [p(2); p(2) + p(4)];
        [X, Y] = obj.mibModel.convertMouseToDataCoordinates(screenX, screenY, 'shown');
        X = ceil(X);  Y = ceil(Y);
        newData.type = cellstr('rectangle');

    case 'Ellipse'
        verts = roi.Vertices;   % Nx2 array of ellipse boundary points
        [X, Y] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
        X = X(:);  Y = Y(:);
        newData.type = cellstr('ellipse');

    case 'Polyline'
        verts = roi.Position;   % Nx2
        [X, Y] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
        X = ceil(X(:));  Y = ceil(Y(:));
        newData.type = cellstr('polygon');

    case 'Lasso'
        verts = roi.Position;   % Nx2
        [X, Y] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
        nTotal = size(verts, 1);
        defaultCoef = max(1, round(nTotal / 10));
        spinDef = struct('Value', defaultCoef, 'Limits', [1, nTotal], ...
            'Step', 1, 'Round', true, 'ValueDisplayFormat', '%.0f');
        dlgOpts.Type = 'spinner';
        dlgOpts.mibPath = obj.mibModel.mibPath;
        coef = utils.dlgs.inputSingleDlg(obj.view.gui, ...
            sprintf('Total lasso vertices: %d\nDecrease the number of points N times:', nTotal), ...
            spinDef, 'Lasso to Polygon', dlgOpts);
        if isempty(coef)
            coef = defaultCoef;
        end
        X = X(1:coef:end);  Y = Y(1:coef:end);
        X = X(:);  Y = Y(:);
        newData.type = cellstr('polygon');
end

% delete the temporary drawing ROI object
delete(roi);

% restore cursor
cImageDoc.UIFigure.Pointer = 'cross';
cImageDoc.updateBrushCursor();

% generate a unique label
labelStr = sprintf('%d', newIndex);
if hROI.getNumberOfROI(0) > 0
    existingLabels = {hROI.Data.label};
    for i = 1:numel(existingLabels)
        if iscell(existingLabels{i}); existingLabels{i} = existingLabels{i}{1}; end
    end
    if ismember(labelStr, existingLabels)
        labelStr = sprintf('%d', randi(9999));
    end
end

newData.label       = cellstr(labelStr);
newData.X           = X;
newData.Y           = Y;
newData.orientation = dataset.orientation;
newData.BoundingBox.x = [max([floor(min(X)) 1]); min([ceil(max(X)) dataset.image.width])];
newData.BoundingBox.y = [max([floor(min(Y)) 1]); min([ceil(max(Y)) dataset.image.height])];

hROI.storeROI(newData, newIndex);
obj.refreshROIList([]);
obj.handles.roiList.Value = 'All';
dataset.selectedROI = 0;
% ensure the "Show ROI" checkbox is on
obj.handles.roiShowROI.Value = true;
obj.mibController.cQuickAccessBar.handles.roiMode.Value = true;

notify(obj.mibModel, 'ShowImage');
end
