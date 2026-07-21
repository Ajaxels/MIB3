function result = setData3D(obj, dataset, type, time, orient, col_channel, options)
% SETDATA3D - set the 3D dataset with colors: height:width:depth:colors to the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setData3D(dataset, type, time, orient, col_channel, options)
%
% Input Arguments:
%   - **dataset** — [numeric or cell] 3D image with colors to set:
%
%     - When ``options.roiId`` is not used (negative): numeric array or cell ``{1}`` with dimensions:
%
%       - Image: ``[height, width, depth, colors]``
%       - Other types: ``[height, width, depth]``
%
%     - When ``options.roiId`` is used: cell array ``{roiId}`` with dimensions:
%
%       - Image: ``[height, width, depth, colors]``
%       - Other types: ``[height, width, depth]``
%   - **type** — [char] layer type to set:
%
%     - ``'image'`` — image layer (default)
%     - ``'labels'`` — labels layer with segmentation
%     - ``'mask'`` — mask layer for segmentation support
%     - ``'selection'`` — selection layer (temporary segmentation layer)
%     - ``'everything'`` — packed data (``'labels'``, ``'mask'``, ``'selection'`` for ``maxMaterials==63`` only)
%
%   - **time** *(optional)* — [numeric or ``[]``] time point index to set:
%
%     - ``[]`` — set the current time point (default)
%     - integer — set dataset at the specified time point
%
%   - **orient** *(optional)* — [numeric or ``[]``] orientation for dataset update:
%
%     - ``[]`` — use currently shown orientation (default)
%     - ``1`` — ``ZX`` plane: transpose ``[y,x,z,c,t]`` → ``[x,z,y,c,t]``
%     - ``2`` — ``ZY`` plane: transpose ``[y,x,z,c,t]`` → ``[y,z,x,c,t]``
%     - ``3`` — ``YX`` plane: native orientation ``[y,x,z,c,t]``
%
%   - **col_channel** *(optional)* — [numeric, ``[]``, or ``NaN``] channel(s) or material(s) to update:
%
%     - When **type** is ``'image'`` (color channel indices):
%
%       - ``[]`` — use channels from ``obj.slices{4}`` (default)
%       - ``NaN`` — update all color channels
%       - integer or vector — update specific channel(s)
%
%     - When **type** is ``'labels'`` (material selection):
%
%       - ``[]`` or ``NaN`` — update all materials (default)
%       - integer — update specific material (data with value 1 will get this material index)
%   - **options** *(optional)* — [struct] additional parameters:
%
%     - ``.blockModeSwitch`` — [logical] override block mode (``false`` = full dataset, ``true`` = visible area only)
%     - ``.roiId`` — [numeric or ``[]``] ROI mode control:
%
%       - ``-1`` or missing — full dataset without ROI (default)
%       - ``[]`` — currently selected ROI
%       - ``0`` — all ROIs
%       - integer — specific ROI by index
%
%     - ``.fillBg`` — [numeric or ``NaN``] fill color for ROI background:
%
%       - ``NaN`` — crop to rectangular ROI bounding box (default)
%       - number — fill areas outside ROI with this intensity
%
%     - ``.y`` *(optional)* — [numeric] ``[ymin, ymax]`` of dataset region to set
%     - ``.x`` *(optional)* — [numeric] ``[xmin, xmax]`` of dataset region to set
%     - ``.z`` *(optional)* — [numeric] ``[zmin, zmax]`` of dataset region to set
%     - ``.level`` *(optional)* — [numeric] image pyramid level index
%     - ``.PixelIdxList`` *(optional)* — [numeric vector] pixel indices to update (XY orientation). When used,
%       all other spatial parameters are ignored and ``dataset`` should be a vector. **Not implemented for 'image' type**
%
% Output Arguments:
%   - **result** — [logical] ``true`` on success, ``false`` on failure
%
% **Example 1** — Set 3D dataset for current time point in current orientation:
%
%   .. code-block:: matlab
%
%      result = obj.setData3D(dataset, 'image');
%
% **Example 2** — Set 3D dataset for time point 5 in XY orientation:
%
%   .. code-block:: matlab
%
%      result = obj.setData3D(dataset, 'image', 5, 3);
%
% **Example 3** — Set selection for time point 5 in ZX orientation, color channel 2:
%
%   .. code-block:: matlab
%
%      result = obj.setData3D(dataset, 'selection', 5, 1, 2);
%   **Example 4**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.mibModel.I{obj.mibModel.id}.setData3D(dataset, 'image', dataset, [], 3);% Call from mibController: set the 4D dataset for the current time point in the XY orientation
%
%
%   **Attention:** **sensitive** to the ``obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false``
%
%   **Attention:** **NOT** **sensitive** to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters
%

