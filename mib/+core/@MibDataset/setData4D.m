function result = setData4D(obj, dataset, type, orient, col_channel, options)
% result = setData4D(obj, dataset, type, orient, col_channel, options)
% Set complete 4D dataset with colors [height:width:depth:colors:time]
%
% Parameters:
% dataset: 4D dataset with colors
%   @li if options.roiId is @b not @b used, @em slice can be either 
%       a cell for images ({1}[1:height, 1:width, 1:depth, 1:colors, 1:time]; for all other types: {1}[1:height, 1:width, 1:depth, 1:time]) or 
%       a matrix for images ([1:height, 1:width, 1:depth, 1:colors, 1:time]; for all other types: [1:height, 1:width, 1:depth, 1:time])
%   @li if options.roiId is @b used, @em slice should be 
%       a cell array ({roiId}[1:height, 1:width, 1:depth, 1:colors, 1:time]; for all other types: {roiId}[1:height, 1:width, 1:depth, 1:time])
% type: type of the dataset layer to retrieve
%   @li 'image' - [@b default] the image layer
%   @li 'labels' - labels layer with segmentation
%   @li 'mask' - mask layer, supporting segmentation
%   @li 'selection' - selection layer, a temporary layer for segmentation
%   @li 'everything' - ('model','mask' and 'selection' for "obj.labels.maxMaterials == 63" only)
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
% @li .y -> [@em optional], [ymin, ymax] coordinates of the dataset to take after transpose, height (sets .blockModeSwitch to 0)
% @li .x -> [@em optional], [xmin, xmax] coordinates of the dataset to take after transpose, width (sets .blockModeSwitch to 0)
% @li .z -> [@em optional], [zmin, zmax] coordinates of the dataset to take after transpose, depth (sets .blockModeSwitch to 0)
% @li .t -> [@em optional], [tmin, tmax] coordinates of the dataset to take after transpose, time
% @li .replaceDatasetSwitch -> [@em optional], force to replace dataset completely with a new dataset
% @li .keepModel -> [@em optional], do not resize the model/selection
%       layers when type='image' and submitting complete dataset; 
%       as result the selection/model layers have to be modified manually layer. 
%       Used in mibResampleController. Default = true;
%
% Return values:
% result: true-success, false-fail, result of function execution

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.setData4D(dataset, 'image');      // Call from mibController: update the complete dataset in the shown orientation @endcode
% @code obj.mibModel.I{obj.mibModel.id}.setData4D(dataset, 'image', NaN, NaN, options.blockModeSwitch=1); // Call from mibController: update the croped to the viewing window dataset, with shown colors @endcode
% @code obj.mibModel.I{obj.mibModel.id}.setData4D(dataset, 'image', 3, 2); // Call from mibController: update complete dataset in the XY orientation with only second color channel @endcode
% @attention @b sensitive to the @code obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false @endcode
% @attention @b NOT @b sensitive to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters

% Updates
% 

result = false;

if nargin < 6; options=struct(); end
if nargin < 5; col_channel = NaN; end
if nargin < 4; orient = NaN; end
if nargin < 3; type = 'image'; end

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

% setting default values for the orientation
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
    if strcmp(type,'image')
        typeIsImage = 1; 
        timeDimIndex = 5;
    else
        typeIsImage = 0; 
        timeDimIndex = 4;
    end
    
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
            result = obj.setData(type, dataset{roiId2}, orient, col_channel, options);
        else
            % crop mask to its bounding box
            mask = mask(max([1 bb(3)]):bb(4), max([1 bb(1)]):bb(2));
            mask = repmat(mask,[1, 1, size(dataset{roiId2},3), size(dataset{roiId2},4)]);
            
            setTime = options.t(1);
            for timePnt = 1:size(dataset{roiId2}, timeDimIndex)
                options.t = [setTime+timePnt-1, setTime+timePnt-1];
                sliceTemp = obj.getData(type, orient, col_channel, options);     % get current dataset
                if typeIsImage
                    datasetTemp = dataset{roiId2}(:,:,:,:,timePnt);
                else
                    datasetTemp = dataset{roiId2}(:,:,:,timePnt);
                end
                sliceTemp(mask==1) = datasetTemp(mask==1);
                result = obj.setData(type, sliceTemp, orient, col_channel, options);
            end
        end
        roiId2 = roiId2 + 1;
    end
else
    if obj.labels.maxMaterials == 63 && ~strcmp(type, 'image')
        % labels -> contains selection, mask, and labels == everything
        if iscell(dataset)
            result = oobj.labels.setData(dataset{1}, type, orient, col_channel, options);
        else
            result = oobj.labels.setData(dataset, type, orient, col_channel, options);
        end
    else
        if obj.labels.maxMaterials ~= 63 && strcmp(type, 'everything')
            errorText = sprintf('!!! Error !!!\n\nType = "everything" available only for the models with 63 materials!');
            utils.dlgs.showErrorDialog([], errorText, 'MibDataset.setData4D');
            return;
        end
        if iscell(dataset)
            result = oobj.(type).setData(dataset{1}, type, orient, col_channel, options);
        else
            result = oobj.(type).setData(dataset, type, orient, col_channel, options);
        end
    end
end

setDataOpt.type = type;
setDataOpt.mode = '4D';
eventdata = core.ToggleEventData(setDataOpt);
notify(obj, 'SetData', eventdata);
end