function result = setData4D(obj, dataset, type, orient, col_channel, options)
% SETDATA4D - result = setData4D(obj, dataset, type, orient, col_channel, options).
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setData4D(dataset, type, orient, col_channel, options)
%
% Set complete 4D dataset with colors [height:width:depth:colors:time]
%
% Input Arguments:
%   - **dataset** - 4D dataset with colors
%   - if options.roiId is **not** **used,** *slice* can be either
%     a cell for images ({1}[1:height, 1:width, 1:depth, 1:colors, 1:time]; for all other types: {1}[1:height, 1:width, 1:depth, 1:time]) or
%     a matrix for images ([1:height, 1:width, 1:depth, 1:colors, 1:time]; for all other types: [1:height, 1:width, 1:depth, 1:time])
%   - if options.roiId is **used,** *slice* should be
%     a cell array ({roiId}[1:height, 1:width, 1:depth, 1:colors, 1:time]; for all other types: {roiId}[1:height, 1:width, 1:depth, 1:time])
%   - **type** - type of the dataset layer to retrieve:
%
%     - ``'image'`` - [*default*] the image layer
%     - ``'labels'`` - labels layer with segmentation
%     - ``'mask'`` - mask layer, supporting segmentation
%     - ``'selection'`` - selection layer, a temporary layer for segmentation
%     - ``'everything'`` - (``'model'``, ``'mask'`` and ``'selection'`` for ``obj.labels.maxMaterials == 63`` only)
%
%   - **orient** - [*optional,* can be []]
%
%     - ``[]`` - updates transposed dataset in the currently shown orientation *(default)*
%     - ``1`` - updates transposed dataset in the zx configuration: [y,x,z,c,t] → [x,z,y,c,t]
%     - ``2`` - updates transposed dataset in the zy configuration: [y,x,z,c,t] → [y,z,x,c,t]
%     - ``3`` - updates the original dataset in the yx configuration: [y,x,z,c,t]
%
%   - **col_channel** - [*optional*] color channel(s) to update; can be ``[]`` or ``NaN``:
%
%     - when **type** is ``'image'``: a vector of color channel indices:
%
%       - ``[]`` - *(default)* update color channels from ``obj.slices{4}``
%       - ``NaN`` - update all color channels of the dataset
%       - index - update specific color channel(s) with provided index(s)
%
%     - when **type** is ``'labels'``: the material selection:
%
%       - ``[]`` - *(default)* update all materials of the model
%       - ``NaN`` - update all materials of the model
%       - index - update specific material; the selected material in **slice** will have index = 1
%   - **options** - *(optional)*, a structure with extra parameters
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
%     - ``.y`` *(optional)*, [ymin, ymax] coordinates of the dataset to take after transpose, height (sets .blockModeSwitch to 0)
%     - ``.x`` *(optional)*, [xmin, xmax] coordinates of the dataset to take after transpose, width (sets .blockModeSwitch to 0)
%     - ``.z`` *(optional)*, [zmin, zmax] coordinates of the dataset to take after transpose, depth (sets .blockModeSwitch to 0)
%     - ``.t`` *(optional)*, [tmin, tmax] coordinates of the dataset to take after transpose, time
%     - ``.replaceDatasetSwitch`` *(optional)*, force to replace dataset completely with a new dataset
%     - ``.keepModel`` *(optional)*, do not resize the model/selection
%       layers when type='image' and submitting complete dataset;
%       as result the selection/model layers have to be modified manually layer.
%       Used in mibResampleController. Default = true;
%
% Output Arguments:
%   - **result** - true-success, false-fail, result of function execution
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.setData4D(dataset, 'image');% Call from mibController: update the complete dataset in the shown orientation
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.setData4D(dataset, 'image', NaN, NaN, options.blockModeSwitch=1);% Call from mibController: update the croped to the viewing window dataset, with shown colors
%
%   **Example 3**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.setData4D(dataset, 'image', 3, 2);% Call from mibController: update complete dataset in the XY orientation with only second color channel
%
%
%   **Attention:** **sensitive** to the ``obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false``
%
%   **Attention:** **NOT** **sensitive** to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters
%

% Updates
% 

result = false;