% Updates
% 

if nargin < 7; options = struct();   end
if nargin < 6; col_channel = [];   end
if nargin < 5; orient = []; end
if nargin < 4; time = []; end
if nargin < 3; type = 'image'; end

result = false;

% === FAST PATH ===
% Standard in-memory, YX orient (3), no ROI, no blockMode, no x/y/z subregion.
% Directly writes data{1} and skips ROI/Virtual/blockMode machinery.
% Set options.suppressNotify = true in batch loops to also skip ToggleEventData+notify.
if strcmp(obj.datasetType, 'Standard') && ~strcmp(type, 'everything')
    fastOrient = orient;
    if isempty(fastOrient) || (isscalar(fastOrient) && isnan(fastOrient))
        fastOrient = obj.orientation;
    end
    if fastOrient == 3 && ~isfield(options, 'x') && ~isfield(options, 'y') && ~isfield(options, 'z') && ~isfield(options, 'PixelIdxList')
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
            else
                col_channel = 1;
            end
            if iscell(dataset); dataset = dataset{1}; end
            if strcmp(type, 'mask') && ~obj.mask.exists; obj.allocateMask(); end
            obj.(type).setDataFast(dataset, [], col_channel, time);   % [] z ⇒ all-z volume write; single-hop in-place (avoids COW)
            if ismember(type, {'labels', 'everything'}); obj.modelExist = true;
            elseif strcmp(type, 'mask'); obj.maskExist = true; end
            if (~isfield(options, 'suppressNotify') || ~options.suppressNotify) && event.hasListener(obj, 'SetData')
                setDataOpt.type = type; setDataOpt.mode = '3D';
                notify(obj, 'SetData', core.ToggleEventData(setDataOpt));
            end
            result = true;
            return;
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
    % Route through the MibDataset wrapper so the write lands in the correct
    % layer: for 63-material datasets selection/mask are bit-packed into
    % obj.labels, but for >63 materials obj.selection / obj.mask are separate
    % layers. Calling obj.labels.setPixelIdxList directly would misroute a
    % selection/mask write into the model layer.
    result = obj.setPixelIdxList(type, dataset, options.PixelIdxList);
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
                sliceTemp = obj.(datasetVariable).getData(type, orient, col_channel, options);     % get current dataset
                sliceTemp(mask==1) = dataset{roiId2}(mask==1);
            else
                mask = repmat(mask, [1, 1, size(dataset, 3), size(dataset, max([ndims(dataset) 3]))]);
                sliceTemp = obj.(datasetVariable).getData(type, orient, col_channel, options);     % get current dataset
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

% notify about setData method used; skipped when nothing listens or the
% caller passed options.suppressNotify = true (batch loops)
if (~isfield(options, 'suppressNotify') || ~options.suppressNotify) && event.hasListener(obj, 'SetData')
    setDataOpt.type = type;
    setDataOpt.mode = '3D';
    eventdata = core.ToggleEventData(setDataOpt);
    notify(obj, 'SetData', eventdata);
end
end
