classdef AmiraMeshLoader < io.loaders.BaseImageLoader
    % classdef AmiraMeshLoader
    % Loader for Amira Mesh (.am) files, based on io.loaders.BaseImageLoader base class
    %
    % This loader implements the legacy Amira Mesh reader from getImageMetadata.m
    % and getImages.m as a standalone loader class.
    %
    % It uses the existing helper functions:
    %   - getAmiraMeshHeader.m
    %   - amiraMesh2bitmap.m
    %   - ib_amiraImportGui.m (optional, used for custom binning / section selection)

    methods
        function obj = AmiraMeshLoader(options)
            % function obj = AmiraMeshLoader(options)
            % Constructor for AmiraMeshLoader class
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
            %     @li .parentGUI - handle of the main MIB window (parent for uiprogressdlg)
            %
            % Return values:
            %   obj: instance of the AmiraMeshLoader class
            %
            % Example:
            %   @code
            %   options.waitbar = true;
            %   loader = io.loaders.AmiraMeshLoader(options);
            %   @endcode

            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % function [imginfo, files] = loadMetadata(obj, filenames, options)
            % Load metadata for Amira Mesh files
            %
            % This method reads the Amira Mesh header and populates:
            %   - files structure array (dimensions, class, binning options)
            %   - imginfo dictionary (format metadata)
            %   - pixSize structure (voxel sizes)
            %
            % Parameters:
            %   filenames: cell array with filenames of Amira Mesh files
            %   options: [@em struct] options for metadata loading
            %     @li .waitbar - [logical] show or not the waitbar
            %     @li .customSections - [logical] load part of the dataset
            %     @li .Font - [struct] font settings for dialogs
            %     @li .parentGUI - parent figure handle for uiprogressdlg
            %
            % Return values:
            %   imginfo: dictionary with image metadata, including pixSize structure
            %   files: structure array with file information
            %
            % Example:
            %   @code
            %   loader = io.loaders.AmiraMeshLoader();
            %   filenames = {'dataset.am'};
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
                    'Message', sprintf('Loading AmiraMesh metadata\n(press Cancel when metadata is the same for all files)'), ...
                    'Cancelable', 'on');
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', [], ...
                'dim_xyczt', [], ...
                'depth_start', [], 'depth_end', [], 'depth_step', [], 'xy_step', [], 'resizeMethod', []);

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    imginfo = dictionary();
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error in io.loaders.AmiraMeshLoader!\n\nThe required file\n%s\nwas not found!', filenames{fnIndex}), ...
                        'Wrong filename', 'Error in io.loaders.AmiraMeshLoader');
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
                files(fnIndex).objecttype = 'amiramesh';

                % Read header
                try
                    [par, info, dim_xyczt] = io.AmiraMesh.getAmiraMeshHeader(files(fnIndex).filename);
                catch err
                    imginfo = dictionary();
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error reading Amira Mesh header:\n%s', err.message), 'Amira Mesh Error', 'Error in io.loaders.AmiraMeshLoader');
                    return;
                end

                if isempty(par)
                    imginfo = dictionary();
                    if options.waitbar; delete(wb); end
                    return;
                end

                % Consistency check for color type
                if fnIndex == 1
                    if isKey(info, 'ColorType')
                        imginfo{'ColorType'} = info('ColorType');
                    end
                else
                    if isKey(info, 'ColorType') && ~strcmp(imginfo{'ColorType'}, info('ColorType'))
                        imginfo = dictionary();
                        if options.waitbar; delete(wb); end
                        utils.dlgs.showErrorDialog(options.parentGUI, 'Files have dissimilar ColorType', 'Mixed colors', 'Error in io.loaders.AmiraMeshLoader');
                        return;
                    end
                end

                % Update LUT colors (optional)
                if isKey(info, 'Channel1Color')
                    lutColors = zeros(dim_xyczt(3), 3);
                    for colId = 1:dim_xyczt(3)
                        colChName = sprintf('Channel%dColor', colId);
                        if isKey(info, colChName)
                            tmp = str2num(info(colChName)); %#ok<ST2NM>
                            if numel(tmp) == 3
                                lutColors(colId, :) = tmp;
                            end
                        end
                    end
                    if isKey(imginfo, 'lutColors')
                        lutColorsExisting = imginfo{'lutColors'};
                        lutColorsExisting(1:size(lutColorsExisting, 1), :) = lutColorsExisting;
                        imginfo{'lutColors'} = [lutColorsExisting; lutColors];
                    else
                        imginfo{'lutColors'} = lutColors;
                    end
                end

                % Custom sections for Amira Mesh (binning + partial Z)
                if options.customSections
                    % start dialog to import part of Amira mesh dataset
                    controller = utils.dlgs.AmiraImportDlg(dim_xyczt, options.parentGUI, options.Font);
                    result = controller.run();
                    
                    if ~isstruct(result)
                        imginfo = dictionary();
                        if options.waitbar; delete(wb); end
                        return;
                    end

                    files(fnIndex).noLayers = numel(result.startIndex:result.zstep:result.endIndex);
                    files(fnIndex).depth_start = result.startIndex;
                    files(fnIndex).depth_end = result.endIndex;
                    if files(fnIndex).noLayers == 1
                        files(fnIndex).depth_step = 1;
                    else
                        files(fnIndex).depth_step = result.zstep;
                    end
                    files(fnIndex).xy_step = result.xy_step;
                    files(fnIndex).resizeMethod = result.method;
                    files(fnIndex).height = floor(dim_xyczt(2) / result.xy_step);
                    files(fnIndex).width = floor(dim_xyczt(1) / result.xy_step);
                else
                    files(fnIndex).noLayers = dim_xyczt(4);
                    files(fnIndex).height = dim_xyczt(2);
                    files(fnIndex).width = dim_xyczt(1);
                end

                files(fnIndex).color = dim_xyczt(3);
                files(fnIndex).time = 1;
                files(fnIndex).dim_xyczt = dim_xyczt;

                % Image class
                if isKey(info, 'imgClass')
                    files(fnIndex).imgClass = info('imgClass');
                else
                    files(fnIndex).imgClass = 'uint8';
                end

                % Update pixel size only for the first file
                if fnIndex == 1
                    bbStart = strfind(info('ImageDescription'), 'BoundingBox');
                    if ~isempty(bbStart)
                        info('ImageDescription') = strrep(info('ImageDescription'), sprintf('\t'), '|');    % replace tabs (from old MIB versions) with |
                        brakePnt = strfind(info('ImageDescription'), '|');
                        if isempty(brakePnt); brakePnt = numel(info('ImageDescription'))+1; end
                        try
                            brakePnt = brakePnt(1);
                            bbString = info('ImageDescription');
                            bb_coord = str2num(bbString(bbStart+11:brakePnt-1)); %#ok<ST2NM>
                            dx = bb_coord(2)-bb_coord(1);
                            dy = bb_coord(4)-bb_coord(3);
                            dz = bb_coord(6)-bb_coord(5);
                        catch err
                            dx = max([files(fn_index).width 2])-1;
                            dy = max([files(fn_index).height 2])-1;
                            dz = max([files(fn_index).noLayers 2])-1;
                        end
                    end

                    pixSize.x = dx/(max([files(fnIndex).width 2])-1);  % tweek for saving single layered tifs for Amira
                    pixSize.y = dy/(max([files(fnIndex).height 2])-1);
                    pixSize.z = dz/(max([files(fnIndex).noLayers 2])-1);
                    if pixSize.z == 0; pixSize.z = min([pixSize.x pixSize.y]); end
                    pixSize.units = 'um';
    
                    % update img_info
                    info('Filename') = files(fnIndex).filename;
                    fields = sort(keys(info));
                    for ind = 1:numel(fields)
                        if ~strcmp(fields{ind}, 'lutColors')
                            imginfo{fields{ind}} = info(fields{ind});
                        else
                            if ischar(info(fields{ind}))
                                imginfo{fields{ind}} = str2num(info(fields{ind})); %#ok<ST2NM>
                            end
                        end
                    end
                end

                % update pixSize
                imginfo{"pixSize"} = pixSize;

                % Update waitbar
                if options.waitbar
                    if mod(fnIndex, ceil(noFiles/50)) == 0
                        wb.Value = fnIndex / noFiles;
                    end
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
            % Load image data from Amira Mesh files
            %
            % This method calls amiraMesh2bitmap() and stores the returned data
            % into the MIB image array.
            %
            % Parameters:
            %   files: structure array from loadMetadata
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
            %   options: [@em struct] options for image loading
            %
            % Return values:
            %   img: loaded image dataset
            %   imginfo: updated dictionary
            %
            % Example:
            %   @code
            %   loader = io.loaders.AmiraMeshLoader();
            %   [imginfo, files] = loader.loadMetadata({'dataset.am'}, options);
            %   [img, imginfo] = loader.loadImages(files, imginfo, options);
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

            % Pre-allocate image array: [Y, X, C, Z, T]
            img = zeros(height, width, maxZ, color, time, imgClass);

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            layerId = 1;
            noFiles = numel(files);

            % Initialize uiprogressdlg
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Loading Amira Mesh images...',...
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

                % Pass waitbar handle to amiraMesh2bitmap
                if options.waitbar
                    options.hWaitbar = wb;
                    options.maxZ = maxZ;
                else
                    options.hWaitbar = NaN;
                end

                % Send custom Amira options
                if isfield(files(fnIndex), 'depth_start') && ~isempty(files(fnIndex).depth_start)
                    options.depth_start = files(fnIndex).depth_start;
                    options.depth_end = files(fnIndex).depth_end;
                    options.depth_step = files(fnIndex).depth_step;
                    options.xy_step = files(fnIndex).xy_step;
                    options.resizeMethod = files(fnIndex).resizeMethod;
                else
                    if isfield(options, 'depth_start'); options = rmfield(options, 'depth_start'); end
                    if isfield(options, 'depth_end'); options = rmfield(options, 'depth_end'); end
                    if isfield(options, 'depth_step'); options = rmfield(options, 'depth_step'); end
                    if isfield(options, 'xy_step'); options = rmfield(options, 'xy_step'); end
                    if isfield(options, 'resizeMethod'); options = rmfield(options, 'resizeMethod'); end
                end

                % Load image
                try
                    imgIn = io.AmiraMesh.amiraMesh2bitmap(files(fnIndex).filename, options);
                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error loading Amira Mesh file:\n%s', err.message), 'Amira Mesh Error', 'Error in io.loaders.AmiraMeshLoader');
                    img = [];
                    return;
                end

                img(1:maxY, 1:maxX, layerId:layerId+files(fnIndex).noLayers-1, 1:maxC, 1) = ...
                    imgIn(1:maxY, 1:maxX, 1:files(fnIndex).noLayers, 1:maxC);

                % Fix BoundingBox info for Amira Mesh binned dataset (legacy behavior)
                if isfield(options, 'depth_start') && isKey(imginfo, 'ImageDescription')
                    currtext = imginfo{'ImageDescription'};
                    bbinfoexist = strfind(currtext, 'BoundingBox');
                    if ~isempty(bbinfoexist)
                        % Extract BoundingBox numbers
                        startIdx = bbinfoexist(1) + 11;
                        stopIdx = regexp(currtext(startIdx:end), '[\t\r\n]', 'once');
                        if isempty(stopIdx)
                            stopIdx = numel(currtext) - startIdx + 2;
                        end
                        stopIdx = startIdx + stopIdx - 2;

                        bb = str2num(currtext(startIdx:stopIdx)); %#ok<ST2NM>
                        if numel(bb) >= 6
                            % BoundingBox: [xmin xmax ymin ymax zmin zmax]
                            zmin = bb(5);
                            zmax = bb(6);
                            fullZ = files(fnIndex).dim_xyczt(4);

                            startZShift = (options.depth_start - 1) / fullZ * (zmax - zmin);
                            endZShift = startZShift + options.depth_step / fullZ * (zmax - zmin) * (max([files(fnIndex).noLayers 2]) - 1);

                            bb(6) = zmin + endZShift;
                            bb(5) = zmin + startZShift;

                            newBB = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f', ...
                                bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));

                            imginfo{'ImageDescription'} = [currtext(1:bbinfoexist(1)-1) newBB currtext(stopIdx+1:end)];
                        end
                    end
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
