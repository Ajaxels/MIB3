classdef MibDataset < matlab.mixin.Copyable    
    %MIBDATASET Summary of this class goes here
    %   Detailed explanation goes here

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
        % a vector to remember last selected slice number of each 'yx', 'zx', 'zy' planes,
        % @note dimensions: @code [1 1 1] @endcode
        datasetType
        % [char, @default 'Standard'] type of the dataset, one of these
        %   @li 'Standard' - standard image, one that is loaded to memory completely
        %   @li 'Virtual' - virtual dataset that is loaded upon demand
        %   @li 'BigData' - big-data compatible dataset
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
        modelExist 
        % a switch to indicate presence of the 'Model' layer. Can be 0 (no model) or 1 (model exist)
        orientation
        % Orientation of the currently shown dataset,
        % @li @b 3 = the 'yz' plane, @b default
        % @li @b 1 = the 'zx' plane
        % @li @b 2 = the 'zy' plane
        pixSize
        % a structure with diminsions of voxels, @code .x .y .z .t .tunits .units @endcode
        % the fields are
        % @li .x - physical width of a pixel
        % @li .y - physical height of a pixel
        % @li .z - physical thickness of a pixel
        % @li .t - time between the frames for 2D movies
        % @li .tunits - time units
        % @li .units - physical units for x, y, z. Possible values: [m, cm, mm, um, nm]
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
    end

    events
        SetData 
        % when the set data method was used
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        initialize(obj, img, meta, datasetType, modelType, enableSelection) % init MibDataset class and set all elements of the class to default values

        insertSlice(obj, img, insertPosition, meta, options)    % Insert a slice or a dataset into the existing volume

        clearLayer(obj, layer, y, x, z, t, blockModeSwitch)    % Clear the layer, a wrapper function that is using obj.labels.clearLayer or obj.(layer).clearLayer

        closeVirtualDataset(obj)        % Close opened virtual dataset readers, otherwise the files locked

        [axesX, axesY] = getAxesLimits(obj)  % get axes limits for the dataset

        [yMin, yMax, xMin, xMax, zMin, zMax] = getCoordinatesOfShownImage(obj, transposeTo3) % Return minimal and maximal coordinates (XY) of the image that is currently shown.

        slice_no = getCurrentSliceNumber(obj)        % get slice number of the currently shown image

        dataset = getData2D(obj, type, slice_no, orient, col_channel, options)        % Get the a 2D slice with colors: height:width:colors

        dataset = getData3D(obj, type, time, orient, col_channel, options)        % Get the a 3D dataset with colors: height:width:depth:colors

        dataset = getData4D(obj, type, time, orient, col_channel, options)        % Get the a 4D dataset with colors: [height:width:depth:colors:time]

        varargout = getDatasetDimensions(obj, type, orient, options) % Get dimensions of the dataset, [height, width, depth, color, time]

        index = getSelectedMaterialIndex(obj, target)        % return the index of the currently selected material in the mibView.handles.materialsTable

        [labelsList, labelValues, labelPositions, indices] = getSliceLabels(obj, sliceNumber, timePoint, options)        % Get list of labels (mibImage.hLabels) shown at the specified slice

        moveView(obj, x, y, orient)        % Center the image view at the provided coordinates: x, y
        
        setAxesLimits(obj, axesX, axesY)        % set axes limits for the dataset

        newMode = switchDatasetMode(obj, newMode, enableSelection, initWithImage)  % Function to switch between loading datasets to different modes, defined in bj.handles.panels.activeDataset.handles.datasetType as 'Standard', 'Virtual', 'BigData'

        transpose(obj, new_orient)        % Change orientation of the image to the YX, XZ, or YZ plane

        result = setData2D(obj, slice, type, slice_no, orient, col_channel, options)        % set the 2D slice with colors: height:width:colors to the dataset

        result = setData3D(obj, type, dataset, time, orient, col_channel, options)        % set the 3D dataset with colors: height:width:depth:colors to the dataset

        result = setData4D(obj, dataset, type, orient, col_channel, options)        % Set complete 4D dataset with colors [height:width:depth:colors:time]

        fnOut = saveImage(obj, layerType, filename, options)        % Save a data layer ('image'|'labels'|'mask') to file. Intermediate entry point — injects pixSize/boundingBox and delegates to the appropriate layer object's save() method. See core.MibDataset.save for details.

        function obj = MibDataset(img, meta, datasetType, modelType)
            % obj = MibDataset(img, meta, datasetType, modelType)
            % Constructor of MibDataset class
            %
            % Parameters:
            % img: matrix with the image to initialize the class, can be empty
            % meta: a dictionary with default settings for the class, can be empty;
            %       the following fields are used,
            %       .filename -> full path to the dataset
            %       .sliceName -> cell array with slice names, can be empty
            %       .lutColors -> matrix with LUT colors to use (colChannel, R G B) in range 0-1
            %       .pixSize -> dictionary with
            %           @li .x - physical width of a pixel
            %           @li .y - physical height of a pixel
            %           @li .z - physical thickness of a pixel
            %           @li .t - time between the frames for 2D movies
            %           @li .tunits - time units
            %           @li .units - physical units for x, y, z. Possible values: [m, cm, mm, um, nm]
            %       .viewPort -> dictionary with viewing parameters:
            %           @li .min - a vector with minimal value for intensity stretching for each color channel
            %           @li .max - a vector with maximal value for intensity stretching for each color channel
            %           @li .gamma a vector with gamma factor for contrast adjustment for each color channel
            % datasetType: [char, @default 'Standard']type of the dataset, one of these
            %   @li 'Standard' - standard image, one that is loaded to memory completely
            %   @li 'Virtual' - virtual dataset that is loaded upon demand
            %   @li 'BigData' - big-data compatible dataset
            % modelType: type of the labels, 
            % .'imageOnly' - [@default], init with the provided image, keep other layers as NaN
            % .'labels', - init with model with 255 materials; obj.mask, obj.selection have the same dimensions as labels
            % .'labels63' - init with model with 63 materials, obj.mask, obj.selection are NaN

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
end