function result = setData3D(obj, dataset, type, time, orient, col_channel, options)
% function result = setData3D(obj, type, dataset, time, orient, col_channel, options)
% set the 3D dataset with colors: height:width:depth:colors to the dataset
%
% Parameters:
% dataset: 3D image with colors
%   @li if options.roiId is @b not @b used, @em slice can be either 
%       a cell for images ({1}[1:height, 1:width, 1:depth, 1:colors]; for all other types: {1}[1:height, 1:width, 1:depth]) or 
%       a matrix for images ([1:height, 1:width, 1:depth, 1:colors]; for all other types: [1:height, 1:width, 1:depth])
%   @li if options.roiId is @b used, @em slice should be 
%       a cell array ({roiId}[1:height, 1:width, 1:depth, 1:colors]; for all other types: {roiId}[1:height, 1:width, 1:depth])
% type: type of the dataset layer to retrieve
%   @li 'image' - [@b default] the image layer
%   @li 'labels' - labels layer with segmentation
%   @li 'mask' - mask layer, supporting segmentation
%   @li 'selection' - selection layer, a temporary layer for segmentation
%   @li 'everything' - ('model','mask' and 'selection' for "obj.labels.maxMaterials == 63" only)
% time: [@em optional, can be []], an index of the time point to get
%   @li when @b [] - get the current time point
%   @li when @b index - get dataset with that time point 
% orient: [@em optional, can be []]
%   @li when @b [] updates the transposed dataset to the currently shown orientation
%   @li when @b 1 updates the transposed dataset to the zx configuration, [y,x,z,c,t] -> [x,z,y,c,t]
%   @li when @b 2 updates the transposed dataset to the zy configuration, [y,x,z,c,t] -> [y,z,x,c,t]
%   @li when @b 3 updates the original dataset to the yx configuration, [y,x,z,c,t]
% col_channel: [@em optional, can be [], when [] -> update the currently selected color channels, can be @em NaN]
%   @li when @b type is 'image', col_channel is a vector with numbers of color channels to update, 
%       when @b [] [@em default] update color channels selected in the obj.slices{4} variable, 
%       when @b NaN - update all color channels of the dataset
%       when @b Index - update color channels with provided index(s)
%   @li when @b type is 'labels' col_channel 
%       when @b [] [@em default] - to update all materials of the model
%       when @b NaN - to update all materials of the model
%       when @b Index - [integer] update specific material, in this case the selected material in @b slice will have index = 1.
% options: [@em optional], a structure with extra parameters
%   @li .blockModeSwitch -> [@em logical] override the block mode switch obj.blockModeSwitch; 
%           use or not the block mode (@b false - return full dataset, @b true - return only the shown part)
%   @li .roiId -> [@em integer] use or not the ROI mode 
%          when @b missing or less than 0, return full dataset, without ROI
%          when @b [] - currently selected 
%          when @b 0 - return all ROIs of the dataset
%          when @b Index - return ROI with the index
%          (@b Attention: see also fillBg parameter!)
%   @li .fillBg -> filling color for ROI
%          when @em NaN (@b default) -> crops the dataset as a rectangle; 
%          when @em a @em number fills the areas out of the ROI area with this intensity number
% @li .y -> [@em optional], [ymin, ymax] of the part of the dataset to take (sets .blockModeSwitch to 0)
% @li .x -> [@em optional], [xmin, xmax] of the part of the dataset to take (sets .blockModeSwitch to 0)
% @li .z -> [@em optional], [zmin, zmax] of the part of the dataset to take (sets .blockModeSwitch to 0)
% @li .level -> [@em optional], index of image level from the image pyramid
% @li .PixelIdxList -> [@em optional], indices of pixels that have to be updated 
%       (calculated for the current 3D stack of the dataset in the XY orientation), when used all other parameters are not considered 
%       also in this case @b dataset should be a vector. [@b not @b implemented @b for @b 'images'
%
% Return values:
% result: true-success, false-fail, result of function execution

%| 
% @b Examples:
% @code dataset = obj.mibModel.I{obj.mibModel.id}.setData3D(dataset, 'image');      // Call from mibController: set the 4D dataset for the current time point, in the shown orientation  @endcode
% @code dataset = obj.mibModel.I{obj.mibModel.id}.setData3D(dataset, 'image', 5, 3); // Call from mibController: set the 4D dataset for the 5-th time point in the XY orientation @endcode
% @code dataset = obj.mibModel.I{obj.mibModel.id}.setData3D(dataset, 'selection', 5, 1, 2); // Call from mibController: set the 5-th timepoint in the the XZ-orientation, color channel=2 @endcode
% @code dataset = obj.mibModel.I{obj.mibModel.id}.setData3D(dataset, 'image', dataset, [], 3);      // Call from mibController: set the 4D dataset for the current time point in the XY orientation  @endcode
% @attention @b sensitive to the @code obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false @endcode
% @attention @b NOT @b sensitive to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters

% Updates
% 

if nargin < 7; options = struct();   end
if nargin < 6; col_channel = [];   end
if nargin < 5; orient = []; end
if nargin < 4; time = []; end
if nargin < 3; type = 'image'; end

if ~isfield(options, 'fillBg'); options.fillBg = NaN; end
if ~isfield(options, 'roiId');    options.roiId = -1;  end
if isempty(options.roiId); options.roiId = obj.selectedROI; end

% define datasetVariable for obj.(datasetVariable).getData
datasetVariable = type;
if obj.labels.maxMaterials == 63 
    if ismember(type, {'selection', 'mask', 'everything'}) 
        datasetVariable = 'labels';
    end
end

if ~isfield(options, 'blockModeSwitch')
    if isfield(options, 'x') || isfield(options, 'y') || isfield(options, 'z')
        options.blockModeSwitch = 0; 
    else
        options.blockModeSwitch = obj.blockModeSwitch; 
    end
end
if options.blockModeSwitch == 1; options.roiId = -1; end   % turn off the ROI mode, when the block mode is on

if isempty(orient) || isnan(orient); orient = obj.orientation; end
if isempty(time); time = obj.slices{5}(1); end

if isfield(options, 'PixelIdxList')
    if strcmp(type, 'image')
        errorText = sprintf('!!! Error !!!\n\nThe PixelIdxList parameter is not compatible with the the Image layer');
        utils.dlgs.showErrorDialog([], errorText, 'MibDataset.setData3D');
        return; 
    end

    if time > 1     % shift the indices to the choosen time point
        options.PixelIdxList = options.PixelIdxList + ...
            obj.labels.width*obj.labels.height*obj.labels.depth*(time-1);
    end
    result = obj.labels.setPixelIdxList(type, dataset, options.PixelIdxList);
    return;
end

if strcmp(type, 'image')
    if isempty(col_channel)
        col_channel = obj.slices{4};
    elseif isnan(col_channel)
        col_channel = 1:obj.image.colors;
    end
else
    if ~isempty(col_channel) && isnan(col_channel)
        % to take all materials of the model
        col_channel = [];
    end
end

if isfield(options, 'blockModeSwitch') && options.blockModeSwitch
    [axesX, axesY] = obj.getAxesLimits();
    options.x = ceil(axesX);
    options.y = ceil(axesY);
end

options.t = [time time];   % define the time point

if options.roiId >= 0
    % get indices of ROI
    if options.roiId == 0
        [~, options.roiId] = obj.hROI.getNumberOfROI(orient);  % get number of ROI for the selected orientation
    end
    roiId2 = 1;
    for roiId = options.roiId
        mask = obj.hROI.returnMask(roiId);
        bb = obj.hROI.getBoundingBox(roiId);
        options.x = [bb(1), bb(2)];
        options.y = [bb(3), bb(4)];
        
        if ~isnan(options.fillBg)
            if iscell(dataset)
                result = obj.(datasetVariable).setData(dataset{roiId2}, type, orient, col_channel, options);
            else
                result = obj.(datasetVariable).setData(dataset, type, orient, col_channel, options);
            end
        else
            % crop mask to its bounding box
            mask = mask(bb(3):bb(4), bb(1):bb(2));
            if iscell(dataset)
                mask = repmat(mask, [1, 1, size(dataset{roiId2}, 3), size(dataset{roiId2}, max([ndims(dataset{roiId2}) 4]))]);
                sliceTemp = obj.I{options.id}.(datasetVariable).getData(type, orient, col_channel, options);     % get current dataset
                sliceTemp(mask==1) = dataset{roiId2}(mask==1);
            else
                mask = repmat(mask, [1, 1, size(dataset, 3), size(dataset, max([ndims(dataset) 3]))]);
                sliceTemp = obj.I{options.id}.(datasetVariable).getData(type, orient, col_channel, options);     % get current dataset
                sliceTemp(mask==1) = dataset(mask==1);
            end
            result = obj.(datasetVariable).setData(sliceTemp, type, orient, col_channel, options);
        end
        roiId2 = roiId2 + 1;
    end
else
    if obj.labels.maxMaterials == 63 && ~strcmp(type, 'image')
        % labels -> contains selection, mask, and labels == everything
        if iscell(dataset)
            result = obj.labels.setData(dataset{1}, type, orient, col_channel, options);
        else
            result = obj.labels.setData(dataset, type, orient, col_channel, options);
        end
    else
        if obj.labels.maxMaterials ~= 63 && strcmp(type, 'everything')
            errorText = sprintf('!!! Error !!!\n\nType = "everything" available only for the models with 63 materials!');
            utils.dlgs.showErrorDialog([], errorText, 'MibDataset.setData3D');
            return;
        end
        if iscell(dataset)
            result = obj.(datasetVariable).setData(dataset{1}, type, orient, col_channel, options);
        else
            result = obj.(datasetVariable).setData(dataset, type, orient, col_channel, options);
        end
    end
end

% update logical switches 
if ismember(type, {'labels', 'everything'})
    obj.modelExist = true;
elseif strcmp(type, 'mask')
    obj.maskExist = true;
end

% notify about setData method used
setDataOpt.type = type;
setDataOpt.mode = '3D';
eventdata = core.ToggleEventData(setDataOpt);
notify(obj, 'SetData', eventdata);
end