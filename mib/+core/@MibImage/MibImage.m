classdef MibImage < matlab.mixin.Copyable
    % classdef MibImage < matlab.mixin.Copyable 
    % a base image class of MIB3

    properties
        colors
        % number of color channels
        colormap
        % colormap for indexed images
        colorType 
        % a char with type of colors: grayscale, multichannel, hsvcolor, indexed
        depth
        % number of stacks in the dataset
        dim_yxzct 
        % a matrix with dimensions of the dataset [height, width, depth, colors, time] equal to size obj.data{1} 
        exists = false
        % logical switch indicating whether the obj.data exists or it is empty/dummy place maker
        filename = 'none.tif';
        % the full filename of the dataset
        height
        % image height, px
        data = []
        % a cell array to keep the 'Image' layer. The layer data{1} has image in full resolution,
        % @note The 'Image' layer dimensions: @code [1:height, 1:width, 1:depth, 1:colors, 1:time] @endcode
        dataClass
        % a char with image class, 'uint8', 'uint16', 'uint32';
        actionLog = {}
        % Cell array of per-operation log strings.
        % Each entry is a timestamped record of a processing step, e.g.:
        %   'MIB(2601041823): MIB demo dataset, Huh7 SBEM'
        %   'MIB(2603131934): ImFilter: Gaussian, HSize:3 3, Sigma:0.6'
        % Populated from the pipe-separated tail of the ImageDescription tag
        % when a file is loaded.  Appended to by model operations.
        % MibDataset.actionLog is a Dependent property that forwards here.
        boundingBox = []
        % Physical extent of the dataset as [xmin xmax ymin ymax zmin zmax]
        % in the units stored in pixSize.units (default: µm).
        % Populated from the 'BoundingBox' prefix of the ImageDescription tag
        % when a file is loaded; falls back to a default computed from the
        % image dimensions × voxel size when no BoundingBox tag is present.
        pixSize
        % Physical voxel dimensions. A struct with fields:
        %   .x      physical width of a pixel in .units
        %   .y      physical height of a pixel in .units
        %   .z      physical thickness of a slice in .units
        %   .t      time between frames (for movies)
        %   .units  spatial units: 'm' | 'cm' | 'mm' | 'um' | 'nm'
        %   .tunits time units string
        %
        % IMPORTANT — always write via MibDataset.setPixSize():
        %   ds.setPixSize(newPixSize)       % updates image + labels + mask + selection
        % Read directly from the layer that owns the data:
        %   pixSize = ds.image.pixSize;     % the authoritative copy
        lutColors
        % a matrix with LUT colors [1:colorChannel, R G B], (0-1)
        maskFilename = 'Mask_none.tif'
        % default filename for the mask, when MibLabels63 is used both mask and model are within the same class, thus additional property is needed
        maxInt
        % maximal value that is available in the dataset
        pyramid
        % a structure with specifications of the image pyramid downsampling levels, order of dimensions as in MIB
        % pyramid = struct(); % structure to keep pyramid organization of data, convert axes to MIB order
        % pyramid.levelNames = meta.levelNames;
        % pyramid.levelImageSizes = meta.levelImageSizes(:, [2, 3, 1]);
        % pyramid.levelImageTranslations = meta.levelImageTranslations(:, [2, 3, 1]);
        % pyramid.levelScaleFactors = meta.levelScaleFactors(:, [2, 3, 1]);
        % pyramid.levelVoxelSizes = meta.levelVoxelSizes(:, [2, 3, 1]);
        % pyramid.chunkSizes = meta.chunkSizes(:, [4, 5, 2, 3, 1]);
        % pyramid.shardSizes = meta.shardSizes(:, [4, 5, 2, 3, 1]);
        sliceName
        % a cell array of slice filenames that composing the dataset
        time
        % number of time points in the dataset
        type
        % type of the dataset: image (MibImage), labels (MibLabels), labels63 (MibLabels63), virtual (MibVirtualImage)
        width
        % image width, px
        viewPort    
        % a structure with viewing parameters:
        % @li .min - a vector with minimal value for intensity stretching for each color channel
        % @li .max - a vector with maximal value for intensity stretching for each color channel
        % @li .gamma a vector with gamma factor for contrast adjustment for each color channel
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        
        clearLayer(obj, layerName, y, x, z, t)        % Clear the layer, use parameters to specify the area where the layer should be cleared.

        output = addColorChannel(obj, img, channelId, lutColors, options)    % Add or replace a color channel in the dataset

        insertSlice(obj, img, insertPosition, dim, options)    % Low-level insert of img into obj.data{1} along depth or time; updates sliceName

        dataset = getData(obj, layerType, orient, colChannel, options)   % Get dataset from MibImage class

        varargout = getDatasetDimensions(obj, orient, splitDims, blockModeSwitch)        % Get dimensions of the dataset

        viewPort = getDefaultViewPort(obj)        % get default view port for stretching the image for visualization

        [lowIn, highIn, lowOut, highOut] = getImAdjustStretchCoef(obj, channels)        % Return image stretching coefficients to be used for imadjust function to stretch contrast of the image

        initialize(obj, data, meta, type);  % initialize the class using default or provided values

        result = setData(obj, dataset, layerType, orient, col_channel, options)        % update contents of the class

        fnOut = save(obj, filename, options)        % save image data to file; see core.MibImage.save for details. Lowest-level saver; works standalone without MibDataset/MibModel.

        updateBoundingBox(obj, newBB, xyzShift, imgDims)    % Update obj.boundingBox and recalculate obj.pixSize from the new extent; pass [] as newBB to shift the existing box by xyzShift.

    end

    methods (Static)
        % declaration of static functions in the external files

        imginfo = initializeImgInfo(varargin)   % Create the standard MibImage metadata dictionary, optionally overriding defaults via Name-Value pairs.

        [imageDescription, actionLog] = splitImageDescription(fullStr)  % Split a full ImageDescription string at the first '|' into the BoundingBox part and a cell array of log entries.

        str = buildImageDescription(bb, actionLog)  % Reconstruct the full ImageDescription string from a bounding box vector and action log cell array. Inverse of splitImageDescription.

    end

    methods
        function obj = MibImage(data, meta)
            % obj = MibImage(data, meta)
            % MibImage class constructor
            
            % Constructor for the MibBaseImage class. 
            % Create a new instance of the class with default parameters
            %
            % Parameters:
            % data: an 2D-5D image stack
            % meta: a structure with parameters of the dataset, can be @e [], see obj.initImage for details
            % type: type of the data, 'image', 'labels' (MibLabels class), 'labels63' (MibLabels63 class)
            
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; data = []; end
            
            % update type
            switch class(obj)
                case 'core.MibImage'
                    obj.type = 'image';
                case 'core.MibVirtualImage'
                    obj.type = 'virtual';
                case 'core.MibLabels'
                    obj.type = 'labels';
                case 'core.MibLabels63'
                    obj.type = 'labels63';
            end

            if isempty(data) 
                obj.initialize(data, meta);
            else
                % permute the 3rd dimension into the 4th dimension
                if ndims(data)==3 && size(data, 3) < 4
                    data = permute(data, [1 2 4 3]);
                end
                obj.initialize(data, meta);
            end
        end

        
    end
end