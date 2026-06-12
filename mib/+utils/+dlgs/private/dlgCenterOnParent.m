function xy = dlgCenterOnParent(parent, dlgWidth, dlgHeight)
% DLGCENTERONPARENT - Bottom-left [x y] that centers a dialog on its parent window.
%
% Syntax:
%   .. code-block:: matlab
%
%      xy = dlgCenterOnParent(parent, dlgWidth, dlgHeight)
%
% AppContainer exposes ``WindowBounds`` (top-left origin); figures expose
% ``Position`` (bottom-left origin). Returns ``[]`` when the parent is
% missing/invalid or its position cannot be determined — the caller then keeps
% the default position.
%
% Input Arguments:
%   - **parent** — [handle] parent window (AppContainer, uifigure, or ``[]``)
%   - **dlgWidth** — [numeric] final dialog width in pixels
%   - **dlgHeight** — [numeric] final dialog height in pixels
%
% Output Arguments:
%   - **xy** — [1x2 numeric] bottom-left dialog position ``[x y]``; ``[]`` when
%     centering is not possible

xy = [];
if isempty(parent) || ~isvalid(parent); return; end
try
    if isa(parent, 'matlab.ui.container.internal.AppContainer')
        parentPos = parent.WindowBounds;    % [x y w h], top-left origin
        screenSize = get(0, 'ScreenSize');  % [left bottom width height]
        x1 = parentPos(1) + (parentPos(3) - dlgWidth) / 2;
        % Convert Y from distance-from-top to distance-from-bottom of the screen
        y1 = screenSize(4) - parentPos(2) - parentPos(4) + (parentPos(4) - dlgHeight) / 2;
    elseif isprop(parent, 'Position')
        parentPos = parent.Position;        % [x y w h], bottom-left origin
        x1 = parentPos(1) + (parentPos(3) - dlgWidth) / 2;
        y1 = parentPos(2) + (parentPos(4) - dlgHeight) / 2;
    else
        return;
    end
    xy = [x1 y1];
catch
    xy = [];
end
end
