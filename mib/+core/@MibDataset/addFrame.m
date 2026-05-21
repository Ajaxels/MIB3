function addFrame(obj, BatchOpt, parentFigure)
% ADDFRAME - Add a frame around the dataset using dX/dY padding.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.addFrame(BatchOpt, parentFigure)
%
% Ported from MIB2 ``@mibModel/addFrame.m``.
%
% Input Arguments:
%   - **BatchOpt** — [struct] parameters for the frame operation:
%
%     - ``.FrameWidth`` — [numeric cell] frame width in pixels (may be negative to trim);
%       ``{1}`` value, ``{2}`` limits ``[-Inf, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.FrameHeight`` — [numeric cell] frame height in pixels (may be negative to trim);
%       ``{1}`` value, ``{2}`` limits ``[-Inf, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.IntensityPadValue`` — [numeric cell] fill intensity when method is ``'use the pad value'``;
%       ``{1}`` value, ``{2}`` limits ``[0, Inf]``, ``{3}`` ``'off'``
%     - ``.Method`` — [cell] one of:
%       ``{'use the pad value'}``, ``{'replicate'}``, ``{'circular'}``, ``{'symmetric'}``
%     - ``.Direction`` — [cell] one of: ``{'both'}``, ``{'pre'}``, ``{'post'}``
%     - ``.showWaitbar`` — [logical] show progress dialog (default: ``true``)
%
%   - **parentFigure** *(optional)* — handle to the parent figure for the progress dialog;
%     pass ``[]`` to suppress the progress dialog
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** — add a 10-pixel symmetric frame
%
%   .. code-block:: matlab
%
%      BatchOpt.FrameWidth = '10';
%      BatchOpt.FrameHeight = '10';
%      BatchOpt.IntensityPadValue = '0';
%      BatchOpt.Method = {'use the pad value'};
%      BatchOpt.Direction = {'both'};
%      BatchOpt.showWaitbar = true;
%      obj.mibModel.I{id}.addFrame(BatchOpt, obj.mibModel.mibGUI);
%

% Updates
%

if nargin < 3; parentFigure = []; end

tic

height     = obj.image.height;
width      = obj.image.width;
depth      = obj.image.depth;
colors     = obj.image.colors;
timePoints = obj.image.time;

padValue  = BatchOpt.IntensityPadValue{1};
direction = BatchOpt.Direction{1};
method    = BatchOpt.Method{1};
extW      = BatchOpt.FrameWidth{1};
extH      = BatchOpt.FrameHeight{1};

if strcmp(direction, 'both')
    newH = height + extH * 2;
    newW = width  + extW * 2;
else
    newH = height + extH;
    newW = width  + extW;
end

if BatchOpt.showWaitbar && ~isempty(parentFigure)
    waitbar = uiprogressdlg(parentFigure, 'Value', 0, ...
        'Message', sprintf('Adding a frame to the image\nPlease wait...'), ...
        'Title', 'Add frame');
else
    waitbar = [];
end

% Process image layer [H,W,Z,C,T]
imageData = obj.image.data{1};
imageOut  = zeros([newH, newW, depth, colors, timePoints], obj.image.dataClass); %#ok<ZEROLIKE>
for t = 1:timePoints
    img = imageData(:,:,:,:,t);   % [H,W,Z,C]
    if extW >= 0 && extH >= 0
        if strcmp(method, 'use the pad value')
            imageOut(:,:,:,:,t) = padarray(img, [extH, extW], padValue, direction);
        else
            imageOut(:,:,:,:,t) = padarray(img, [extH, extW], method, direction);
        end
    else
        imageOut(:,:,:,:,t) = img(-extH+1:end+extH, -extW+1:end+extW, :, :);
    end
    if ~isempty(waitbar); waitbar.Value = t / timePoints * 0.5; end
end
obj.image.data{1} = imageOut;
clear imageData imageOut;

% Process layers [H,W,Z,1,T]
if isa(obj.labels, 'core.MibLabels63') && obj.enableSelection
    if ~isempty(waitbar); waitbar.Value = 0.5; waitbar.Message = sprintf('Adding a frame to other layers\nPlease wait...'); end
    if ~isnan(obj.labels.data{1}(1))
        layerData = obj.labels.data{1};
        layerOut  = zeros([newH, newW, depth, 1, timePoints], 'uint8');
        for t = 1:timePoints
            slice = layerData(:,:,:,1,t);   % [H,W,Z]
            if extW >= 0 && extH >= 0
                if strcmp(method, 'use the pad value')
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], 0, direction);
                else
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], method, direction);
                end
            else
                layerOut(:,:,:,1,t) = slice(-extH+1:end+extH, -extW+1:end+extW, :);
            end
            if ~isempty(waitbar); waitbar.Value = 0.5 + t / timePoints * 0.5; end
        end
        obj.labels.data{1} = layerOut;
        updateLayerDims(obj.labels, newH, newW, depth, timePoints);
        clear layerData layerOut;
    end
