function dataset = getData3D(obj, type, time, orient, col_channel, options)
% GETDATA3D - Get the a 3D dataset with colors: height:width:depth:colors.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getData3D(type, time, orient, col_channel, options)
%
% Input Arguments:
%   - **type** — type of the dataset layer to retrieve:
%
%     - ``'image'`` — [*default*] the image layer
%     - ``'labels'`` — labels layer with segmentation
%     - ``'mask'`` — mask layer, supporting segmentation
%     - ``'selection'`` — selection layer, a temporary layer for segmentation
%     - ``'everything'`` — (``'model'``, ``'mask'`` and ``'selection'`` for ``obj.labels.maxMaterials == 63`` only)
%
%   - **time** — [*optional,* can be []], an index of the time point to get:
%
%     - ``[]`` — get the current time point *(default)*
%     - any index — get dataset with that time point
%
%   - **orient** — [*optional,* can be []]
%
%     - ``[]`` — returns transposed dataset in the currently shown orientation *(default)*
%     - ``1`` — returns transposed dataset in the zx configuration: [y,x,z,c,t] → [x,z,y,c,t]
%     - ``2`` — returns transposed dataset in the zy configuration: [y,x,z,c,t] → [y,z,x,c,t]
%     - ``3`` — returns the original dataset in the yx configuration: [y,x,z,c,t]
%
%   - **col_channel** — [*optional*] color channel(s) to retrieve; can be ``[]`` or ``NaN``:
%
%     - when **type** is ``'image'``: a vector of color channel indices:
%
%       - ``[]`` — *(default)* take color channels from ``obj.slices{4}``
%       - ``NaN`` — take all color channels of the dataset
%       - index — get specific color channel(s) with provided index(s)
%
%     - when **type** is ``'labels'``: the material selection:
%
%       - ``[]`` — *(default)* take all materials of the model
%       - ``NaN`` — take all materials of the model
%       - index — get specific material; the selected material in **dataset** will have index = 1
%   - **options** — *(optional)*, a structure with extra parameters
%
%     - ``.blockModeSwitch`` [*logical]* override the block mode switch obj.blockModeSwitch;
%       use or not the block mode (**false** - return full dataset, **true** - return only the shown part)
%     - ``.roiId`` [*integer]* use or not the ROI mode
%       when **missing** or less than 0, return full dataset, without ROI
%       when **[]** - currently selected
%       when **0** - return all ROIs of the dataset
%       when **Index** - return ROI with the index
%       (**Attention:** see also fillBg parameter!)
%     - ``.fillBg`` filling color for ROI
%       when *NaN* (**default)** crops the dataset as a rectangle;
%       when *a* *number* fills the areas out of the ROI area with this intensity number
%     - ``.y`` *(optional)*, [ymin, ymax] of the part of the dataset to take (sets .blockModeSwitch to 0)
%     - ``.x`` *(optional)*, [xmin, xmax] of the part of the dataset to take (sets .blockModeSwitch to 0)
%     - ``.z`` *(optional)*, [zmin, zmax] of the part of the dataset to take (sets .blockModeSwitch to 0)
%
% Output Arguments:
%   - **dataset** — a cell array with 3D dataset with colors.
%     For the 'image' type: {roiId}[1:height, 1:width, 1:depth, 1:colors];
%     for all other types: {roiId}[1:height, 1:width, 1:depth]
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.mibModel.I{obj.mibModel.id}.getData3D('image');% Call from mibController: get the 4D dataset for the current time point, in the shown orientation
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.mibModel.I{obj.mibModel.id}.getData3D('image', 5, 3, 2);% Call from mibController: get the 4D dataset for the 5-th time point in the XY orientation
%
%
%   **Attention:** **sensitive** to the ``obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false``
%
%   **Attention:** **NOT** **sensitive** to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters
%

% Updates
% 

