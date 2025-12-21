% File: +io/@ImageLoaderFactory/ImageLoaderFactory.m
classdef ImageLoaderFactory
    % Factory for creating format-specific loaders
    
    methods (Static)
        function loader = createLoader(filename, options)
            % Detect format and return appropriate loader instance
            %
            % Usage:
            %   loader = ImageLoaderFactory.createLoader(file, opts);
            %   [img_info, files, pixSize] = loader.getMetadata();
            
            if nargin < 2; options = struct(); end
            
            % Detect format
            format = io.ImageLoaderFactory.detectFormat(filename);
            
            if options.UseBioFormats
                loader = 'bioformats';
            else
                

            end

            % Create appropriate loader
            switch format
                case 'tif'
                    loader = io.Loaders.ImageLoaderTIF(filename, options);
                case 'hdf5'
                    loader = io.Loaders.ImageLoaderHDF5(filename, options);
                case 'bioformats'
                    loader = io.Loaders.ImageLoaderBioFormats(filename, options);
                case 'nrrd'
                    loader = io.Loaders.ImageLoaderNRRD(filename, options);
                case 'zarr'
                    loader = io.Loaders.ImageLoaderZarr(filename, options);
                case 'amiramesh'
                    loader = io.Loaders.ImageLoaderAmiraMesh(filename, options);
                case 'mrc'
                    loader = io.Loaders.ImageLoaderMRC(filename, options);
                case 'movie'
                    loader = io.Loaders.ImageLoaderMovie(filename, options);
                otherwise
                    error('io:ImageLoaderFactory:UnknownFormat', ...
                        'Unknown image format: %s', format);
            end
        end
        
        function [img_info, files, pixSize] = loadImageMetadata(filenames, options)
            % Public API (wrapper around loaders)
            % Maintains compatibility with existing code
            
            if ischar(filenames)
                filenames = {filenames};
            end
            
            if nargin < 2; options = struct(); end
            
            % Initialize output
            %img_info = io.imageMetadata.createContainer();
            img_info = dictionary;
            files = struct();
            pixSize = [];
            
            % Load metadata for each file
            for i = 1:numel(filenames)
                filename = filenames{i};
                
                % Create loader for this file
                loader = io.ImageLoaderFactory.createLoader(filename, options);
                
                % Get metadata
                [info, fileInfo, pix] = loader.getMetadata();
                
                % Combine results
                if i == 1
                    img_info = info;
                    pixSize = pix;
                end
                
                files(i) = fileInfo;
            end
        end
        
        function [img, img_info, pixSize, files] = loadImages(filenames, options)
            % Public API for loading images
            
            if nargin < 2; options = struct(); end
            
            % Get metadata first
            [img_info, files, pixSize] = ...
                io.ImageLoaderFactory.loadImageMetadata(filenames, options);
            
            % Load images
            img = [];
            for i = 1:numel(files)
                filename = files(i).filename;
                loader = io.ImageLoaderFactory.createLoader(filename, options);
                
                [imgTemp, img_info] = loader.getImages(files(i), img_info);
                
                if isempty(img)
                    img = imgTemp;
                else
                    % Concatenate along Z dimension
                    img = cat(4, img, imgTemp);
                end
            end
        end
        
    end
    
    methods (Static, Access = private)
        
        function format = detectFormat(filename)
            % Detect file format by extension + magic bytes
            
            [~, ~, ext] = fileparts(filename);
            ext = lower(ext);
            
            % First try extension
            switch ext
                case {'.tif', '.tiff'}
                    format = 'tif';
                case {'.h5', '.hdf5'}
                    format = 'hdf5';
                case '.nrrd'
                    format = 'nrrd';
                case {'.zarr', '.zarr2', '.zarr3'}
                    format = 'zarr';
                case {'.am', '.amiramesh'}
                    format = 'amiramesh';
                case {'.mrc', '.mrcs', '.ali'}
                    format = 'mrc';
                case {'.avi', '.mp4', '.mov', '.wmv'}
                    format = 'movie';
                case '.xml'
                    format = 'hdf5';  % HDF5 with XML header
                otherwise
                    % Check if BioFormats can handle it
                    if exist('bfGetReader', 'file')
                        format = 'bioformats';
                    else
                        error('io:ImageLoaderFactory:UnknownExt', ...
                            'Unknown file extension: %s', ext);
                    end
            end
        end
        
    end
    
end

