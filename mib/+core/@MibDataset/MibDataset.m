classdef MibDataset < matlab.mixin.Copyable
    % MIBDATASET - Container for a single open dataset with image and annotation layers.
    %
    % MibDataset represents one open dataset in MIB3. Each dataset contains multiple layers
    % (image, labels, mask, selection) and associated metadata. Supports Standard, Virtual, and
    % BigData dataset types with comprehensive layer management and coordinate conversion utilities.

    properties
        % layers
        image
        % image layer, instance of core.MibImage
        labels
        % label layer for the model, instance of core.MibLabels or core.MibLabels63
        mask
        % mask layer 
        selection
        % selection layer
        annotations
        % a handle to class for keeping annotations
        lines3D
        % a handle to class for keeping 3D Lines and skeletons
        measure
        % a handle to class to keep measurements
        hROI
        % handle to ROI class, @b mibRoiRegion

        % other properties
        axesX
        % a vector [min, max] with minimal and maximal coordinates of
        % the axes X of the 'obj.mibController.cImageDoc{setId}.handles.imViewAxes' axes; use @code obj.mibModel.getAxesLimits() @endcode to read this property
        axesY
        % a vector [min, max] with minimal and maximal coordinates of
        % the axes Y of the 'obj.mibController.cImageDoc{setId}.handles.imViewAxes' axes; use @code obj.mibModel.getAxesLimits() @endcode to read this property
        bioFormatsMemoizerMemoDir
        % path to directory where BioFormats Memoizer is storing memo files
        blockModeSwitch
        % a variable to hold a status of the block mode (mibView.handles.toolbarBlockModeSwitch), 1 - enabled, 0 - disabled
        current_yxz
        % a vector to remember last selected slice number of each 'yx', 'zx', 'zy' planes.
        % Dimensions: ``[1 1 1]``
        datasetType
        % [char] type of the dataset (default: ``'Standard'``), one of:
        %
        % - ``'Standard'`` - standard image, loaded to memory completely
        % - ``'Virtual'`` - virtual dataset, loaded upon demand
        % - ``'BigData'`` - big-data compatible dataset
        dim_yxzct
        % a matrix with dimensions of the dataset [height, width, depth, colors, time]
        % equal to size obj.image{1} for non-virtual datasets
        enableSelection
        % a switch (0/1) to enable or not the selection, mask, model layers
        lastSegmSelection
        % a vector with 2 elements of two previously selected materials for use with the 'e' key shortcut
        magFactor
        % magnification factor for the datasets, 1=100%,
        % 1.5 = 150%; use @code mibModel.getMagFactor() @endcode to read this property
        maskExist
        % a switch to indicate presence of the 'Mask' layer. Can be 0 (no mask) or 1 (mask exist)
        maskStats
        % Statistics for the 'Mask' layer with the 'PixelList' info returned by 'regionprops' Matlab function
        instanceIndex
        % Cached per-object index of an instance model (65535/4294967295 types),
        % built by obj.buildInstanceIndex() and used by controllers.InstanceEditor
        % so that split/merge/connect touch only one object's bounding box
        % instead of scanning the whole volume. See utils.instances.objectIndex for
        % the fields. Empty when not built.
        % @note it goes STALE on any edit made outside the editor (brush, undo,
        % a new model). The editor watches the SetData and Undo events and marks
        % it; acting on a stale bounding box writes the wrong voxels, so a stale
        % index must be rebuilt rather than used.
        modelExist
        % a switch to indicate presence of the 'Model' layer. Can be 0 (no model) or 1 (model exist)
        orientation
        % Orientation of the currently shown dataset,
        % @li @b 3 = the 'yz' plane, @b default
        % @li @b 1 = the 'zx' plane
        % @li @b 2 = the 'zy' plane
        restrictSelectionToMask
        % a switch indicating the value of the obj.view.handles.panels.segmentation.handles.restrictMask
        restrictSelectionToMaterial
        % a switch indicating the value of the obj.view.handles.panels.segmentation.handles.restrictMaterial
        roiShow
        % a switch to show or not ROI on the image axes
        selectedAddToMaterial
        % index of selected Add to Material, where the Selection layer should be targeted, assigned in the AddTo column of the obj.view.handles.panels.segmentation.handles.materialsTable
        % @b 1 - Mask; @b 2 - Exterior; @b 3 - first material of the model, @b 4 - second material etc
        selectedColorChannel
        % color channel selected in the Color channel dropdown (obj.view.handles.panels.selection.handles.colChannel) of the
        % Selection panel. 0 - all colors, 1, 2 - 1st, 2nd ...
        selectedMaterial
        % index of material selected in obj.view.handles.panels.segmentation.handles.materialsTable: 
        % @b 1 - Mask; @b 2 - Exterior; @b 3 - first material of the model, @b 4 - second material etc
        selectedROI
        % a vector of indices (as stored in mibRoiRegion class) of the
        % selected ROI in the mibView.handles.mibRoiList table; -1 -> roi is not shown; [1, 3] -> first and third...
        slices 
        % coordinates of the shown part of the dataset
        % @note dimensions are @code ([height, width, color, depth, time],[min max]) @endcode
        % @li (1,[min max]) - height
        % @li (2,[min max]) - width
        % @li (3,[min max]) - z - value
        % @li (4,[min max]) - colors , array of color channels to show, for example [1, 3, 4]
        % @li (5,[min max]) - t - time point
        showAllMaterials
        % a switch to show all materials of the model in the image view axes, or only a single one; defined in context menu of obj.cSegmentation.handles.materialsTable
        useLUT
        % use or not LUT for visualization of image, a number @b 0 - do not use; @b 1 - use a status of obj.view.handles.panels.selection.handles.lutColors
        unlinkMaterials = false
        % unlink materials in the segmentation table, when true click on
        % the segmentation table selects individually Materials or addTo
        % columns
        snapshotFilename = ''
        % filename for the snapshot, used by controllers.Snapshot; initialized on first open
        movieFilename = ''
        % filename for the movie, used by controllers.MakeMovie; initialized on first open
    end

    events
        SetData 
        % when the set data method was used
    end

    methods
        % declaration of methods in external files
        addFrame(obj, BatchOpt, parentFigure)                   % add a frame by specifying dX/dY padding
        addFrameToImage(obj, BatchOpt, parentFigure)            % add a frame by specifying new absolute width and height
        [result, newMaterialIndex] = addMaterial(obj, materialName, newMaterialIndex, wb)        % add a material; scans time-points for large models, checks capacity, updates metadata
        allocateMask(obj)        % allocate a zero-filled Mask layer when it is missing; no-op for MibLabels63 models (mask lives in the packed bits)
        clearLayer(obj, layer, y, x, z, t, blockModeSwitch)    % Clear the layer, a wrapper function that is using obj.labels.clearLayer or obj.(layer).clearLayer
        closeVirtualDataset(obj)        % Close opened virtual dataset readers, otherwise the files locked
        [x, y, z] = convertPixelsToUnits(obj, x, y, z)        % Convert pixel coordinates to physical imaging units using pixSize and boundingBox
        [x, y, z] = convertUnitsToPixels(obj, x, y, z)        % Convert physical imaging units to pixel coordinates using pixSize and boundingBox
        PixelIdxList = convertPixelIdxListCrop2Full(obj, PixelIdxListCrop, options) % Convert PixelIdxList of a cropped sub-volume to the full dataset
        convertModel(obj, newType, wb)        % convert the segmentation model to a different storage type (63/255/65535/4294967295 or indexed objects)
        stats = stitchModelInstances(obj, options, wb)        % stitch per-slice 2D instance labels into a consistent 3D instance model
        [index, cancelled] = buildInstanceIndex(obj, options, wb)  % build or refresh obj.instanceIndex, the per-object bounding box cache of an instance model
        snapshot = copyModelLayers(obj)        % take independent copies of the labels, selection and mask layer objects (model type travels with them)
        restoreModelLayers(obj, snapshot)      % put back layer objects taken with copyModelLayers
        result = copySlice(obj, sliceFrom, sliceTo, orient)      % Copy a slice from one position to another across all layers
        createModel(obj, modelType, modelMaterialNames)        % allocate memory for a new model layer; handles conversion between packed (type-63) and separate-layer models
        result = cropDataset(obj, cropF, options)        % Crop all layers of the dataset (image, labels, mask, selection); handles Virtual → Standard conversion
        result = deleteSlice(obj, sliceNumbers, orient, options) % Delete slices from all layers and synchronize metadata
        flipDataset(obj, mode, parentFigure, showWaitbar)       % flip dataset horizontally, vertically, along Z or T
        [axesX, axesY] = getAxesLimits(obj)  % get axes limits for the dataset
        [yMin, yMax, xMin, xMax, zMin, zMax] = getCoordinatesOfShownImage(obj, transposeTo3) % Return minimal and maximal coordinates (XY) of the image that is currently shown.
        [stretchX, stretchY] = getDisplayStretch(obj, orient) % Aspect-ratio stretch of the shown slice along the horizontal and vertical screen axes
        slice_no = getCurrentSliceNumber(obj)        % get slice number of the currently shown image
        timePnt = getCurrentTimePoint(obj)        % Get time point of the currently shown image.
        dataset = getData2D(obj, type, slice_no, orient, col_channel, options)        % Get the a 2D slice with colors: height:width:colors
        dataset = getData3D(obj, type, time, orient, col_channel, options)        % Get the a 3D dataset with colors: height:width:depth:colors
        dataset = getData4D(obj, type, time, orient, col_channel, options)        % Get the a 4D dataset with colors: [height:width:depth:colors:time]
        varargout = getDatasetDimensions(obj, type, orient, options) % Get dimensions of the dataset, [height, width, depth, color, time]
        dataset = getPixelIdxList(obj, type, PixelIdxList, options)  % Get pixel values at a list of linear indices; routes to correct layer (image/labels/mask/selection)
        bb = getRoiBoundingBox(obj, roiIndex)        % Return the bounding box for a ROI at its native orientation.
        index = getSelectedMaterialIndex(obj, target)        % return the index of the currently selected material in the mibView.handles.materialsTable
        [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, sliceNumber, timePoint, options)        % Get list of labels (mibImage.hLabels) shown at the specified slice
        initialize(obj, img, meta, datasetType, modelType, enableSelection) % init MibDataset class and set all elements of the class to default values
        insertMaterial(obj, materialIndex, materialName, wb)     % insert a new material at the specified position, shifting pixel values and metadata
        insertSlice(obj, img, insertPosition, meta, options)    % Insert a slice or a dataset into the existing volume
        result = loadMask(obj, filenames, options)   % Load a binary mask into this dataset from files or a raw array
        result = loadModel(obj, filenames, options)          % load a segmentation model from files or a raw array; orchestrates loader dispatch, dimension validation, and metadata assignment
        moveMaskToModelDataset(obj, action_type, options)            % move Mask layer to Model for full dataset (fast path, no ROI/block mode)
        moveMaskToSelectionDataset(obj, action_type, options)        % move Mask layer to Selection for full dataset (fast path, no ROI/block mode)
        moveModelToMaskDataset(obj, action_type, options)            % move Model material to Mask for full dataset (fast path, no ROI/block mode)
        moveModelToSelectionDataset(obj, action_type, options)       % move Model material to Selection for full dataset (fast path, no ROI/block mode)
        moveSelectionToMaskDataset(obj, action_type, options)        % move Selection layer to Mask for full dataset (fast path, no ROI/block mode)
        moveSelectionToModelDataset(obj, action_type, options)       % move Selection layer to Model for full dataset (fast path, no ROI/block mode)
        moveView(obj, x, y, orient)        % Center the image view at the provided coordinates: x, y
        removeMaterial(obj, materialIndices, wb)                % remove materials: remaps/zeros pixel data across time-points, then updates metadata
        reorderMaterials(obj, newOrder, wb)                     % reorder materials in the model according to a permutation vector (small models only)
        result = resliceDataset(obj, sliceNumbers, orient, options) % Keep only indexed slices across all layers and synchronize metadata
        rotateDataset(obj, mode, parentFigure, showWaitbar)     % rotate dataset 90 or -90 degrees
        fnOut = saveImage(obj, layerType, filename, options)        % Save a data layer ('image'|'labels'|'mask') to file. Intermediate entry point - injects pixSize/boundingBox and delegates to the appropriate layer object's save() method. See core.MibDataset.save for details.
        setAxesLimits(obj, axesX, axesY)        % set axes limits for the dataset
        result = setData2D(obj, slice, type, slice_no, orient, col_channel, options)        % set the 2D slice with colors: height:width:colors to the dataset
        result = setData3D(obj, type, dataset, time, orient, col_channel, options)        % set the 3D dataset with colors: height:width:depth:colors to the dataset
        result = setData4D(obj, dataset, type, orient, col_channel, options)        % Set complete 4D dataset with colors [height:width:depth:colors:time]
        result = setPixelIdxList(obj, type, dataset, PixelIdxList, options)  % Write pixel values at a list of linear indices; routes to correct layer and updates modelExist/maskExist flags
        setPixSize(obj, val)        % Propagate a new pixSize struct to image, labels, mask, and selection layers.
        swapMaterials(obj, material1, material2, wb)            % swap two materials in the model: pixel data and metadata
        result = swapSlices(obj, sliceFrom, sliceTo, orient)     % Swap two or more slices across all layers
        newMode = switchDatasetMode(obj, newMode, enableSelection, initWithImage)  % Function to switch between loading datasets to different modes, defined in bj.handles.panels.activeDataset.handles.datasetType as 'Standard', 'Virtual', 'BigData'
        transpose(obj, new_orient)        % Change orientation of the image to the YX, XZ, or YZ plane
        transposeDataset(obj, mode, parentFigure, showWaitbar, noColorChannels)  % transpose dataset between YZ/XZ/XY/ZX/Z-T/Z-C
        updateBoundingBox(obj, newBB, xyzShift, imgDims)  % Delegate bounding-box update to obj.image; ds.image.pixSize is updated in place.

        function obj = MibDataset(img, meta, datasetType, modelType)
            % MIBDATASET - Constructor for a dataset container with image and annotation layers.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = core.MibDataset()
            %      obj = core.MibDataset(img)
            %      obj = core.MibDataset(img, meta)
            %      obj = core.MibDataset(img, meta, datasetType)
            %      obj = core.MibDataset(img, meta, datasetType, modelType)
            %
            % Input Arguments:
            %   - **img** *(optional)* - [numeric] matrix with the image data; can be empty or omitted
            %   - **meta** *(optional)* - [dictionary] metadata dictionary with optional fields:
            %
            %     - ``.filename`` - [char] full path to the dataset
            %     - ``.sliceName`` - [cell] cell array with slice names
            %     - ``.lutColors`` - [numeric] LUT colors matrix ``(colChannel, RGB)`` in range ``[0-1]``
            %     - ``.pixSize`` - [dictionary] physical pixel size with sub-fields:
            %
            %       - ``.x`` - [numeric] physical width of a pixel
            %       - ``.y`` - [numeric] physical height of a pixel
            %       - ``.z`` - [numeric] physical thickness of a voxel
            %       - ``.t`` - [numeric] time between frames for 2D movies
            %       - ``.tunits`` - [char] time units (e.g., ``'sec'``, ``'ms'``)
            %       - ``.units`` - [char] spatial units: ``'m'``, ``'cm'``, ``'mm'``, ``'um'``, or ``'nm'``
            %
            %     - ``.viewPort`` - [dictionary] viewing parameters with sub-fields:
            %
            %       - ``.min`` - [numeric] minimal value for intensity stretching per channel
            %       - ``.max`` - [numeric] maximal value for intensity stretching per channel
            %       - ``.gamma`` - [numeric] gamma factor for contrast adjustment per channel
            %
            %   - **datasetType** *(optional)* - [char] dataset type (default: ``'Standard'``):
            %
            %     - ``'Standard'`` - image loaded completely into memory
            %     - ``'Virtual'`` - image loaded on demand
            %     - ``'BigData'`` - big-data compatible dataset
            %
            %   - **modelType** *(optional)* - [char] labels layer type (default: ``'imageOnly'``):
            %
            %     - ``'imageOnly'`` - initialize with image only; other layers are ``NaN``
            %     - ``'labels'`` - initialize model with 255 materials; ``mask`` and ``selection`` same dimensions as ``labels``
            %     - ``'labels63'`` - initialize model with 63 materials; ``mask`` and ``selection`` are ``NaN``
            %
            % Output Arguments:
            %   - **obj** - [core.MibDataset] initialized dataset instance
            %
            % **Example 1** - Minimal: create an empty dataset:
            %
            %   .. code-block:: matlab
            %
            %      ds = core.MibDataset();
            %
            % **Example 2** - Create from a raw uint8 volume (grayscale):
            %
            %   .. code-block:: matlab
            %
            %      vol = imread('myImage.tif');    % [H, W] or [H, W, C]
            %      ds = core.MibDataset(vol);
            %
            % **Example 3** - Create from a 3D stack with 63-material labels:
            %
            %   .. code-block:: matlab
            %
            %      vol = zeros(512, 512, 40, 'uint8');    % [H, W, Z]
            %      ds = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
            %      ds.image.pixSize.x = 0.013;
            %      ds.image.pixSize.y = 0.013;
            %      ds.image.pixSize.z = 0.030;
            %      ds.image.sliceName = {'myStack.tif'};
            %      ds.updateBoundingBox([], [0 0 0]);
            %
            % **Example 4** - Create with pre-filled metadata:
            %
            %   .. code-block:: matlab
            %
            %      meta = dictionary();
            %      meta('filename') = 'C:\data\myImage.tif';
            %      ds = core.MibDataset(vol, meta, 'Standard', 'labels63');
            %
            % **Example 5** - Replace active dataset in model with fresh volume:
            %
            %   .. code-block:: matlab
            %
            %      vol = imread('newdata.tif');
            %      obj.mibModel.I{obj.mibModel.id} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
            %      obj.mibModel.I{obj.mibModel.id}.image.sliceName = {'newdata.tif'};
            %      notify(obj.mibModel, 'NewDataset');
            %      notify(obj.mibModel, 'ShowImage');
            %

            if nargin < 4; modelType = 'imageOnly'; end
            if nargin < 3; datasetType = 'Standard'; end
            if nargin < 2; meta = []; end
            if nargin < 1; img = []; end

            % init meta as empty struct
            if isempty(meta); meta = dictionary(); end
            
            % initialize default and custom parameters from the supplied img
            obj.initialize(img, meta, datasetType, modelType);

        end
    end

    methods (Static)
        outArray = applySizeMismatch(rawArray, imgH, imgW, action, offsetY, offsetX)   % crop/place or resize rawArray (Model/Mask) to [imgH, imgW]; pure data transform used by loadModel/loadMask after a size-mismatch dialog
    end

    methods (Static, Access = private)
        choice = promptSizeMismatch(itemLabel, curH, curW, imgH, imgW, boundingBox, options)   % ask the user how to resolve a Model/Mask size mismatch (crop/place, resize, or use bounding box); returns struct('action','offsetY','offsetX','cancelled')
    end
end