if nargin < 6; options = struct();  end
if nargin < 5; col_channel = [];   end
if nargin < 4; orient = []; end
if nargin < 3; time = []; end
if nargin < 2; type = 'image'; end

% === FAST PATH ===
% Standard in-memory, YX orient (3), no ROI, no blockMode, no x/y/z subregion.
% Directly indexes data{1} and returns without going through MibImage.getData.
% Output matches slow path: non-image → cell{[H,W,Z,1]}; image → cell{[H,W,Z,C,1]}.
if strcmp(obj.datasetType, 'Standard') && ~strcmp(type, 'everything')
    fastOrient = orient;
    if isempty(fastOrient) || (isscalar(fastOrient) && isnan(fastOrient))
        fastOrient = obj.orientation;
    end
    if fastOrient == 3 && ~isfield(options, 'x') && ~isfield(options, 'y') && ~isfield(options, 'z')
        if isfield(options, 'blockModeSwitch')
            blockIsOff = (options.blockModeSwitch == 0);
        else
            blockIsOff = (obj.blockModeSwitch == 0);
        end
        noROI = ~isfield(options, 'roiId') || (isscalar(options.roiId) && options.roiId < 0);
        skipLabelsIdx = strcmp(type, 'labels') && ~isempty(col_channel) && ...
                        isnumeric(col_channel) && ~any(isnan(col_channel(:)));
        skipPacked63  = (obj.labels.maxMaterials == 63) && ~strcmp(type, 'image');

        if blockIsOff && noROI && ~skipLabelsIdx && ~skipPacked63
            if isempty(time); time = obj.slices{5}(1); end
            if strcmp(type, 'image')
                if isempty(col_channel); col_channel = obj.slices{4};
                elseif isscalar(col_channel) && isnan(col_channel); col_channel = 1:obj.image.colors; end
                dataset = {obj.(type).data(:,:,:,col_channel,time)};
            else
                col_channel = 1;
                rawVol = obj.(type).data(:,:,:,col_channel,time);
                % Replicate slow-path reshape: MibImage.getData drops singleton C dim for non-image
                sz = size(rawVol);
                dataset = {reshape(rawVol, sz(1), sz(2), sz(3), 1)};
            end
            return;
        end
    end
end
% === END FAST PATH ===

% define datasetVariable for obj.(datasetVariable).getData
datasetVariable = type;
if obj.labels.maxMaterials == 63 
    if ismember(type, {'selection', 'mask', 'everything'}) 
        datasetVariable = 'labels';
    end
end

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
if isempty(time); time = obj.slices{5}(1); end

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

options.t = [time time];   % define the time point

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

        dataset{roiId2} = obj.(datasetVariable).getData(type, orient, col_channel, options);
        if ~isnan(options.fillBg)
            mask = mask(bb(3):bb(4), bb(1):bb(2));
            
            mask = repmat(mask,[1, 1, size(dataset{roiId2},3)]);
            for layerId = 1:size(dataset{roiId2}, max([ndims(dataset{roiId2}) 4]))
                if strcmp(type, 'image')
                    slice = dataset{roiId2}(:,:,:,layerId);
                    slice(~mask) = options.fillBg;
                    dataset{roiId2}(:,:,:,layerId) = slice; 
                else
                    slice = dataset{roiId2}(:,:,layerId);
                    slice(~mask) = options.fillBg;
                    dataset{roiId2}(:,:,layerId) = slice; 
                end
            end
        end
        roiId2 = roiId2 + 1;
    end
else   
    if obj.labels.maxMaterials ~= 63 && strcmp(type, 'everything')
        errorText = sprintf('!!! Error !!!\n\nType = "everything" available only for the models with 63 materials!');
        utils.dlgs.showErrorDialog([], errorText, 'MibDataset.getData3D');
        dataset = [];
        return;
    end
    dataset = {obj.(datasetVariable).getData(type, orient, col_channel, options)};
end
end
