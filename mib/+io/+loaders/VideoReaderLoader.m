classdef VideoReaderLoader < io.loaders.BaseImageLoader
% VIDEOREADERLOADER - Loader for video formats using VideoReader, based on.
%
% io.loaders.BaseImageLoader base class

    % This loader handles video formats that can be read using
    % MATLAB's built-in VideoReader function (AVI, MPG, MP4, MOV, etc.).
    % It supports frame extraction, frame rate detection, and custom
    % frame range selection.

    methods
        function obj = VideoReaderLoader(options)
            % VIDEOREADERLOADER - Constructor for VideoReaderLoader class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.VideoReaderLoader(options)
            %
            % Input Arguments:
            %   - **options** — *(optional)* struct with fields:
            %
            %     - ``waitbar`` — [logical] show or not the waitbar; default: ``false``
            %     - ``mibPath`` — [char] path to MIB directory
            %     - ``customSections`` — [logical] load custom sections only; default: ``false``
            %     - ``customSectionsSettings`` — [struct] custom section parameters
            %     - ``imgStretch`` — [logical] stretch uint32 images to uint16; default: ``false``
            %     - ``silentMode`` — [logical] do not ask user questions; default: ``false``
            %     - ``verbose`` — [logical] show timing information; default: ``false``
            %     - ``Font`` — [struct] font settings for dialogs
            %     - ``ParentFigure`` — handle of the main MIB window (parent for uiprogressdlg)
            %
            % Output Arguments:
            %   - **obj** — instance of the VideoReaderLoader class
            %
            % **Example 1** — create loader with options:
            %
            %   .. code-block:: matlab
            %
            %      options.waitbar = true;
            %      options.mibPath = 'c:\\mib';
            %      loader = io.loaders.VideoReaderLoader(options);
            %

            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - Load metadata for video files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [imginfo, files] = obj.loadMetadata(filenames, options)
            %
            % This method extracts video metadata using VideoReader for
            % standard video formats. It handles frame count detection,
            % frame dimensions, and frame rate extraction.
            %
            % Input Arguments:
            %   - **filenames** — cell array with filenames of video files
            %   - **options** — *(optional)* struct with fields:
            %
            %     - ``waitbar`` — [logical] show or not the waitbar; default: ``false``
            %     - ``customSections`` — [logical] load part of the dataset; default: ``false``
            %     - ``customSectionsSettings`` — [struct] custom section settings
            %       - ``xMin`` — [numeric] min X coordinate
            %       - ``xMax`` — [numeric] max X coordinate
            %       - ``yMin`` — [numeric] min Y coordinate
            %       - ``yMax`` — [numeric] max Y coordinate
            %       - ``zMin`` — [numeric] min Z coordinate (frame)
            %       - ``zMax`` — [numeric] max Z coordinate (frame)
            %       - ``xyStep`` — [numeric] XY binning step
            %     - ``mibPath`` — [char] path to MIB directory
            %     - ``ParentFigure`` — handle to the parent window to show progress dialog
            %     - ``Font`` — [struct] font settings for dialogs
            %
            % Output Arguments:
            %   - **imginfo** — dictionary with image metadata containing fields:
            %
            %     - ``Height`` — image height in pixels
            %     - ``Width`` — image width in pixels
            %     - ``Colors`` — number of color channels
            %     - ``Depth`` — number of frames
            %     - ``Time`` — number of time points
            %     - ``imgClass`` — image class (``uint8``, ``uint16``, etc.)
            %     - ``ColorType`` — ``'grayscale'``, ``'truecolor'``, or ``'indexed'``
            %     - ``ImageDescription`` — description with BoundingBox info
            %     - ``FrameRate`` — frames per second
            %     - ``Duration`` — video duration in seconds
            %     - ``pixSize`` — struct with pixel sizes: ``.x``, ``.y``, ``.z``, ``.t``,
            %       ``.units``, ``.tunits``
            %     - other format-specific metadata fields
            %
            %   - **files** — structure array with file information for each file
            %
            %     - ``filename`` — [char] full filename
            %     - ``objecttype`` — [char] type of the image loader ``'movie'``
            %     - ``extension`` — [char] file extension, including the leading dot
            %     - ``height`` — [numeric] image height
            %     - ``width`` — [numeric] image width
            %     - ``color`` — [numeric] number of color channels
            %     - ``noLayers`` — [numeric] number of video frames
            %     - ``time`` — [numeric] number of time points
            %     - ``imgClass`` — [char] image class, ``'uint8'``, ``'uint16'``, ``'uint32'``
            %     - ``xMin``, ``xMax``, ``yMin``, ``yMax`` — [numeric] region coordinates
            %     - ``xyStep`` — [numeric] XY step for binning
            %
            % **Example 1** — load metadata from video files:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.VideoReaderLoader();
            %      options.waitbar = true;
            %      filenames = {'video1.avi', 'video2.mp4'};
            %      [imginfo, files] = loader.loadMetadata(filenames, options);
            %      fprintf('Video size: %d x %d x %d frames\n', imginfo{"Width"}, imginfo{"Height"}, imginfo{"Depth"});
            %

            % Merge constructor options with runtime options
            if nargin < 3; options = obj.Options; end
            options = obj.mergeOptions(obj.Options, options);

            % init imginfo dictionary with the default set of keys
            imginfo = core.MibImage.initializeImgInfo();
            pixSize = imginfo{"pixSize"}; % get default pixel size

            % Initialize default options
            if ~isfield(options, 'waitbar'); options.waitbar = false; end
            if ~isfield(options, 'customSections'); options.customSections = false; end
            if ~isfield(options, 'mibPath'); options.mibPath = ''; end

            noFiles = numel(filenames);

            % Initialize waitbar if requested
            wb = [];
            if options.waitbar
                wb = obj.createProgressDialog('Metadata import', ...
                    sprintf('Loading metadata\n(press Cancel when metadata is the same for all files)'), true);
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
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.VideoReaderLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.VideoReaderLoader');
                    return;
                end

                % Check for cancel button
                if ~isempty(wb) && wb.CancelRequested
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
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.VideoReaderLoader!\n\nCannot open video file:\n%s\n\nError: %s', ...
                        filenames{fnIndex}, err.message), ...
                        'Video reading error', 'Error in io.loaders.VideoReaderLoader');
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
                        if ~isempty(wb); delete(wb); end
                        utils.dlgs.showErrorDialog(options.ParentFigure, ...
                            sprintf('!!! Error !!!\n\nThe files have dissimilar ColorType'), ...
                            'Mixed colors', 'Error in io.loaders.VideoReaderLoader');
                        return;
                    end
                end

                % Update waitbar
                if ~isempty(wb)
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
                    if ~isempty(wb); delete(wb); end
                    return;
                end
            end

            % Handle dimension mismatches and bounding box
            imginfo = obj.handleDimensionMismatches(files, imginfo);

            % Generate slice names from filenames
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if ~isempty(wb); delete(wb); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % LOADIMAGES - Load image data for video files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.loadImages(files, imginfo, options)
            %
            % This method loads actual video frames using VideoReader.
            % It supports frame range selection, custom region loading,
            % and dimension mismatch handling with background filling.
            %
            % Input Arguments:
            %   - **files** — structure array from loadMetadata with file information:
            %
            %     - ``filename`` — [char] full filename
            %     - ``objecttype`` — [char] type of the image loader ``'movie'``
            %     - ``extension`` — [char] file extension with dot - ``'.avi'``
            %     - ``height`` — [numeric] image height
            %     - ``width`` — [numeric] image width
            %     - ``color`` — [numeric] number of color channels
            %     - ``noLayers`` — [numeric] number of video frames
            %     - ``time`` — [numeric] number of time frames
            %     - ``imgClass`` — [char] image class, ``'uint8'``, ``'uint16'``, ``'uint32'``
            %     - ``xMin``, ``xMax``, ``yMin``, ``yMax`` — [numeric] region coordinates (optional)
            %     - ``zMin``, ``zMax`` — [numeric] frame range (optional)
            %     - ``xyStep`` — [numeric] XY step for binning (optional)
            %     - ``backgroundColor`` — [numeric] background color value (optional)
            %
            %   - **imginfo** — dictionary from loadMetadata with image metadata
            %   - **options** — *(optional)* struct with fields:
            %
            %     - ``waitbar`` — [logical] show or not the waitbar; default: ``true``
            %     - ``imgStretch`` — [logical] stretch uint32 to uint16; default: ``true``
            %     - ``silentMode`` — [logical] do not ask user questions; default: ``false``
            %
            % Output Arguments:
            %   - **img** — loaded image dataset [1:height, 1:width, 1:depth, 1:color, 1:time]
            %   - **imginfo** — updated dictionary with final metadata containing fields:
            %
            %     - ``Height`` — final image height
            %     - ``Width`` — final image width
            %     - ``Depth`` — final number of frames
            %     - ``Time`` — number of time points
            %     - ``ColorType`` — color type
            %
            % **Example 1** — load images from video file:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.VideoReaderLoader();
            %      options.waitbar = true;
            %      [imginfo, files] = loader.loadMetadata({'video.avi'}, options);
            %      [img, imginfo] = loader.loadImages(files, imginfo, options);
            %      fprintf('Loaded video size: %s\n', mat2str(size(img)));
            %

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
            wb = [];
            if options.waitbar
                wb = obj.createProgressDialog('Loading video frames...', ...
                    sprintf('Please wait...'), true);
            end

            % Process each file
            for fnIndex = 1:noFiles
                % Check for cancel button
                if ~isempty(wb) && wb.CancelRequested
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
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error loading video file:\n%s\n\nError: %s', ...
                        files(fnIndex).filename, err.message), ...
                        'Video loading error', 'Error in io.loaders.VideoReaderLoader');
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
                    if ~isempty(wb)
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
            if ~isempty(wb) && wb.CancelRequested
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

            if ~isempty(wb); delete(wb); end
        end
    end
end