else
    if obj.enableSelection
        if ~isempty(waitbar); waitbar.Value = 0.55; waitbar.Message = sprintf('Adding a frame to the selection layer\nPlease wait...'); end
        layerData = obj.selection.data{1};
        layerOut  = zeros([newH, newW, depth, 1, timePoints], 'uint8');
        for t = 1:timePoints
            slice = layerData(:,:,:,1,t);
            if extW >= 0 && extH >= 0
                if strcmp(method, 'use the pad value')
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], 0, direction);
                else
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], method, direction);
                end
            else
                layerOut(:,:,:,1,t) = slice(-extH+1:end+extH, -extW+1:end+extW, :);
            end
        end
        obj.selection.data{1} = layerOut;
        updateLayerDims(obj.selection, newH, newW, depth, timePoints);
        clear layerData layerOut;
        if ~isempty(waitbar); waitbar.Value = 0.65; end
    end

    if obj.maskExist
        if ~isempty(waitbar); waitbar.Value = 0.65; waitbar.Message = sprintf('Adding a frame to the mask layer\nPlease wait...'); end
        layerData = obj.mask.data{1};
        layerOut  = zeros([newH, newW, depth, 1, timePoints], 'uint8');
        for t = 1:timePoints
            slice = layerData(:,:,:,1,t);
            if extW >= 0 && extH >= 0
                if strcmp(method, 'use the pad value')
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], 0, direction);
                else
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], method, direction);
                end
            else
                layerOut(:,:,:,1,t) = slice(-extH+1:end+extH, -extW+1:end+extW, :);
            end
        end
        obj.mask.data{1} = layerOut;
        updateLayerDims(obj.mask, newH, newW, depth, timePoints);
        clear layerData layerOut;
        if ~isempty(waitbar); waitbar.Value = 0.8; end
    end

    if obj.modelExist
        if ~isempty(waitbar); waitbar.Value = 0.8; waitbar.Message = sprintf('Adding a frame to the labels layer\nPlease wait...'); end
        layerData = obj.labels.data{1};
        layerOut  = zeros([newH, newW, depth, 1, timePoints], 'uint8');
        for t = 1:timePoints
            slice = layerData(:,:,:,1,t);
            if extW >= 0 && extH >= 0
                if strcmp(method, 'use the pad value')
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], 0, direction);
                else
                    layerOut(:,:,:,1,t) = padarray(slice, [extH, extW], method, direction);
                end
            else
                layerOut(:,:,:,1,t) = slice(-extH+1:end+extH, -extW+1:end+extW, :);
            end
        end
        obj.labels.data{1} = layerOut;
        updateLayerDims(obj.labels, newH, newW, depth, timePoints);
        clear layerData layerOut;
    end
end

if ~isempty(waitbar); waitbar.Value = 0.9; waitbar.Message = sprintf('Finishing...'); end

% Update image dimension properties
obj.image.height = newH;
obj.image.width  = newW;
obj.image.dim_yxzct = [newH, newW, depth, colors, timePoints];
obj.dim_yxzct = obj.image.dim_yxzct;

% Update bounding box
bb = obj.image.boundingBox;
switch direction
    case 'both'
        bbNew = [bb(1) - extW * obj.image.pixSize.x, ...
                 bb(2) + extW * obj.image.pixSize.x, ...
                 bb(3) - extH * obj.image.pixSize.y, ...
                 bb(4) + extH * obj.image.pixSize.y, ...
                 bb(5:6)];
    case 'pre'
        bbNew = [bb(1) - extW * obj.image.pixSize.x, ...
                 bb(2), ...
                 bb(3) - extH * obj.image.pixSize.y, ...
                 bb(4:6)];
    case 'post'
        bbNew = [bb(1), ...
                 bb(2) + extW * obj.image.pixSize.x, ...
                 bb(3), ...
                 bb(4) + extH * obj.image.pixSize.y, ...
                 bb(5:6)];
end
obj.updateBoundingBox(bbNew);

% Update ROI and annotation coordinates
cropFactor = [-extW+1, -extH+1, NaN, NaN, 1, NaN, 1, NaN];
obj.hROI.crop(cropFactor);
obj.annotations.crop(cropFactor);
obj.measure.crop(cropFactor);

if strcmp(method, 'use the pad value')
    logText = sprintf('Add frame: dX=%d, dY=%d, padValue=%d, direction=%s', extW, extH, padValue, direction);
else
    logText = sprintf('Add frame: dX=%d, dY=%d, method=%s, direction=%s', extW, extH, method, direction);
end
obj.image.updateActionLog(logText);
if ~isempty(waitbar); delete(waitbar); end
toc;
end


function updateLayerDims(layer, newH, newW, newZ, newT)
% Update dimension properties on a layer after data{1} has been replaced.
layer.height = newH;
layer.width  = newW;
layer.depth  = newZ;
layer.time   = newT;
layer.dim_yxzct = [newH, newW, newZ, 1, newT];
end
