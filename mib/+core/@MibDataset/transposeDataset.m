function transposeDataset(obj, mode, parentFigure, showWaitbar, noColorChannels)
% TRANSPOSEDATASET - Transpose the dataset between dimensions.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.transposeDataset(mode, parentFigure, showWaitbar)
%       obj.transposeDataset('Transpose Z<->C', parentFigure, showWaitbar, noColorChannels)
%
% Ported from MIB2 ``@mibModel/transposeDataset.m`` and ``@mibModel/transposeZ2T.m``.
%
% Input Arguments:
%   - **mode** — [char] transpose mode:
%
%     - ``'Transpose YX -> YZ'`` — YX plane becomes YZ plane
%     - ``'Transpose YX -> XZ'`` — YX plane becomes XZ plane
%     - ``'Transpose YX -> XY'`` — YX plane becomes XY plane
%     - ``'Transpose YX -> ZX'`` — YX plane becomes ZX plane
%     - ``'Transpose Z<->T'`` — swap Z (depth) and T (time) dimensions
%     - ``'Transpose Z<->C'`` — swap Z (depth) and C (color) dimensions
%
%   - **parentFigure** *(optional)* — handle to the parent figure for the progress dialog;
%     pass ``[]`` to suppress the progress dialog
%   - **showWaitbar** *(optional)* — logical, ``true`` to show a progress dialog (default: ``true``)
%   - **noColorChannels** *(optional)* — [numeric] for ``'Transpose Z<->C'`` only:
%     number of color channels in the output; pass ``NaN`` to use all Z-sections as channels
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** — transpose YX to YZ from a MibModel context
%
%   .. code-block:: matlab
%
%      id = obj.mibModel.getActiveId();
%      obj.mibModel.I{id}.transposeDataset('Transpose YX -> YZ', obj.mibModel.mibGUI, true);
%
%   **Example 2** — transpose Z to C with 3 output channels
%
%   .. code-block:: matlab
%
%      id = obj.mibModel.getActiveId();
%      obj.mibModel.I{id}.transposeDataset('Transpose Z<->C', obj.mibModel.mibGUI, true, 3);
%

% Updates
%

if nargin < 5; noColorChannels = NaN; end
if nargin < 4; showWaitbar = true; end
if nargin < 3; parentFigure = []; end

tic

height = obj.image.height;
width  = obj.image.width;
depth  = obj.image.depth;
colors = obj.image.colors;
timePoints = obj.image.time;

if showWaitbar && ~isempty(parentFigure)
    waitbar = uiprogressdlg(parentFigure, 'Value', 0, ...
        'Message', sprintf('Transposing dataset\nPlease wait...'), ...
        'Title', sprintf('Transpose dataset [%s]', mode));
else
    showWaitbar = false;
    waitbar = [];
end

