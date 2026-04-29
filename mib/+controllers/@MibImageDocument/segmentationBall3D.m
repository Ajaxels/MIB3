function segmentationBall3D(obj, y, x, z, modifier, BatchOptIn)
% SEGMENTATIONBALL3D - Do segmentation using the 3D ball tool.
%
% Syntax:
%   function segmentationBall3D(obj, y, x, z, modifier, BatchOptIn)
%
% Places an ellipsoidal 3D ball in the dataset at the given coordinate.
% The ball is anisotropy-corrected: radii along each axis are scaled by
% the voxel size ratio so the ball appears physically spherical.
%
% Input Arguments:
%   - **y** — double, y-coordinate of the ball centre in full-dataset pixels
%   - **x** — double, x-coordinate of the ball centre in full-dataset pixels
%   - **z** — double, z-coordinate (slice index) of the ball centre
%   - **modifier** — cell array of chars or char, modifier keys held during click
%     - empty '' - add ball to the selection/mask layer
%     - 'control' - subtract ball from the selection/mask layer
%   - **BatchOptIn** — *(optional)* struct for batch processing mode; when NaN,
%     returns default options via the 'SyncBatch' event
%     - .Radius - [char] ball radius in pixels (raw spinner value)
%     - .X - [char] vector or single X coordinate of the ball centre
%     - .Y - [char] vector or single Y coordinate of the ball centre
%     - .Z - [char] vector or single Z coordinate of the ball centre;
%   empty = current slice
%     - .Mode - [char, {'add','erase'}] add or subtract ball
%     - .restrictSelectionToMask - [logical] paint only within the mask
%     - .restrictSelectionToMaterial - [logical] paint only within the
%   selected material
%     - .Target - [char, {'selection','mask'}] destination layer
%     - .showWaitbar - [logical] show or not the progress bar
%     - .id *(optional)* dataset index 1-9, default = obj.mibModel.getActiveId()
%
% Output Arguments:
%   (none)
%
% Usage:
%   Example 1::
%
%     obj.segmentationBall3D(50, 75, 10, '');  // add 3D ball at [y,x,z]=[50,75,10]
%
%   Example 2::
%
%     obj.segmentationBall3D(50, 75, 10, 'control');  // erase 3D ball
%
%   Example 3::
%
%     BatchOpt.Radius = '6';
%     BatchOpt.X = '75'; BatchOpt.Y = '50'; BatchOpt.Z = '10';
%     BatchOpt.Mode = {'add'};
%     BatchOpt.Target = {'selection'};
%     BatchOpt.showWaitbar = false;
%     obj.segmentationBall3D(50, 75, 10, '', BatchOpt);   // batch / scripted call
%

% Updates
%

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

% ---- read ball radius from the brush-radius spinner (shared with brush/spot) ----
radius = obj.mibController.cSegmentation.handles.brushRadius.Value;

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();
BatchOpt.Radius = num2str(radius);
if ~isempty(x)
    BatchOpt.X = num2str(x);
else
    BatchOpt.X = '';
end
if ~isempty(y)
    BatchOpt.Y = num2str(y);
else
    BatchOpt.Y = '';
end
if ~isempty(z)
    BatchOpt.Z = num2str(z);
else
    BatchOpt.Z = '';
end

if isempty(modifier)
    BatchOpt.Mode = {'add'};
else
    isCtrl = false;
    if iscell(modifier)
        isCtrl = any(strcmp(modifier, 'control'));
    elseif ischar(modifier)
        isCtrl = strcmp(modifier, 'control');
    end
    if isCtrl
        BatchOpt.Mode = {'erase'};
    else
        BatchOpt.Mode = {'add'};
    end
end
BatchOpt.Mode{2} = {'add', 'erase'};

dataset = obj.mibModel.I{BatchOpt.id};
BatchOpt.restrictSelectionToMask = logical(dataset.restrictSelectionToMask);
BatchOpt.restrictSelectionToMaterial = logical(dataset.restrictSelectionToMaterial);
BatchOpt.Target = {'selection'};
BatchOpt.Target{2} = {'selection', 'mask'};
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = '3D ball';

BatchOpt.mibBatchTooltip.Radius = 'Ball radius in pixels';
BatchOpt.mibBatchTooltip.X = 'Vector or a single X coordinate of the 3D ball centre';
BatchOpt.mibBatchTooltip.Y = 'Vector or a single Y coordinate of the 3D ball centre';
BatchOpt.mibBatchTooltip.Z = 'Vector or a single Z coordinate of the 3D ball centre; empty = current slice';
BatchOpt.mibBatchTooltip.Mode = 'Add or subtract a 3D ball at the provided coordinate(s)';
BatchOpt.mibBatchTooltip.restrictSelectionToMask = 'Apply 3D ball only to the masked area';
BatchOpt.mibBatchTooltip.restrictSelectionToMaterial = 'Apply 3D ball only to the area of the selected material';
BatchOpt.mibBatchTooltip.Target = 'Destination layer for the 3D ball';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%%
if nargin == 6  % batch mode
    if ~isstruct(BatchOptIn)
        if isnan(BatchOptIn)     % return possible settings via SyncBatch event
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_error';
            header = 'A structure as the 6th parameter is required!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'segmentationBall3D', dlgOpt);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%%
