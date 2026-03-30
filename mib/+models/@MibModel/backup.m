function backup(obj, type, switch3d, getDataOptions)
% function backup(obj, type, switch3d, getDataOptions)
% Store the dataset for Undo
%
% The dataset is stored in the MibBackup class (obj.Backup).
%
% Parameters:
% type: 'image', 'selection', 'mask', 'model' (swapped to labels), 'labels',
%   'everything' (for MibLabels63 only), 'lines3d',
%   'annotations', 'measurements', 'mibDataset'
% switch3d: a switch to define a 2D or 3D mode to store the dataset
% @li @b 0 - 2D slice
% @li @b 1 - 3D dataset
% getDataOptions: [@em optional] a structure with extra parameters
% @li .blockModeSwitch -> [@em optional], crop the stored dataset to the visible portion of the data, when true, overrides .y and .x fields
% @li .y -> [@em optional], [ymin, ymax] of the part of the dataset to store
% @li .x -> [@em optional], [xmin, xmax] of the part of the dataset to store
% @li .z -> [@em optional], [zmin, zmax] of the part of the dataset to store
% @li .t -> [@em optional], [tmin, tmax] of the part of the dataset to store
% @li .roiId -> [@em optional], use or not the ROI mode (@b when missing or less than 0, return full dataset; @b 0 - return all shown ROIs dataset, @b Index or [] - return ROI with this index or currently selected)
% @li .id -> [@em optional], index of the dataset to backup
% @li .LinkedVariable - [@em optional] an additional structure with parameters that should be stored
%     .LinkedVariable.Fieldname - string that specifies variable name seen
%     from mibController, for example:
%     getDataOptions.LinkedVariable.Points = 'obj.mibModel.sessionSettings.SAMsegmenter.Points';
% @li .LinkedData - [@em optional] an additional structure with data that
%     should be stored, Fieldname should match Fieldname in .LinkedVariable
%     .LinkedData.Fieldname.Value1 - values1 to be stored
%     .LinkedData.Fieldname.Value2 - values2 to be stored
%     for example:
%       getDataOptions.LinkedData.Points.Position = [];
%       getDataOptions.LinkedData.Points.Value = [];
%
% Return values:

%|
% @b Examples:
% @code
% % Store the current 2D selection slice before modifying it
% obj.mibModel.backup('selection', 0);
% @endcode
% @code
% % Store the full 3D selection volume before a 3D operation
% obj.mibModel.backup('selection', 1);
% @endcode
% @code
% % Store the mask layer for the current 2D slice
% obj.mibModel.backup('mask', 0);
% @endcode
% @code
% % Store the model layer as 3D before batch processing
% obj.mibModel.backup('labels', 1);
% @endcode
% @code
% % For type-63 models, 'selection'/'mask'/'labels' are automatically
% % converted to 'everything' (all three layers are packed together)
% obj.mibModel.backup('selection', 0);  // internally stores 'everything'
% @endcode
% @code
% % Store image data (2D slice) — also saves full image metadata
% obj.mibModel.backup('image', 0);
% @endcode
% @code
% % Store image data (3D volume)
% obj.mibModel.backup('image', 1);
% @endcode
% @code
% % Store annotations before editing them
% obj.mibModel.backup('annotations', 0);
% @endcode
% @code
% % Store 3D lines/skeletons before modification
% obj.mibModel.backup('lines3d', 0);
% @endcode
% @code
% % Store the entire MibDataset (deep copy) for complex operations
% obj.mibModel.backup('mibDataset', 1);
% @endcode
% @code
% % Store only the visible block (block mode) of the selection
% backupOpt.blockModeSwitch = true;
% obj.mibModel.backup('selection', 0, backupOpt);
% @endcode
% @code
% % Store a specific sub-region of the dataset
% backupOpt.x = [100, 200];
% backupOpt.y = [50, 150];
% backupOpt.z = [10, 10];
% obj.mibModel.backup('selection', 0, backupOpt);
% @endcode
% @code
% % Store backup for a specific dataset (not the currently shown one)
% backupOpt.id = 2;
% obj.mibModel.backup('selection', 1, backupOpt);
% @endcode
% @code
% % Store with LinkedData for SAM segmenter undo support
% backupOpt.LinkedData.Points.Position = [10, 10];
% backupOpt.LinkedData.Points.Value = [5];
% backupOpt.LinkedVariable.Points = 'obj.sessionSettings.SAMsegmenter.Points';
% obj.mibModel.backup('selection', 0, backupOpt);
% @endcode

