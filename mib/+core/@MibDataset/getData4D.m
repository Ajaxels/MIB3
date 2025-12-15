function dataset = getData4D(obj, type, orient, col_channel, options)
% function dataset = getData4D(obj, type, time, orient, col_channel, options)
% Get the a 4D dataset with colors: [height:width:depth:colors:time]
%
% Parameters:
% type: type of the dataset layer to retrieve
%   @li 'image' - [@b default] the image layer
%   @li 'labels' - labels layer with segmentation
%   @li 'mask' - mask layer, supporting segmentation
%   @li 'selection' - selection layer, a temporary layer for segmentation
%   @li 'everything' - ('model','mask' and 'selection' for "obj.labels.maxMaterials == 63" only)% time: [@em optional], an index of the time point to show, when @em NaN gets the dataset for the current time point
% orient: [@em optional, can be []]
%   @li when @b [] returns the transposed dataset to the currently shown orientation
%   @li when @b 1 returns the transposed dataset to the zx configuration, [y,x,z,c,t] -> [x,z,y,c,t]
%   @li when @b 2 returns the transposed dataset to the zy configuration, [y,x,z,c,t] -> [y,z,x,c,t]
%   @li when @b 3 returns the original dataset to the yx configuration, [y,x,z,c,t]
% col_channel: [@em optional, can be [], when [] -> get the currently selected color channels, can be @em NaN]
%   @li when @b type is 'image', col_channel is a vector with numbers of color channels to get, 
%       when @b [] [@em default] take color channels selected in the obj.slices{4} variable, 
%       when @b NaN - take all color channels of the dataset
%       when @b Index - get color channels with provided index(s)
%   @li when @b type is 'labels' col_channel 
%       when @b [] [@em default] - to take all materials of the model
%       when @b NaN - to take all materials of the model
%       when @b Index - [integer] get specific material, in this case the selected material in @b dataset will have index = 1.
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
% @li .t -> [@em optional], [tmin, tmax] of the part of the dataset to take
%
% Return values:
% dataset: a cell array with 4D image with colors. 
%           For the 'image' type: {roiId}[1:height, 1:width, 1:depth, 1:color, 1:time]; 
%           for all other types: {roiId}[1:height, 1:width, 1:depth, 1:time]

%| 
% @b Examples:
% @code dataset = obj.mibModel.I{obj.mibModel.id}.getData4D('image');      //  Call from mibController: get the 4D dataset for the current time point, in the shown orientation  @endcode
% @code dataset = obj.mibModel.I{obj.mibModel.id}.getData4D('image', 5, 3, 2); //  Call from mibController: get the 4D dataset for the 5-th time point in the XY orientation @endcode
% @attention @b sensitive to the @code obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false @endcode
% @attention @b NOT @b sensitive to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters

% Updates
% 
 

if nargin < 5; options = struct();  end
if nargin < 4; col_channel = [];   end
if nargin < 3; orient = []; end
if nargin < 2; type = 'image'; end

if ~isfield(options, 'fillBg'); options.fillBg = NaN; end
if ~isfield(options, 'roiId');    options.roiId = -1;  end
if isempty(options.roiId); options.roiId = obj.selectedROI; end

if ~isfield(options, 'blockModeSwitch')
    if isfield(options, 'x') || isfield(options, 'y') || isfield(options, 'z')
        options.blockModeSwitch = 0; 
    else
        options.blockModeSwitch = obj.blockModeSwitch; 
    end
end
if options.blockModeSwitch == 1; options.roiId = -1; end   % turn off the ROI mode, when the block mode is on

if isempty(orient) || isnan(orient); orient = obj.orientation; end

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

if options.roiId >= 0
    % get indices of ROI
    if options.roiId == 0
        [~, options.roiId] = obj.hROI.getNumberOfROI(orient);  % get number of ROI for the selected orientation
    end
    roiId2 = 1;
    dataset{roiId2} = cell(numel(options.roiId), 1);
    for roiId = options.roiId
        mask = obj.hROI.returnMask(roiId);
        bb = obj.hROI.getBoundingBox(roiId);
        options.x = [bb(1), bb(2)];
        options.y = [bb(3), bb(4)];
        
        dataset{roiId2} = obj.getData(type, orient, col_channel, options);
        if ~isnan(options.fillBg)
            mask = mask(max([1 bb(3)]):bb(4), max([1 bb(1)]):bb(2));
            mask = repmat(mask,[1, 1, numel(col_channel)]);
            for timePnt = 1:size(dataset{roiId2}, ndims(dataset{roiId2}))
                for layerId = 1:size(dataset{roiId2}, ndims(dataset{roiId2})-1)
                    if strcmp(type, 'image')
                        slice = dataset{roiId2}(:,:,:,layerId,timePnt);
                        slice(~mask) = options.fillBg;
                        dataset{roiId2}(:,:,:,layerId,timePnt) = slice;
                    else
                        slice = dataset{roiId2}(:,:,layerId,timePnt);
                        slice(~mask) = options.fillBg;
                        dataset{roiId2}(:,:,layerId,timePnt) = slice;
                    end
                end
            end
        end
        roiId2 = roiId2 + 1;
    end
else
    if obj.labels.maxMaterials ~= 63 && strcmp(type, 'everything')
        errorText = sprintf('!!! Error !!!\n\nType = "everything" available only for the models with 63 materials!');
        utils.dlgs.showErrorDialog([], errorText, 'MibDataset.getData4D');
        dataset = [];
        return;
    end
    dataset = {obj.(type).getData(type, orient, col_channel, options)};
end
end