% --- Transpose Z<->C ---
if strcmp(mode, 'Transpose Z<->C')
    if isnan(noColorChannels)
        colorsNew = depth;
        depthNew  = colors;
        logText = 'Transpose: mode=Z->C';
    else
        if colors > 1
            if showWaitbar; delete(waitbar); end
            utils.dlgs.showErrorDialog(parentFigure, ...
                sprintf('!!! Error !!!\n\nTransformation of Z to C works only with a single color channel before the transformation!'), ...
                'Wrong number of color channels');
            return;
        end
        colorsNew = noColorChannels;
        depthNew  = depth / noColorChannels;
        logText = sprintf('Transpose: mode=Z->C; ColChNo=%d', noColorChannels);
    end
    if mod(depthNew, 1) ~= 0
        if showWaitbar; delete(waitbar); end
        utils.dlgs.showErrorDialog(parentFigure, ...
            'Division of Z by C should give a round number!', ...
            'Wrong number of resulting color channels');
        return;
    end

    if showWaitbar; waitbar.Value = 0.05; end

    viewPortOld = obj.image.viewPort;
    imageData = obj.image.data{1};    % [H,W,Z,C,T]
    imageOut = zeros([height, width, depthNew, colorsNew, timePoints], obj.image.dataClass); %#ok<ZEROLIKE>

    for t = 1:timePoints
        img = imageData(:,:,:,:,t);   % [H,W,Z,C]
        if isnan(noColorChannels)
            % Simple case: permute Z↔C.  [H,W,Z,C] → [H,W,C,Z] = new [H,W,Z',C']
            imageOut(:,:,:,:,t) = permute(img, [1, 2, 4, 3]);
        else
            % Repack Z-slices into color channels
            for z = 1:depth
                imageOut(:,:, ceil(z/noColorChannels), mod(z-1, noColorChannels)+1, t) = img(:,:,z,1);
            end
        end
        if showWaitbar; waitbar.Value = 0.05 + t / timePoints * 0.5; end
    end

    % Replace image data and update dimension properties
    obj.image.data{1} = imageOut;
    obj.image.height  = height;
    obj.image.width   = width;
    obj.image.depth   = depthNew;
    obj.image.colors  = colorsNew;
    obj.image.time    = timePoints;
    obj.image.dim_yxzct = [height, width, depthNew, colorsNew, timePoints];
    if colorsNew > 1
        obj.image.colorType = 'multichannel';
    else
        obj.image.colorType = 'grayscale';
    end

    % Restore/extend viewPort for new number of color channels
    if colorsNew < colors
        obj.image.viewPort.min   = viewPortOld.min(1:colorsNew);
        obj.image.viewPort.max   = viewPortOld.max(1:colorsNew);
        obj.image.viewPort.gamma = viewPortOld.gamma(1:colorsNew);
    else
        obj.image.viewPort.min   = repmat(viewPortOld.min(1),   [colorsNew, 1]);
        obj.image.viewPort.max   = repmat(viewPortOld.max(1),   [colorsNew, 1]);
        obj.image.viewPort.gamma = repmat(viewPortOld.gamma(1), [colorsNew, 1]);
    end
    clear imageData imageOut;

    % Clear labels/mask/selection — dimensions are now inconsistent with new Z
    obj.labels.data{1} = zeros([height, width, depthNew, 1, timePoints], 'uint8');
    updateLayerDims(obj.labels, height, width, depthNew, timePoints);
    obj.modelExist = false;
    if ~isa(obj.labels, 'core.MibLabels63')
        obj.mask.data{1} = zeros([height, width, depthNew, 1, timePoints], 'uint8');
        updateLayerDims(obj.mask, height, width, depthNew, timePoints);
        obj.maskExist = false;
        obj.selection.data{1} = zeros([height, width, depthNew, 1, timePoints], 'uint8');
        updateLayerDims(obj.selection, height, width, depthNew, timePoints);
    end

    obj.dim_yxzct = obj.image.dim_yxzct;
    if showWaitbar; waitbar.Value = 1; waitbar.Message = sprintf('Finishing...'); end
    obj.image.updateActionLog(logText);
    if showWaitbar; delete(waitbar); end
    toc;
    return;
end

% --- Transpose Z<->T ---
if strcmp(mode, 'Transpose Z<->T')
    if showWaitbar; waitbar.Value = 0.1; end
    % Image [H,W,Z,C,T]: swap Z(dim3)↔T(dim5) → [H,W,T,C,Z] = new [H,W,Z',C,T']
    obj.image.data{1} = permute(obj.image.data{1}, [1,2,5,4,3]);
    obj.image.depth = timePoints;
    obj.image.time  = depth;
    obj.image.dim_yxzct = [height, width, timePoints, colors, depth];
    if showWaitbar; waitbar.Value = 0.4; end

    % Layers [H,W,Z,1,T]: swap Z(dim3)↔T(dim5) → [H,W,T,1,Z]
    if isa(obj.labels, 'core.MibLabels63') && obj.enableSelection
        if showWaitbar; waitbar.Value = 0.5; waitbar.Message = sprintf('Transposing other layers\nPlease wait...'); end
        obj.labels.data{1} = permute(obj.labels.data{1}, [1,2,5,4,3]);
        updateLayerDims(obj.labels, height, width, timePoints, depth);
    elseif obj.enableSelection
        obj.selection.data{1} = permute(obj.selection.data{1}, [1,2,5,4,3]);
        updateLayerDims(obj.selection, height, width, timePoints, depth);
        if showWaitbar; waitbar.Value = 0.6; end
        if obj.maskExist
            obj.mask.data{1} = permute(obj.mask.data{1}, [1,2,5,4,3]);
            updateLayerDims(obj.mask, height, width, timePoints, depth);
            if showWaitbar; waitbar.Value = 0.75; end
        end
        if obj.modelExist
            obj.labels.data{1} = permute(obj.labels.data{1}, [1,2,5,4,3]);
            updateLayerDims(obj.labels, height, width, timePoints, depth);
        end
    end

    obj.dim_yxzct = obj.image.dim_yxzct;
    if showWaitbar; waitbar.Value = 1; waitbar.Message = sprintf('Finishing...'); end
    obj.image.updateActionLog('Transpose: mode=Z->T');
    if showWaitbar; delete(waitbar); end
    toc;
    return;
end

% --- Orientation transpose: YX->YZ / YX->XZ / YX->XY / YX->ZX ---
% Image layout: [H,W,Z,C,T].  Layers: [H,W,Z,1,T].
% Permute indices for image (5D) and layers (5D, C=1 so same indices work):
%   YX->YZ: new=[H, Z, W, C, T] = permute([1,3,2,4,5])  → new H'=H, W'=Z, Z'=W
%   YX->XZ: new=[W, Z, H, C, T] = permute([2,3,1,4,5])  → new H'=W, W'=Z, Z'=H
%   YX->XY: new=[W, H, Z, C, T] = permute([2,1,3,4,5])  → new H'=W, W'=H, Z'=Z
%   YX->ZX: new=[Z, W, H, C, T] = permute([3,2,1,4,5])  → new H'=Z, W'=W, Z'=H

