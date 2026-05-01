function roiModify(obj)
% ROIMODIFY - Interactively modify (redraw) an existing ROI.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.roiModify()
%
% If "All" is selected in the ROI list a dialog prompts the user to choose
% which ROI to edit.  The appropriate draw tool is then re-launched with
% the current ROI position pre-loaded.  After the user confirms
% (double-click), the ROI data is updated in-place (label preserved).
%
% Input Arguments:
%   - **obj** — controllers.MibRoi — the ROI panel controller
%
%   Return values: none
%
% Usage:
%   Example 1::
%
%     // called from gui_Callbacks when roiModify is triggered
%     obj.roiModify();
%

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.roiModify: pressed\n');
end

dataset = obj.mibModel.I{obj.mibModel.id};
hROI    = dataset.hROI;

if hROI.getNumberOfROI(0) < 1; return; end

% --- Determine which ROI to modify ---
[~, indices] = hROI.getNumberOfROI(0);
roiIdx = dataset.selectedROI;   % 0 = All, >0 = list position

if roiIdx == 0
    % build label list for a selection dialog
    labels = cell(1, numel(indices));
    for i = 1:numel(indices)
        lbl = hROI.Data(indices(i)).label;
        if iscell(lbl); lbl = lbl{1}; end
        labels{i} = lbl;
    end
    dlgOpts.mibPath = obj.mibModel.mibPath;
    dlgOpts.Icon    = 'puffin_question';
    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
        {'Select ROI to modify:'}, ...
        {[labels, 1]}, ...
        'Modify ROI', dlgOpts);
    if isempty(answer); return; end
    roiIdx = hROI.findIndexByLabel(answer{1});
    if isempty(roiIdx); return; end
else
    roiIdx = indices(roiIdx);
end

% --- Get existing ROI data and determine tool type ---
roiData = hROI.Data(roiIdx);
roiType = roiData.type;
if iscell(roiType); roiType = roiType{1}; end

% map stored type string to draw-tool name
switch roiType
    case 'rectangle'; drawType = 'Rectangle';
    case 'ellipse';   drawType = 'Ellipse';
    otherwise;        drawType = 'Polygon';   % polygon / freehand stored as polygon
end

% convert stored data-pixel coordinates to current axes coordinates
X = roiData.X;
Y = roiData.Y;
[XAxes, YAxes] = obj.mibModel.convertDataToMouseCoordinates(X, Y, 'shown');

% --- Set up interactive axes ---
cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
axH = cImageDoc.handles.imViewAxes;

if ~isempty(cImageDoc.brushCursor); cImageDoc.brushCursor.Visible = false; end
cImageDoc.UIFigure.Pointer = 'cross';
obj.mibModel.disableSegmentation = 1;

try
    switch drawType
        case 'Rectangle'
            w = XAxes(2) - XAxes(1);
            h = YAxes(2) - YAxes(1);
            roi = drawrectangle(axH, 'Position', [XAxes(1), YAxes(1), w, h]);
        case 'Ellipse'
            cx = (min(XAxes) + max(XAxes)) / 2;
            cy = (min(YAxes) + max(YAxes)) / 2;
            rx = (max(XAxes) - min(XAxes)) / 2;
            ry = (max(YAxes) - min(YAxes)) / 2;
            roi = drawellipse(axH, 'Center', [cx, cy], 'SemiAxes', [rx, ry]);
        otherwise  % Polygon
            roi = drawpolygon(axH, 'Position', [XAxes(:), YAxes(:)]);
    end
catch ME
    obj.mibModel.disableSegmentation = 0;
    obj.drawingROI.active = false;
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    rethrow(ME);
end

if ~isvalid(roi)
    obj.mibModel.disableSegmentation = 0;
    obj.drawingROI.active = false;
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

