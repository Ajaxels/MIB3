function [dx, dy, rbMatrix] = applyExtendedMode(obj, id, depth, tformMatrix, ...
    rbMatrix, bgImage, pwb)
% APPLYEXTENDEDMODE - Warp image + service layers onto an enlarged canvas.
%
% Syntax:
%   .. code-block:: matlab
%
%      [dx, dy, rbMatrix] = applyExtendedMode(obj, id, depth, tformMatrix, ...
%                                              rbMatrix, bgImage, pwb)
%
% Private helper for the alignment algorithms. Warps every image slice
% (cubic, no ``OutputView`` so the canvas grows) into ``iMatrix{layer}``
% with a per-slice :class:`imref2d`, computes the union canvas, replaces
% ``obj.mibModel.I{id}.image.data{1}`` atomically with the assembled
% canvas (and syncs ``dim_yxzct`` / ``slices``), then warps + re-assembles
% every present service layer (labels / mask / selection, or packed
% ``everything`` for :class:`core.MibLabels63`) via
% :func:`assembleServiceCanvas`.
%
% Output Arguments:
%   - **dx**, **dy** — canvas offsets used to update the bounding box and
%     to relocate annotations. Returned empty when ``pwb`` was cancelled.
%   - **rbMatrix** — ``{depth, 1}`` cell of per-slice :class:`imref2d`
%     returned by ``imwarp`` (or an identity-anchored ``imref2d`` when the
%     slice carried no tform).

% Updates
%

dx = []; dy = [];
optionsGetData = struct('blockModeSwitch', 0);
ds       = obj.mibModel.I{id};
img5D    = ds.image;
nColors  = img5D.colors;
nTime    = img5D.time;
imgClass = class(img5D.data{1});
isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

% Step A: warp every slice. Slices without a tform reuse the original size
% with an identity-anchored rbMatrix.
iMatrix    = cell(depth, 1);
identityRb = imref2d([img5D.height, img5D.width]);
for layer = 1:depth
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.increment();
    end
    if ~isempty(tformMatrix{layer})
        slice2D = cell2mat(obj.mibModel.getData2D('image', layer, [], NaN, optionsGetData));
        [iMatrix{layer}, rbMatrix{layer}] = imwarp(slice2D, tformMatrix{layer}, 'cubic', ...
            'FillValues', double(bgImage));
    else
        iMatrix{layer}  = cell2mat(obj.mibModel.getData2D('image', layer, [], NaN, optionsGetData));
        rbMatrix{layer} = identityRb;
    end
end

% Step B: compute the union canvas
xmin = zeros(depth, 1);  xmax = zeros(depth, 1);
ymin = zeros(depth, 1);  ymax = zeros(depth, 1);
for layer = 1:depth
    xmin(layer) = floor(rbMatrix{layer}.XWorldLimits(1));
    xmax(layer) = floor(rbMatrix{layer}.XWorldLimits(2));
    ymin(layer) = floor(rbMatrix{layer}.YWorldLimits(1));
    ymax(layer) = floor(rbMatrix{layer}.YWorldLimits(2));
end
dx   = min(xmin);
dy   = min(ymin);
newW = max(xmax) - dx;
newH = max(ymax) - dy;

% Step C: assemble the new image canvas in MIB3 layout [h, w, d, c]
Iout = zeros(newH, newW, depth, nColors, imgClass) + cast(bgImage, imgClass);
for layer = 1:depth
    rbL = rbMatrix{layer};
    x1  = xmin(layer) - dx + 1;
    y1  = ymin(layer) - dy + 1;
    x2  = x1 + rbL.ImageSize(2) - 1;
    y2  = y1 + rbL.ImageSize(1) - 1;
    Iout(y1:y2, x1:x2, layer, :) = reshape(iMatrix{layer}, ...
        rbL.ImageSize(1), rbL.ImageSize(2), 1, nColors);
end
clear iMatrix;

% Step D: replace the image canvas (setData4D cannot grow data{1})
img5D.data{1}   = reshape(Iout, [newH, newW, depth, nColors, nTime]);
img5D.height    = newH;
img5D.width     = newW;
img5D.dim_yxzct = [newH, newW, depth, nColors, nTime];
clear Iout;

% Sync MibDataset metadata BEFORE any service-layer setData4D
ds.dim_yxzct = img5D.dim_yxzct;
oldSlices = ds.slices;
ds.slices{1} = [1, newH];
ds.slices{2} = [1, newW];
ds.slices{3} = 1:depth;
ds.slices{4} = [1, 1];
ds.slices{5} = [1, 1];
ds.slices{ds.orientation} = repmat(oldSlices{ds.orientation}(1), 1, 2);

% Step E: warp + assemble service layers
if isLabels63
    if ~isempty(pwb); pwb.updateText('Warping selection / mask / labels...'); end
    everythingOut = assembleServiceCanvas(obj, 'everything', tformMatrix, ...
        rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, 0);
    if isempty(everythingOut); return; end
    obj.mibModel.I{id}.labels.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
    obj.mibModel.I{id}.labels.height    = newH;
    obj.mibModel.I{id}.labels.width     = newW;
    obj.mibModel.I{id}.labels.depth     = depth;
    obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, depth, 1, nTime];
    obj.mibModel.setData4D(everythingOut, 'everything', [], 0);
else
    if obj.mibModel.I{id}.modelExist
        if ~isempty(pwb); pwb.updateText('Warping labels...'); end
        labelsOut = assembleServiceCanvas(obj, 'labels', tformMatrix, ...
            rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, NaN);
        if isempty(labelsOut); return; end
        obj.mibModel.I{id}.labels.data{1}  = zeros([newH, newW, depth, nTime], class(obj.mibModel.I{id}.labels.data{1}));
        obj.mibModel.I{id}.labels.height    = newH;
        obj.mibModel.I{id}.labels.width     = newW;
        obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(labelsOut, 'labels', [], NaN);
    end
    if obj.mibModel.I{id}.maskExist
        if ~isempty(pwb); pwb.updateText('Warping mask...'); end
        maskOut = assembleServiceCanvas(obj, 'mask', tformMatrix, ...
            rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, 0);
        if isempty(maskOut); return; end
        obj.mibModel.I{id}.mask.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
        obj.mibModel.I{id}.mask.height    = newH;
        obj.mibModel.I{id}.mask.width     = newW;
        obj.mibModel.I{id}.mask.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(maskOut, 'mask', [], 0);
    end
    if obj.mibModel.I{id}.enableSelection
        if ~isempty(pwb); pwb.updateText('Warping selection...'); end
        selOut = assembleServiceCanvas(obj, 'selection', tformMatrix, ...
            rbMatrix, xmin, ymin, dx, dy, newH, newW, depth, NaN);
        if isempty(selOut); return; end
        obj.mibModel.I{id}.selection.data{1}  = zeros([newH, newW, depth, nTime], 'uint8');
        obj.mibModel.I{id}.selection.height    = newH;
        obj.mibModel.I{id}.selection.width     = newW;
        obj.mibModel.I{id}.selection.dim_yxzct = [newH, newW, depth, 1, nTime];
        obj.mibModel.setData4D(selOut, 'selection', [], NaN);
    end
end
end