switch mode
    case 'Transpose YX -> YZ'
        perm = [1,3,2,4,5];
        newH = height; newW = depth;  newZ = width;
        pixSizeNew.x = obj.image.pixSize.z;
        pixSizeNew.y = obj.image.pixSize.y;
        pixSizeNew.z = obj.image.pixSize.x;
        bb = obj.image.boundingBox;    % [xmin xmax ymin ymax zmin zmax]
        bbNew = [bb(5:6), bb(3:4), bb(1:2)];
    case 'Transpose YX -> XZ'
        perm = [2,3,1,4,5];
        newH = width; newW = depth;  newZ = height;
        pixSizeNew.x = obj.image.pixSize.z;
        pixSizeNew.y = obj.image.pixSize.x;
        pixSizeNew.z = obj.image.pixSize.y;
        bb = obj.image.boundingBox;
        bbNew = [bb(5:6), bb(1:2), bb(3:4)];
    case 'Transpose YX -> XY'
        perm = [2,1,3,4,5];
        newH = width; newW = height; newZ = depth;
        pixSizeNew.x = obj.image.pixSize.y;
        pixSizeNew.y = obj.image.pixSize.x;
        pixSizeNew.z = obj.image.pixSize.z;
        bb = obj.image.boundingBox;
        bbNew = [bb(3:4), bb(1:2), bb(5:6)];
    case 'Transpose YX -> ZX'
        perm = [3,2,1,4,5];
        newH = depth; newW = width;  newZ = height;
        pixSizeNew.x = obj.image.pixSize.x;
        pixSizeNew.y = obj.image.pixSize.z;
        pixSizeNew.z = obj.image.pixSize.y;
        bb = obj.image.boundingBox;
        bbNew = [bb(1:2), bb(5:6), bb(3:4)];
    otherwise
        if showWaitbar; delete(waitbar); end
        error('MibDataset:transposeDataset', 'Unknown mode: %s', mode);
end

% Copy non-spatial pixSize fields
pixSizeNew.t      = obj.image.pixSize.t;
pixSizeNew.units  = obj.image.pixSize.units;
pixSizeNew.tunits = obj.image.pixSize.tunits;

% Permute image
obj.image.data{1} = permute(obj.image.data{1}, perm);
obj.image.height  = newH;
obj.image.width   = newW;
obj.image.depth   = newZ;
obj.image.dim_yxzct = [newH, newW, newZ, colors, timePoints];
if showWaitbar; waitbar.Value = 0.5; end

% Permute layers
if isa(obj.labels, 'core.MibLabels63') && obj.enableSelection
    if showWaitbar; waitbar.Value = 0.6; waitbar.Message = sprintf('Transposing other layers\nPlease wait...'); end
    obj.labels.data{1} = permute(obj.labels.data{1}, perm);
    updateLayerDims(obj.labels, newH, newW, newZ, timePoints);
elseif obj.enableSelection
    obj.selection.data{1} = permute(obj.selection.data{1}, perm);
    updateLayerDims(obj.selection, newH, newW, newZ, timePoints);
    if showWaitbar; waitbar.Value = 0.65; end
    if obj.maskExist
        obj.mask.data{1} = permute(obj.mask.data{1}, perm);
        updateLayerDims(obj.mask, newH, newW, newZ, timePoints);
        if showWaitbar; waitbar.Value = 0.8; end
    end
    if obj.modelExist
        obj.labels.data{1} = permute(obj.labels.data{1}, perm);
        updateLayerDims(obj.labels, newH, newW, newZ, timePoints);
    end
end

obj.dim_yxzct = obj.image.dim_yxzct;

% Update pixSize via MibDataset.setPixSize (propagates to all layers)
obj.setPixSize(pixSizeNew);

% Update bounding box
obj.updateBoundingBox(bbNew);

if showWaitbar; waitbar.Value = 1; waitbar.Message = sprintf('Finishing...'); end
obj.image.updateActionLog(['Transpose: mode=' mode]);
if showWaitbar; delete(waitbar); end
toc;
end


function updateLayerDims(layer, newH, newW, newZ, newT)
% Update dimension properties on a layer (MibLabels/MibLabels63/MibImage subclass)
% after its data{1} has been replaced.
layer.height = newH;
layer.width  = newW;
layer.depth  = newZ;
layer.time   = newT;
layer.dim_yxzct = [newH, newW, newZ, 1, newT];
end
