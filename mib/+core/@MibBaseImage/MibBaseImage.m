classdef MibBaseImage < matlab.mixin.Copyable
    % classdef MibBaseImage < matlab.mixin.Copyable 
    % a base image class of MIB3

    properties
        colors
        % number of color channels
        colorType 
        % a char with type of colors: grayscale, multichannel, hsvcolor, indexed
        depth
        % number of stacks in the dataset
        filename
        % the full filename of the dataset
        height
        % image height, px
        img
        % a cell array to keep the 'Image' layer. The layer img{1} has image in full resolution,
        % @note The 'Image' layer dimensions: @code [1:height, 1:width, 1:depth, 1:colors, 1:time] @endcode
        imgClass
        % a char with image class, 'uint8', 'uint16', 'uint32';
        lutColors
        % a matrix with LUT colors [1:colorChannel, R G B], (0-1)
        maxInt
        % maximal value that is available in the dataset
        pixSize
        % a structure with dimensions of voxels, @code .x .y .z .t .tunits .units @endcode
        % the fields are
        % @li .x - physical width of a pixel
        % @li .y - physical height of a pixel
        % @li .z - physical thickness of a pixel
        % @li .t - time between the frames for 2D movies
        % @li .tunits - time units
        % @li .units - physical units for x, y, z. Possible values: [m, cm, mm, um, nm]
        sliceName
        % a cell array of slice filenames that composing the dataset
        time
        % number of time points in the dataset
        width
        % image width, px
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        dataset = getData(obj, type, orient, col_channel, options, custom_img)        % get dataset

        varargout = getDatasetDimensions(obj, splitDims, orient)        % Get dimensions of the dataset

        [totalSize, imSize] = getDatasetSizeInBytes(obj)        % Get size of the loaded dataset in bytes

        initImage(obj, img, meta);  % initialize the class using default or provided values

        result = setData(obj, type, dataset, orient, col_channel, options)        % update contents of the class

        function obj = MibBaseImage(img, meta)
            % obj = MibBaseImage(img, meta)
            % MibBaseImage class constructor
            
            % Constructor for the MibBaseImage class. 
            % Create a new instance of the class with default parameters
            %
            % Parameters:
            % img: an 2D-5D image stack
            % meta: a structure with parameters of the dataset, can be @e []
            
            if nargin < 2; meta = []; end
            if nargin < 1; img = []; end

            if isempty(img) 
                obj.initImage();
            else
                obj.initImage(img, meta);
            end
        end

        
    end
end