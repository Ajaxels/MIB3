function initialize(obj, img, meta, datasetType, modelType, enableSelection)
    % INITIALIZE - init MibDataset class and set all elements of the class to default values.
    %
    % Syntax:
    %   .. code-block:: matlab
    %
    %       obj.initialize(img, meta, datasetType, modelType, enableSelection)
    %
    % Input Arguments:
    %   - **img** — matrix with the image to initialize the class, can be empty
    %   - **meta** — a dictionary with default settings for the class, can be empty;
    %     the following fields are used:
    %
    %     - ``.filename`` — full path to the dataset
    %     - ``.sliceName`` — cell array with slice names, can be empty
    %     - ``.lutColors`` — matrix with LUT colors (colChannel × R G B) in range 0–1
    %     - ``.pixSize`` — structure with physical voxel size:
    %
    %       - ``.x`` — physical width of a pixel
    %       - ``.y`` — physical height of a pixel
    %       - ``.z`` — physical thickness of a pixel
    %       - ``.t`` — time between the frames for 2D movies
    %       - ``.tunits`` — time units
    %       - ``.units`` — physical units for x, y, z; possible values: ``m``, ``cm``, ``mm``, ``um``, ``nm``
    %
    %     - ``.viewPort`` — structure with viewing parameters:
    %
    %       - ``.min`` — vector with minimal value for intensity stretching per color channel
    %       - ``.max`` — vector with maximal value for intensity stretching per color channel
    %       - ``.gamma`` — vector with gamma factor for contrast adjustment per color channel
    %
    %   - **datasetType** — [char] type of the dataset, one of:
    %
    %     - ``'Standard'`` — *(default)* standard image loaded to memory completely
    %     - ``'Virtual'`` — virtual dataset loaded upon demand
    %     - ``'BigData'`` — big-data compatible dataset
    %
    %   - **modelType** — type of the labels layer; when empty, ``'imageOnly'`` is used:
    %
    %     - ``'imageOnly'`` — *(default)* init with the provided image, keep other layers as NaN
    %     - ``'labels'`` — init with model with 255 materials; ``obj.mask``, ``obj.selection`` have the same dimensions as labels
    %     - ``'labels63'`` — init with model with 63 materials; ``obj.mask``, ``obj.selection`` are NaN
    %
    %   - **enableSelection** — a logical (true/false) switch to enable/disable selection layer
    %
    
    if nargin < 6; enableSelection = true; end
    if nargin < 5; modelType = []; end
    if nargin < 4; datasetType = obj.datasetType; end
    if nargin < 3; meta = []; end
    if nargin < 2; img = []; end
    
    if isempty(modelType); modelType = 'imageOnly'; end

    % init meta as empty dictionary
    if isempty(meta)
        meta = core.MibImage.initializeImgInfo();
    else
        % update meta dictionary, filling any missing keys with defaults
        metaDefault = core.MibImage.initializeImgInfo();
        meta = utils.concatenateDictionaries(metaDefault, meta);
    end

    % close open bio-format readers, otherwise the files locked
    if ~isempty(obj.datasetType) && obj.datasetType(1)=='V'; obj.closeVirtualDataset();  end  

    % reset the state of the main layers
    obj.image = NaN;
    obj.labels = NaN;
    obj.mask = core.MibLabels([], meta);
    obj.selection =  core.MibLabels([], meta);
    
    switch datasetType
        case 'Standard'
            obj.image = core.MibImage(img, meta);
            % Build metadata matching the image dimensions for label layers
            labelsMeta = core.MibImage.initializeImgInfo( ...
                'pixSize', obj.image.pixSize, ...
                'Height',  obj.image.height, ...
                'Width',   obj.image.width,  ...
                'Depth',   obj.image.depth,  ...
                'Time',    obj.image.time,   ...
                'Colors',  1);
            labelsDims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];
            switch modelType
                case 'imageOnly'
                    % Allocate a zero-filled MibLabels63 so that selection/mask
                    % layers are immediately usable (e.g. brush tool) without
                    % requiring an explicit createModel call first.
                    obj.labels = core.MibLabels63(zeros(labelsDims, 'uint8'), labelsMeta);
                case 'labels'
                    obj.labels = core.MibLabels(zeros(size(img), 'uint8'), meta);
                case 'labels63'
                    obj.labels = core.MibLabels63(zeros(labelsDims, 'uint8'), labelsMeta);
            end
        case 'Virtual'
            obj.image = core.MibVirtualImage(img, meta);
            obj.labels = core.MibLabels63(zeros([], 'uint8'), meta);

        case 'BigData'
            error('core.MibDataset.initialize: BigData - not implemented');
    end
    
    % update the dataset type
    obj.datasetType = datasetType;
    
    % ---------- main layers ----------
    obj.annotations = core.Annotations;     % handle to class for keeping annotations
    obj.lines3D = core.Lines3D;             % handle to class for keeping 3D Lines and skeletons
    obj.measure = core.Measurements(obj);   % handle to class to keep measurements
    obj.hROI = core.RoiRegion(obj);         % handle to ROI class, core.RoiRegion
    
    % ---------- other properties ----------
    % a vector [min, max] with minimal and maximal coordinates of
    % the axes X of the 'obj.cImageDoc{setId}.handles.imViewAxes' axes; use @code obj.mibModel.getAxesLimits() @endcode to read this property
    obj.axesX = NaN;    
    
    % a vector [min, max] with minimal and maximal coordinates of
    % the axes Y of the 'obj.cImageDoc{setId}.handles.imViewAxes' axes; use @code obj.mibModel.getAxesLimits() @endcode to read this property
    obj.axesY = NaN;    
    
    % a variable to hold a status of the block mode (obj.handles.qab.blockMode), true - enabled, false - disabled
    obj.blockModeSwitch = false;

    % a vector to remember last selected slice number of each 'yx', 'zx', 'zy' planes,
    % @note dimensions: @code [1 1 1] @endcode
    obj.current_yxz = [1 1 1];  

    % switch (0/1) to enable or not the selection, mask, model layers
    obj.enableSelection = enableSelection;
                        
    % a vector with 2 elements of two previously selected materials for use with the 'e' key shortcut
    obj.lastSegmSelection = [2 1];
                        
    % magnification factor for the datasets, 1=100%, 1.5 = 150%; use @code mibModel.getMagFactor() @endcode to read this property
    obj.magFactor = 1;  

    % a switch to indicate presence of the 'Mask' layer. Can be 0 (no mask) or 1 (mask exist)
    obj.maskExist = false;

    % Statistics for the 'Mask' layer with the 'PixelList' info returned by 'regionprops' Matlab function
    obj.maskStats = []; 
    
    % a switch to indicate presence of the 'Model' layer. Can be 0 (no model) or 1 (model exist)
    obj.modelExist = false; 
    
    % Orientation of the currently shown dataset,
    % @li @b 3 = the 'yz' plane, @b default
    % @li @b 1 = the 'zx' plane
    % @li @b 2 = the 'zy' plane
    obj.orientation = 3;    

    % a switch indicating the value of the obj.view.handles.panels.segmentation.handles.restrictMask
    obj.restrictSelectionToMask = false;
                        
    % a switch indicating the value of the obj.view.handles.panels.segmentation.handles.restrictMaterial
    obj.restrictSelectionToMaterial = false;
          
    % show or not ROI on the image axes
    obj.roiShow = false;

    % index of selected Add to Material, where the Selection layer
    % should be targeted, assigned in the AddTo column of the obj.view.handles.panels.segmentation.handles.materialsTable
    % @b 1 - Mask; @b 2 - Exterior; @b 3 - first material of the model, @b 4 - second material etc
    obj.selectedAddToMaterial = 1;
                        
    % color channel selected in the Color channel dropdown (obj.view.handles.panels.selection.handles.colChannel) of the
    % Selection panel. 0 - all colors, 1, 2 - 1st, 2nd ...
    obj.selectedColorChannel = 1;
                        
    obj.selectedMaterial = 1;   % index of material selected in the obj.view.handles.panels.segmentation.handles.materialsTable: @b 1 - Mask; @b 2 - Exterior; @b 3 - first material of the model, @b 4 - second material etc
    
    % index into hROI.Data of the ROI to display; 0 -> show all ROIs,
    % >0 -> show only that specific ROI index
    obj.selectedROI = 0;
    
    % Allocate slices
    % coordinates of the shown part of the dataset
    % @note dimensions are @code ([height, width, depth, color, time],[min max]) @endcode
    % @li (1,[min max]) - height
    % @li (2,[min max]) - width
    % @li (3,[min max]) - depth
    % @li (4,[min max]) - colors , array of color channels to show, for example [1, 3, 4]
    % @li (5,[min max]) - t - time point
    obj.slices{1} = [1, 1];
    obj.slices{2} = [1, 1];
    obj.slices{3} = [1, 1];
    obj.slices{4} = 1:obj.image.colors;
    obj.slices{5} = [1 1];
    
    obj.showAllMaterials = true; % show all materials of the model in the image view axes

    % use or not LUT for visualization of image, a number @b false - do not use; @b true - use a status of obj.view.handles.panels.selection.handles.lutColors
    obj.useLUT = false;
                        
    % update additional properties
    obj.setPixSize(meta{'pixSize'});
    obj.dim_yxzct  = obj.image.dim_yxzct;
    % boundingBox and actionLog are owned by obj.image (core.MibImage).
    % They are parsed from meta{'ImageDescription'} inside MibImage.initialize()
    % and accessed here as obj.image.boundingBox / obj.image.actionLog.

end
