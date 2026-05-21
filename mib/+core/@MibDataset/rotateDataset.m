function rotateDataset(obj, mode, parentFigure, showWaitbar)
% ROTATEDATASET - Rotate the dataset and all layers by 90 or -90 degrees.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.rotateDataset(mode, parentFigure, showWaitbar)
%
% Ported from MIB2 ``@mibModel/rotateDataset.m``.
%
% Input Arguments:
%   - **mode** — [char] rotation mode:
%
%     - ``'Rotate 90 degrees'`` — clockwise 90° rotation (height ↔ width swap)
%     - ``'Rotate -90 degrees'`` — counter-clockwise 90° rotation
%
%   - **parentFigure** *(optional)* — handle to the parent figure for the progress dialog;
%     pass ``[]`` to suppress the progress dialog
%   - **showWaitbar** *(optional)* — logical, ``true`` to show a progress dialog (default: ``true``)
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** — rotate 90° clockwise from a MibModel context
%
%   .. code-block:: matlab
%
%      id = obj.mibModel.getActiveId();
%      obj.mibModel.I{id}.rotateDataset('Rotate 90 degrees', obj.mibModel.mibGUI, true);
%

% Updates
%

if nargin < 4; showWaitbar = true; end
if nargin < 3; parentFigure = []; end

if showWaitbar && ~isempty(parentFigure)
    waitbar = uiprogressdlg(parentFigure, 'Value', 0, ...
        'Message', sprintf('Rotating image\nPlease wait...'), ...
        'Title', 'Rotate dataset');
else
    showWaitbar = false;
    waitbar = [];
end

height = obj.image.height;
width  = obj.image.width;
depth  = obj.image.depth;
colors = obj.image.colors;
timePoints = obj.image.time;

% Rotate image: [H,W,Z,C,T] → [W,H,Z,C,T]
% rot90 by k=3 gives 90° CW; k=1 gives 90° CCW.
imageData = obj.image.data{1};    % [H,W,Z,C,T]
imageOut = zeros([width, height, depth, colors, timePoints], obj.image.dataClass); %#ok<ZEROLIKE>
if strcmp(mode, 'Rotate 90 degrees')
    k = 3;   % 3×90° CCW = 90° CW
else
    k = 1;   % 1×90° CCW
end
for t = 1:timePoints
    for z = 1:depth
        for c = 1:colors
            imageOut(:,:,z,c,t) = rot90(imageData(:,:,z,c,t), k);
        end
    end
    if showWaitbar; waitbar.Value = t / timePoints * 0.5; end
end
obj.image.data{1} = imageOut;
clear imageData imageOut;

% Update image dimension properties (H↔W swapped)
obj.image.height = width;
obj.image.width  = height;
obj.image.dim_yxzct = [width, height, depth, colors, timePoints];

if showWaitbar; waitbar.Value = 0.5; end

% Rotate layers [H,W,Z,1,T] → [W,H,Z,1,T]
if isa(obj.labels, 'core.MibLabels63') && obj.enableSelection
    if showWaitbar; waitbar.Value = 0.6; waitbar.Message = sprintf('Rotating other layers\nPlease wait...'); end
    layerData = obj.labels.data{1};    % [H,W,Z,1,T]
    layerOut = zeros([width, height, depth, 1, timePoints], 'uint8');
    for t = 1:timePoints
        for z = 1:depth
            layerOut(:,:,z,1,t) = rot90(layerData(:,:,z,1,t), k);
        end
        if showWaitbar; waitbar.Value = 0.6 + t / timePoints * 0.4; end
    end
    obj.labels.data{1} = layerOut;
    updateLayerDims(obj.labels, width, height, depth, timePoints);
    clear layerData layerOut;
elseif obj.enableSelection
    % Selection layer
    layerData = obj.selection.data{1};
    layerOut = zeros([width, height, depth, 1, timePoints], 'uint8');
    for t = 1:timePoints
        for z = 1:depth
            layerOut(:,:,z,1,t) = rot90(layerData(:,:,z,1,t), k);
        end
    end
    obj.selection.data{1} = layerOut;
    updateLayerDims(obj.selection, width, height, depth, timePoints);
    clear layerData layerOut;
    if showWaitbar; waitbar.Value = 0.6; end

    if obj.maskExist
        layerData = obj.mask.data{1};
        layerOut = zeros([width, height, depth, 1, timePoints], 'uint8');
        for t = 1:timePoints
            for z = 1:depth
                layerOut(:,:,z,1,t) = rot90(layerData(:,:,z,1,t), k);
            end
        end
        obj.mask.data{1} = layerOut;
        updateLayerDims(obj.mask, width, height, depth, timePoints);
        clear layerData layerOut;
        if showWaitbar; waitbar.Value = 0.75; end
    end

    if obj.modelExist
        layerData = obj.labels.data{1};
        layerOut = zeros([width, height, depth, 1, timePoints], 'uint8');
        for t = 1:timePoints
            for z = 1:depth
                layerOut(:,:,z,1,t) = rot90(layerData(:,:,z,1,t), k);
            end
        end
        obj.labels.data{1} = layerOut;
        updateLayerDims(obj.labels, width, height, depth, timePoints);
        clear layerData layerOut;
    end
end

% Update MibDataset dim_yxzct
obj.dim_yxzct = obj.image.dim_yxzct;

% Swap pixSize.x and pixSize.y via MibDataset.setPixSize
pixSizeNew = obj.image.pixSize;
pixSizeNew.x = obj.image.pixSize.y;
pixSizeNew.y = obj.image.pixSize.x;
obj.setPixSize(pixSizeNew);

% Update bounding box: swap X and Y extents [xmin xmax ymin ymax zmin zmax]
bb = obj.image.boundingBox;
boundingBoxNew = [bb(3:4), bb(1:2), bb(5:6)];
obj.updateBoundingBox(boundingBoxNew);

if showWaitbar; waitbar.Value = 1; waitbar.Message = sprintf('Finishing...'); end
obj.image.updateActionLog(['Rotate: mode=' mode]);
if showWaitbar; delete(waitbar); end
end


function updateLayerDims(layer, newHeight, newWidth, newDepth, newTime)
% Update dimension properties on a layer object after its data{1} has been replaced.
layer.height = newHeight;
layer.width  = newWidth;
layer.depth  = newDepth;
layer.time   = newTime;
layer.dim_yxzct = [newHeight, newWidth, newDepth, 1, newTime];
end
