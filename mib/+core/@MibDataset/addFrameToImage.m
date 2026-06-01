function addFrameToImage(obj, BatchOpt, parentFigure)
% ADDFRAMETOIMAGE - Add a frame to the dataset by specifying new absolute width and height.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.addFrameToImage(BatchOpt, parentFigure)
%
% Ported from MIB2 ``@mibImage/addFrameToImage.m``.
%
% Input Arguments:
%   - **BatchOpt** — [struct] parameters for the frame operation:
%
%     - ``.Position`` — [cell] one of:
%       ``{'Center'}``, ``{'Left-upper corner'}``, ``{'Center-top'}``,
%       ``{'Right-upper corner'}``, ``{'Left-bottom corner'}``,
%       ``{'Center-bottom'}``, ``{'Right-bottom corner'}``
%     - ``.NewImageWidth`` — [numeric cell] new image width in pixels;
%       ``{1}`` value, ``{2}`` limits ``[1, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.NewImageHeight`` — [numeric cell] new image height in pixels;
%       ``{1}`` value, ``{2}`` limits ``[1, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.FrameColorIntensity`` — [numeric cell] fill intensity for the frame pixels;
%       ``{1}`` value, ``{2}`` limits ``[0, Inf]``, ``{3}`` ``'off'``
%     - ``.showWaitbar`` — [logical] show progress dialog (default: ``true``)
%
%   - **parentFigure** *(optional)* — handle to the parent figure for the progress dialog;
%     pass ``[]`` to suppress the progress dialog
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** — add a frame centering the image in 600×500
%
%   .. code-block:: matlab
%
%      BatchOpt.Position = {'Center'};
%      BatchOpt.NewImageWidth = '600';
%      BatchOpt.NewImageHeight = '500';
%      BatchOpt.FrameColorIntensity = '0';
%      BatchOpt.showWaitbar = true;
%      obj.mibModel.I{id}.addFrameToImage(BatchOpt, obj.mibModel.mibGUI);
%

% Updates
%

if nargin < 3; parentFigure = []; end

height     = obj.image.height;
width      = obj.image.width;
depth      = obj.image.depth;
colors     = obj.image.colors;
timePoints = obj.image.time;

newWidth   = BatchOpt.NewImageWidth{1};
newHeight  = BatchOpt.NewImageHeight{1};
frameColor = min(max(BatchOpt.FrameColorIntensity{1}, 0), obj.image.maxInt);

if newWidth < width || newHeight < height
    utils.dlgs.showErrorDialog(parentFigure, sprintf('The new width and height should be larger than the current width and height!'), 'Wrong dimensions');
    return;
end

switch BatchOpt.Position{1}
    case 'Center'
        leftFrame   = round((newWidth  - width)  / 2);
        rightFrame  = newWidth  - width  - leftFrame;
        topFrame    = round((newHeight - height) / 2);
        bottomFrame = newHeight - height - topFrame;
    case 'Left-upper corner'
        leftFrame = 0; rightFrame = newWidth - width;
        topFrame  = 0; bottomFrame = newHeight - height;
    case 'Center-top'
        leftFrame   = floor((newWidth - width) / 2);
        rightFrame  = newWidth - leftFrame - width;
        topFrame    = 0; bottomFrame = newHeight - height;
    case 'Right-upper corner'
        leftFrame = newWidth - width;  rightFrame  = 0;
        topFrame  = 0;                 bottomFrame = newHeight - height;
    case 'Left-bottom corner'
        leftFrame = 0;                 rightFrame  = newWidth - width;
        topFrame  = newHeight - height; bottomFrame = 0;
    case 'Center-bottom'
        leftFrame   = floor((newWidth - width) / 2);
        rightFrame  = newWidth - leftFrame - width;
        topFrame    = newHeight - height;  bottomFrame = 0;
    case 'Right-bottom corner'
        leftFrame = newWidth - width;  rightFrame  = 0;
        topFrame  = newHeight - height; bottomFrame = 0;
    otherwise
        leftFrame = 0; rightFrame = 0; topFrame = 0; bottomFrame = 0;
end

newWidth  = width  + leftFrame + rightFrame;
newHeight = height + topFrame  + bottomFrame;
x1 = leftFrame + 1;
x2 = newWidth  - rightFrame;
y1 = topFrame  + 1;
y2 = newHeight - bottomFrame;

if BatchOpt.showWaitbar && ~isempty(parentFigure)
    waitbar = uiprogressdlg(parentFigure, 'Value', 0, ...
        'Message', sprintf('Adding a frame to the image\nPlease wait...'), ...
        'Title', 'Add frame to image', 'Indeterminate', 'on');
else
    waitbar = [];
end

% Resize image layer: [H,W,Z,C,T]
imageData = obj.image.data;
newImageData = zeros([newHeight, newWidth, depth, colors, timePoints], obj.image.dataClass) + cast(frameColor, obj.image.dataClass); %#ok<ZEROLIKE>
newImageData(y1:y2, x1:x2, :, :, :) = imageData;
obj.image.data = newImageData;
clear imageData newImageData;

% Resize label/mask/selection layers: [H,W,Z,1,T]
if isa(obj.labels, 'core.MibLabels63') && obj.enableSelection
    % For MibLabels63 mask+selection+labels are packed in obj.labels.data
    if ~isnan(obj.labels.data(1))
        layerData = obj.labels.data;
        newLayerData = zeros([newHeight, newWidth, depth, 1, timePoints], 'uint8');
        newLayerData(y1:y2, x1:x2, :, :, :) = layerData;
        obj.labels.data = newLayerData;
        updateLayerDims(obj.labels, newHeight, newWidth, depth, timePoints);
        clear layerData newLayerData;
    end
else
    if obj.modelExist
        layerData = obj.labels.data;
        newLayerData = zeros([newHeight, newWidth, depth, 1, timePoints], 'uint8');
        newLayerData(y1:y2, x1:x2, :, :, :) = layerData;
        obj.labels.data = newLayerData;
        updateLayerDims(obj.labels, newHeight, newWidth, depth, timePoints);
        clear layerData newLayerData;
    end
    
    if obj.maskExist
        layerData = obj.mask.data;
        newLayerData = zeros([newHeight, newWidth, depth, 1, timePoints], 'uint8');
        newLayerData(y1:y2, x1:x2, :, :, :) = layerData;
        obj.mask.data = newLayerData;
        updateLayerDims(obj.mask, newHeight, newWidth, depth, timePoints);
        clear layerData newLayerData;
    end

    if obj.enableSelection
        layerData = obj.selection.data;
        newLayerData = zeros([newHeight, newWidth, depth, 1, timePoints], 'uint8');
        newLayerData(y1:y2, x1:x2, :, :, :) = layerData;
        obj.selection.data = newLayerData;
        updateLayerDims(obj.selection, newHeight, newWidth, depth, timePoints);
        clear layerData newLayerData;
    end
end

% Update image dimension properties
obj.image.height = newHeight;
obj.image.width  = newWidth;
obj.image.dim_yxzct = [newHeight, newWidth, depth, colors, timePoints];
obj.dim_yxzct = obj.image.dim_yxzct;

% Cap current_yxz to new dimensions
if obj.image.height < obj.current_yxz(1); obj.current_yxz(1) = obj.image.height; end
if obj.image.width  < obj.current_yxz(2); obj.current_yxz(2) = obj.image.width;  end

% Update slices to reflect new H and W
obj.slices{1} = [1, newHeight];
obj.slices{2} = [1, newWidth];

% Update bounding box: frame extends the physical extent
xyzShift = [(leftFrame - 1) * obj.image.pixSize.x, (topFrame - 1) * obj.image.pixSize.y, 0];
obj.updateBoundingBox([], xyzShift);

% Update ROI and annotation coordinates
cropFactor = [-leftFrame+1, -topFrame+1, NaN, NaN, 1, NaN, 1, NaN];
obj.hROI.crop(cropFactor);
obj.annotations.crop(cropFactor);
obj.measure.crop(cropFactor);

logText = sprintf('AddFrame: %s [left right top bottom]: %d %d %d %d; color=%d', ...
    BatchOpt.Position{1}, leftFrame, rightFrame, topFrame, bottomFrame, frameColor);
obj.image.updateActionLog(logText);

if ~isempty(waitbar); delete(waitbar); end
end


function updateLayerDims(layer, newH, newW, newZ, newT)
% Update dimension properties on a layer after data{1} has been replaced.
layer.height = newH;
layer.width  = newW;
layer.depth  = newZ;
layer.time   = newT;
layer.dim_yxzct = [newH, newW, newZ, 1, newT];
end
