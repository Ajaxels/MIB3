classdef MibImage < matlab.mixin.Copyable
    % MIBIMAGE - a base image class of MIB3.
    %

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
        % a cell array to keep the 'Image' layer. The layer data{1} has image in full resolution.
        % Note: The 'Image' layer dimensions: ``[1:height, 1:width, 1:depth, 1:colors, 1:time]``
        dataClass
        % a char with image class, 'uint8', 'uint16', 'uint32';
        actionLog = {}
        % Cell array of per-operation log strings.
        % Each entry is a timestamped record of a processing step, e.g.:
        %
        %   'MIB(2601041823): MIB demo dataset, Huh7 SBEM'
        %   'MIB(2603131934): ImFilter: Gaussian, HSize:3 3, Sigma:0.6'
        %
        % Populated from the pipe-separated tail of the ImageDescription tag
        % when a file is loaded.  Appended to by model operations via
        % ``updateActionLog()``, which prepends the timestamp automatically:
        %
        %   img.updateActionLog('ImFilter: Gaussian, HSize:3 3, Sigma:0.6');
        %
        % MibDataset.actionLog is a Dependent property that forwards here.
        boundingBox = []
        % Physical extent of the dataset as [xmin xmax ymin ymax zmin zmax]
        % in the units stored in pixSize.units (default: µm).
        % Populated from the 'BoundingBox' prefix of the ImageDescription tag
        % when a file is loaded; falls back to a default computed from the
        % image dimensions × voxel size when no BoundingBox tag is present.
        pixSize
        % Physical voxel dimensions. A struct with fields:
        %
        % - ``.x`` — physical width of a pixel in ``.units``
        % - ``.y`` — physical height of a pixel in ``.units``
        % - ``.z`` — physical thickness of a slice in ``.units``
        % - ``.t`` — time between frames (for movies)
        % - ``.units`` — spatial units: 'm' | 'cm' | 'mm' | 'um' | 'nm'
        % - ``.tunits`` — time units string
        %
        % IMPORTANT — always write via ``MibDataset.setPixSize()``:
        %
        %   ds.setPixSize(newPixSize)       % updates image + labels + mask + selection
        %
        % Read directly from the layer that owns the data:
        %
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
        sliceSize
        % an [N×2] double matrix of original [height, width] per slice; empty [] when all slices share the same size
        time
        % number of time points in the dataset
        type
        % type of the dataset: image (MibImage), labels (MibLabels), labels63 (MibLabels63), virtual (MibVirtualImage)
        width
        % image width, px
        viewPort    
        % a structure with viewing parameters:
        %
        % - ``.min`` — a vector with minimal value for intensity stretching for each color channel
        % - ``.max`` — a vector with maximal value for intensity stretching for each color channel
        % - ``.gamma`` — a vector with gamma factor for contrast adjustment for each color channel
    end

    methods
        % declaration of methods in external files
        output = addColorChannel(obj, img, channelId, lutColors, options)    % Add or replace a color channel in the dataset
        clearLayer(obj, layerName, y, x, z, t, blockModeSwitch)        % Clear the layer, use parameters to specify the area where the layer should be cleared.
        status = convertImage(obj, format, options)     % Convert pixel data to a new color type or bit depth
        crop(obj, cropF)        % Crop obj.data{1} in-place and update scalar dimension properties (height, width, depth, time, dim_yxzct, sliceName)
        result = copySlice(obj, sliceFrom, sliceTo, orient)     % Copy a slice from one position to another within obj.data{1}
        result = deleteSlice(obj, sliceNumbers, orient)         % Remove slices from obj.data{1} along the specified dimension; updates dim_yxzct and sliceName
        dataset = getData(obj, layerType, orient, colChannel, options)   % Get dataset from MibImage class
        varargout = getDatasetDimensions(obj, orient, splitDims, blockModeSwitch)        % Get dimensions of the dataset
        viewPort = getDefaultViewPort(obj)        % get default view port for stretching the image for visualization
        [lowIn, highIn, lowOut, highOut] = getImAdjustStretchCoef(obj, channels)        % Return image stretching coefficients to be used for imadjust function to stretch contrast of the image
        dataset = getPixelIdxList(obj, type, PixelIdxList)          % Get pixel values at a list of linear indices; handles MibLabels63 bit-unpacking automatically
        meta = getMeta(obj)        % collect properties into a metadata dictionary (inverse of initialize)
        initialize(obj, data, meta, type);  % initialize the class using default or provided values
        insertSlice(obj, img, insertPosition, dim, options)    % Low-level insert of img into obj.data{1} along depth or time; updates sliceName
        result = resliceDataset(obj, sliceNumbers, orient)      % Keep only the indexed slices; remove all others from obj.data{1}
        setMeta(obj, meta)        % apply a metadata dictionary to properties (inverse of getMeta)
        result = setData(obj, dataset, layerType, orient, col_channel, options)        % update contents of the class
        result = setPixelIdxList(obj, type, dataset, PixelIdxList)  % Write pixel values at a list of linear indices; handles MibLabels63 bit-packing automatically
        fnOut = save(obj, filename, options)        % save image data to file; see core.MibImage.save for details. Lowest-level saver; works standalone without MibDataset/MibModel.
        result = swapSlices(obj, sliceFrom, sliceTo, orient)    % Swap two or more slices within obj.data{1}
        updateActionLog(obj, logEntry, action, entryIndex)    % Append, insert, delete, or modify a timestamped entry in obj.actionLog.
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
            % MIBIMAGE - obj = MibImage(data, meta).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MibImage(data, meta)
            %
            % MibImage class constructor
            %
            % Creates a new MibImage for raw pixel data.  The constructor
            % calls initialize() which derives all dimension properties
            % (height, width, depth, colors, time, dim_yxzct, maxInt,
            % dataClass) from the actual data size.
            %
            % Input Arguments:
            %   - **data** — *(optional)* 2-D to 5-D numeric array, any class.
            %     Accepted input shapes and how they are interpreted:
            %
            %     - ``[]`` or omitted — empty placeholder; ``obj.exists = false``
            %     - ``[H, W]`` — single grayscale slice
            %     - ``[H, W, C]`` — C-channel 2-D image (C < 4); dim 3 is
            %       permuted to dim 4 so storage becomes ``[H,W,1,C]``
            %     - ``[H, W, C]`` — 3-D stack when C >= 4 (no permute)
            %     - ``[H, W, Z, C]`` — multi-channel 3-D stack
            %     - ``[H, W, Z, C, T]`` — full 5-D dataset
            %
            %     **Note** — the ``[H,W,C]`` → ``[H,W,1,C]`` permute applies to MibImage
            %     only. MibLabels and MibLabels63 store depth in dim 3 and are never permuted.
            %
            %   - **meta** — *(optional)* metadata dictionary from
            %     ``core.MibImage.initializeImgInfo()``. Pass ``[]`` to use defaults.
            %
            % Usage:
            %   **Example 1** — 1. Grayscale 3-D stack (512×512×10, uint8)
            %
            %   .. code-block:: matlab
            %
            %
            %     % 1. Grayscale 3-D stack (512×512×10, uint8)
            %     data = uint8(zeros(512, 512, 10));
            %     meta = core.MibImage.initializeImgInfo('pixSize', pixSize);
            %     img  = core.MibImage(data, meta);
            %     % img.depth == 10, img.colors == 1
            %
            %     % 2. RGB 2-D image stored as [H,W,3]  (C < 4 → permuted to [H,W,1,3])
            %     rgb  = uint8(rand(256, 256, 3) * 255);
            %     img  = core.MibImage(rgb);          % meta defaults OK
            %     % img.depth == 1, img.colors == 3
            %
            %     % 3. Empty placeholder (no pixel data yet)
            %     img  = core.MibImage();
            %     % img.exists == false
            %
            
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

            % if isempty(data) 
            obj.initialize(data, meta);
            % else
            %     % For image data only: permute [H,W,C] → [H,W,1,C] so the
            %     % colour dimension lands in position 4.  Labels store depth
            %     % in position 3, so the permute must be skipped for them.
            %     if ndims(data)==3 && size(data, 3) < 4 && strcmp(obj.type, 'image')
            %         data = permute(data, [1 2 4 3]);
            %     end
            %     obj.initialize(data, meta);
            % end
        end

        
    end
end
