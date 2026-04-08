function segmentationSpot(obj, y, x, modifier, BatchOptIn)
% function segmentationSpot(obj, y, x, modifier, BatchOptIn)
% Do segmentation using the spot tool
%
% Places a circular or square spot (selection or mask) at the given image
% coordinate. Supports 2D and 3D modes, restriction to mask/material, and
% batch scripting.
%
% Parameters:
% y: double, y-coordinate of the spot centre in full-dataset pixels
% x: double, x-coordinate of the spot centre in full-dataset pixels
% modifier: cell array of chars or char, modifier keys held during click
% @li empty '' - add selection
% @li 'control' - subtract selection (eraser mode)
% BatchOptIn: [@em optional] struct for batch processing mode; when NaN,
%   returns default options via the 'SyncBatch' event
% @li .Shape - [char, {'circle','square'}] shape of the spot
% @li .Radius - [char] spot radius in pixels; two numbers separated by ';'
%   set independent half-width / half-height
% @li .X - [char] vector or single X coordinate of the spot centre
% @li .Y - [char] vector or single Y coordinate of the spot centre
% @li .Z - [char] vector or single Z slice index; empty = current slice
% @li .Mode - [char, {'add','erase'}] add or subtract spot
% @li .Check3D - [logical] apply spot across all z-slices (3-D sphere); default from obj.mibModel.applySegmentationIn3D
% @li .restrictSelectionToMask - [logical] paint only within the mask
% @li .restrictSelectionToMaterial - [logical] paint only within the
%   selected material
% @li .Orientation - [char, {'XZ','YZ','not available','YX'}] dataset
%   orientation used when computing the spot
% @li .Target - [char, {'selection','mask'}] destination layer
% @li .showWaitbar - [logical] show or not the progress bar
% @li .id -> [@em optional] dataset index 1-9, default = obj.mibModel.getActiveId()
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code obj.segmentationSpot(50, 75, '');  // add spot at dataset [y,x]=[50,75] @endcode
% @code obj.segmentationSpot(50, 75, 'control');  // erase spot @endcode
% @code
% BatchOpt.Shape = {'circle'};
% BatchOpt.Radius = '5';
% BatchOpt.X = '75'; BatchOpt.Y = '50'; BatchOpt.Z = '';
% BatchOpt.Mode = {'add'};
% BatchOpt.Check3D = false;
% BatchOpt.Target = {'selection'};
% BatchOpt.showWaitbar = false;
% obj.segmentationSpot(50, 75, '', BatchOpt);   // batch / scripted call
% @endcode

% Updates
%

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

% ---- read spot radius from the brush-radius spinner (shared with brush/3D ball) ----
radius = obj.mibController.cSegmentation.handles.brushRadius.Value - 1;
if radius < 1; radius = 0.5; end
radius = round(radius);

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();
BatchOpt.Shape = {'circle'};
BatchOpt.Shape{2} = {'circle', 'square'};
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
BatchOpt.Z = '';

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
BatchOpt.Check3D = logical(obj.mibModel.applySegmentationIn3D);
BatchOpt.restrictSelectionToMask = logical(dataset.restrictSelectionToMask);
BatchOpt.restrictSelectionToMaterial = logical(dataset.restrictSelectionToMaterial);
orientChoices = {'XZ', 'YZ', 'not available', 'YX'};
BatchOpt.Orientation{2} = orientChoices;
BatchOpt.Orientation(1) = orientChoices(dataset.orientation);
BatchOpt.Target = {'selection'};
BatchOpt.Target{2} = {'selection', 'mask'};
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = 'Spot';

BatchOpt.mibBatchTooltip.Radius = 'Spot radius in pixels';
BatchOpt.mibBatchTooltip.X = 'Vector or a single X coordinate of the spot centre';
BatchOpt.mibBatchTooltip.Y = 'Vector or a single Y coordinate of the spot centre';
BatchOpt.mibBatchTooltip.Z = 'Vector or a single Z coordinate of the spot centre; empty = current slice';
BatchOpt.mibBatchTooltip.Mode = 'Add or subtract a spot at the provided coordinate(s)';
BatchOpt.mibBatchTooltip.Check3D = 'Make spot in 3D — the spot will be visible on all slices';
BatchOpt.mibBatchTooltip.restrictSelectionToMask = 'Apply spot only to the masked area';
BatchOpt.mibBatchTooltip.restrictSelectionToMaterial = 'Apply spot only to the area of the selected material';
BatchOpt.mibBatchTooltip.Orientation = 'Orientation of the dataset';
BatchOpt.mibBatchTooltip.Target = 'Destination layer for spot';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%%
if nargin == 5  % batch mode
    if ~isstruct(BatchOptIn)
        if isnan(BatchOptIn)     % return possible settings via SyncBatch event
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            dlgOpt.MsgBoxOnly = true;
            header = 'A structure as the 5th parameter is required!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'segmentationSpot', dlgOpt);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%%
selcontour = dataset.getSelectedMaterialIndex();
xVec = str2num(BatchOpt.X); %#ok<ST2NM>
yVec = str2num(BatchOpt.Y); %#ok<ST2NM>
if isempty(BatchOpt.Z)
    zVec = dataset.getCurrentSliceNumber();
else
    zVec = str2num(BatchOpt.Z); %#ok<ST2NM>
end

if numel(xVec) ~= numel(yVec)
    dlgOpt.MsgBoxOnly = true;
    header = 'Number of X and Y coordinates mismatch!';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Spot segmentation', dlgOpt);
    notify(obj.mibModel, 'StopProtocol');
    return;