if nargin < 6; options=struct(); end
if nargin < 5; col_channel = NaN; end
if nargin < 4; orient = NaN; end
if nargin < 3; type = 'image'; end

% the mask of a fresh dataset is an empty placeholder; allocate it before either
% path, otherwise the fast path size test fails and MibImage.setData divides by
% zero colors. setData2D/setData3D do the same.
if strcmp(type, 'mask') && strcmp(obj.datasetType, 'Standard') && ~obj.mask.exists
    obj.allocateMask();
end

% === FAST PATH ===
% Standard in-memory, YX orient (3), no ROI, no blockMode, no x/y/z/t subregion.
% Routes through MibImage.setDataFast (single handle hop, in-place / O(1) full-array
% swap) and skips all ROI/Virtual/blockMode machinery. Falls through to the slow
% path when the incoming array would resize the container (handled there).
if strcmp(obj.datasetType, 'Standard') && ~strcmp(type, 'everything')
    fastOrient = orient;
    if isempty(fastOrient) || (isscalar(fastOrient) && isnan(fastOrient))
        fastOrient = obj.orientation;
    end
    if fastOrient == 3 && ~isfield(options, 'x') && ~isfield(options, 'y') && ...
            ~isfield(options, 'z') && ~isfield(options, 't')
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
            % Use fastCh (local) so col_channel is not mutated here.
            % If the fast path falls through (size mismatch), the caller's
            % col_channel must reach the slow path unchanged so the NaN→[]
            % conversion below works and MibImage.setData does a full replace.
            if strcmp(type, 'image')
                fastCh = col_channel;
                if isempty(fastCh); fastCh = obj.slices{4};
                elseif isscalar(fastCh) && isnan(fastCh); fastCh = 1:obj.image.colors; end
            else
                fastCh = 1;
            end
            channelsNo = numel(fastCh);
            if iscell(dataset); dataset = dataset{1}; end
            layerData = obj.(type).data;
            expectedNumel = size(layerData,1)*size(layerData,2)*size(layerData,3)*channelsNo*size(layerData,5);
            if numel(dataset) == expectedNumel
                obj.(type).setDataFast(dataset, [], fastCh, []);   % [] z & [] t ⇒ full-extent write
                if ismember(type, {'labels', 'everything'}); obj.modelExist = true;
                elseif strcmp(type, 'mask'); obj.maskExist = true; end
                if (~isfield(options, 'suppressNotify') || ~options.suppressNotify) && event.hasListener(obj, 'SetData')
                    setDataOpt.type = type; setDataOpt.mode = '4D';
                    notify(obj, 'SetData', core.ToggleEventData(setDataOpt));
                end
                result = true;
                return;
            end
        end
    end
end
% === END FAST PATH ===

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
            result = obj.(datasetVariable).setData(dataset{roiId2}, type, orient, col_channel, options);
        else
            % crop mask to its bounding box
            mask = mask(max([1 bb(3)]):bb(4), max([1 bb(1)]):bb(2));
            mask = repmat(mask,[1, 1, size(dataset{roiId2}, 3), size(dataset{roiId2}, 4)]);
            
            setTime = options.t(1);
            for timePnt = 1:size(dataset{roiId2}, timeDimIndex)
                options.t = [setTime+timePnt-1, setTime+timePnt-1];
                sliceTemp = obj.(datasetVariable).getData(type, orient, col_channel, options);     % get current dataset
                if typeIsImage
                    datasetTemp = dataset{roiId2}(:,:,:,:,timePnt);
                else
                    datasetTemp = dataset{roiId2}(:,:,:,timePnt);
                end
                sliceTemp(mask==1) = datasetTemp(mask==1);
                result = obj.(datasetVariable).setData(sliceTemp, type, orient, col_channel, options);
            end
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
            utils.dlgs.showErrorDialog([], errorText, 'MibDataset.setData4D');
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

% notify about setData method used; skipped when nothing listens or the
% caller passed options.suppressNotify = true (batch loops)
if (~isfield(options, 'suppressNotify') || ~options.suppressNotify) && event.hasListener(obj, 'SetData')
    setDataOpt.type = type;
    setDataOpt.mode = '4D';
    eventdata = core.ToggleEventData(setDataOpt);
    notify(obj, 'SetData', eventdata);
end
end
