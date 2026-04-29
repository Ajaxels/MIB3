function result = setData2D(obj, dataset, type, slice_no, orient, col_channel, options)
% SETDATA2D - set the 2D slice with colors: height:width:colors to the dataset.
%
% Syntax:
%   function result = setData2D(obj, dataset, type, slice_no, orient, col_channel, options)
%
% Input Arguments:
%   - **slice** — 2D image with colors
%   - if options.roiId is **not** **used,** *slice* can be either
%     a cell for images ({1}[1:height, 1:width, 1:colors]; for all other types: {1}[1:height, 1:width]) or
%     a matrix for images ([1:height, 1:width, 1:colors]; for all other types: [1:height, 1:width])
%   - if options.roiId is **used,** *slice* should be
%     a cell array ({roiId}[1:height, 1:width, 1:colors]; for all other types: {roiId}[1:height, 1:width])
%   - **type** — type of the dataset layer to retrieve:
%
%     - ``'image'`` — [*default*] the image layer
%     - ``'labels'`` — labels layer with segmentation
%     - ``'mask'`` — mask layer, supporting segmentation
%     - ``'selection'`` — selection layer, a temporary layer for segmentation
%     - ``'everything'`` — (``'model'``, ``'mask'`` and ``'selection'`` for ``obj.labels.maxMaterials == 63`` only)
%
%   - **slice_no** — [*optional,* can be []], an index of the slice to set:
%
%     - ``[]`` — set the current slice *(default)*
%     - any index — set slice with that index at the current time point (use options to define the time point)
%
%   - **orient** — [*optional,* can be []]
%
%     - ``[]`` — updates transposed dataset in the currently shown orientation *(default)*
%     - ``1`` — updates transposed dataset in the zx configuration: [y,x,z,c,t] → [x,z,y,c,t]
%     - ``2`` — updates transposed dataset in the zy configuration: [y,x,z,c,t] → [y,z,x,c,t]
%     - ``3`` — updates the original dataset in the yx configuration: [y,x,z,c,t]
%
%   - **col_channel** — [*optional*] color channel(s) to update; can be ``[]`` or ``NaN``:
%
%     - when **type** is ``'image'``: a vector of color channel indices:
%
%       - ``[]`` — *(default)* update color channels from ``obj.slices{4}``
%       - ``NaN`` — update all color channels of the dataset
%       - index — update specific color channel(s) with provided index(s)
%
%     - when **type** is ``'labels'``: the material selection:
%
%       - ``[]`` — *(default)* update all materials of the model
%       - ``NaN`` — update all materials of the model
%       - index — update specific material; the selected material in **slice** will have index = 1
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
%     - ``.y`` *(optional)*, [ymin, ymax] of the part of the slice to set (sets .blockModeSwitch to 0)
%     - ``.x`` *(optional)*, [xmin, xmax] of the part of the slice to set (sets .blockModeSwitch to 0)
%     - ``.t`` *(optional)*, [tmin, tmax] indicate the time point to set, when missing return the currently selected time point
%
% Output Arguments:
%   - **result** — true-success, false-fail, result of function execution
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{obj.mibModel.id}.setData2D(slice, 'image', 5);% Call from mibController: set the 5-th slice of the current stack orientation
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{obj.mibModel.id}.setData2D(slice, 'image', 5, 3, 2);% Call from mibController: set the 5-th slice of the XY-orientation, color channel=2
%
%
%   **Attention:** **sensitive** to the ``obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false``
%
%   **Attention:** **NOT** **sensitive** to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters
%

% Updates
% 
result = false;

if nargin < 7; options = struct();   end
if nargin < 6; col_channel = [];   end
if nargin < 5; orient = []; end
if nargin < 4; slice_no = []; end
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

% notify about setData method used
setDataOpt.type = type;
setDataOpt.mode = '2D';
eventdata = core.ToggleEventData(setDataOpt);
notify(obj, 'SetData', eventdata);

end
