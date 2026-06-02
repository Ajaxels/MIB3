function centerCursorInAxes(obj)
% CENTERCURSORINAXES - Move the OS mouse cursor to the centre of this document's image axes.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.centerCursorInAxes()
%
% Called after ``moveView`` so the cursor lands at the new image centre,
% matching the zoom-in behaviour in ``MibStatusBar.zoomEdit_Callback``.
%
% Input Arguments:
%   (none — all state read from ``obj``)
%
% Output Arguments:
%   (none)
%

mibView = obj.mibController.view;

leftPanelW = 0;
if isfield(mibView.gui.Layout.panelLayout, 'left')
    leftPanelW = mibView.gui.Layout.panelLayout.left.freeDimension;
    if mibView.gui.Layout.panelLayout.left.collapsed; leftPanelW = 0; end
end
bottomPanelH = 0;
if isfield(mibView.gui.Layout.panelLayout, 'bottom')
    bottomPanelH = mibView.gui.Layout.panelLayout.bottom.freeDimension;
    if mibView.gui.Layout.panelLayout.bottom.collapsed; bottomPanelH = 0; end
end

winBounds = mibView.gui.WindowBounds;   % [left, top, width, height], top-left origin
posAxes   = obj.handles.imViewAxes.Position;  % [left, bottom, width, height] within doc

% horizontal offset for documents to the left of this one in split view
splitOffsetX = 0;
docIdx = obj.setOfDatasetsIndex;
if numel(obj.mibController.cImageDoc) > 1 && docIdx > 1
    for iDoc = 1:docIdx-1
        splitOffsetX = splitOffsetX + obj.mibController.cImageDoc{iDoc}.figureDoc.Figure.Position(3);
    end
end

screenX = winBounds(1) + leftPanelW + splitOffsetX + posAxes(1) + posAxes(3)/2;
screenY = winBounds(2) + winBounds(4) - bottomPanelH - posAxes(2) - posAxes(4)/2;

scaling = obj.mibModel.preferences.System.GUI.systemscaling;
monPos  = get(groot, 'MonitorPositions');   % [x y width height] per monitor

idx = find(screenX >= monPos(:,1) & screenX <= (monPos(:,1) + monPos(:,3) - 1), 1, 'first');
if isempty(idx)
    [~, idx] = min(abs(screenX - (monPos(:,1) + monPos(:,3)/2)));
end

monitorTop = monPos(idx,2) + monPos(idx,4) - 1;
pointerX = round((screenX + 8) * scaling);
pointerY = round((monitorTop - (screenY - monPos(idx,2)) + 26) * scaling);

gr = groot();
gr.PointerLocation = [pointerX, pointerY];
end
