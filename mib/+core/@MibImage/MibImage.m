classdef MibImage < matlab.mixin.Copyable
    % classdef MibImage < matlab.mixin.Copyable 
    % a base image class of MIB3

    properties
        colors
        % number of color channels
        colorType 
        % a char with type of colors: grayscale, multichannel, hsvcolor, indexed
        depth
        % number of stacks in the dataset
        exist
        % logical switch indicating whether the obj.img exists or it is empty/dummy place maker
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
        type
        % type of the dataset: image, labels, labels63
        width
        % image width, px
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        dataset = getData(obj, orient, col_channel, options)        % get dataset

        varargout = getDatasetDimensions(obj, splitDims, orient)        % Get dimensions of the dataset

        initImage(obj, img, meta, type);  % initialize the class using default or provided values

        result = setData(obj, dataset, orient, col_channel, options)        % update contents of the class

        function obj = MibImage(img, meta, type)
            % obj = MibImage(img, meta)
            % MibImage class constructor
            
            % Constructor for the MibBaseImage class. 
            % Create a new instance of the class with default parameters
            %
            % Parameters:
            % img: an 2D-5D image stack
            % meta: a structure with parameters of the dataset, can be @e []
            
            if nargin < 3; type = 'image'; end
            if nargin < 2; meta = []; end
            if nargin < 1; img = []; end

            if isempty(img) 
                obj.initImage();
            else
                % permute the 3rd dimension into the 4th dimension
                if ndims(img)==3 && size(img,3) < 4
                    img = permute(img, [1 2 4 3]);
                end
                obj.initImage(img, meta, type);
            end
        end

        
    end
end