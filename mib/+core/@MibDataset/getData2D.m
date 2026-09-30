function dataset = getData2D(obj, type, slice_no, orient, col_channel, options)
% GETDATA2D - Get the a 2D slice with colors: height:width:colors.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getData2D(type, slice_no, orient, col_channel, options)
%
% Input Arguments:
%   - **type** - type of the dataset layer to retrieve:
%
%     - ``'image'`` - [*default*] the image layer
%     - ``'labels'`` - labels layer with segmentation
%     - ``'mask'`` - mask layer, supporting segmentation
%     - ``'selection'`` - selection layer, a temporary layer for segmentation
%     - ``'everything'`` - (``'model'``, ``'mask'`` and ``'selection'`` for ``obj.labels.maxMaterials == 63`` only)
%
%   - **slice_no** - [*optional,* can be []], an index of the slice to get:
%
%     - ``[]`` - get the current slice *(default)*
%     - any index - get slice with that index at the current time point (use options to define the time point)
%
%   - **orient** - [*optional,* can be []]
%
%     - ``[]`` - returns transposed dataset in the currently shown orientation *(default)*
%     - ``1`` - returns transposed dataset in the zx configuration: [y,x,z,c,t] → [z,x,y,c,t]
%       (rows = Z, columns = X: X stays horizontal as in the yx view)
%     - ``2`` - returns transposed dataset in the zy configuration: [y,x,z,c,t] → [y,z,x,c,t]
%     - ``3`` - returns the original dataset in the yx configuration: [y,x,z,c,t]
%
%   - **col_channel** - [*optional*] color channel(s) to retrieve; can be ``[]`` or ``NaN``:
%
%     - when **type** is ``'image'``: a vector of color channel indices:
%
%       - ``[]`` - *(default)* take color channels from ``obj.slices{4}``
%       - ``NaN`` - take all color channels of the dataset
%       - index - get specific color channel(s) with provided index(s)
%
%     - when **type** is ``'labels'``: the material selection:
%
%       - ``[]`` - *(default)* take all materials of the model
%       - ``NaN`` - take all materials of the model
%       - index - get specific material; the selected material will have index = 1
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
%     - ``.y`` *(optional)*, [ymin, ymax] of the part of the slice to take (sets .blockModeSwitch to 0)
%     - ``.x`` *(optional)*, [xmin, xmax] of the part of the slice to take (sets .blockModeSwitch to 0)
%     - ``.t`` *(optional)*, [tmin, tmax] indicate the time point to take,
%       when missing return the currently selected time point
%     - ``.level`` *(optional)*, an index of image level from the image pyramid
%
% Output Arguments:
%   - **dataset** - a cell array with 2D image with colors.
%     For the 'image' type: {roiId}[1:height, 1:width, 1:colors]; for all other types: {roiId}[1:height, 1:width]
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     slice = obj.mibModel.I{obj.mibModel.id}.getData2D('image', 5);% Call from mibController: get the 5-th slice of the current stack orientation
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     slice = obj.mibModel.I{obj.mibModel.id}.getData2D('image', 5, 3, 2);% Call from mibController:  get the 5-th slice of the XY-orientation, color channel=2
%
%
%   **Attention:** **sensitive** to the ``obj.cQuickAccessBar.view.handles.blockMode; to override the blockMode use options.blockModeSwitch=false``
%
%   **Attention:** **NOT** **sensitive** to the shown ROI (obj.cQuickAccessBar.view.handles.roiMode), if areas under ROIs are required use options.roiId and options.fillBg parameters
%

% Updates
% 

if nargin < 6; options = struct();   end
if nargin < 5; col_channel = [];   end
if nargin < 4; orient = []; end
if nargin < 3; slice_no = []; end
if nargin < 2; type = 'image'; end

% === FAST PATH ===
% Shortcut for the most common case: Standard in-memory dataset, YX orientation (orient==3),
% no ROI, no viewport crop, no x/y/z subregion. Bypasses MibImage.getData() entirely
% (eliminates 3 function-call levels, ~25 guard checks, blockMode limit clamping, and cell
% boxing overhead per call - critical for slice-by-slice batch loops).
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
        % Exclude: labels with a material index (needs binary mask extraction → slow path)
        skipLabelsIdx = strcmp(type, 'labels') && ~isempty(col_channel) && ...
                        isnumeric(col_channel) && ~any(isnan(col_channel(:)));
        % Exclude: MibLabels63 model where selection/mask are packed into obj.labels
        skipPacked63  = (obj.labels.maxMaterials == 63) && ~strcmp(type, 'image');

        if blockIsOff && noROI && ~skipLabelsIdx && ~skipPacked63
            if isempty(slice_no); slice_no = obj.slices{fastOrient}(1); end
            if isfield(options, 't'); timeT = options.t(1); else; timeT = obj.slices{5}(1); end
            if strcmp(type, 'image')
                if isempty(col_channel); col_channel = obj.slices{4};
                elseif isscalar(col_channel) && isnan(col_channel); col_channel = 1:obj.image.colors; end
            else
                col_channel = 1;  % selection / mask / labels: single colour channel
            end
            dataset = {squeeze(obj.(type).data(:,:,slice_no,col_channel,timeT))};
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

% update options .x, .y .z
if ~isfield(options, 'z'); options.z = [slice_no, slice_no]; end
if ~isfield(options, 't'); options.t = [obj.slices{5}(1), obj.slices{5}(2)]; end

if isfield(options, 'blockModeSwitch') && options.blockModeSwitch
    [axesX, axesY] = obj.getAxesLimits();
    options.x = ceil(axesX);
    options.y = ceil(axesY);
end

% Pass current magnification factor so pyramid-based virtual images (zarr3)
% can select the correct pyramid level and pre-resize the returned slice to
% match the display resolution.  For non-pyramid datasets this is ignored.
% When resizeToMagnification=false the caller wants pixel-for-pixel data
% (e.g. padded pan mode), so pass magFactor=1 to suppress pyramid resizing.
if ~isfield(options, 'magFactor')
    if isfield(options, 'resizeToMagnification') && ~options.resizeToMagnification
        options.magFactor = 1;
    else
        options.magFactor = obj.magFactor;
    end
end

if options.roiId >= 0
    % get indices of ROI
    if options.roiId == 0
        [~, options.roiId] = obj.hROI.getNumberOfROI(orient);  % get number of ROI for the selected orientation
    end
    
    dataset = {};   % stays empty when no ROIs match, e.g. stale ROI mode without ROIs
    roiId2 = 1;
    for roiId = options.roiId
        mask = obj.hROI.returnMask(roiId);
        bb = obj.hROI.getBoundingBox(roiId);
        options.x = [bb(1), bb(2)];
        options.y = [bb(3), bb(4)];
        
        sliceTemp = obj.(datasetVariable).getData(type, orient, col_channel, options);
        if ~isnan(options.fillBg)
            mask = mask(bb(3):bb(4), bb(1):bb(2));
            mask = repmat(mask,[1, 1, numel(col_channel)]);
            sliceTemp(~mask) = options.fillBg;
        end
        dataset{roiId2} = sliceTemp; %#ok<AGROW>
        roiId2 = roiId2 + 1;
    end
else
    if obj.labels.maxMaterials ~= 63 && strcmp(type, 'everything')
        errorText = sprintf('Type = "everything" available only for the models with 63 materials!');
        utils.dlgs.showErrorDialog([], errorText, 'MibDataset.getData2D');
        dataset = [];
        return;
    end
    dataset = {squeeze(obj.(datasetVariable).getData(type, orient, col_channel, options))};
end
end