end

if numel(zVec) < numel(xVec)    % broadcast single Z to match X/Y
    zVec = repmat(zVec(1), [1, numel(xVec)]);
end

orientation = find(ismember(BatchOpt.Orientation{2}, BatchOpt.Orientation{1}));
options.id = BatchOpt.id;

radius = str2num(BatchOpt.Radius); %#ok<ST2NM>
if isscalar(radius)
    radius(2) = radius;  % use same value for both axes
end

% show waitbar only for 3D or multi-point operations
showWaitbarLocal = false;
if BatchOpt.showWaitbar && (BatchOpt.Check3D || numel(xVec) > 1)
    showWaitbarLocal = true;
end
if showWaitbarLocal
    wb = uiprogressdlg(obj.view.gui, 'Value', 0, ...
        'Message', 'Please wait...', 'Title', 'Spot segmentation');
end

backupOptions.id = BatchOpt.id;

for index = 1:numel(xVec)
    options.x = [xVec(index)-radius(1), xVec(index)+radius(1)];
    options.y = [yVec(index)-radius(2), yVec(index)+radius(2)];
    options.z = [zVec(index), zVec(index)];
    options.blockModeSwitch = 0;

    % local centre inside the cropped sub-image
    xLocal = radius(1) + min([options.x(1), 1]);
    yLocal = radius(2) + min([options.y(1), 1]);

    currSelection = cell2mat(obj.mibModel.getData2D(BatchOpt.Target{1}, zVec(index), orientation, NaN, options));

    if strcmp(BatchOpt.Shape{1}, 'circle')
        currSelection2 = zeros(size(currSelection), 'uint8');
        currSelection2(yLocal, xLocal) = 1;
        currSelection2 = bwdist(currSelection2);
        currSelection2 = uint8(currSelection2 <= radius(1));
    else   % square
        currSelection2 = ones(size(currSelection), 'uint8');
    end

    if BatchOpt.Check3D
        % ---- 3D spot: replicate the 2D disk across all z-slices ----
        if orientation == 4      % YX
            backupOptions.y = options.y;
            backupOptions.x = options.x;
        elseif orientation == 1  % XZ
            backupOptions.x = options.y;
            backupOptions.z = options.x;
        elseif orientation == 2  % YZ
            backupOptions.y = options.y;
            backupOptions.z = options.x;
        end

        if isscalar(xVec)
            obj.mibModel.backup(BatchOpt.Target{1}, 1, backupOptions);
        end

        orient = orientation;
        [~, ~, ~, localThick] = dataset.getDatasetDimensions(BatchOpt.Target{1}, orient, NaN, options);
        selarea = zeros([size(currSelection,1), size(currSelection,2), localThick], 'uint8');
        options.z = [1, localThick];
        for layer_id = 1:size(selarea, 3)
            selarea(:,:,layer_id) = currSelection2;
        end

        % limit to the selected material of the model
        if BatchOpt.restrictSelectionToMaterial
            currModel = cell2mat(obj.mibModel.getData3D('labels', NaN, orient, selcontour, options));
            selarea = bitand(selarea, currModel);
        end
        % limit selection to the masked area
        if BatchOpt.restrictSelectionToMask && dataset.maskExist
            currMask = cell2mat(obj.mibModel.getData3D('mask', NaN, orient, NaN, options));
            selarea = bitand(selarea, currMask);
        end

        currSelection = cell2mat(obj.mibModel.getData3D(BatchOpt.Target{1}, NaN, orient, NaN, options));
        if strcmp(BatchOpt.Mode{1}, 'add')
            obj.mibModel.setData3D(bitor(selarea, currSelection), BatchOpt.Target{1}, NaN, orient, NaN, options);
        else
            currSelection(selarea==1) = 0;
            obj.mibModel.setData3D(currSelection, BatchOpt.Target{1}, NaN, orient, NaN, options);
        end

    else
        % ---- 2D spot ----
        if index == 1
            if isscalar(xVec)
                obj.mibModel.backup(BatchOpt.Target{1}, 0, options);
            else
                if isscalar(unique(zVec))
                    backupOpt.id = options.id;
                    backupOpt.z = options.z;
                    obj.mibModel.backup(BatchOpt.Target{1}, 0, backupOpt);
                end
            end
        end

        selarea = currSelection2;

        % limit to the selected material of the model
        if BatchOpt.restrictSelectionToMaterial
            currModel = cell2mat(obj.mibModel.getData2D('labels', zVec(index), orientation, selcontour, options));
            selarea = bitand(selarea, currModel);
        end
        % limit selection to the masked area
        if BatchOpt.restrictSelectionToMask && dataset.maskExist
            currMask = cell2mat(obj.mibModel.getData2D('mask', zVec(index), orientation, NaN, options));
            selarea = bitand(selarea, currMask);
        end

        if strcmp(BatchOpt.Mode{1}, 'add')
            obj.mibModel.setData2D(bitor(currSelection, selarea), BatchOpt.Target{1}, zVec(index), orientation, NaN, options);
        else
            currSelection(selarea==1) = 0;
            obj.mibModel.setData2D(currSelection, BatchOpt.Target{1}, zVec(index), orientation, NaN, options);
        end
    end

    if showWaitbarLocal
        wb.Value = index / numel(xVec);
    end
end

if showWaitbarLocal; delete(wb); end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfSpots = obj.mibModel.preferences.Users.Tiers.numberOfSpots + 1;
notify(obj.mibModel, 'UpdateUserScore');

obj.mibController.showImage();
end
