classdef NrrdLoader < io.loaders.BaseImageLoader
    % classdef NrrdLoader
    % Loader for NRRD (Nearly Raw Raster Data) files, based on
    % io.loaders.BaseImageLoader base class

    % This loader handles NRRD files (.nrrd, .nhdr).
    % It supports:
    %   - Standard NRRD files
    %   - Detached headers (.nhdr)
    %   - Metadata parsing (voxel sizes, space directions)
    %   - Automatic dimension permutation for MIB compatibility

    methods
        function obj = NrrdLoader(options)
            % function obj = NrrdLoader(options)
            % Constructor for NrrdLoader class

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
            %     @li .parentFigure - handle of the main MIB window to be a parent for uiprogressdlg

            % Return values:
            %   obj: instance of the NrrdLoader class

            % Example:
            %   @code
            %   options.waitbar = true;
            %   loader = io.loaders.NrrdLoader(options);
            %   @endcode

            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % function [imginfo, files] = loadMetadata(obj, filenames, options)
            % Load metadata for NRRD files

            % This method parses NRRD headers to extract dataset metadata.
            % It handles voxel sizes, space directions, and dimension ordering.

            % Parameters:
            %   filenames: cell array with filenames of NRRD files
            %   options: [@em struct] options for metadata loading
            %     @li .waitbar - [logical] show or not the waitbar
            %     @li .customSections - [logical] load part of the dataset
            %     @li .Font - [struct] font settings for dialogs

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
            
            % Example:
            %   @code
            %   loader = io.loaders.NrrdLoader();
            %   filenames = {'dataset.nrrd'};
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
                wb = uiprogressdlg(options.parentFigure, 'Title', 'Metadata import',...
                    'Message', sprintf('Loading NRRD metadata\n(press Cancel when metadata is the same for all files)'), ...
                    'Cancelable', 'on');
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', [], ...
                'dim_xyczt', [], 'seriesName', [], 'transMatrix', []);

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentFigure, ...
                        sprintf('Error in io.loaders.NrrdLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.NrrdLoader');
                    imginfo = dictionary();
                    return;
                end

                % Check for cancel button
                if options.waitbar && wb.CancelRequested
                    % Use metadata from first file for all remaining files
                    files(fnIndex:noFiles) = files(1);
                    [files.filename] = filenames{:};
                    fnIndex = noFiles;
                    continue;
                end

                % Extract file parts
                [~, ~, ext] = fileparts(filenames{fnIndex});
                ext = lower(ext);
                files(fnIndex).extension = ext;
                files(fnIndex).filename = cell2mat(filenames(fnIndex));
                files(fnIndex).objecttype = 'nrrd';

                % Read NRRD metadata using existing helpers
                [meta, datatype] = get_nrrd_metadata(files(fnIndex).filename);
                dims = str2num(meta.sizes); %#ok<ST2NM>

                % Handle dimension ordering
                % NRRD usually stores as [X Y Z] or [C X Y Z]
                if str2double(meta.dimension) == 4
                    % Color image or stack [C X Y Z]
                    files(fnIndex).dim_xyczt = [dims(2), dims(3), dims(1), dims(4), 1];
                    currentColorType = 'multichannel';
                else
                    % Grayscale image or stack [X Y Z]
                    files(fnIndex).dim_xyczt = [dims(1), dims(2), 1, dims(3), 1];
                    currentColorType = 'grayscale';
                end

                % Populate file structure
                files(fnIndex).noLayers = files(fnIndex).dim_xyczt(4);
                files(fnIndex).height = files(fnIndex).dim_xyczt(2);
                files(fnIndex).width = files(fnIndex).dim_xyczt(1);
                files(fnIndex).color = files(fnIndex).dim_xyczt(3);
                files(fnIndex).time = 1;
                files(fnIndex).imgClass = datatype;

                % Parse Metadata for First File
                if fnIndex == 1
                    imginfo{"imgClass"} = datatype;
                    imginfo{"ColorType"} = currentColorType;

                    % Pixel Sizes from 'spacedirections'
                    if isfield(meta, 'spacedirections')
                        % Parse space directions: "(x,y,z) (x,y,z) ..."
                        openBr = strfind(meta.spacedirections, '(');
                        closeBr = strfind(meta.spacedirections, ')');

                        if numel(openBr) >= 3
                             voxX = str2num(meta.spacedirections(openBr(1)+1:closeBr(1)-1)); %#ok<ST2NM>
                             voxY = str2num(meta.spacedirections(openBr(2)+1:closeBr(2)-1)); %#ok<ST2NM>
                             voxZ = str2num(meta.spacedirections(openBr(3)+1:closeBr(3)-1)); %#ok<ST2NM>

                             pixSize.x = voxX(1);
                             pixSize.y = voxY(2);
                             pixSize.z = voxZ(3);
                        end
                    end

                    % Bounding Box / Origin
                    if isfield(meta, 'spaceorigin')
                         shiftsXYZ = str2num(meta.spaceorigin(2:end-1)); %#ok<ST2NM>
                         if numel(shiftsXYZ) < 3; shiftsXYZ = [0 0 0]; end

                         % Fix sign conventions (often needed for NRRD->MIB)
                         shiftsXYZ(1) = -shiftsXYZ(1);
                         shiftsXYZ(2) = -shiftsXYZ(2);

                         % Construct ImageDescription
                         labelOut = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f', ...
                             shiftsXYZ(1), shiftsXYZ(1) + pixSize.y * (max([1 files(fnIndex).dim_xyczt(1)])-1), ...
                             shiftsXYZ(2), shiftsXYZ(2) + pixSize.x * (max([1 files(fnIndex).dim_xyczt(2)])-1), ...
                             shiftsXYZ(3), shiftsXYZ(3) + pixSize.z * (max([1 files(fnIndex).dim_xyczt(4)])-1));

                         imginfo{"ImageDescription"} = labelOut;
                    else
                         shiftsXYZ = [0 0 0];
                    end
                elseif ~strcmp(imginfo{"ColorType"}, currentColorType)
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentFigure, ...
                        'Files have dissimilar ColorType', 'Mixed colors', 'Error in io.loaders.NrrdLoader');
                    imginfo = dictionary();
                    return;
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

            % Generate slice names
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if options.waitbar; delete(wb); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % Load image data from NRRD files

            % This method loads actual image data.
            % It uses nrrdLoadWithMetadata (Linux/Win) or nhdr_nrrd_read (Mac)
            % and handles dimension permutation.

            % Parameters:
            %   files: structure array from loadMetadata
            %   imginfo: dictionary from loadMetadata
            %   options: [@em struct] options for image loading

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

            if maxZ == 0; return; end

            % Prepare image class
            imgClass = files(1).imgClass;
            if strcmp(imgClass, 'int16'); imgClass = 'uint16'; end

            % Pre-allocate image array
            % MIB structure: [Height, Width, Depth, Color, Time]
            % Wait, getImages.m allocates: [height, width, color, maxZ, time]
            % Let's stick to MIB Standard Allocation used in getImages.m
            img = zeros(height, width, maxZ, color, time, imgClass);

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            % Initialize layer counter
            layerId = 1;
            noFiles = numel(files);

            % Initialize uiprogressdlg
            if options.waitbar
                wb = uiprogressdlg(options.parentFigure, 'Title', 'Loading NRRD images...',...
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

                % Calculate dimensions for this file
                maxY = min(height, files(fnIndex).height);
                maxX = min(width, files(fnIndex).width);
                maxC = min(color, files(fnIndex).color);

                % Read NRRD
                try
                    if ~ismac
                        % Windows/Linux, faster
                        I = nrrdLoadWithMetadata(files(fnIndex).filename);
                    else
                        % Mac, slower
                        I = nhdr_nrrd_read(files(fnIndex).filename, 1);
                    end
                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentFigure, ...
                        sprintf('Error loading NRRD file:\n%s', err.message), 'NRRD Error', 'Error in io.loaders.NrrdLoader');
                    img = [];
                    return;
                end

                % Permute dimensions to match MIB [Y, X, Z, C, T]
                if files(fnIndex).dim_xyczt(3) == 1 
                    % Grayscale stack [X, Y, Z] -> [Y, X, Z]
                    I.data = permute(I.data, [2 1 3]);
                else
                    % Color stack [C, X, Y, Z] -> [Y, X, Z, C]
                    I.data = permute(I.data, [3 2 4 1]);
                end

                img(1:maxY,1:maxX, layerId:layerId+files(fnIndex).noLayers-1, 1:maxC) = I.data;

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