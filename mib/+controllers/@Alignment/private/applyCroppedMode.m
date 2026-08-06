function applyCroppedMode(obj, id, depth, tformMatrix, refImgSize, bgImage, pwb)
% APPLYCROPPEDMODE - Warp image + service layers in place on the original canvas.
%
% Syntax:
%   .. code-block:: matlab
%
%      applyCroppedMode(obj, id, depth, tformMatrix, refImgSize, bgImage, pwb)
%
% Private helper for the alignment algorithms. Walks slices 2..depth, warps
% the image (cubic) and every present service layer (labels / mask /
% selection, or packed ``everything`` for :class:`core.MibLabels63`) with
% nearest-neighbour, and writes each warped slice back via
% :meth:`models.MibModel.setData2D`. Slices with an empty ``tformMatrix{layer}``
% entry are skipped. The original canvas size (``refImgSize``) is preserved.
%
% Input Arguments:
%   - **obj** - :class:`controllers.Alignment` instance.
%   - **id** - [scalar] dataset index in ``obj.mibModel.I``.
%   - **depth** - [scalar] number of slices.
%   - **tformMatrix** - ``{depth, 1}`` cell of 2-D geometric transforms.
%   - **refImgSize** - :class:`imref2d` for ``imwarp`` ``'OutputView'``.
%   - **bgImage** - [numeric] fill value for image warp; service layers
%     always fill with 0.
%   - **pwb** - :class:`core.PoolWaitbar` or ``[]`` to disable progress.

% Updates
%

optionsGetData = struct('blockModeSwitch', 0);
isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

if ~isempty(pwb)
    pwbIncrement = max([1 floor(depth/10)]);
    pwb.updateMaxNumberOfIterations(depth);
    pwb.setCurrentIteration(0);
    pwb.setIncrement(pwbIncrement);
end

for layer = 2:depth
    if ~isempty(pwb)
        %if pwb.getCancelState(); return; end
        if mod(layer, pwbIncrement)==0; pwb.increment(); end
    end
    if isempty(tformMatrix{layer}); continue; end

    slice2D = cell2mat(obj.mibModel.getData2D('image', layer, [], NaN, optionsGetData));
    warped  = imwarp(slice2D, tformMatrix{layer}, 'cubic', ...
        'OutputView', refImgSize, 'FillValues', double(bgImage));
    obj.mibModel.setData2D(warped, 'image', layer, [], NaN, optionsGetData);

    if isLabels63
        layerData = cell2mat(obj.mibModel.getData2D('everything', layer, [], 0, optionsGetData));
        layerData = imwarp(layerData, tformMatrix{layer}, 'nearest', ...
            'OutputView', refImgSize, 'FillValues', 0);
        obj.mibModel.setData2D(layerData, 'everything', layer, [], 0, optionsGetData);
    else
        if obj.mibModel.I{id}.modelExist
            lab = cell2mat(obj.mibModel.getData2D('labels', layer, [], NaN, optionsGetData));
            lab = imwarp(lab, tformMatrix{layer}, 'nearest', ...
                'OutputView', refImgSize, 'FillValues', 0);
            obj.mibModel.setData2D(lab, 'labels', layer, [], NaN, optionsGetData);
        end
        if obj.mibModel.I{id}.maskExist
            mk = cell2mat(obj.mibModel.getData2D('mask', layer, [], 0, optionsGetData));
            mk = imwarp(mk, tformMatrix{layer}, 'nearest', ...
                'OutputView', refImgSize, 'FillValues', 0);
            obj.mibModel.setData2D(mk, 'mask', layer, [], 0, optionsGetData);
        end
        if obj.mibModel.I{id}.enableSelection
            sel = cell2mat(obj.mibModel.getData2D('selection', layer, [], NaN, optionsGetData));
            sel = imwarp(sel, tformMatrix{layer}, 'nearest', ...
                'OutputView', refImgSize, 'FillValues', 0);
            obj.mibModel.setData2D(sel, 'selection', layer, [], NaN, optionsGetData);
        end
    end
end
end