% Updates
%

% check for the virtual stacking mode and return
if strcmp(obj.I{obj.id}.datasetType, 'Virtual')
    if ismember(type, {'mask', 'selection', 'model', 'labels', 'everything'})
        return;
    end
end

% swap labels with model for compatibility with MIB2
if strcmp(type, 'model'); type = 'labels'; end

% cancel if the undo system is disabled
if obj.Backup.enableSwitch == 0; return; end
if nargin < 4; getDataOptions = struct(); end
if nargin < 3; switch3d = 1; end

if ~isfield(getDataOptions, 'id'); getDataOptions.id = obj.id; end
id = getDataOptions.id;

if isfield(getDataOptions, 'blockModeSwitch') && getDataOptions.blockModeSwitch == true
    [axesX, axesY] = obj.getAxesLimits(id);
    if obj.I{id}.orientation == 3       % yx
        getDataOptions.x = ceil(axesX);
        getDataOptions.y = ceil(axesY);
    elseif obj.I{id}.orientation == 1   % zx
        getDataOptions.z = ceil(axesX);
        getDataOptions.x = ceil(axesY);
    elseif obj.I{id}.orientation == 2   % zy
        getDataOptions.z = ceil(axesX);
        getDataOptions.y = ceil(axesY);
    end
end

if strcmp(type, 'lines3d')
    obj.Backup.store(type, {copy(obj.I{id}.lines3D)}, [], getDataOptions);
    return;
end

% disable backup for 5D datasets
if ~isfield(getDataOptions, 'x') || ~isfield(getDataOptions, 'y') || ...
        ~isfield(getDataOptions, 'z') || ~isfield(getDataOptions, 't')
    depth = obj.I{id}.image.depth;
    time = obj.I{id}.image.time;
    if depth > 1 && time > 1
        return;
    end
end

% disable switch3d when getDataOptions.z is available and points to the same slice
if isfield(getDataOptions, 'z') && getDataOptions.z(2) - getDataOptions.z(1) == 0
    switch3d = 0;
end

if switch3d && obj.Backup.max3d_steps == 0; return; end

if strcmp(type, 'mibDataset')
    mibDatasetCopy = copy(obj.I{id});
    obj.Backup.store(type, mibDatasetCopy, [], getDataOptions);
    return;
end

% replace types 'selection','mask','labels' to 'everything' for type-63 models
if isa(obj.I{id}.labels, 'core.MibLabels63')
    if strcmp(type, 'selection') || strcmp(type, 'mask') || strcmp(type, 'labels')
        type = 'everything';
    end
end

% return when no mask
if strcmp(type, 'mask') && obj.I{id}.maskExist == 0; return; end

[axesX, axesY] = obj.getAxesLimits(id);
orientation = obj.I{id}.orientation;
blockModeSwitch = obj.I{id}.blockModeSwitch;
if ~isfield(getDataOptions, 'orient')
    if switch3d == 1
        getDataOptions.orient = 3;          % YX (non-transposed, full dataset)
    else
        getDataOptions.orient = orientation;
    end
end

% disable the block mode for the getData
getDataOptions.blockModeSwitch = 0;
getDataOptions.switch3d = switch3d;
getDataOptions.modelExist = obj.I{id}.modelExist;
getDataOptions.maskExist = obj.I{id}.maskExist;

% deal with the ROI mode
if isfield(getDataOptions, 'roiId') && blockModeSwitch == 0
    % populate getDataOptions from roiId
    if isempty(getDataOptions.roiId); getDataOptions.roiId = obj.I{id}.selectedROI; end

    if getDataOptions.roiId >= 0
        roiIds = getDataOptions.roiId;
        if roiIds >= 0
            if roiIds == 0
                [~, roiIds] = obj.I{id}.hROI.getNumberOfROI();
            end
            roiId2 = 1;
            getDataOptions.x = zeros([numel(roiIds), 2]);
            getDataOptions.y = zeros([numel(roiIds), 2]);
            for roiId = 1:numel(roiIds)
                bb = obj.I{id}.hROI.getBoundingBox(roiIds(roiId));
                getDataOptions.x(roiId2, :) = [bb(1), bb(2)];
                getDataOptions.y(roiId2, :) = [bb(3), bb(4)];
                roiId2 = roiId2 + 1;
            end
            getDataOptions.orient = orientation;
        end
    end
else
    getDataOptions.roiId = -1;  % turn off the ROI mode
end

