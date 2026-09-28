function tileOrder_Callback(obj, tileIdx, action)
% TILEORDER_CALLBACK - Move a tile of the current seam in the Overwrite drawing order.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.tileOrder_Callback(tileIdx, action)
%
% Called from the pair view's right-click menu (built by ``pairViewButtonDown``
% when a right-click is released without dragging - a right DRAG still pans).
% Where tiles overlap, ``'Overwrite'`` keeps the tile drawn last. By default that
% order is derived (:func:`utils.stitch.tileDrawOrder`: the tile imaged first
% with a re-exposure damage model, otherwise the highest index); this is where the
% user overrides it. The first move freezes the order in force into
% ``stitching.tileStack`` and edits that from then on, so the default can no
% longer shift underneath a choice the user made.
%
% The order is used by Stitch and saved in the project; it changes no position,
% edge or seam score, so nothing is re-solved or re-scored. It matters only to
% ``'Overwrite'`` - the other blend modes do not depend on the order - which the
% status line points out when another mode is selected.
%
% Input Arguments:
%   - **tileIdx** - [double] the tile to move.
%   - **action** - [char] ``'top'`` | ``'up'`` | ``'down'`` | ``'bottom'``, see
%     :func:`utils.stitch.moveInTileStack`.
%
% See also utils.stitch.moveInTileStack, utils.stitch.tileDrawOrder

layout = obj.stitching.layout;
positions = obj.stitching.positions;
if isempty(positions); positions = reshape([layout.nomOrigin], 3, []).'; end
tileSizes = reshape([layout.tileSize], 4, []).';

before = obj.currentTileStack();
after = utils.stitch.moveInTileStack(before, tileIdx, action, positions, tileSizes);
obj.stitching.tileStack = after;

obj.renderPairView();   % recolours the pair: the tile on top is magenta / red

position = find(after == tileIdx, 1);
message = sprintf('Tile %d is now %d of %d in the drawing order (%d = on top); Stitch keeps the tile on top where tiles overlap.', ...
    tileIdx, position, numel(after), numel(after));
blendMode = obj.stitching.BatchOpt.BlendMode{1};
if ~strcmp(blendMode, 'Overwrite')
    message = sprintf('%s The blend mode is %s, which mixes the tiles, so the order only takes effect with Overwrite.', ...
        message, blendMode);
end
obj.setStatus(message);
end