% ---- compute anisotropy-corrected radii ----
pixSize = dataset.image.pixSize;
minVox = min([pixSize.x, pixSize.y, pixSize.z]);
ratioX = pixSize.x / minVox;
ratioY = pixSize.y / minVox;
ratioZ = pixSize.z / minVox;

radius = str2double(BatchOpt.Radius) - 1;
% radius matrix: rows = [y; x; z], cols = [-delta, +delta]
radius = [radius/ratioX, radius/ratioX; ...
          radius/ratioY, radius/ratioY; ...
          radius/ratioZ, radius/ratioZ];
radius = round(radius);
rad_vec = radius;   % clipping vectors, trimmed at image borders below

y_max = dataset.image.height;
x_max = dataset.image.width;
z_max = dataset.image.depth;

xVec = str2num(BatchOpt.X); %#ok<ST2NM>
yVec = str2num(BatchOpt.Y); %#ok<ST2NM>
if isempty(BatchOpt.Z)
    zVec = dataset.getCurrentSliceNumber();
else
    zVec = str2num(BatchOpt.Z); %#ok<ST2NM>
end

if numel(xVec) ~= numel(yVec)
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    header = 'Number of X and Y coordinates mismatch!';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, '3D ball segmentation', dlgOpt);
    notify(obj.mibModel, 'StopProtocol');
    return;
end

if numel(zVec) < numel(xVec)
    zVec = repmat(zVec(1), [1, numel(xVec)]);
end

showWaitbarLocal = false;
if BatchOpt.showWaitbar && ~isscalar(xVec)
    showWaitbarLocal = true;
end
if showWaitbarLocal
    wb = uiprogressdlg(obj.view.gui, 'Value', 0, ...
        'Message', 'Please wait...', 'Title', '3D ball segmentation');
end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfBall3D = obj.mibModel.preferences.Users.Tiers.numberOfBall3D + 1;
notify(obj.mibModel, 'UpdateUserScore');

% ---- pre-compute the full-size ball template ----
max_rad = max(radius(:));
[x1, y1, z1] = meshgrid(-max_rad:max_rad, -max_rad:max_rad, -max_rad:max_rad);
ball = sqrt((x1/radius(1,1)).^2 + (y1/radius(2,1)).^2 + (z1/radius(3,1)).^2);

for index = 1:numel(xVec)
    yi = yVec(index);
    xi = xVec(index);
    zi = zVec(index);
    rad_vec2 = rad_vec;

    % clip radii at image borders
    if yi - radius(1,1) <= 0;  rad_vec2(1,1) = yi - 1;     end
    if yi + radius(1,2) > y_max; rad_vec2(1,2) = y_max - yi; end
    if xi - radius(2,1) <= 0;  rad_vec2(2,1) = xi - 1;     end
    if xi + radius(2,2) > x_max; rad_vec2(2,2) = x_max - xi; end
    if zi - radius(3,1) <= 0;  rad_vec2(3,1) = zi - 1;     end
    if zi + radius(3,2) > z_max; rad_vec2(3,2) = z_max - zi; end

    % carve the clipped sub-ball from the template
    selarea = zeros(max_rad*2+1, max_rad*2+1, max_rad*2+1, 'uint8');
    selarea(ball <= 1) = 1;
    selarea = selarea( ...
        max_rad - rad_vec2(1,1) + 1 : max_rad + rad_vec2(1,2) + 1, ...
        max_rad - rad_vec2(2,1) + 1 : max_rad + rad_vec2(2,2) + 1, ...
        max_rad - rad_vec2(3,1) + 1 : max_rad + rad_vec2(3,2) + 1);

    options.y  = [yi - rad_vec2(1,1), yi + rad_vec2(1,2)];
    options.x  = [xi - rad_vec2(2,1), xi + rad_vec2(2,2)];
    options.z  = [zi - rad_vec2(3,1), zi + rad_vec2(3,2)];
    options.id = BatchOpt.id;
    options.blockModeSwitch = 0;

    % do backup on first point only
    if index == 1
        if isscalar(xVec)
            obj.mibModel.backup(BatchOpt.Target{1}, 1, options);
        else
            backupOpt.id = options.id;
            obj.mibModel.backup(BatchOpt.Target{1}, 1, backupOpt);
        end
    end

    % limit to the selected material of the model
    if BatchOpt.restrictSelectionToMaterial
        selcontour = dataset.getSelectedMaterialIndex();
        modelData = cell2mat(obj.mibModel.getData3D('labels', NaN, 3, selcontour, options));
        selarea = selarea & modelData;
    end

    % limit selection to the masked area
    if BatchOpt.restrictSelectionToMask && dataset.maskExist
        maskData = cell2mat(obj.mibModel.getData3D('mask', NaN, 3, NaN, options));
        selarea = selarea & maskData;
    end

    currData = cell2mat(obj.mibModel.getData3D(BatchOpt.Target{1}, NaN, 3, NaN, options));
    if strcmp(BatchOpt.Mode{1}, 'add')
        obj.mibModel.setData3D(currData | selarea, BatchOpt.Target{1}, NaN, 3, NaN, options);
    else
        currData(selarea == 1) = 0;
        obj.mibModel.setData3D(currData, BatchOpt.Target{1}, NaN, 3, NaN, options);
    end

    if showWaitbarLocal
        wb.Value = index / numel(xVec);
    end
end

if showWaitbarLocal; delete(wb); end

obj.mibController.showImage();
end
