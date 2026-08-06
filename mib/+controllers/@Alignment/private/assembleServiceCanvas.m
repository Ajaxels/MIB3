function out3D = assembleServiceCanvas(obj, layerType, tformMatrix, ...
    rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, colArg)
% ASSEMBLESERVICECANVAS - Warp + tile a service layer onto an enlarged canvas.
%
% Syntax:
%   .. code-block:: matlab
%
%      out3D = assembleServiceCanvas(obj, layerType, tformMatrix, ...
%          rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, colArg)
%
% Private helper for :func:`applyExtendedMode`. Reads ``layerType`` for
% every slice in one shot via :meth:`models.MibModel.getData4D`, warps
% each slice with nearest neighbour, and places the result at the
% per-slice offset on the new ``[newH, newW, depth]`` canvas.
%
% Input Arguments:
%   - **layerType** - [char] one of ``'labels'``, ``'mask'``,
%     ``'selection'``, or ``'everything'``.
%   - **colArg** - color-channel argument forwarded to
%     :meth:`models.MibModel.getData4D` (``NaN`` for labels/selection,
%     ``0`` for mask/everything).

% Updates
%

src = obj.mibModel.getData4D(layerType, [], colArg);
src = squeeze(cell2mat(src));            % [H, W, Z] (single time-point)
out3D = zeros(newH, newW, depth, class(src));
for layer = 1:depth
    if ~isempty(tformMatrix{layer})
        warped = imwarp(src(:,:,layer), tformMatrix{layer}, 'nearest', 'FillValues', 0);
    else
        warped = src(:,:,layer);
    end
    rbL = rbMatrix{layer};
    x1  = xmin(layer) - dx + 1;
    y1  = ymin(layer) - dy + 1;
    x2  = x1 + rbL.ImageSize(2) - 1;
    y2  = y1 + rbL.ImageSize(1) - 1;
    out3D(y1:y2, x1:x2, layer) = warped;
end
end
