classdef ImodLoader < io.loaders.BaseImageLoader
    % classdef ImodLoader
    % Loader for IMOD MRC/REC files (.mrc, .rec, .st, .pre, .ali), based on
    % io.loaders.BaseImageLoader base class
    %
    % This loader handles IMOD format files using the MRCImage class.
    % It supports:
    %   - MRC/REC format (electron microscopy)
    %   - Tomogram stacks (.st, .preali, .ali)
    %   - Automatic conversion from signed/float to unsigned integers
    %   - Dimension permutation and vertical flipping

    methods
        function obj = ImodLoader(options)
            % function obj = ImodLoader(options)
            % Constructor for ImodLoader class
            %
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
            %
            % Return values:
            %   obj: instance of the ImodLoader class
            %
            % Example:
            %   @code
            %   options.waitbar = true;
            %   loader = io.loaders.ImodLoader(options);
            %   @endcode

            % default Options settings
            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % function [imginfo, files] = loadMetadata(obj, filenames, options)
            % Load metadata for IMOD MRC/REC files
            %
            % This method uses MRCImage to read file headers and determine
            % dimensions and data types.
            %
            % Parameters:
            %   filenames: cell array with filenames of IMOD files
            %   options: [@em struct] options for metadata loading
            %     @li .waitbar - [logical] show or not the waitbar
            %     @li .customSections - [logical] load part of the dataset
            %     @li .Font - [struct] font settings for dialogs
            %
            % Return values:
            %   imginfo: dictionary with image metadata
            %     @li "Height" - image height in pixels
            %     @li "Width" - image width in pixels
            %     @li "Colors" - number of color channels
            %     @li "Depth" - number of z-slices
            %     @li "Time" - number of time points
            %     @li "imgClass" - image class (uint8, uint16, etc.)
            %     @li "ColorType" - 'grayscale', 'truecolor', or 'indexed'
            %     @li "ImageDescription" - description with BoundingBox info
            %     @li "Format" - HDF5 format type ('matlab.hdf5' or 'bdv.hdf5')
            %     @li "Levels" - number of pyramid levels (for BDV only)
            %     @li "ReturnedLevel" - selected pyramid level (for BDV only)
            %     @li "pixSize" - structire with pixel sizes, .x, .y, .z, .t, .units, .tunits
            %     @li other format-specific metadata fields
            %   files: structure array with file information
            %
            % Example:
            %   @code
            %   loader = io.loaders.ImodLoader();
            %   filenames = {'dataset.mrc'};
            %   [imginfo, files] = loader.loadMetadata(filenames, options);
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

            noFiles = numel(filenames);

            % Initialize waitbar if requested
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Metadata import',...
                    'Message', sprintf('Loading IMOD metadata\n(press Cancel when metadata is the same for all files)'), ...
                    'Cancelable', 'on');
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', []);

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error in io.loaders.ImodLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists');
                    imginfo = dictionary();
                    return;
                end

                % Check for cancel button
                if options.waitbar && wb.CancelRequested
                    % Use metadata from first file for all remaining files
                    files(fnIndex:noFiles) = files(1);
                    [files.filename] = filenames{:};
                    [~, ~, ext] = fileparts(filenames(fnIndex:noFiles));
                    [files(fnIndex:noFiles).extension] = ext{:};
                    fnIndex = noFiles; %#ok<NASGU>
                    continue;
                end

                % Extract file parts
                [~, ~, ext] = fileparts(filenames{fnIndex});
                ext = lower(ext);

                files(fnIndex).extension = ext;
                files(fnIndex).filename = cell2mat(filenames(fnIndex));
                files(fnIndex).objecttype = 'mrc_image';

                % Read MRC header using MRCImage
                try
                    mrcFile = MRCImage(files(fnIndex).filename, 0);  % create pointer to a file volume
                    info = getHeader(mrcFile);     % get header

                    % Get dimensions
                    files(fnIndex).width = info.nX;
                    files(fnIndex).height = info.nY;
                    files(fnIndex).noLayers = info.nZ;
                    files(fnIndex).color = 1; % MRC is always grayscale
                    files(fnIndex).time = 1;

                    % reshape the labels into ImageDescription
                    pixSize.x = info.cellDimensionX/info.nX/10000;
                    pixSize.y = info.cellDimensionY/info.nY/10000;
                    pixSize.z = info.cellDimensionZ/info.nZ/10000;
                    pixSize.units = 'um';
                    xyzZero(1) = info.xOrigin/10000;
                    xyzZero(2) = info.yOrigin/10000;
                    xyzZero(3) = info.zOrigin/10000;
                    dx = (info.nX-1)*pixSize.x;
                    dy = (info.nY-1)*pixSize.y;
                    dz = (info.nZ-1)*pixSize.z;
                    labelOut = sprintf('BoundingBox %.6f %.6f %.6f %.6f %.6f %.6f \t',...
                        xyzZero(1), xyzZero(1)+dx, ...
                        xyzZero(2), xyzZero(2)+dy, ...
                        xyzZero(3), xyzZero(3)+dz);

                    for labelId = 1:size(info.labels,1)
                        if ~isempty(strtrim(info.labels(labelId,:)))
                            labelOut = sprintf('%s|%s', labelOut, regexprep(info.labels(labelId,:), '\s+', ' '));
                        end
                    end
                    info.ImageDescription = labelOut;
                    info = rmfield(info, 'labels');

                    % Determine data type from MRC mode
                    % MRC modes:
                    % 0 = uint8 (signed byte in spec, but MATLAB uses unsigned)
                    % 1 = int16
                    % 2 = float32
                    % 3 = complex int16
                    % 4 = complex float32
                    % 6 = uint16
                    % 16 = RGB (3 bytes per pixel)

                    mrcMode = info.mode;
                    switch mrcMode
                        case 0
                            files(fnIndex).imgClass = 'uint8';
                        case 1
                            files(fnIndex).imgClass = 'int16';
                        case 2
                            files(fnIndex).imgClass = 'single';
                        case 6
                            files(fnIndex).imgClass = 'uint16';
                        otherwise
                            files(fnIndex).imgClass = 'single'; % fallback
                    end

                    % Close file
                    close(mrcFile);

                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error reading IMOD file:\n%s', err.message), 'IMOD Error');
                    imginfo = dictionary();
                    return;
                end

                % Metadata for first file
                if fnIndex == 1
                    imginfo{'imgClass'} = files(fnIndex).imgClass;
                    imginfo{'ColorType'} = 'grayscale'; % MRC is always grayscale
                    fields = sort(fieldnames(info));

                    for ind = 1:numel(fields)
                        imginfo{fields{ind}} = info.(fields{ind});
                    end
                end

                % Update waitbar
                if options.waitbar
                    if mod(fnIndex, ceil(noFiles/50)) == 0
                        wb.Value = fnIndex/noFiles;
                    end
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

            % Generate slice names
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if options.waitbar; delete(wb); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % Load image data from IMOD MRC/REC files
            %
            % This method uses MRCImage.getVolume() to load actual data.
            % It handles:
            %   - Conversion from signed/float to unsigned integers
            %   - Dimension permutation (X,Y,Z -> Y,X,Z)
            %   - Vertical flipping (MRC convention)
            %
            % Parameters:
            %   files: structure array from loadMetadata
            %   imginfo: dictionary from loadMetadata
            %   options: [@em struct] options for image loading
            %
            % Return values:
            %   img: loaded image dataset
            %   imginfo: updated dictionary

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
            else
                maxZ = sum([files.noLayers]);
            end

            if maxZ == 0
                img = [];
                return;
            end

            % Prepare image class
            imgClass = files(1).imgClass;
            if strcmp(imgClass, 'int16'); imgClass = 'uint16'; end

            % Pre-allocate image array: [Y, X, Z, C, T]
            img = zeros(height, width, maxZ, color, time, imgClass);

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            layerId = 1;
            noFiles = numel(files);

            % Initialize uiprogressdlg
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Loading IMOD images...',...
                    'Message', sprintf('Please wait...'), ...
                    'Cancelable', 'on');
            end

            for fnIndex = 1:noFiles
                % Check for cancel button
                if options.waitbar && wb.CancelRequested
                    delete(wb);
                    img = [];
                    return;
                end

                maxY = min(height, files(fnIndex).height);
                maxX = min(width, files(fnIndex).width);
                maxC = min(color, files(fnIndex).color);

                % Load MRC data
                try
                    mrcFile = MRCImage(files(fnIndex).filename, 0);
                    mrcimage = getVolume(mrcFile);

                    % Flip vertically (MRC convention)
                    mrcimage = flip(mrcimage, 2);

                    % Check if conversion is needed (single/int16 -> unsigned)
                    if isa(mrcimage, 'single') || isa(mrcimage, 'int16')
                        [minInt, maxInt] = getMinAndMaxDensity(mrcFile);

                        if minInt < 0 && ~options.silentMode
                            selection = uiconfirm(options.parentGUI, ...
                                'The dataset will be converted to unsigned integer class.', ...
                                'Convert image', ...
                                'Icon', 'warning', 'DefaultOption', 1);
                            if strcmp(selection, 'Cancel')
                                if options.waitbar; delete(wb); end
                                img = [];
                                return;
                            end
                            options.silentMode = true; % Don't ask again
                        end

                        % Shift to positive range
                        if minInt < 0
                            mrcimage = mrcimage - minInt;
                        end

                        % Convert based on dynamic range
                        diffInt = maxInt - minInt;
                        if diffInt <= 255
                            mrcimage = uint8(mrcimage);
                        elseif diffInt <= 65535
                            mrcimage = uint16(mrcimage);
                        elseif diffInt <= 4294967295
                            mrcimage = uint32(mrcimage);
                        end
                    end

                    % Permute dimensions: [X, Y, Z] -> [Y, X, Z]
                    mrcimage = permute(mrcimage, [2 1 3]);

                    % Assign data
                    img(1:maxY, 1:maxX, layerId:layerId+files(fnIndex).noLayers-1, 1:maxC, 1) = ...
                        mrcimage(1:maxY, 1:maxX, 1:files(fnIndex).noLayers, 1:maxC);

                    close(mrcFile);
                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error loading IMOD file:\n%s', err.message), 'IMOD Error');
                    img = [];
                    return;
                end

                % Update waitbar
                if options.waitbar
                    if mod(layerId, waitbarUpdateFrequency) == 0
                        wb.Value = layerId / maxZ;
                    end
                end

                layerId = layerId + files(fnIndex).noLayers;
            end

            if options.waitbar; delete(wb); end

            % Finalize
            imginfo{'Height'} = height;
            imginfo{'Width'} = width;
            imginfo{'Depth'} = maxZ;
            imginfo{'Time'} = time;

            [img, imginfo] = obj.finalizeImageLoading(img, imginfo, options);
        end
    end
end