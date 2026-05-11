function relocateAnnotations(obj, id, depth, tformMatrix, rbMatrix, ...
    isCropped, dxCanvas, dyCanvas)
% RELOCATEANNOTATIONS - Move annotation labels through the per-slice warps.
%
% Syntax:
%   .. code-block:: matlab
%
%      relocateAnnotations(obj, id, depth, tformMatrix, rbMatrix, ...
%          isCropped, dxCanvas, dyCanvas)
%
% Private helper for the alignment algorithms. For each slice that has a
% non-empty ``tformMatrix{layer}`` entry, applies
% :func:`transformPointsForward` to the annotation ``[x, y]`` columns; in
% **extended** mode additionally shifts positions by the canvas offset
% (``dxCanvas`` / ``dyCanvas``) so annotations follow the assembled
% image. In **cropped** mode slices without a tform are skipped; in
% **extended** mode their annotations are still shifted by the per-slice
% canvas offset derived from ``rbMatrix{layer}``.

% Updates
%

for layer = 1:depth
    [labelsList, labelValues, labelPositions, indices] = obj.mibModel.I{id}.getSliceLabels(layer);
    if isempty(labelsList); continue; end
    if isempty(tformMatrix{layer})
        if isCropped
            continue;                    % cropped + no tform = identity
        end
        rbL = rbMatrix{layer};
        x1  = floor(rbL.XWorldLimits(1)) - dxCanvas + 1;
        y1  = floor(rbL.YWorldLimits(1)) - dyCanvas + 1;
        labelPositions(:,2) = labelPositions(:,2) + x1 - 1;
        labelPositions(:,3) = labelPositions(:,3) + y1 - 1;
    else
        [labelPositions(:,2), labelPositions(:,3)] = transformPointsForward( ...
            tformMatrix{layer}, labelPositions(:,2), labelPositions(:,3));
        if ~isCropped
            labelPositions(:,2) = labelPositions(:,2) - dxCanvas - 1;
            labelPositions(:,3) = labelPositions(:,3) - dyCanvas - 1;
        end
    end
    obj.mibModel.I{id}.annotations.updateLabels(indices, labelsList, labelPositions, labelValues);
end
end
