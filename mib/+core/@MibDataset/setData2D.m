function result = setData2D(obj, dataset, type, slice_no, orient, col_channel, options)
% SETDATA2D - set the 2D slice with colors: height:width:colors to the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setData2D(dataset, type, slice_no, orient, col_channel, options)
%
% Input Arguments:
%   - **dataset** — [numeric or cell] 2D image with colors to set:
%
%     - When ``options.roiId`` is not used (negative): numeric array or cell ``{1}`` with dimensions:
%
%       - Image: ``[height, width, colors]``
%       - Other types: ``[height, width]``
%
%     - When ``options.roiId`` is used: cell array ``{roiId}`` with dimensions:
%
%       - Image: ``[height, width, colors]``
%       - Other types: ``[height, width]``
%   - **type** — [char] layer type to set:
%
%     - ``'image'`` — image layer (default)
%     - ``'labels'`` — labels layer with segmentation
%     - ``'mask'`` — mask layer for segmentation support
%     - ``'selection'`` — selection layer (temporary segmentation layer)
%     - ``'everything'`` — packed data (``'labels'``, ``'mask'``, ``'selection'`` for ``maxMaterials==63`` only)
%
%   - **slice_no** *(optional)* — [numeric or ``[]``] slice index to set:
%
%     - ``[]`` — set the current slice (default)
%     - integer — set slice at the specified index for current time point
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
%     - ``.y`` *(optional)* — [numeric] ``[ymin, ymax]`` of slice region to set
%     - ``.x`` *(optional)* — [numeric] ``[xmin, xmax]`` of slice region to set
%     - ``.t`` *(optional)* — [numeric] ``[tmin, tmax]`` time point range (default: current time point)
%
% Output Arguments:
%   - **result** — [logical] ``true`` on success, ``false`` on failure
%
% **Example 1** — Set the 5th slice of current stack orientation:
%
%   .. code-block:: matlab
%
%      result = obj.setData2D(dataset, 'image', 5);
%
% **Example 2** — Set the 5th slice in XY orientation, color channel 2:
%
%   .. code-block:: matlab
%
%      result = obj.setData2D(dataset, 'image', 5, 3, 2);
%
%   .. note::
%      This function is **sensitive** to ``obj.blockModeSwitch``. To override block mode, use
%      ``options.blockModeSwitch=false``. It is **not** sensitive to visible ROI selections;
%      to work with ROI areas, use ``options.roiId`` and ``options.fillBg`` parameters.
%

% Updates
% 
result = false;

if nargin < 7; options = struct();   end
if nargin < 6; col_channel = [];   end
if nargin < 5; orient = []; end
if nargin < 4; slice_no = []; end
if nargin < 3; type = 'image'; end

% === FAST PATH ===
% Shortcut for the most common case: Standard in-memory, YX orient, no ROI, no blockMode.
% Directly writes data{1}(...) and skips all ROI/Virtual/blockMode machinery.
% Also skips the notify(obj,'SetData') call when options.suppressNotify==true — the
% MibDataset.SetData event currently has no registered listeners, so the overhead is pure waste
% for batch loops. Future callers that need the event should leave suppressNotify unset (default).
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
            if isempty(slice_no); slice_no = obj.slices{fastOrient}(1); end
            if isfield(options, 't'); timeT = options.t(1); else; timeT = obj.slices{5}(1); end
            if strcmp(type, 'image')
                if isempty(col_channel); col_channel = obj.slices{4};
                elseif isscalar(col_channel) && isnan(col_channel); col_channel = 1:obj.image.colors; end
            else
                col_channel = 1;
            end
            if iscell(dataset); dataset = dataset{1}; end
            obj.(type).setDataFast(dataset, slice_no, col_channel, timeT);   % single-hop in-place write (avoids COW)
            if ismember(type, {'labels', 'everything'}); obj.modelExist = true;
            elseif strcmp(type, 'mask'); obj.maskExist = true; end
            if (~isfield(options, 'suppressNotify') || ~options.suppressNotify) && event.hasListener(obj, 'SetData')
                setDataOpt.type = type; setDataOpt.mode = '2D';
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

% setting default values for the orientation
if isempty(orient) || isnan(orient); orient = obj.orientation; end
if isempty(slice_no); slice_no = obj.slices{orient}(1); end

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

options.z = [slice_no slice_no];
if ~isfield(options, 't'); options.t = [obj.slices{5}(1), obj.slices{5}(2)]; end

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
    for roiId = options.roiId
        mask = obj.hROI.returnMask(roiId);
        bb = obj.hROI.getBoundingBox(roiId);
        options.x = [bb(1), bb(2)];
        options.y = [bb(3), bb(4)];
        
        if ~isnan(options.fillBg)
            result = obj.(datasetVariable).setData(dataset{roiId2}, type, orient, col_channel, options);
        else
            % crop mask to its bounding box
            mask = mask(bb(3):bb(4), bb(1):bb(2));
            mask = repmat(mask, [1, 1, size(dataset{roiId2}, 3)]);
            sliceTemp = obj.(datasetVariable).getData(type, orient, col_channel, options);     % get current dataset
            sliceTemp(mask==1) = dataset{roiId2}(mask==1);
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
            utils.dlgs.showErrorDialog([], errorText, 'MibDataset.setData2D');
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
    setDataOpt.mode = '2D';
    eventdata = core.ToggleEventData(setDataOpt);
    notify(obj, 'SetData', eventdata);
end

end
