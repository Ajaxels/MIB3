function [pointerX, pointerY] = axesCenterPointerLocation(obj, cursorOverAxes)
% AXESCENTERPOINTERLOCATION - Screen-pixel location of this document's image axes centre.
%
% Syntax:
%   .. code-block:: matlab
%
%      [pointerX, pointerY] = obj.axesCenterPointerLocation()
%      [pointerX, pointerY] = obj.axesCenterPointerLocation(cursorOverAxes)
%
% Returns the value to assign to ``groot().PointerLocation`` so that the OS
% mouse cursor lands at the centre of this document's ``imViewAxes``.
%
% Two strategies are used:
%
% - **Runtime self-calibration** *(preferred)* — when ``cursorOverAxes`` is
%   ``true`` (the caller knows the cursor is currently over this document's
%   axes, e.g. zoom or middle-click recenter), the target is computed from the
%   live offset between ``groot().PointerLocation`` and the figure's
%   ``CurrentPoint``. Only a small in-axes displacement is converted, so this
%   needs no window/monitor/chrome geometry and works identically docked,
%   floating, on any monitor and (for small displacements) any scaling.
% - **Geometric reconstruction** *(fallback)* — used when the cursor is not over
%   the axes (e.g. ribbon-triggered orientation switch). Derives the absolute
%   screen position from the docked main window or the floating document window;
%   relies on the AppContainer chrome insets ``+9`` / ``+31`` for the docked case.
%
% Input Arguments:
%   - **cursorOverAxes** *(optional)* — [logical] whether the OS cursor is
%     currently over this document's axes (default: ``false``)
%
% Output Arguments:
%   - **pointerX** — [double] horizontal pointer location in screen pixels
%   - **pointerY** — [double] vertical pointer location in screen pixels
%
% See also :func:`centerCursorInAxes`.

arguments
    obj
    cursorOverAxes (1,1) logical = false
end

posAxes  = obj.handles.imViewAxes.Position;   % [left, bottom, width, height] within doc figure
scaling  = obj.mibModel.preferences.System.GUI.systemscaling;
axCenter = [posAxes(1) + posAxes(3)/2, posAxes(2) + posAxes(4)/2];   % axes centre, figure-client px

% ---- Preferred: runtime self-calibration ----
% fig.CurrentPoint (figure-client px) corresponds to the live PointerLocation
% (physical px) whenever the cursor is over the figure. Shifting the cursor by
% the in-client displacement (axCenter - CurrentPoint) needs no absolute
% window/monitor/chrome geometry. fig.Position(3:4) reports the client size
% reliably in every dock state, so it bounds-checks that the cursor really is
% inside the figure before trusting CurrentPoint.
if cursorOverAxes
    fig = obj.figureDoc.Figure;
    cpFig = fig.CurrentPoint;             % figure-client px (logical)
    clientSize = fig.Position(3:4);
    if all(cpFig >= 0) && all(cpFig <= clientSize)
        target   = groot().PointerLocation + (axCenter - cpFig) * scaling;
        pointerX = round(target(1));
        pointerY = round(target(2));
        return;
    end
    % cursor not actually inside the figure -> fall through to geometry
end

% figureDoc.Docked is 1 when docked inside the AppContainer, 0 when floating.
if ~obj.figureDoc.Docked
    % ---- FLOATING (undocked) document ----
    % figureDoc.WindowBounds is [left bottom width height] and is asymmetric:
    % the X (left) is a GLOBAL desktop coordinate, but the Y (bottom) is measured
    % relative to the BOTTOM of the monitor the window sits on. To get a global
    % bottom-left PointerLocation Y we add that monitor's PL y-offset. The
    % figure's own Position only reports the client area size [1 1 clientW clientH].
    winBounds = obj.figureDoc.WindowBounds;       % [left bottom width height]
    clientPos = obj.figureDoc.Figure.Position;    % [1 1 clientW clientH]

    % Window chrome: left/right/bottom borders are equal; the larger remainder
    % is the title bar at the top (not needed here since we measure from bottom).
    borderSide = (winBounds(3) - clientPos(3)) / 2;

    % Identify the monitor hosting the window via its global X coordinate.
    monPos = get(groot, 'MonitorPositions');
    m = find(winBounds(1) >= monPos(:,1) & winBounds(1) <= monPos(:,1) + monPos(:,3) - 1, 1, 'first');
    if isempty(m)
        [~, m] = min(abs(winBounds(1) - (monPos(:,1) + monPos(:,3)/2)));
    end

    clientLeft   = winBounds(1) + borderSide;                   % global X
    clientBottom = monPos(m,2) + winBounds(2) + borderSide;     % global Y (monitor offset + local)

    pointerX = round((clientLeft   + axCenter(1)) * scaling);
    pointerY = round((clientBottom + axCenter(2)) * scaling);
    return;
end

% ---- DOCKED document (inside the main MIB window) ----
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

winBounds = mibView.gui.WindowBounds;   % main window [left, top, width, height]

% horizontal offset for documents to the left of this one in split view
splitOffsetX = 0;
docIdx = obj.setOfDatasetsIndex;
if numel(obj.mibController.cImageDoc) > 1 && docIdx > 1
    for iDoc = 1:docIdx-1
        splitOffsetX = splitOffsetX + obj.mibController.cImageDoc{iDoc}.figureDoc.Figure.Position(3);
    end
end

screenX = winBounds(1) + leftPanelW + splitOffsetX + axCenter(1);
screenY = winBounds(2) + winBounds(4) - bottomPanelH - axCenter(2);

monPos = get(groot, 'MonitorPositions');   % [x y width height] per monitor

% Flip screenY to the bottom-left-origin PointerLocation system using the
% monitor that contains the axes centre. monitorTop and the vertical offset
% monPos(idx,2) must come from the SAME monitor, so this stays correct when the
% main window is on a second monitor. screenX is already global and needs no
% monitor term. The +9 / +31 constants are the AppContainer chrome insets
% (calibrated against the real cursor on docked single/second-monitor windows).
idx = find(screenX >= monPos(:,1) & screenX <= (monPos(:,1) + monPos(:,3) - 1), 1, 'first');
if isempty(idx)
    [~, idx] = min(abs(screenX - (monPos(:,1) + monPos(:,3)/2)));
end

monitorTop = monPos(idx,2) + monPos(idx,4) - 1;
pointerX = round((screenX + 9) * scaling);
pointerY = round((monitorTop - (screenY - monPos(idx,2)) + 31) * scaling);
end
