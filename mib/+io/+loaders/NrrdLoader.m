classdef NrrdLoader < io.loaders.BaseImageLoader
% NRRDLOADER - Loader for NRRD (Nearly Raw Raster Data) files, based on.
%
% io.loaders.BaseImageLoader base class

    % This loader handles NRRD files (.nrrd, .nhdr).
    % It supports:
    %   - Standard NRRD files
    %   - Detached headers (.nhdr)
    %   - Metadata parsing (voxel sizes, space directions)
    %   - Automatic dimension permutation for MIB compatibility

    methods
        function obj = NrrdLoader(options)
            % NRRDLOADER - Constructor for NrrdLoader class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.NrrdLoader(options)
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
            %   - **obj** — instance of the NrrdLoader class
            %
            % **Example 1** — create loader with options:
            %
            %   .. code-block:: matlab
            %
            %      options.waitbar = true;
            %      loader = io.loaders.NrrdLoader(options);
            %

            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
            obj.initBaseProps(options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - Load metadata for NRRD files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [imginfo, files] = obj.loadMetadata(filenames, options)
            %
            % This method parses NRRD headers to extract dataset metadata.
            % It handles voxel sizes, space directions, and dimension ordering.
            %
            % Input Arguments:
            %   - **filenames** — cell array with filenames of NRRD files
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
            % **Example 1** — load metadata from NRRD file:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.NrrdLoader();
            %      filenames = {'dataset.nrrd'};
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
            wb = [];
            if options.waitbar
                wb = obj.createProgressDialog('Metadata import', ...
                    sprintf('Loading NRRD metadata\n(press Cancel when metadata is the same for all files)'), true);
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', [], ...
                'dim_xyczt', [], 'seriesName', [], 'transMatrix', []);

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.NrrdLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.NrrdLoader');
                    imginfo = dictionary();
                    return;
                end

                % Check for cancel button
                if ~isempty(wb) && wb.CancelRequested
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
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        'Files have dissimilar ColorType', 'Mixed colors', 'Error in io.loaders.NrrdLoader');
                    imginfo = dictionary();
                    return;
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

            % Set number of entries (required by MibDataset.loadModel)
            imginfo{"numEntries"} = noFiles;

            % Generate slice names
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if ~isempty(wb); delete(wb); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % LOADIMAGES - Load image data from NRRD files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.loadImages(files, imginfo, options)
            %
            % This method loads actual image data.
            % It uses ``nrrdLoadWithMetadata`` (Linux/Win) or ``nhdr_nrrd_read`` (Mac)
            % and handles dimension permutation.
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
            % **Example 1** — load images from NRRD file:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.NrrdLoader();
            %      [imginfo, files] = loader.loadMetadata({'dataset.nrrd'}, options);
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
            wb = [];
            if options.waitbar
                wb = obj.createProgressDialog('Loading NRRD images...', ...
                    sprintf('Please wait...'), true);
            end

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
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
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
                if ~isempty(wb)
                    if mod(layerId, waitbarUpdateFrequency) == 0
                        wb.Value = layerId / maxZ;
                    end
                end
                layerId = layerId + files(fnIndex).noLayers;
            end

            if ~isempty(wb); delete(wb); end

            % Finalize
            imginfo{'Height'} = height;
            imginfo{'Width'} = width;
            imginfo{'Depth'} = maxZ;
            imginfo{'Time'} = time;

            [img, imginfo] = obj.finalizeImageLoading(img, imginfo, options);
        end
    end
end
