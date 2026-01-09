classdef VideoReaderLoader < io.loaders.BaseImageLoader
    % classdef VideoReaderLoader
    % Loader for video formats using VideoReader, based on
    % io.loaders.BaseImageLoader base class

    % This loader handles video formats that can be read using
    % MATLAB's built-in VideoReader function (AVI, MPG, MP4, MOV, etc.).
    % It supports frame extraction, frame rate detection, and custom
    % frame range selection.

    methods
        function obj = VideoReaderLoader(options)
            % function obj = VideoReaderLoader(options)
            % Constructor for VideoReaderLoader class

            % Parameters:
            %   options: [@em optional, struct] options structure
            %     @li .waitbar - [logical] show or not the waitbar
            %     @li .mibPath - [char] path to MIB directory
            %     @li .customSections - [logical] load custom sections only
            %     @li .customSectionsSettings - [struct] custom section parameters
            %     @li .imgStretch - [logical] stretch uint32 images to uint16
            %     @li .silentMode - [logical] do not ask user questions
            %     @li .verbose - [logical] show timing information
            %     @li .Font - [struct] font settings for dialogs
            %     @li .parentGUI - handle of the main MIB window to be a parent for uiprogressdlg

            % Return values:
            %   obj: instance of the VideoReaderLoader class

            % Example:
            %   @code
            %   options.waitbar = true;
            %   options.mibPath = 'c:\\mib';
            %   loader = io.loaders.VideoReaderLoader(options);
            %   @endcode

            if nargin < 1; options = struct(); end
            obj.Options = options;
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % function [imginfo, files] = loadMetadata(obj, filenames, options)
            % Load metadata for video files

            % This method extracts video metadata using VideoReader for
            % standard video formats. It handles frame count detection,
            % frame dimensions, and frame rate extraction.

            % Parameters:
            %   filenames: cell array with filenames of video files
            %   options: [@em struct] options for metadata loading
            %     @li .waitbar - [logical] show or not the waitbar, [@b default] = @em false
            %     @li .customSections - [logical] load part of the dataset, [@b default] = @em false
            %     @li .customSectionsSettings - [struct] custom section settings
            %     @li .xMin - [numeric] min X coordinate
            %     @li .xMax - [numeric] max X coordinate
            %     @li .yMin - [numeric] min Y coordinate
            %     @li .yMax - [numeric] max Y coordinate
            %     @li .zMin - [numeric] min Z coordinate (frame)
            %     @li .zMax - [numeric] max Z coordinate (frame)
            %     @li .xyStep - [numeric] XY binning step
            %     @li .mibPath - [char] path to MIB directory
            %     @li .parentGUI - handle to the parent window to show progress dialog
            %     @li .Font - [struct] font settings for dialogs

            % Return values:
            %   imginfo: dictionary with image metadata
            %     @li "Height" - image height in pixels
            %     @li "Width" - image width in pixels
            %     @li "Colors" - number of color channels
            %     @li "Depth" - number of frames
            %     @li "Time" - number of time points
            %     @li "imgClass" - image class (uint8, uint16, etc.)
            %     @li "ColorType" - 'grayscale', 'truecolor', or 'indexed'
            %     @li "ImageDescription" - description with BoundingBox info
            %     @li "FrameRate" - frames per second
            %     @li "Duration" - video duration in seconds
            %     @li "pixSize" - structire with pixel sizes, .x, .y, .z, .t, .units, .tunits
            %     @li other format-specific metadata fields
            %   files: structure array with file information for each file
            %     @li .filename - [char] full filename
            %     @li .objecttype - [char] type of the image loader 'movie'
            %     @li .extension - [char] file extension, including the leading dot
            %     @li .height - [numeric] image height
            %     @li .width - [numeric] image width
            %     @li .color - [numeric] number of color channels
            %     @li .noLayers - [numeric] number of video frames
            %     @li .time - [numeric] number of time points
            %     @li .imgClass - [char] image class, 'uint8', 'uint16', 'uint32'
            %     @li .xMin, .xMax, .yMin, .yMax - [numeric] region coordinates
            %     @li .xyStep - [numeric] XY step for binning
            
            % Example:
            %   @code
            %   loader = io.loaders.VideoReaderLoader();
            %   options.waitbar = true;
            %   filenames = {'video1.avi', 'video2.mp4'};
            %   [imginfo, files] = loader.loadMetadata(filenames, options);
            %   fprintf('Video size: %d x %d x %d frames\n', imginfo{"Width"}, imginfo{"Height"}, imginfo{"Depth"});
            %   @endcode

            % Merge constructor options with runtime options
            if nargin < 3; options = obj.Options; end
            options = obj.mergeOptions(obj.Options, options);

            % init imginfo dictionary with the default set of keys
            imginfo = utils.defaults.initializeImgInfo();
            pixSize = imginfo{"pixSize"}; % get default pixel size

            % Initialize default options
            if ~isfield(options, 'waitbar'); options.waitbar = false; end
            if ~isfield(options, 'customSections'); options.customSections = false; end
            if ~isfield(options, 'mibPath'); options.mibPath = ''; end

            noFiles = numel(filenames);

            % Initialize waitbar if requested
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Metadata import',...
                    'Message', sprintf('Loading metadata\n(press Cancel when metadata is the same for all files)'), ...
                    'Cancelable', 'on');
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', []);

            % update the objecttype
            [files.objecttype] = deal('movie');

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    imginfo = dictionary();
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error in io.loaders.VideoReaderLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists');
                    return;
                end

                % Check for cancel button
                if options.waitbar && wb.CancelRequested
                    % Use metadata from first file for all remaining files
                    files(fnIndex:noFiles) = files(1);
                    [files.filename] = filenames{:}; % update filenames
                    [~, ~, ext] = fileparts(filenames(fnIndex:noFiles));
                    [files(fnIndex:noFiles).extension] = ext{:}; % update extensions
                    fnIndex = noFiles;
                    continue;
                end

                % Extract file parts
                [~, ~, ext] = fileparts(filenames{fnIndex});
                ext = lower(ext);
                files(fnIndex).extension = ext;
                files(fnIndex).filename = cell2mat(filenames(fnIndex));

                % Open video file with VideoReader
                try
                    xyloObj = VideoReader(files(fnIndex).filename);
                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error in io.loaders.VideoReaderLoader!\n\nCannot open video file:\n%s\n\nError: %s', ...
                        filenames{fnIndex}, err.message), ...
                        'Video reading error');
                    imginfo = dictionary();
                    return;
                end

                % Get number of frames
                files(fnIndex).noLayers = xyloObj.NumFrames;

                % Read first frame to get dimensions
                I = read(xyloObj, 1);
                files(fnIndex).height = size(I, 1);
                files(fnIndex).width = size(I, 2);
                files(fnIndex).color = size(I, 3);
                files(fnIndex).time = 1;
                files(fnIndex).imgClass = class(I);

                % Store video properties in imginfo (only for first file)
                if fnIndex == 1
                    % Generate imginfo from first video file
                    fields = sort(fieldnames(xyloObj));
                    for ind = 1:numel(fields)
                        imginfo{fields{ind}} = xyloObj.(fields{ind});
                    end

                    % Set color type
                    if files(fnIndex).color == 1
                        imginfo{"ColorType"} = 'grayscale';
                    else
                        imginfo{"ColorType"} = 'multichannel';
                    end

                    % Set time between frames from frame rate
                    if isprop(xyloObj, 'FrameRate') && xyloObj.FrameRate > 0
                        pixSize.t = 1 / xyloObj.FrameRate;
                    end
                else
                    % Check ColorType consistency
                    currentColorType = 'grayscale';
                    if files(fnIndex).color > 1
                        currentColorType = 'multichannel';
                    end

                    if ~isempty(imginfo{"ColorType"}) && ~strcmp(imginfo{"ColorType"}, currentColorType)
                        imginfo = dictionary();
                        if options.waitbar; delete(wb); end
                        utils.dlgs.showErrorDialog(options.parentGUI, ...
                            sprintf('!!! Error !!!\n\nThe files have dissimilar ColorType'), ...
                            'Mixed colors');
                        return;
                    end
                end

                % Update waitbar
                if options.waitbar
                    if mod(fnIndex, ceil(noFiles/50)) == 0; wb.Value = fnIndex/noFiles; end
                end
            end

            % update pixSize
            imginfo{"pixSize"} = pixSize;

            % Handle custom sections
            if options.customSections
                [files, imginfo, cancelled] = obj.handleCustomSections(files, imginfo, options);
                if cancelled
                    imginfo = dictionary();
                    if options.waitbar; delete(wb); end
                    return;
                end
            end

            % Handle dimension mismatches and bounding box
            imginfo = obj.handleDimensionMismatches(files, imginfo);

            % Generate slice names from filenames
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if options.waitbar; delete(wb); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % Load image data for video files

            % This method loads actual video frames using VideoReader.
            % It supports frame range selection, custom region loading,
            % and dimension mismatch handling with background filling.

            % Parameters:
            %   files: structure array from loadMetadata with file information
            %     @li .filename - [char] full filename
            %     @li .objecttype - [char] type of the image loader 'movie'
            %     @li .extension - [char] file extension with dot - '.avi'
            %     @li .height - [numeric] image height
            %     @li .width - [numeric] image width
            %     @li .color - [numeric] number of color channels
            %     @li .noLayers - [numeric] number of video frames
            %     @li .time - [numeric] number of time frames
            %     @li .imgClass - [char] image class, 'uint8', 'uint16', 'uint32'
            %     @li .xMin, .xMax, .yMin, .yMax - [numeric] region coordinates (optional)
            %     @li .zMin, .zMax - [numeric] frame range (optional)
            %     @li .xyStep - [numeric] XY step for binning (optional)
            %     @li .backgroundColor - [numeric] background color value (optional)
            %   imginfo: dictionary from loadMetadata with image metadata
            %   options: [@em struct] options for image loading
            %     @li .waitbar - [logical] show or not the waitbar, [@b default] = @em true
            %     @li .imgStretch - [logical] stretch uint32 to uint16, [@b default] = @em true
            %     @li .silentMode - [logical] do not ask user questions, [@b default] = @em false

            % Return values:
            %   img: loaded image dataset [1:height, 1:width, 1:depth, 1:color, 1:time]
            %   imginfo: updated dictionary with final metadata
            %     @li "Height" - final image height
            %     @li "Width" - final image width
            %     @li "Depth" - final number of frames
            %     @li "Time" - number of time points
            %     @li "ColorType" - color type

            % Example:
            %   @code
            %   loader = io.loaders.VideoReaderLoader();
            %   options.waitbar = true;
            %   [imginfo, files, pixSize] = loader.loadMetadata({'video.avi'}, options);
            %   [img, imginfo] = loader.loadImages(files, imginfo, options);
            %   fprintf('Loaded video size: %s\n', mat2str(size(img)));
            %   @endcode

            % Merge constructor options with runtime options
            if nargin < 4; options = obj.Options; end
            options = obj.mergeOptions(obj.Options, options);

            % Initialize default options
            if ~isfield(options, 'waitbar'); options.waitbar = true; end
            if ~isfield(options, 'imgStretch'); options.imgStretch = true; end
            if ~isfield(options, 'silentMode'); options.silentMode = false; end

            % Calculate dimensions
            height = max([files.height]);
            width = max([files.width]);
            color = max([files.color]);
            time = max([files.time]);

            % Calculate total number of frames
            if isfield(files, 'zMin')
                maxZ = sum([files.zMax] - [files.zMin] + 1);
            else
                maxZ = sum([files.noLayers]);
            end

            if maxZ == 0; return; end

            % Prepare image class
            imgClass = files(1).imgClass;
            if strcmp(imgClass, 'int16'); imgClass = 'uint16'; end

            % Pre-allocate image array
            if isfield(files, 'backgroundColor')
                img = zeros(height, width, maxZ, color, time, imgClass) + files(1).backgroundColor;
            else
                img = zeros(height, width, maxZ, color, time, imgClass);
            end

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            % Initialize layer counter
            layerid = 1;
            noFiles = numel(files);

            % Initialize uiprogressdlg
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Loading video frames...',...
                    'Message', sprintf('Please wait...'), ...
                    'Cancelable', 'on');
            end

            % Process each file
            for fnIndex = 1:noFiles
                % Check for cancel button
                if options.waitbar && wb.CancelRequested
                    delete(wb);
                    img = [];
                    return;
                end

                % Calculate dimensions for this file
                maxY = min(height, files(fnIndex).height);
                maxX = min(width, files(fnIndex).width);
                maxC = min(color, files(fnIndex).color);
                maxT = min(time, files(fnIndex).time);

                % Open video file
                try
                    xyloObj = VideoReader(files(fnIndex).filename);
                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error loading video file:\n%s\n\nError: %s', ...
                        files(fnIndex).filename, err.message), ...
                        'Video loading error');
                    img = [];
                    return;
                end

                % Determine frame range
                if isfield(files, 'zMin')
                    startFrame = files(fnIndex).zMin;
                    endFrame = files(fnIndex).zMax;
                else
                    startFrame = 1;
                    endFrame = files(fnIndex).noLayers;
                end

                % Load each frame
                for subLayer = startFrame:endFrame
                    % Read frame
                    I = read(xyloObj, subLayer);

                    % Handle custom region extraction
                    if isfield(files, 'xMin')
                        % Extract region with optional binning
                        I = I(files(fnIndex).yMin:files(fnIndex).xyStep:files(fnIndex).yMax, ...
                              files(fnIndex).xMin:files(fnIndex).xyStep:files(fnIndex).xMax, :);
                    end

                    % Store frame - permute from H x W x C to H x W x 1 x C
                    img(1:min(maxY, size(I,1)), 1:min(maxX, size(I,2)), layerid, 1:min(maxC, size(I,3))) = ...
                        permute(I(1:min(maxY, size(I,1)), 1:min(maxX, size(I,2)), 1:min(maxC, size(I,3))), [1 2 4 3]);

                    % Update uiprogressdlg
                    if options.waitbar
                        if mod(layerid, waitbarUpdateFrequency) == 0
                            if wb.CancelRequested
                                delete(wb);
                                img = [];
                                return;
                            end
                            wb.Value = layerid / maxZ;
                        end
                    end

                    layerid = layerid + 1;
                end
            end

            % Check for cancel after loading large single files
            if options.waitbar && wb.CancelRequested
                delete(wb);
                img = [];
                return;
            end

            % Update imginfo with final dimensions
            imginfo{'Height'} = height;
            imginfo{'Width'} = width;
            imginfo{'Depth'} = maxZ;
            imginfo{'Time'} = maxT;

            [img, imginfo] = obj.finalizeImageLoading(img, imginfo, options);

            if options.waitbar; delete(wb); end
        end
    end
end