% when the block mode is enabled store only information inside the shown block
if blockModeSwitch
    if switch3d
        if orientation == 1         % zx
            if ~isfield(getDataOptions, 'x')
                getDataOptions.z = ceil(axesX);
            end
            if ~isfield(getDataOptions, 'y')
                getDataOptions.x = ceil(axesY);
            end
        elseif orientation == 2     % zy
            if ~isfield(getDataOptions, 'x')
                getDataOptions.z = ceil(axesX);
            end
            if ~isfield(getDataOptions, 'y')
                getDataOptions.y = ceil(axesY);
            end
        elseif orientation == 3     % yx
            if ~isfield(getDataOptions, 'x')
                getDataOptions.x = ceil(axesX);
            end
            if ~isfield(getDataOptions, 'y')
                getDataOptions.y = ceil(axesY);
            end
        end
        % make sure that the coordinates are within the dimensions of the dataset
        if isfield(getDataOptions, 'x')
            getDataOptions.x = [max([getDataOptions.x(1) 1]) min([getDataOptions.x(2) obj.I{id}.image.width])];
        end
        if isfield(getDataOptions, 'y')
            getDataOptions.y = [max([getDataOptions.y(1) 1]) min([getDataOptions.y(2) obj.I{id}.image.height])];
        end
        if isfield(getDataOptions, 'z')
            getDataOptions.z = [max([getDataOptions.z(1) 1]) min([getDataOptions.z(2) obj.I{id}.image.depth])];
        end
        getDataOptions.orient = 3;  % force the orientation for 3D datasets to YX
    else
        [blockHeight, blockWidth] = obj.I{id}.getDatasetDimensions('image', orientation, getDataOptions);
        if ~isfield(getDataOptions, 'x')
            getDataOptions.x = ceil(axesX);
            getDataOptions.x = [max([getDataOptions.x(1) 1]) min([getDataOptions.x(2) blockWidth])];
        end
        if ~isfield(getDataOptions, 'y')
            getDataOptions.y = ceil(axesY);
            getDataOptions.y = [max([getDataOptions.y(1) 1]) min([getDataOptions.y(2) blockHeight])];
        end
        getDataOptions.orient = orientation;
    end
end

if ~isfield(getDataOptions, 'z') && switch3d == 0
    sliceNo = obj.I{id}.getCurrentSliceNumber();
    getDataOptions.z = [sliceNo, sliceNo];
end

if ~isfield(getDataOptions, 't')
    timePnt = obj.I{id}.getCurrentTimePoint();
    getDataOptions.t = [timePnt, timePnt];
end

if switch3d == 1        % 3D mode
    if strcmp(type, 'image')
        getDataOptions.viewPort = obj.I{id}.image.viewPort;
        obj.Backup.store(type, obj.I{id}.getData3D(type, NaN, getDataOptions.orient, [], getDataOptions), ...
            obj.I{id}.image.getMeta(), getDataOptions);
    elseif strcmp(type, 'annotations')
        [labels.labelText, labels.labelValue, labels.labelPosition] = obj.I{id}.annotations.getLabels();
        obj.Backup.store(type, {labels}, NaN, getDataOptions);
    elseif strcmp(type, 'measurements')
        obj.Backup.store(type, {obj.I{id}.measure.Data}, NaN, getDataOptions);
    else
        if obj.I{id}.enableSelection == 0; return; end
        obj.Backup.store(type, obj.I{id}.getData3D(type, NaN, getDataOptions.orient, NaN, getDataOptions), NaN, getDataOptions);
    end
else                    % 2D mode
    if strcmp(type, 'image')
        getDataOptions.viewPort = obj.I{id}.image.viewPort;
        obj.Backup.store(type, obj.I{id}.getData2D(type, getDataOptions.z(1), getDataOptions.orient, [], getDataOptions), ...
            obj.I{id}.image.getMeta(), getDataOptions);
    elseif strcmp(type, 'annotations')
        [labels.labelText, labels.labelValue, labels.labelPosition] = obj.I{id}.annotations.getLabels();
        obj.Backup.store(type, {labels}, NaN, getDataOptions);
    elseif strcmp(type, 'measurements')
        obj.Backup.store(type, {obj.I{id}.measure.Data}, NaN, getDataOptions);
    else
        if obj.I{id}.enableSelection == 0; return; end
        obj.Backup.store(type, obj.I{id}.getData2D(type, getDataOptions.z(1), getDataOptions.orient, NaN, getDataOptions), NaN, getDataOptions);
    end
end
end
