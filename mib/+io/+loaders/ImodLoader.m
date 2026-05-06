classdef ImodLoader < io.loaders.BaseImageLoader
% IMODLOADER - Loader for IMOD MRC/REC files (.mrc, .rec, .st, .pre, .ali), based on.
%
% io.loaders.BaseImageLoader base class
%
% This loader handles IMOD format files using the MRCImage class.
% It supports:
% - MRC/REC format (electron microscopy)
% - Tomogram stacks (.st, .preali, .ali)
% - Automatic conversion from signed/float to unsigned integers
% - Dimension permutation and vertical flipping

    methods
        function obj = ImodLoader(options)
            % IMODLOADER - Constructor for ImodLoader class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.ImodLoader(options)
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
            %   - **obj** — instance of the ImodLoader class
            %
            % **Example 1** — create loader with options:
            %
            %   .. code-block:: matlab
            %
            %      options.waitbar = true;
            %      loader = io.loaders.ImodLoader(options);
            %

            % default Options settings
            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
            obj.initBaseProps(options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - Load metadata for IMOD MRC/REC files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [imginfo, files] = obj.loadMetadata(filenames, options)
            %
            % This method uses MRCImage to read file headers and determine
            % dimensions and data types.
            %
            % Input Arguments:
            %   - **filenames** — cell array with filenames of IMOD files
            %   - **options** — *(optional)* struct with fields:
            %
            %     - ``waitbar`` — [logical] show or not the waitbar; default: ``false``
            %     - ``customSections`` — [logical] load part of the dataset; default: ``false``
            %     - ``Font`` — [struct] font settings for dialogs
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
            %     - ``Format`` — HDF5 format type (``'matlab.hdf5'`` or ``'bdv.hdf5'``)
            %     - ``Levels`` — number of pyramid levels (for BDV only)
            %     - ``ReturnedLevel`` — selected pyramid level (for BDV only)
            %     - ``pixSize`` — struct with pixel sizes: ``.x``, ``.y``, ``.z``, ``.t``,
            %       ``.units``, ``.tunits``
            %     - other format-specific metadata fields
            %
            %   - **files** — structure array with file information
            %
            % **Example 1** — load metadata from IMOD file:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.ImodLoader();
            %      filenames = {'dataset.mrc'};
            %      [imginfo, files] = loader.loadMetadata(filenames, options);
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

            noFiles = numel(filenames);

            % Initialize waitbar if requested
            pwb = [];
            if options.waitbar && ~isempty(obj.ParentFigure)
                pwb = core.PoolWaitbar(noFiles, ...
                    sprintf('Loading IMOD metadata\n(press Cancel when metadata is the same for all files)'), ...
                    obj.ParentFigure, 'Metadata import', true);
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', []);

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.ImodLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.ImodLoader');
                    imginfo = dictionary();
                    return;
                end

                % Check for cancel button
                if ~isempty(pwb) && pwb.getCancelState()
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
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error reading IMOD file:\n%s', err.message), 'IMOD Error', 'Error in io.loaders.ImodLoader');
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
                if ~isempty(pwb); pwb.increment(); end
            end

            % update pixSize
            imginfo{"pixSize"} = pixSize;

            % Handle custom sections
            if options.customSections
                [files, imginfo, cancelled] = obj.handleCustomSections(files, imginfo, options);
                if cancelled
                    imginfo = dictionary();
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    return;
                end
            end

            % Set number of entries (required by MibDataset.loadModel)
            imginfo{"numEntries"} = noFiles;

            % Generate slice names
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % LOADIMAGES - Load image data from IMOD MRC/REC files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.loadImages(files, imginfo, options)
            %
            % This method uses ``MRCImage.getVolume()`` to load actual data.
            % It handles:
            %
            % - Conversion from signed/float to unsigned integers
            % - Dimension permutation (X,Y,Z → Y,X,Z)
            % - Vertical flipping (MRC convention)
            %
            % Input Arguments:
            %   - **files** — structure array from loadMetadata
            %   - **imginfo** — dictionary from loadMetadata
            %   - **options** — *(optional)* struct for image loading
            %
            % Output Arguments:
            %   - **img** — loaded image dataset
            %   - **imginfo** — updated dictionary
            %
            % **Example 1** — load images from IMOD MRC file:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.ImodLoader();
            %      [imginfo, files] = loader.loadMetadata({'dataset.mrc'}, options);
            %      [img, imginfo] = loader.loadImages(files, imginfo, options);
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

            % Initialize waitbar
            pwb = [];
            if options.waitbar && ~isempty(obj.ParentFigure)
                pwb = core.PoolWaitbar(maxZ, 'Please wait...', obj.ParentFigure, 'Loading IMOD images...', true);
                if ~isempty(pwb); pwb.setIncrement(waitbarUpdateFrequency); end
            end

            for fnIndex = 1:noFiles
                % Check for cancel button
                if ~isempty(pwb) && pwb.getCancelState()
                    pwb.deletePoolWaitbar();
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
                            selection = uiconfirm(options.ParentFigure, ...
                                'The dataset will be converted to unsigned integer class.', ...
                                'Convert image', ...
                                'Icon', 'warning', 'DefaultOption', 1);
                            if strcmp(selection, 'Cancel')
                                if ~isempty(pwb); pwb.deletePoolWaitbar(); end
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
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error loading IMOD file:\n%s', err.message), 'IMOD Error', 'Error in io.loaders.ImodLoader');
                    img = [];
                    return;
                end

                % Update waitbar
                if ~isempty(pwb) && mod(layerId, waitbarUpdateFrequency) == 0
                    pwb.increment();
                end

                layerId = layerId + files(fnIndex).noLayers;
            end

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end

            % Finalize
            imginfo{'Height'} = height;
            imginfo{'Width'} = width;
            imginfo{'Depth'} = maxZ;
            imginfo{'Time'} = time;

            [img, imginfo] = obj.finalizeImageLoading(img, imginfo, options);
        end
    end
end
