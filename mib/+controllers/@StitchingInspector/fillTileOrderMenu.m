function fillTileOrderMenu(obj)
% FILLTILEORDERMENU - Fill the pair view's right-click menu for the seam on screen.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.fillTileOrderMenu()
%
% The ``ContextMenuOpeningFcn`` of ``obj.tileOrderMenu`` (set in
% ``addCallbacks``). One submenu per tile of the seam, the tile on top first,
% each with Move to top / Move up / Move down / Move to bottom
% (:meth:`tileOrder_Callback`); a move that would leave the order unchanged
% (:func:`utils.stitch.moveInTileStack` returns the same stack) is greyed out
% rather than hidden, so the four entries keep their place.
%
% The menu is left EMPTY - which keeps it from appearing - when there is nothing
% to offer:
%
% - the right press became a PAN (``obj.rightDragMoved``, set by
%   ``pairViewButtonDown``). The menu opens when the right button is RELEASED,
%   so without this every pan would end with a menu popping up;
% - the Fix Z boundary view, whose two images are one tile;
% - a two-click match in progress, or no seam to act on.
%
% .. note::
%    Why a real ``ContextMenu``: opening a ``uicontextmenu`` by hand with
%    ``open(menu, x, y)`` from the right-button-up callback was the first
%    implementation, and on Windows nothing ever appears - the menu is built and
%    opened, then dismissed by the window's own right-click handling.
%
% See also utils.stitch.moveInTileStack, controllers.StitchingInspector.tileOrder_Callback

menu = obj.tileOrderMenu;
if isempty(menu) || ~isvalid(menu); return; end
delete(menu.Children);

panned = obj.rightDragMoved;
obj.rightDragMoved = false;   % a right-click outside the images never resets it
if panned || ~obj.dataValid() || isempty(obj.currentEdgeIdx) || ...
        obj.twoClick.active || obj.boundaryModeActive()
    return;
end

edge = obj.stitching.edges(obj.currentEdgeIdx);
layout = obj.stitching.layout;
positions = obj.stitching.positions;
if isempty(positions); positions = reshape([layout.nomOrigin], 3, []).'; end
tileSizes = reshape([layout.tileSize], 4, []).';
stack = obj.currentTileStack();

if find(stack == edge.j, 1) > find(stack == edge.i, 1)
    pairTiles = [edge.j, edge.i];
else
    pairTiles = [edge.i, edge.j];
end
roleNames   = {'on top', 'below'};
actions     = {'top', 'up', 'down', 'bottom'};
actionNames = {'Move to top', 'Move up', 'Move down', 'Move to bottom'};

for pairIdx = 1:2
    tileIdx = pairTiles(pairIdx);
    tileMenu = uimenu(menu, 'Text', sprintf('Tile %d (%s)', tileIdx, roleNames{pairIdx}));
    for actionIdx = 1:numel(actions)
        moved = utils.stitch.moveInTileStack(stack, tileIdx, actions{actionIdx}, positions, tileSizes);
        enableState = 'on';
        if isequal(moved, stack); enableState = 'off'; end
        action = actions{actionIdx};
        uimenu(tileMenu, 'Text', actionNames{actionIdx}, 'Enable', enableState, ...
            'MenuSelectedFcn', @(~, ~) obj.tileOrder_Callback(tileIdx, action));
    end
end
end
