classdef (Abstract) BaseImageLoader < handle
    % classdef BaseImageLoader
    % Abstract base class for image format loaders
    %
    % This abstract class provides common functionality shared across all
    % image format loaders in MIB. It defines the interface that all loaders
    % must implement and provides utility methods for handling custom sections,
    % bounding box calculations, and slice name generation. Child classes must
    % implement format-specific loading logic.
    
    properties
        Options struct  % Options structure passed during construction
    end
    
    methods (Abstract)
        [imginfo, files, pixSize] = loadMetadata(obj, filenames, options)
        % function [imginfo, files, pixSize] = loadMetadata(obj, filenames, options)
        % Load metadata for image files
        %
        % This abstract method must be implemented by child classes to extract
        % format-specific metadata from image files.
        %
        % Parameters:
        %   filenames: cell array with filenames of images to load
        %   options: [@em optional, struct] options for metadata loading
        %
        % Return values:
        %   imginfo: dictionary with image metadata
        %   files: structure array with file information
        %   pixSize: structure with voxel dimensions
        
        [img, imginfo] = loadImages(obj, files, imginfo, options)
        % function [img, imginfo] = loadImages(obj, files, imginfo, options)
        % Load image data from files
        %
        % This abstract method must be implemented by child classes to load
        % actual image data using format-specific readers.
        %
        % Parameters:
        %   files: structure array from loadMetadata with file information
        %   imginfo: dictionary from loadMetadata with image metadata
        %   options: [@em optional, struct] options for image loading
        %
        % Return values:
        %   img: loaded image dataset [1:height, 1:width, 1:color, 1:depth]
        %   imginfo: updated dictionary with final metadata
    end
    
    methods (Access = protected)

        function imginfo = initializeImgInfo(~)
            % function imginfo = initializeImgInfo(~)
            % Initialize imginfo dictionary with standard keys
            %
            % This method creates a dictionary with all standard metadata fields
            % initialized to empty values. This ensures consistent structure across
            % all loaders and prevents missing key errors.
            %
            % Parameters:
            %   none
            %
            % Return values:
            %   imginfo: dictionary with standard image metadata keys
            %       @li "Filename" - [char] source filename
            %       @li "Height" - [numeric] image height in pixels
            %       @li "Width" - [numeric] image width in pixels
            %       @li "Colors" - [numeric] number of color channels
            %       @li "Depth" - [numeric] number of z-slices
            %       @li "Time" - [numeric] number of time points
            %       @li "imgClass" - [char] image class (uint8, uint16, etc.)
            %       @li "ColorType" - [char] 'grayscale', 'truecolor', or 'indexed'
            %       @li "ImageDescription" - [char] description with BoundingBox
            %       @li "MaxInt" - [numeric] maximum intensity value
            %       @li "SliceName" - [cell] slice names
            %
            % Example:
            %   @code
            %   imginfo = obj.initializeImgInfo();
            %   imginfo{"Width"} = 1024;
            %   imginfo{"Height"} = 768;
            %   @endcode

            coreImgInfoKeys = [ ...
                "Filename" ...
                "Height" ...
                "Width" ...
                "Colors" ...
                "Depth" ...
                "Time" ...
                "imgClass" ...
                "ColorType" ...
                "ImageDescription" ...
                "MaxInt" ...
                "SliceName" ...
                ];
            coreImgInfoValues = repmat({[]}, size(coreImgInfoKeys));
            imginfo = dictionary(coreImgInfoKeys, coreImgInfoValues);
        end

        function pixSize = initializePixSize(~)
            % function pixSize = initializePixSize(~)
            % Initialize pixSize structure with default values
            %
            % This method creates a structure with default voxel dimensions.
            % Physical units default to micrometers and temporal units to seconds.
            %
            % Parameters:
            %   none
            %
            % Return values:
            %   pixSize: structure with voxel dimensions
            %       @li .x - [numeric] pixel width, default = 1
            %       @li .y - [numeric] pixel height, default = 1
            %       @li .z - [numeric] slice thickness, default = 1
            %       @li .units - [char] physical units, default = 'um'
            %       @li .t - [numeric] time between frames, default = 1
            %       @li .tunits - [char] time units, default = 's'
            %
            % Example:
            %   @code
            %   pixSize = obj.initializePixSize();
            %   pixSize.x = 0.065;  % 65 nm pixel size
            %   pixSize.units = 'um';
            %   @endcode

            pixSize.x = 1;
            pixSize.y = 1;
            pixSize.z = 1;
            pixSize.units = 'um';
            pixSize.t = 1;
            pixSize.tunits = 's';
        end

        function [files, imginfo, pixSize, cancelled] = handleCustomSections(~, files, imginfo, pixSize, options)
            % function [files, imginfo, pixSize, cancelled] = handleCustomSections(obj, files, imginfo, pixSize, options)
            % Handle custom section loading dialog and adjustments
            %
            % This method displays a dialog for selecting a custom region to load
            % and adjusts the files structure, pixel size, and metadata accordingly.
            % It supports XY binning, Z range selection, and file subsampling.
            %
            % Parameters:
            %   files: structure array with file information
            %       @li .filename - [char] full filename
            %       @li .width - [numeric] image width
            %       @li .height - [numeric] image height
            %       @li .noLayers - [numeric] number of image frames
            %   imginfo: dictionary with image metadata
            %   pixSize: structure with voxel dimensions
            %       @li .x - [numeric] pixel width in units
            %       @li .y - [numeric] pixel height in units
            %       @li .z - [numeric] slice thickness in units
            %       @li .units - [char] physical units
            %   options: [@em struct] options structure
            %       @li .customSections - [logical] load part of the dataset
            %       @li .customSectionsSettings - [struct] custom section settings (optional)
            %           @li .xMin - [numeric] min X coordinate
            %           @li .xMax - [numeric] max X coordinate
            %           @li .yMin - [numeric] min Y coordinate
            %           @li .yMax - [numeric] max Y coordinate
            %           @li .zMin - [numeric] min Z coordinate
            %           @li .zMax - [numeric] max Z coordinate
            %           @li .xyStep - [numeric] XY binning step
            %       @li .mibPath - [char] path to MIB directory
            %       @li .parentGUI - handle to the parent window
            %       @li .waitbar - [logical] show or not the waitbar
            %
            % Return values:
            %   files: updated structure array with custom section parameters
            %       @li .xMin, .xMax, .yMin, .yMax - [numeric] region coordinates
            %       @li .zMin, .zMax - [numeric] slice range
            %       @li .xyStep - [numeric] XY step for binning
            %       @li .width, .height, .noLayers - [numeric] adjusted dimensions
            %   imginfo: updated dictionary with image metadata
            %   pixSize: updated structure with adjusted voxel dimensions
            %   cancelled: [logical] true if user cancelled the dialog
            %
            % Example:
            %   @code
            %   [files, imginfo, pixSize, cancelled] = obj.handleCustomSections(files, imginfo, pixSize, options);
            %   if cancelled; return; end
            %   @endcode
            
            cancelled = false;
            
            if ~options.customSections
                return;
            end
            
            % Calculate maximum dimensions across all files
            maxWidthSeries = max([files.width]);
            maxHeightSeries = max([files.height]);
            maxDepthSeries = max([files.noLayers]);
            
            % Define dialog prompts
            prompts = {sprintf('X min'); sprintf('X max (%d px)', maxWidthSeries); ...
                sprintf('Y min'); sprintf('Y max (%d px)', maxHeightSeries); ...
                sprintf('Z min'); sprintf('Z max (%d px)', maxDepthSeries); ...
                'XY step (not for BioFormats)'; 'Load each Nth file'};
            
            % Set default values from settings or use max dimensions
            if isfield(options, 'customSectionsSettings')
                defAns = {
                    struct('Spinner', true, 'Value', options.customSectionsSettings.xMin, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.xMax, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.yMin, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.yMax, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.zMin, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.zMax, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.xyStep, 'Limits', [1 Inf], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 Inf], 'Round', true)};
            else
                defAns = {
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', maxWidthSeries, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', maxHeightSeries, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', maxDepthSeries, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 Inf], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 Inf], 'Round', true)};
            end
            
            % Show dialog
            dlgTitle = 'Define region to load';
            dlgOptions.Header = 'Provide image range to load';
            dlgOptions.Columns = 2;
            dlgOptions.WindowWidth = 640;
            dlgOptions.WindowHeight = 220;
            dlgOptions.ParentFigure = options.parentGUI;
            
            answer = utils.dlgs.mibInputUniversalDlg(options.mibPath, prompts, defAns, dlgTitle, dlgOptions);
            
            if isempty(answer)
                if options.waitbar; delete(options.waitbar); end
                cancelled = true;
                return;
            end
            
            % Extract user selections
            xMin = answer{1};
            xMax = answer{2};
            yMin = answer{3};
            yMax = answer{4};
            zMin = answer{5};
            zMax = answer{6};
            xyStep = answer{7};
            fileLoadStep = answer{8};
            
            % Adjust files if loading every Nth file
            if fileLoadStep > 1
                files = files(1:fileLoadStep:numel(files));
            end
            
            % Correct pixel size for XY binning
            if xyStep > 1
                pixSize.x = pixSize.x * xyStep;
                pixSize.y = pixSize.y * xyStep;
            end
            
            % Update files structure with custom section parameters
            for i = 1:numel(files)
                files(i).xMin = max(xMin, 1);
                files(i).xMax = min(xMax, maxWidthSeries);
                files(i).yMin = max(yMin, 1);
                files(i).yMax = min(yMax, maxHeightSeries);
                files(i).zMin = max(zMin, 1);
                files(i).zMax = min(zMax, maxDepthSeries);
                files(i).xyStep = xyStep;
                files(i).height = ceil((files(i).yMax - files(i).yMin + 1) / xyStep);
                files(i).width = ceil((files(i).xMax - files(i).xMin + 1) / xyStep);
                files(i).noLayers = files(i).zMax - files(i).zMin + 1;
            end
        end
        
        function imginfo = handleDimensionMismatches(~, files, imginfo, pixSize)
            % function imginfo = handleDimensionMismatches(obj, files, imginfo, pixSize)
            % Handle dimension mismatches and recalculate bounding box
            %
            % This method updates the ImageDescription field with correct bounding
            % box coordinates when files have different dimensions or when custom
            % sections are loaded. It ensures spatial consistency across the dataset.
            %
            % Parameters:
            %   files: structure array with file information
            %       @li .width - [numeric] image width
            %       @li .height - [numeric] image height
            %       @li .noLayers - [numeric] number of layers
            %       @li .xMin, .xMax, .yMin, .yMax - [numeric] region coordinates (optional)
            %       @li .zMin, .zMax - [numeric] slice range (optional)
            %   imginfo: dictionary with image metadata
            %       @li "ImageDescription" - [char] description with BoundingBox info
            %   pixSize: structure with voxel dimensions
            %       @li .x, .y, .z - [numeric] pixel dimensions in units
            %
            % Return values:
            %   imginfo: updated dictionary with recalculated BoundingBox in ImageDescription
            %
            % Example:
            %   @code
            %   imginfo = obj.handleDimensionMismatches(files, imginfo, pixSize);
            %   @endcode
            
            % Check if dimension mismatch exists
            if numel(unique([files.width])) > 1 || numel(unique([files.height])) > 1
                if isfield(files, 'xMin')  % custom sections - recalculate bounding box
                    bbStart = strfind(imginfo{"ImageDescription"}, 'BoundingBox');
                    if ~isempty(bbStart)
                        brakePnt = strfind(imginfo{"ImageDescription"}, '|');
                        if isempty(brakePnt)
                            brakePnt = numel(imginfo{"ImageDescription"}) + 1;
                        end
                        try
                            brakePnt = brakePnt(1);
                            bbString = imginfo{"ImageDescription"};
                            bb = str2num(bbString(bbStart+11:brakePnt-1)); %#ok<ST2NM>
                        catch err
                            bb = [0 0 0 0 0 0];
                        end
                    else
                        bb = [0 0 0 0 0 0];
                    end
                    
                    if isfield(files, 'xMin')  % custom sections
                        bb(1) = bb(1) + (files(1).xMin - 1) * pixSize.x;  % xMin
                        bb(2) = bb(1) + (files(1).xMax - files(1).xMin) * pixSize.x;  % xMax
                        bb(3) = bb(3) + (files(1).yMin - 1) * pixSize.y;  % yMin
                        bb(4) = bb(3) + (files(1).yMax - files(1).yMin) * pixSize.y;  % yMax
                        bb(5) = bb(5) + (files(1).zMin - 1) * pixSize.z;  % zMin
                        bb(6) = bb(5) + (files(1).zMax - files(1).zMin) * pixSize.z;  % zMax
                    else
                        bb(2) = max([files.width]) * pixSize.x - bb(1);
                        bb(4) = max([files.height]) * pixSize.y - bb(3);
                        bb(6) = sum([files.noLayers]) * pixSize.z - bb(5);
                    end
                    
                    str2 = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f ', bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
                    currtext = imginfo{"ImageDescription"};
                    bbinfoexist = strfind(currtext, 'BoundingBox');
                    
                    if bbinfoexist == 1
                        spaces = strfind(currtext, ' ');
                        if ~isempty(spaces)
                            imginfo{"ImageDescription"} = [str2 currtext(spaces(7):end)];
                        else
                            imginfo{"ImageDescription"} = str2;
                        end
                    else
                        imginfo{"ImageDescription"} = [str2 ' ' currtext];
                    end
                end
            elseif isfield(files, 'xMin')  % custom sections without dimension mismatch
                bb = [0 0 0 0 0 0];
                bb(1) = bb(1) + (files(1).xMin - 1) * pixSize.x;
                bb(2) = bb(1) + (files(1).xMax - files(1).xMin) * pixSize.x;
                bb(3) = bb(3) + (files(1).yMin - 1) * pixSize.y;
                bb(4) = bb(3) + (files(1).yMax - files(1).yMin) * pixSize.y;
                bb(5) = bb(5) + (files(1).zMin - 1) * pixSize.z;
                bb(6) = bb(5) + (files(1).zMax - files(1).zMin) * pixSize.z;
                
                bbString = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f ', bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
                imginfo{"ImageDescription"} = bbString;
            end
        end
        
        function imginfo = generateSliceNames(~, files, imginfo)
            % function imginfo = generateSliceNames(~, files, imginfo)
            % Generate slice names from filenames
            %
            % This method creates a cell array of slice names based on the source
            % filenames. Each slice is named after the file it originated from,
            % which helps track data provenance in multi-file datasets.
            %
            % Parameters:
            %   files: structure array with file information
            %       @li .filename - [char] full filename
            %       @li .noLayers - [numeric] number of layers per file
            %   imginfo: dictionary with image metadata
            %
            % Return values:
            %   imginfo: updated dictionary with "SliceName" field
            %       @li "SliceName" - [cell array] slice names for each layer
            %
            % Example:
            %   @code
            %   imginfo = obj.generateSliceNames(files, imginfo);
            %   disp(imginfo{"SliceName"}{1});  % Display first slice name
            %   @endcode
            
            if numel(files) > 1
                totalLayers = sum([files.noLayers]);
                SliceName = cell(totalLayers, 1);
                index = 1;
                for fileId = 1:numel(files)
                    [~, fnShort, ext] = fileparts(files(fileId).filename);
                    fullName = [fnShort, ext];
                    endIdx = index + files(fileId).noLayers - 1;
                    SliceName(index:endIdx) = {fullName};
                    index = endIdx + 1;
                end
                imginfo{"SliceName"} = SliceName;
            else
                [~, fnShort, ext] = fileparts(files.filename);
                imginfo{"SliceName"} = {[fnShort, ext]};
            end
        end
        
        function imginfo = finalizeImgInfo(~, imginfo, files, filename)
            % function imginfo = finalizeImgInfo(~, imginfo, files, filename)
            % Finalize imginfo dictionary with some missing values
            % Parameters:
            %   imginfo: dictionary with image metadata
            %       @li "MaxInt" - [numeric] max value available for the data class
            %       @li "Colors" - [numeric] number of color channels
            %       @li "imgClass" - [char] image class, uint8, uint16, etc
            %       @li "Depth" - [numeric] total number of sections
            %       @li "Filename" - [char] final filename for the combined dataset
            %   files: structure array with file information
            %       @li .width - [numeric] image width
            %       @li .height - [numeric] image height
            %       @li .noLayers - [numeric] number of layers
            %       @li .xMin, .xMax, .yMin, .yMax - [numeric] region coordinates (optional)
            %       @li .zMin, .zMax - [numeric] slice range (optional)
            %
            % Return values:
            %   imginfo: updated dictionary
            
            switch files(1).imgClass
                case {'single', 'double'}
                    imginfo{"MaxInt"} = realmax(files(1).imgClass);
                otherwise
                    imginfo{"MaxInt"} = double(intmax(files(1).imgClass));
            end

            imginfo{"Colors"} = files(1).color;
            imginfo{"imgClass"} = files(1).imgClass;
            imginfo{"Depth"} = sum([files.noLayers]);
            imginfo{"Filename"} = filename;
        end

        function merged = mergeOptions(~, opts1, opts2)
            % function merged = mergeOptions(~, opts1, opts2)
            % Merge two options structures, with opts2 taking precedence
            %
            % This utility method combines two options structures, where fields
            % in opts2 override those in opts1. This allows runtime options to
            % override constructor options.
            %
            % Parameters:
            %   opts1: [@em struct] first options structure (lower priority)
            %   opts2: [@em struct] second options structure (higher priority)
            %
            % Return values:
            %   merged: [@em struct] merged options structure
            %
            % Example:
            %   @code
            %   opts1.waitbar = false;
            %   opts2.waitbar = true;
            %   merged = obj.mergeOptions(opts1, opts2);
            %   % merged.waitbar will be true
            %   @endcode
            
            merged = opts1;
            if isempty(opts2); return; end
            
            fields = fieldnames(opts2);
            for i = 1:numel(fields)
                merged.(fields{i}) = opts2.(fields{i});
            end
        end
    end
end
