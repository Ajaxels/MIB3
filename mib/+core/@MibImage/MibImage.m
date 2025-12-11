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
        dim_yxzct 
        % a matrix with dimensions of the dataset [height, width, depth, colors, time] equal to size obj.data{1} 
        exists
        % logical switch indicating whether the obj.data exists or it is empty/dummy place maker
        filename
        % the full filename of the dataset
        height
        % image height, px
        data
        % a cell array to keep the 'Image' layer. The layer data{1} has image in full resolution,
        % @note The 'Image' layer dimensions: @code [1:height, 1:width, 1:depth, 1:colors, 1:time] @endcode
        dataClass
        % a char with image class, 'uint8', 'uint16', 'uint32';
        lutColors
        % a matrix with LUT colors [1:colorChannel, R G B], (0-1)
        maxInt
        % maximal value that is available in the dataset
        sliceName
        % a cell array of slice filenames that composing the dataset
        time
        % number of time points in the dataset
        type
        % type of the dataset: image (MibImage), labels (MibLabels), labels63 (MibLabels63)
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
        dataset = getData(obj, orient, col_channel, options)        % get dataset

        varargout = getDatasetDimensions(obj, orient, splitDims)        % Get dimensions of the dataset

        initialize(obj, data, meta, type);  % initialize the class using default or provided values

        result = setData(obj, dataset, orient, col_channel, options)        % update contents of the class

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
            
            if nargin < 2; meta = []; end
            if nargin < 1; data = []; end
            
            % update type
            switch class(obj)
                case 'core.MibImage'
                    obj.type = 'image';
                case 'core.MibLabels'
                    obj.type = 'labels';
                case 'core.MibLabels63'
                    obj.type = 'labels63';
            end

            % init meta as empty struct
            if isempty(meta); meta = struct(); end

            if isempty(data) 
                obj.initialize();
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