% File: +io/@ImageLoaderBase/ImageLoaderBase.m
classdef ImageLoaderBase
    % Abstract base class for image format loaders
    % Subclasses implement getMetadata() and getImages()
    
    properties
        filename                % Full path to file
        options                 % Format-agnostic options
        img_info                % Metadata dictionary
        pixSize                 % Pixel size struct
        files                   % File info struct array
    end
    
    properties 
        DEFAULT_OPTIONS = struct( ...
            'waitbar', true, ...
            'silentMode', false, ...
            'verbose', true);
    end
    
    methods
        function obj = ImageLoaderBase(filename, options)
            % Constructor
            obj.filename = filename;
            
            % Merge options with defaults
            if nargin < 2; options = struct(); end
            obj.options = obj.mergeOptions(options);
            
            % Initialize metadata containers
            obj.img_info = io.imageMetadata.createContainer();
            obj.pixSize = obj.createDefaultPixSize();
            obj.files = struct();
        end
        
        function [img_info, files, pixSize] = getMetadata(obj)
            % Template method: subclasses override
            % Validates file, extracts metadata
            
            if ~obj.fileExists()
                error('io:ImageLoader:FileNotFound', ...
                    'File not found: %s', obj.filename);
            end
            
            obj.validateFile();
            obj.extractMetadata();
            
            img_info = obj.img_info;
            files = obj.files;
            pixSize = obj.pixSize;
        end
        
        function [img, img_info] = getImages(obj, files, img_info)
            % Template method: subclasses override
            % Loads actual image data
            
            % Validate we have metadata
            io.imageMetadata.validateRequired(img_info);
            
            % Allocate array
            img = obj.allocateImage(files, img_info);
            
            % Load data
            obj.loadImageData(img, files, img_info);
            
            % Update metadata
            img_info('Height') = size(img, 1);
            img_info('Width') = size(img, 2);
            img_info('Depth') = size(img, 4);
            img_info('Time') = size(img, 5);
        end
        
        function opts = mergeOptions(obj, userOptions)
            % Merge user options with defaults
            opts = obj.DEFAULT_OPTIONS;
            fnames = fieldnames(userOptions);
            for i = 1:numel(fnames)
                opts.(fnames{i}) = userOptions.(fnames{i});
            end
        end
        
        function ps = createDefaultPixSize(~)
            ps = struct('x', 1, 'y', 1, 'z', 1, 'units', 'um', ...
                        't', 1, 'tunits', 's');
        end
        
        function tf = fileExists(obj)
            tf = isfile(obj.filename);
        end
        
        function img = allocateImage(obj, files, img_info)
            % Allocate memory based on dimensions
            height = io.imageMetadata.getRequired(img_info, 'Height');
            width = io.imageMetadata.getRequired(img_info, 'Width');
            color = io.imageMetadata.getOpt(img_info, 'Colors', 1);
            depth = io.imageMetadata.getOpt(img_info, 'Depth', 1);
            time = io.imageMetadata.getOpt(img_info, 'Time', 1);
            imgClass = io.imageMetadata.getRequired(img_info, 'imgClass');
            
            img = zeros([height, width, color, depth, time], imgClass);
        end
        
        % Shared utilities
        function wb = createWaitbar(obj, msg)
            wb = [];
            if obj.options.waitbar
                wb = waitbar(0, msg, ...
                    'CreateCancelBtn', 'setappdata(gcbf, ''canceling'', 1)');
            end
        end
        
        function tf = checkCancelled(~, wb)
            tf = false;
            if ~isempty(wb) && isvalid(wb)
                tf = getappdata(wb, 'canceling');
            end
        end
        
        function deleteWaitbar(~, wb)
            if ~isempty(wb) && isvalid(wb)
                delete(wb);
            end
        end
    end
    
    methods (Abstract)
        validateFile(obj)
        extractMetadata(obj)
        loadImageData(obj, img, files, img_info)
    end
    
end
