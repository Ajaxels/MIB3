classdef ImreadLoader < io.loaders.BaseImageLoader
% IMREADLOADER - Loader for standard MATLAB image formats using imread, based on.
%
% io.loaders.BaseImageLoader base class
%
% This loader handles standard image formats that can be read using
% MATLAB's built-in imread function (TIF, TIFF, PNG, JPEG, BMP, GIF, etc.).
% It supports multi-page TIF files, pyramidal TIF images, custom region
% loading, and pixel size extraction from metadata.

    methods
        function obj = ImreadLoader(options)
            % IMREADLOADER - Constructor for ImreadLoader class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.ImreadLoader(options)
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
            %   - **obj** — instance of the ImreadLoader class
            %
            % **Example 1** — create loader with options:
            %
            %   .. code-block:: matlab
            %
            %      options.waitbar = true;
            %      options.mibPath = 'c:\mib';
            %      loader = io.loaders.ImreadLoader(options);
            %
            
            % default Options settings
            obj.Options = struct();
            obj.Options.Font = struct('Name', 'Helvetica', 'Size', 12);

            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - Load metadata for standard image files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [imginfo, files] = obj.loadMetadata(filenames, options)
            %
            % This method extracts image metadata using imfinfo for standard
            % MATLAB-readable image formats. It handles pyramidal TIF detection,
            % pixel size extraction from various formats (Amira, Zeiss, Fibics),
            % and custom section parameters.
            %
            % Input Arguments:
            %   - **filenames** — cell array with filenames of images
            %   - **options** — *(optional)* struct with fields:
            %
            %     - ``waitbar`` — [logical] show or not the waitbar; default: ``false``
            %     - ``customSections`` — [logical] load part of the dataset; default: ``false``
            %     - ``customSectionsSettings`` — [struct] custom section settings
            %     - ``xMin`` — [numeric] min X coordinate
            %     - ``xMax`` — [numeric] max X coordinate
            %     - ``yMin`` — [numeric] min Y coordinate
            %     - ``yMax`` — [numeric] max Y coordinate
            %     - ``zMin`` — [numeric] min Z coordinate (slice)
            %     - ``zMax`` — [numeric] max Z coordinate (slice)
            %     - ``xyStep`` — [numeric] XY binning step
            %     - ``mibPath`` — [char] path to MIB directory
            %     - ``ParentFigure`` — handle to the parent window for progress dialog
            %     - ``Font`` — [struct] font settings for dialogs
            %     - ``BioFormatsIndices`` — [numeric] level index for pyramidal TIF
            %
            % Output Arguments:
            %   - **imginfo** — dictionary with image metadata containing fields:
            %
            %     - ``Height`` — image height in pixels
            %     - ``Width`` — image width in pixels
            %     - ``Colors`` — number of color channels
            %     - ``Depth`` — number of z-slices
            %     - ``Time`` — number of time points
            %     - ``imgClass`` — image class (``uint8``, ``uint16``, etc.)
            %     - ``ColorType`` — ``'grayscale'``, ``'truecolor'``, or ``'indexed'``
            %     - ``ImageDescription`` — description with BoundingBox info
            %     - other format-specific metadata fields
            %
            %   - **files** — structure array with file information for each file:
            %
            %     - ``filename`` — [char] full filename
            %     - ``objecttype`` — [char] type of the image loader ``'imread'``
            %     - ``extension`` — [char] file extension, including the leading dot
            %     - ``height`` — [numeric] image height
            %     - ``width`` — [numeric] image width
            %     - ``color`` — [numeric] number of color channels
            %     - ``noLayers`` — [numeric] number of image frames
            %     - ``time`` — [numeric] number of time points
            %     - ``imgClass`` — [char] image class (``'uint8'``, ``'uint16'``, ``'uint32'``, ``'single'``)
            %     - ``level`` — [numeric] pyramid level (for pyramidal TIF)
            %     - ``levelMagScale`` — [numeric] magnification scale factor
            %     - ``xMin``, ``xMax``, ``yMin``, ``yMax`` — [numeric] region coordinates
            %     - ``xyStep`` — [numeric] XY step for binning
            %
            % **Example 1** — load metadata from standard image files:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.ImreadLoader();
            %      options.waitbar = true;
            %      filenames = {'image1.tif', 'image2.tif'};
            %      [imginfo, files] = loader.loadMetadata(filenames, options);
            %      fprintf('Image size: %d x %d x %d\n', imginfo{"Width"}, imginfo{"Height"}, imginfo{"Depth"});
            %

            % Merge constructor options with runtime options
            if nargin < 3; options = obj.Options; end
            options = obj.mergeOptions(obj.Options, options);

            % init imginfo dictionary with the default set of keys
            imginfo = core.MibImage.initializeImgInfo();
            pixSize = imginfo{"pixSize"}; % get default pixel size
            bbDz = 0;    % BoundingBox Z range from first file (used to correct pixSize.z after loop)

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
            [files.objecttype] = deal('imread');

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    imginfo = dictionary();
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.ImreadLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.ImreadLoader');
                    return;
                end

                % Check for cancel button
                if ~isempty(wb) && wb.CancelRequested
                    % Use metadata from first file for all remaining files
                    files(fnIndex:noFiles) = files(1);
                    [files.filename] = filenames{:};                % update filenames
                    [~, ~, ext] = fileparts(filenames(fnIndex:noFiles));
                    [files(fnIndex:noFiles).extension] = ext{:};    % update extensions
                    fnIndex = noFiles;
                    continue;
                end

                % Extract file parts
                [~, ~, ext] = fileparts(filenames{fnIndex});
                ext = lower(ext);
                files(fnIndex).extension = ext;
                files(fnIndex).filename = cell2mat(filenames(fnIndex));

                try
                    info = imfinfo(files(fnIndex).filename);
                catch err
                    if ~isempty(wb); delete(wb); end
                    return;
                    %rethrow(err);
                end

                if fnIndex == 1
                    % Extra check for TIF files with pyramids
                    if numel(info) > 1 && (strcmpi(ext(2:end), 'tif') || strcmpi(ext(2:end), 'tiff'))
                        if info(1).Width ~= info(2).Width
                            if ~isfield(options, 'BioFormatsIndices') || isempty(options.BioFormatsIndices)
                                % This is a pyramidal TIF
                                defAns = {};
                                for ii = 1:numel(info)
                                    defAns = [defAns, {sprintf('Lvl: %d, %d x %d', ii, info(ii).Width, info(ii).Height)}]; %#ok<AGROW>
                                end
                                defAns{end+1} = 1; %#ok<AGROW>
                                prompt = {sprintf('This is pyramidal TIF that has %d sub-images\nPlease choose the one to get:', numel(info))};
                                dlgOptions.LabelPosition = 'top';
                                dlgOptions.mibPath = options.mibPath;
                                [answer, selectedIndex] = utils.dlgs.inputUniversalDlg(options.ParentFigure, '', prompt, {defAns}, 'title', dlgOptions);
                                if isempty(answer)
                                    if ~isempty(wb); delete(wb); end
                                    return;
                                end
                                files(fnIndex).level = selectedIndex;
                                files(fnIndex).levelMagScale = info(1).Width / info(files(fnIndex).level).Width; % store magnification scaling factor
                            else
                                files(fnIndex).level = options.BioFormatsIndices;
                                files(fnIndex).levelMagScale = info(1).Width / info(files(fnIndex).level).Width;
                            end
                        end
                    end
                end

                % Select the correct info level for pyramidal images
                if isfield(files, 'level')
                    if isfield(info, 'UnknownTags')
                        UnknownTags = info.UnknownTags; % reserve unknown tags
                        info = info(files(1).level);
                        info.UnknownTags = UnknownTags;
                    else
                        info = info(files(1).level);
                    end
                    files(fnIndex).level = files(1).level;
                    files(fnIndex).levelMagScale = files(1).levelMagScale;
                end

                % Convert cells to chars for metadata fields
                fields = sort(fieldnames(info));
                NumberOfFrames = numel(info);
                for fieldIdx = 1:numel(fields)
                    if iscell(info(1).(fields{fieldIdx}))
                        if numel(info.(fields{fieldIdx})) < 2  % skip multi-element cell arrays
                            info.(fields{fieldIdx}) = cell2mat(info.(fields{fieldIdx}));
                        end
                    end
                end

                % Move Comment to ImageDescription for jpg/png files
                if strcmp(ext, '.jpg') || strcmp(ext, '.png')
                    info.ImageDescription = info.Comment;
                    info = rmfield(info, 'Comment');
                    fields = sort(fieldnames(info));
                end

                % Store file dimensions
                files(fnIndex).height = info(1).Height;
                files(fnIndex).width = info(1).Width;
                files(fnIndex).noLayers = NumberOfFrames;
                files(fnIndex).time = 1;

                % Determine image class from bit depth
                switch info(1).BitDepth  % alternative: info(1).BitsPerSample
                    case {8, 24}  % grayscale and RGB
                        files(fnIndex).imgClass = 'uint8';
                    case {16, 48}  % grayscale and RGB
                        files(fnIndex).imgClass = 'uint16';
                    case {32, 96}  % grayscale and RGB
                        files(fnIndex).imgClass = 'uint32';
                    otherwise
                        files(fnIndex).imgClass = 'single';
                end

                % Check color type consistency
                % change truecolor->multichannel to match MIB color scheme
                if strcmp(info(1).ColorType, 'truecolor'); imginfo{"ColorType"} = 'multichannel'; info(1).ColorType='multichannel'; end
                if ~isempty(imginfo{"ColorType"}) && ~strcmp(imginfo{"ColorType"}, info(1).ColorType)
                    imginfo = dictionary();
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('!!! Error !!!\n\nThe files have dissimilar ColorType'), ...
                        'Mixed colors', 'Error in io.loaders.ImreadLoader');
                    return;
                end

                % Determine number of color channels
                if ismember(info(1).ColorType, {'multichannel', 'YCbCr'})
                    files(fnIndex).color = 3;
                else
                    files(fnIndex).color = 1;
                end

                % Update pixel size (only for first file)
                if fnIndex == 1
                    % Generate imginfo from first image
                    for ind = 1:numel(fields)
                        imginfo{fields{ind}} = info(1).(fields{ind});
                    end

                    if isKey(imginfo, "ImageDescription")
                        bbStart = strfind(imginfo{"ImageDescription"}, 'BoundingBox');
                        if iscell(bbStart); bbStart = bbStart{1}; end
                    else
                        bbStart = [];
                    end

                    if ~isempty(bbStart)
                        % Detect pixel size from BoundingBox in ImageDescription
                        %brakePnt = strfind(imginfo{"ImageDescription"}, '|');
                        % if isempty(brakePnt)
                        %     brakePnt = strfind(imginfo{"ImageDescription"}, sprintf('\t'));
                        %     if isempty(brakePnt)
                        %         brakePnt = strfind(imginfo{"ImageDescription"}, sprintf('\n'));
                        %     end
                        % end
                        brakePnt = regexp(imginfo{"ImageDescription"}, '[\|\t\n]', 'once');

                        if ~isempty(brakePnt)
                            % brakePnt = brakePnt(1);
                            % bbString = imginfo{"ImageDescription"};
                            % bbcoord = str2num(bbString(bbStart+11:brakePnt-1)); %#ok<ST2NM>

                            bbString = imginfo{"ImageDescription"};
                            bbcoord = sscanf(bbString(bbStart+11:brakePnt-1), '%f');
                            
                            dx = bbcoord(2) - bbcoord(1);
                            dy = bbcoord(4) - bbcoord(3);
                            dz = bbcoord(6) - bbcoord(5);
                            bbDz = dz;   % remember for post-loop Z correction
                            % Round to 10 sig-figs to remove IEEE 754 noise from the string→division round-trip
                            pixSize.x = round(dx / max([files(fnIndex).width-1, 1]),  10, 'significant');
                            pixSize.y = round(dy / max([files(fnIndex).height-1, 1]), 10, 'significant');
                            pixSize.z = round(dz / max([files(fnIndex).noLayers-1, 1]), 10, 'significant');
                            % For a single-layer file the full Z range is meaningless as Z spacing;
                            % fall back to the isotropic assumption (same as when dz == 0)
                            if files(fnIndex).noLayers == 1 || pixSize.z == 0
                                pixSize.z = min([pixSize.x, pixSize.y]);
                            end
                            pixSize.units = 'um';
                        end
                    elseif isfield(info, 'Software') && ...
                            (strcmp(info(1).Software(1:min(18, numel(info(1).Software))), 'Fibics AtlasEngine') || ...
                            strcmp(info(1).Software(1:min(18, numel(info(1).Software))), 'NPVE'))
                        % Extract pixel size for Fibics AtlasEngine or NPVE
                        if isfield(info, 'UnknownTags')
                            if isfield(files, 'levelMagScale')
                                scaleFactor = files(1).levelMagScale;
                            elseif isfield(files, 'level')
                                scaleFactor = 2^(files(1).level - 1);
                            else
                                scaleFactor = 1;
                            end

                            pixSizePos1 = strfind(info.UnknownTags.Value, '[Ux]');
                            if ~isempty(pixSizePos1)  % Fibics AtlasEngine
                                pixSizePos2 = strfind(info.UnknownTags.Value, '[Ux]');
                                pixSize.x = str2double(info.UnknownTags.Value(pixSizePos1+4:pixSizePos2-1)) * scaleFactor;
                            else  % NPVE
                                pixSizePos1 = strfind(info.UnknownTags.Value, '[FOVX units]') + 18; % "[FOVX units]=um[32.7667846679687][FOVX]"
                                pixSizePos2 = strfind(info.UnknownTags.Value, '[FOVX]') - 1;
                                xFOV = str2double(info.UnknownTags.Value(pixSizePos1:pixSizePos2));
                                widthPos1 = strfind(info.UnknownTags.Value, '[Width]') + 7;
                                widthPos2 = strfind(info.UnknownTags.Value, '[Width]') - 1;
                                imageWidth = str2double(info.UnknownTags.Value(widthPos1:widthPos2));
                                pixSize.x = xFOV / imageWidth * scaleFactor;
                            end
                            pixSizePos3 = strfind(info.UnknownTags.Value, '[FOVX units]') + 13;
                            pixSize.units = info.UnknownTags.Value(pixSizePos3:pixSizePos3+1);
                            pixSize.y = pixSize.x;
                        end
                    elseif isfield(info, 'UnknownTags') && isfield(info, 'SampleFormat') && ...
                            isfield(info, 'PhotometricInterpretation') && isfield(info, 'ColorType')
                        % Extract pixel size for Zeiss SmartSEM
                        if (strcmp(info(1).ColorType, 'grayscale') && strcmp(info(1).PhotometricInterpretation, 'BlackIsZero')) || ...
                                (strcmp(info(1).ColorType, 'indexed') && strcmp(info(1).PhotometricInterpretation, 'RGB Palette'))
                            metaStr = info(1).UnknownTags.Value;
                            pixSizePos = strfind(metaStr, 'Image Pixel Size');
                            if ~isempty(pixSizePos)
                                try
                                    if isfield(files, 'levelMagScale')
                                        scaleFactor = files(1).levelMagScale;
                                    elseif isfield(files, 'level')
                                        scaleFactor = 2^(files(1).level - 1);
                                    else
                                        scaleFactor = 1;
                                    end
                                    lineBrkPos = strfind(metaStr(pixSizePos:pixSizePos+50), sprintf('\n')); %#ok<SPRINTFN>
                                    metaStr = metaStr(pixSizePos:pixSizePos+lineBrkPos(1)-3);  % "Image Pixel Size = 1.149 nm"
                                    spacesPos = strfind(metaStr, ' ');
                                    pixSizeText = metaStr(spacesPos(end-1)+1:spacesPos(end)-1);
                                    pixSize.x = str2double(pixSizeText) * scaleFactor;
                                    pixSize.y = pixSize.x;
                                    pixSize.units = metaStr(spacesPos(end)+1:end);
                                    if double(pixSize.units(1)) == 181  % convert µm to um
                                        pixSize.units(1) = 'u';
                                    end
                                catch err
                                    if ~isempty(wb); delete(wb); end
                                    rethrow(err);
                                end
                            end
                        end
                    end
                end

                % Update waitbar
                if ~isempty(wb)
                    if mod(fnIndex, ceil(noFiles/50)) == 0; wb.Value = fnIndex/noFiles; end
                end
            end

            % If pixSize.z was estimated from a single-layer file (using the isotropic fallback),
            % recalculate it now that the total Z depth across all files is known.
            if bbDz > 0 && isfield(files, 'noLayers') && files(1).noLayers == 1
                totalDepth = sum([files.noLayers]);
                if totalDepth > 1
                    pixSize.z = round(bbDz / (totalDepth - 1), 10, 'significant');
                end
            end

            % update pixSize
            imginfo{"pixSize"} = pixSize;

            % Replace CR and LF characters with spaces
            if ~isempty(imginfo{"ImageDescription"})
                imginfo{"ImageDescription"} = strrep(strrep(imginfo{"ImageDescription"}, sprintf('\r'), ' '), sprintf('\n'), ' '); %#ok<SPRINTFN>
            end

            % Handle custom sections
            % use io.BaseImageLoader.handleCustomSections of the parent class
            if options.customSections && strcmpi(ext(2:end), 'tif')
                [files, imginfo, cancelled] = obj.handleCustomSections(files, imginfo, options);
                if cancelled
                    imginfo = dictionary();
                    if ~isempty(wb); delete(wb); end
                    return; 
                end
            end

            % Handle dimension mismatches and bounding box
            % use io.BaseImageLoader.handleDimensionMismatches of the parent class
            imginfo = obj.handleDimensionMismatches(files, imginfo);

            % Set number of entries (required by MibDataset.loadModel)
            imginfo{"numEntries"} = noFiles;

            % Generate slice names from filenames
            % use io.BaseImageLoader.generateSliceNames of the parent class
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            % use io.BaseImageLoader.finalizeImgInfo of the parent class
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if ~isempty(wb); delete(wb); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % LOADIMAGES - Load image data for standard image files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.loadImages(files, imginfo, options)
            %
            % This method loads actual image data using imread for standard
            % MATLAB image formats. It supports multi-page TIF files, pyramidal
            % images, custom region loading (PixelRegion), GIF conversion, and
            % dimension mismatch handling with background filling.
            %
            % Input Arguments:
            %   - **files** — structure array from loadMetadata with file information:
            %
            %     - ``filename`` — [char] full filename
            %     - ``objecttype`` — [char] type of the image loader ``'imread'``
            %     - ``extension`` — [char] file extension with dot (e.g., ``'.jpg'``)
            %     - ``height`` — [numeric] image height
            %     - ``width`` — [numeric] image width
            %     - ``color`` — [numeric] number of color channels
            %     - ``noLayers`` — [numeric] number of image layers/frames
            %     - ``time`` — [numeric] number of image frames
            %     - ``imgClass`` — [char] image class (``'uint8'``, ``'uint16'``, ``'uint32'``)
            %     - ``level`` — [numeric] pyramid level (optional)
            %     - ``xMin``, ``xMax``, ``yMin``, ``yMax`` — [numeric] region coordinates (optional)
            %     - ``zMin``, ``zMax`` — [numeric] slice range (optional)
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
            %   - **img** — loaded image dataset [height, width, depth, color, time]
            %   - **imginfo** — updated dictionary with final metadata:
            %
            %     - ``Height`` — final image height
            %     - ``Width`` — final image width
            %     - ``Depth`` — final number of slices
            %     - ``Time`` — number of time points
            %     - ``ColorType`` — color type
            %     - ``ColorTable`` — colormap for indexed images (optional)
            %
            % **Example 1** — load images from standard image file:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.ImreadLoader();
            %      options.waitbar = true;
            %      [imginfo, files] = loader.loadMetadata({'image.tif'}, options);
            %      [img, imginfo] = loader.loadImages(files, imginfo, options);
            %      fprintf('Loaded image size: %s\n', mat2str(size(img)));
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

            % Calculate total number of slices
            if isfield(files, 'zMin')
                maxZ = sum([files.zMax] - [files.zMin] + 1);
                %for i = 1:numel(files)
                %    maxZ = maxZ + (files(i).zMax - files(i).zMin + 1);
                %end
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
                wb = obj.createProgressDialog('Loading images...', ...
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

                % Handle GIF conversion
                convertGifSwitch = false;
                if ~isempty(strfind(files(fnIndex).extension, 'gif')) && files(fnIndex).noLayers > 1
                    selection = uiconfirm(options.ParentFigure, ...
                        'Convert indexed GIF to truecolor?', ...
                        'Image format warning!', ...
                        'Icon', 'warning', 'DefaultOption', 1);
                    if strcmp(selection, 'OK')
                        convertGifSwitch = true;
                        imginfo('ColorType') = {'multichannel'};
                        imginfo = remove(imginfo, 'ColorTable');
                        maxC = max(maxC, 3);
                        files(fnIndex).color = maxC;
                    end
                end

                % Load each layer
                for subLayer = 1:files(fnIndex).noLayers
                    % Determine imread parameters based on custom sections
                    if ~isfield(files, 'xMin')
                        if files(fnIndex).noLayers == 1
                            if ~isfield(files, 'level')
                                I = imread(files(fnIndex).filename);
                            else
                                I = imread(files(fnIndex).filename, files(fnIndex).level);
                            end
                        else
                            I = imread(files(fnIndex).filename, subLayer);
                        end
                    else
                        if files(fnIndex).noLayers == 1
                            if ~isfield(files, 'level')
                                I = imread(files(fnIndex).filename, ...
                                    'PixelRegion', ...
                                    {[files(fnIndex).yMin files(fnIndex).xyStep files(fnIndex).yMax], ...
                                    [files(fnIndex).xMin files(fnIndex).xyStep files(fnIndex).xMax]});
                            else
                                I = imread(files(fnIndex).filename, files(fnIndex).level, ...
                                    'PixelRegion', ...
                                    {[files(fnIndex).yMin files(fnIndex).xyStep files(fnIndex).yMax], ...
                                    [files(fnIndex).xMin files(fnIndex).xyStep files(fnIndex).xMax]});
                            end
                        else
                            if subLayer < files(fnIndex).zMin || subLayer > files(fnIndex).zMax
                                continue;
                            end
                            I = imread(files(fnIndex).filename, subLayer, ...
                                'PixelRegion', ...
                                {[files(fnIndex).yMin files(fnIndex).xyStep files(fnIndex).yMax], ...
                                [files(fnIndex).xMin files(fnIndex).xyStep files(fnIndex).xMax]});
                        end
                    end

                    % Handle single - uint32 RGB TIFs may be this class
                    if isa(I, 'single') 
                        if isKey(imginfo, "MaxSampleValue")
                            I = bsxfun(@times, I, reshape(imginfo{"MaxSampleValue"}, 1, 1, []));
                        end
                    end

                    % Store slice
                    img(1:maxY, 1:maxX, layerid, 1:size(I,3)) = permute(I(1:maxY, 1:maxX, 1:size(I,3)), [1 2 4 3]);

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