% --- Set up live position tracking for zoom/pan repositioning ---
obj.drawingROI.roi           = roi;
obj.drawingROI.type          = drawType;
obj.drawingROI.dataPos       = [];
obj.drawingROI.repositioning = false;
obj.drawingROI.active        = true;

    function captureDataPos()
        if ~isvalid(roi) || obj.drawingROI.repositioning; return; end
        try
            switch drawType
                case 'Rectangle'
                    p = roi.Position;
                    [Xd, Yd] = obj.mibModel.convertMouseToDataCoordinates( ...
                        [p(1); p(1)+p(3)], [p(2); p(2)+p(4)], 'shown');
                    obj.drawingROI.dataPos = [Xd(:), Yd(:)];
                case 'Ellipse'
                    c = roi.Center; sa = roi.SemiAxes;
                    [cx2, cy2] = obj.mibModel.convertMouseToDataCoordinates(c(1), c(2), 'shown');
                    [ex, ~]    = obj.mibModel.convertMouseToDataCoordinates(c(1)+sa(1), c(2), 'shown');
                    [~,  ey]   = obj.mibModel.convertMouseToDataCoordinates(c(1), c(2)+sa(2), 'shown');
                    obj.drawingROI.dataPos = [cx2, cy2, ex-cx2, ey-cy2];
                otherwise
                    verts = roi.Position;
                    [Xd, Yd] = obj.mibModel.convertMouseToDataCoordinates( ...
                        verts(:,1), verts(:,2), 'shown');
                    obj.drawingROI.dataPos = [Xd(:), Yd(:)];
            end
        catch
        end
    end

movingLsn = addlistener(roi, 'MovingROI', @(~,~) captureDataPos());
movedLsn  = addlistener(roi, 'ROIMoved',  @(~,~) captureDataPos());
captureDataPos();

try
    wait(roi);
catch
    delete(movingLsn); delete(movedLsn);
    obj.mibModel.disableSegmentation = 0;
    obj.drawingROI.active = false;
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

delete(movingLsn); delete(movedLsn);
obj.mibModel.disableSegmentation = 0;
obj.drawingROI.active = false;

if ~isvalid(roi)
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

% Guard against Esc before confirming
roiCancelled = false;
switch drawType
    case 'Rectangle'; roiCancelled = numel(roi.Position) < 4;
    case 'Ellipse';   roiCancelled = size(roi.Vertices, 2) < 2 || isempty(roi.Vertices);
    otherwise;        roiCancelled = size(roi.Position, 2) < 2 || size(roi.Position, 1) < 2;
end
if roiCancelled
    delete(roi);
    cImageDoc.UIFigure.Pointer = 'cross';
    cImageDoc.updateBrushCursor();
    return;
end

% --- Convert final axes position back to data coordinates ---
switch drawType
    case 'Rectangle'
        p = roi.Position;
        [Xd, Yd] = obj.mibModel.convertMouseToDataCoordinates( ...
            [p(1); p(1)+p(3)], [p(2); p(2)+p(4)], 'shown');
        Xd = ceil(Xd);  Yd = ceil(Yd);
    case 'Ellipse'
        verts = roi.Vertices;
        [Xd, Yd] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
        Xd = Xd(:);  Yd = Yd(:);
    otherwise
        verts = roi.Position;
        [Xd, Yd] = obj.mibModel.convertMouseToDataCoordinates(verts(:,1), verts(:,2), 'shown');
        Xd = ceil(Xd(:));  Yd = ceil(Yd(:));
end

delete(roi);
cImageDoc.UIFigure.Pointer = 'cross';
cImageDoc.updateBrushCursor();

% --- Update ROI data in-place (label and orientation preserved) ---
roiData.X = Xd;
roiData.Y = Yd;
roiData.BoundingBox.x = [max([floor(min(Xd)) 1]); min([ceil(max(Xd)) dataset.image.width])];
roiData.BoundingBox.y = [max([floor(min(Yd)) 1]); min([ceil(max(Yd)) dataset.image.height])];
hROI.Data(roiIdx) = roiData;

obj.mibController.showImage();
end
