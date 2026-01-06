classdef BioFormatsStdLoader < io.loaders.BaseImageLoader
    % classdef BioFormatsStdLoader
    % Loader for microscopy files using Bio-Formats, based on
    % io.loaders.BaseImageLoader base class
    %
    % This loader handles a wide variety of microscopy file formats via the
    % Bio-Formats library. It supports:
    %   - Standard loading of multi-series datasets
    %   - Metadata extraction (pixel sizes, channels, time points)
    %   - Custom region loading (cropping)
    %   - Memoization for faster metadata access via loci.formats.Memoizer

    methods
        function obj = BioFormatsStdLoader(options)
            % function obj = BioFormatsStdLoader(options)
            % Constructor for BioFormatsStdLoader class
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
            %     @li .BioFormatsMemoizerMemoDir - [char] path to memo directory
            %     @li .BioFormatsIndices - [numeric] specific series indices to load (0 for all)
            %
            % Return values:
            %   obj: instance of the BioFormatsStdLoader class
            %
            % Example:
            %   @code
            %   options.waitbar = true;
            %   options.BioFormatsMemoizerMemoDir = 'c:\temp';
            %   loader = io.loaders.BioFormatsStdLoader(options);
            %   @endcode

            % default Options settings
            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
        end

        function [imginfo, files, pixSize] = loadMetadata(obj, filenames, options)
            % function [imginfo, files, pixSize] = loadMetadata(obj, filenames, options)
            % Load metadata for files using Bio-Formats
            %
            % This method uses loci.formats.Memoizer with bfGetReader to extract
            % metadata efficiently. It handles multi-series selection, pixel size
            % extraction from OME metadata, and sets up the file structure for loading.
            %
            % Parameters:
            %   filenames: cell array with filenames
            %   options: [@em struct] options for metadata loading
            %     @li .waitbar - [logical] show or not the waitbar
            %     @li .customSections - [logical] load part of the dataset
            %     @li .Font - [struct] font settings for dialogs
            %     @li .BioFormatsIndices - [numeric] specific series to load (0 for all)
            %     @li .BioFormatsMemoizerMemoDir - [char] memo directory path
            %
            % Return values:
            %   imginfo: dictionary with image metadata
            %   files: structure array with file information
            %   pixSize: structure with voxel dimensions
            %
            % Example:
            %   @code
            %   loader = io.loaders.BioFormatsStdLoader();
            %   filenames = {'image.czi'};
            %   [imginfo, files, pixSize] = loader.loadMetadata(filenames, options);
            %   @endcode

            % Merge constructor options with runtime options
            if nargin < 3; options = obj.Options; end
            options = obj.mergeOptions(obj.Options, options);

            % init imginfo dictionary with the default set of keys
            imginfo = obj.initializeImgInfo();

            % Initialize default options
            if ~isfield(options, 'waitbar'); options.waitbar = false; end
            if ~isfield(options, 'customSections'); options.customSections = false; end
            if ~isfield(options, 'BioFormatsMemoizerMemoDir'); options.BioFormatsMemoizerMemoDir = 'c:\temp'; end
            if ~isfield(options, 'BioFormatsIndices'); options.BioFormatsIndices = 0; end

            % init the pixel size as pixSize structure
            pixSize = obj.initializePixSize();

            noFiles = numel(filenames);

            % Initialize waitbar if requested
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Metadata import',...
                    'Message', sprintf('Loading Bio-Formats metadata\nPlease wait...'), ...
                    'Cancelable', 'off');
            end

            % Pre-allocate files structure array
            % We use layerId to track individual series as separate "files"
            layerId = 1;
            filesTemp(noFiles) = struct();

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error in io.loaders.BioFormatsStdLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists');
                    imginfo = dictionary();
                    return;
                end

                % Extract file parts
                [dirId, fnId, ext] = fileparts(filenames{fnIndex});
                ext = lower(ext);

                % Initialize Bio-Formats reader with Memoizer
                try
                    if fnIndex == 1
                        % Cache the initialized readers for each file and close the reader
                        try
                            % Disable Bio-Formats debug logging
                            % Logging levels (from most to least verbose):
                            % 'ALL' - Everything
                            % 'DEBUG' - Debug messages (default, very verbose)
                            % 'INFO' - Informational messages
                            % 'WARN' - Warnings only
                            % 'ERROR' - Errors only
                            % 'FATAL' - Fatal errors only
                            % 'OFF' - No logging
                            loci.common.DebugTools.setRootLevel('WARN');

                            filesTemp.hDataset = loci.formats.Memoizer(bfGetReader(), 0, java.io.File(options.BioFormatsMemoizerMemoDir));
                            filesTemp.hDataset.setId(filenames{fnIndex});
                            numSeries = filesTemp.hDataset.getSeriesCount();
                        catch err
                            if options.waitbar==1; delete(wb); end
                            utils.dlgs.showErrorDialog(options.parentGUI, ...
                                sprintf('Error in io.loaders.BioFormatsStdLoader!\n\nMemoizer can not be initialized for :\n%s', filenames{fnIndex}), ...
                                'BioFormats memoizer');
                            imginfo = dictionary();
                            return;
                        end

                        % Series selection
                        if numSeries > 1
                            if isfield(options, 'BioFormatsIndices') && ~isempty(options.BioFormatsIndices) && options.BioFormatsIndices ~= 0
                                % Use provided indices
                                filesTemp(fnIndex).seriesIndex = options.BioFormatsIndices;
                                metaSwitch = 1;
                                filesTemp(fnIndex).dimxyczt = zeros(numel(filesTemp(fnIndex).seriesIndex), 5);
                                filesTemp(fnIndex).seriesRealName = cell(numel(filesTemp(fnIndex).seriesIndex), 1);

                                for i = 1:numel(filesTemp(fnIndex).seriesIndex)
                                    filesTemp(fnIndex).hDataset.setSeries(filesTemp(fnIndex).seriesIndex(i) - 1);
                                    filesTemp(fnIndex).dimxyczt(i, 1) = filesTemp(fnIndex).hDataset.getSizeX();
                                    filesTemp(fnIndex).dimxyczt(i, 2) = filesTemp(fnIndex).hDataset.getSizeY();
                                    filesTemp(fnIndex).dimxyczt(i, 3) = filesTemp(fnIndex).hDataset.getSizeC();
                                    filesTemp(fnIndex).dimxyczt(i, 4) = filesTemp(fnIndex).hDataset.getSizeZ();
                                    filesTemp(fnIndex).dimxyczt(i, 5) = filesTemp(fnIndex).hDataset.getSizeT();
                                    filesTemp(fnIndex).seriesRealName{i} = char(filesTemp(fnIndex).hDataset.getMetadataStore().getImageName(i-1));
                                end
                            else
                                % User selection via selectLociSeries
                                controller = utils.dlgs.SelectLociSeriesDlg( ...
                                    filenames{fnIndex}, filesTemp(fnIndex).hDataset, options.Font, options.parentGUI);
                                [filesTemp(fnIndex).seriesIndex, filesTemp(fnIndex).hDataset, metaSwitch, ...
                                    filesTemp(fnIndex).dimxyczt, filesTemp(fnIndex).seriesRealName] = controller.run();
                                
                                if strcmp(filesTemp(fnIndex).seriesIndex, 'Cancel')
                                    if options.waitbar==1; delete(wb); end
                                    files = struct;
                                    imginfo = dictionary();
                                    return;
                                end
                            end
                        else
                            % Single series - no selection needed
                            filesTemp(fnIndex).seriesIndex = 1;
                            filesTemp(fnIndex).hDataset.setSeries(filesTemp(fnIndex).seriesIndex - 1);
                            metaSwitch = 1;
                            filesTemp(fnIndex).dimxyczt(1, 1) = filesTemp(fnIndex).hDataset.getSizeX();
                            filesTemp(fnIndex).dimxyczt(1, 2) = filesTemp(fnIndex).hDataset.getSizeY();
                            filesTemp(fnIndex).dimxyczt(1, 3) = filesTemp(fnIndex).hDataset.getSizeC();
                            filesTemp(fnIndex).dimxyczt(1, 4) = filesTemp(fnIndex).hDataset.getSizeZ();
                            filesTemp(fnIndex).dimxyczt(1, 5) = filesTemp(fnIndex).hDataset.getSizeT();
                            filesTemp(fnIndex).seriesRealName{1} = char(filesTemp(fnIndex).hDataset.getMetadataStore().getImageName(0));
                        end
                    end
                   

                    % Get OME metadata
                    omeMeta = filesTemp(fnIndex).hDataset.getMetadataStore();

                    % Get dimension order
                    filesTemp(fnIndex).DimensionOrder = char(filesTemp(fnIndex).hDataset.getDimensionOrder());

                    % Check if selection was cancelled
                    if strcmp(filesTemp(fnIndex).seriesIndex, 'Cancel')
                        if options.waitbar; delete(wb); end
                        imginfo = dictionary();
                        return;
                    end

                    if isfloat(filesTemp(fnIndex).seriesIndex)
                        % Close readers on error
                        if ~isempty(filesTemp(fnIndex).hDataset)
                            filesTemp(fnIndex).hDataset.close();
                        end
                        if options.waitbar; delete(wb); end
                        imginfo = dictionary();
                        return;
                    end

                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error reading Bio-Formats metadata:\n%s', err.message), 'Bio-Formats Error');
                    imginfo = dictionary();
                    return;
                end

                % Create individual file entries for each selected series
                for fileSubIndex = 1:numel(filesTemp(fnIndex).seriesIndex)
                    files(layerId).filename = cell2mat(filenames(fnIndex));
                    files(layerId).origFilename = files(layerId).filename;
                    files(layerId).objecttype = 'bioformats';
                    files(layerId).extension = ext;
                    files(layerId).seriesName = filesTemp(fnIndex).seriesIndex(fileSubIndex);
                    files(layerId).dimxyczt = filesTemp(fnIndex).dimxyczt;
                    files(layerId).DimensionOrder = filesTemp(fnIndex).DimensionOrder;
                    files(layerId).BioFormatsMemoizerMemoDir = options.BioFormatsMemoizerMemoDir;
                    files(layerId).seriesRealName = filesTemp(fnIndex).seriesRealName{fileSubIndex};

                    % Dimensions
                    files(layerId).height = filesTemp(fnIndex).dimxyczt(fileSubIndex, 2);
                    files(layerId).width = filesTemp(fnIndex).dimxyczt(fileSubIndex, 1);

                    % Handle Z and T dimensions
                    if filesTemp(fnIndex).dimxyczt(fileSubIndex, 4) == 1 && filesTemp(fnIndex).dimxyczt(fileSubIndex, 5) > 1
                        files(layerId).noLayers = max([filesTemp(fnIndex).dimxyczt(fileSubIndex, 4), filesTemp(fnIndex).dimxyczt(fileSubIndex, 5)]);
                        files(layerId).time = 1;
                    else
                        files(layerId).noLayers = filesTemp(fnIndex).dimxyczt(fileSubIndex, 4);
                        files(layerId).time = filesTemp(fnIndex).dimxyczt(fileSubIndex, 5);
                    end

                    files(layerId).color = filesTemp(fnIndex).dimxyczt(fileSubIndex, 3);

                    % Image class
                    bpp = filesTemp(fnIndex).hDataset.getBitsPerPixel();
                    if bpp == 8
                        files(layerId).imgClass = 'uint8';
                    elseif bpp == 16
                        files(layerId).imgClass = 'uint16';
                    elseif bpp == 32
                        files(layerId).imgClass = 'uint32';
                    else
                        files(layerId).imgClass = 'double';
                    end

                    % Update filename for multi-series
                    [path, name, ext] = fileparts(files(layerId).filename);
                    if numel(filesTemp(fnIndex).seriesIndex) > 1
                        files(layerId).filename = fullfile(path, [name, files(layerId).seriesRealName, ext]);
                    end

                    layerId = layerId + 1;
                end

                % Close reader
                filesTemp(fnIndex).hDataset.close();

                % Update pixel size from OME (first file/series only)
                if fnIndex == 1
                    try
                        xVal = double(omeMeta.getPixelsPhysicalSizeX(filesTemp(fnIndex).seriesIndex(1)-1).value(ome.units.UNITS.MICROMETER));
                        if ~isempty(xVal)
                            pixSize.x = xVal;
                            pixSize.y = double(omeMeta.getPixelsPhysicalSizeY(filesTemp(fnIndex).seriesIndex(1)-1).value(ome.units.UNITS.MICROMETER));
                        end

                        zVal = omeMeta.getPixelsPhysicalSizeZ(filesTemp(fnIndex).seriesIndex(1)-1);
                        if ~isempty(zVal)
                            pixSize.z = double(zVal.value(ome.units.UNITS.MICROMETER));
                        else
                            pixSize.z = pixSize.y;
                        end

                        tVal = omeMeta.getPixelsTimeIncrement(filesTemp(fnIndex).seriesIndex(1)-1);
                        if ~isempty(tVal) && double(tVal.value()) ~= 0
                            pixSize.t = double(tVal.value());
                        end
                    catch
                        % Use defaults
                    end
                end

                % Update waitbar
                if options.waitbar
                    if mod(fnIndex, ceil(noFiles/50)) == 0
                        wb.Value = fnIndex/noFiles;
                    end
                end
            end

            % Set metadata for first file
            if ~isempty(files)
                imginfo{'imgClass'} = files(1).imgClass;
                if files(1).color > 1
                    imginfo{'ColorType'} = 'truecolor';
                else
                    imginfo{'ColorType'} = 'grayscale';
                end
            end

            % Handle custom sections
            if options.customSections
                [files, imginfo, pixSize, cancelled] = obj.handleCustomSections(files, imginfo, pixSize, options);
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
            % Load image data using Bio-Formats
            %
            % This method uses bfopen4 (MIB wrapper around bfopen) to load images.
            % It supports loading multiple series and concatenating them along Z.
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
            % For Bio-Formats, each series is a separate file entry
            if isfield(files, 'zMin')
                maxZ = sum([files.zMax] - [files.zMin] + 1);
            else
                maxZ = sum([files.noLayers]);
            end

            if maxZ == 0; return; end

            % Prepare image class
            imgClass = files(1).imgClass;
            if strcmp(imgClass, 'int16'); imgClass = 'uint16'; end

            % Pre-allocate image array: [Y, X, C, Z, T]
            img = zeros(height, width, color, maxZ, time, imgClass);

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            layerId = 1;
            noFiles = numel(files);

            % Initialize waitbar
            if options.waitbar
                wb = waitbar(0, sprintf('Loading images\nPlease wait...'), 'Name', 'Loading images...', ...
                    'CreateCancelBtn','setappdata(gcbf, ''canceling'', 1)');
            end

            for fnIndex = 1:noFiles
                % Check for cancel button
                if options.waitbar && getappdata(wb, 'canceling')
                    delete(wb);
                    img = [];
                    imginfo = dictionary();
                    return;
                end

                maxY = min(height, files(fnIndex).height);
                maxX = min(width, files(fnIndex).width);
                maxC = min(color, files(fnIndex).color);
                maxT = min(time, files(fnIndex).time);

                % Setup options for bfopen4
                bfopenOptions = struct();
                bfopenOptions.BioFormatsMemoizerMemoDir = files(fnIndex).BioFormatsMemoizerMemoDir;
                if options.waitbar
                    bfopenOptions.waitbarHandle = wb;
                    bfopenOptions.waitbarUpdateFrequency = waitbarUpdateFrequency;
                end
                if isfield(files(fnIndex), 'DimensionOrder')
                    bfopenOptions.DimensionOrder = files(fnIndex).DimensionOrder;
                end

                % Custom sections
                if isfield(files, 'xMin')
                    bfopenOptions.x1 = files(1).xMin;
                    bfopenOptions.y1 = files(1).yMin;
                    bfopenOptions.z1 = files(1).zMin;
                    bfopenOptions.dx = files(1).xMax - files(1).xMin + 1;
                    bfopenOptions.dy = files(1).yMax - files(1).yMin + 1;
                    bfopenOptions.dz = files(1).zMax - files(1).zMin + 1;
                end

                % Load data using bfopen4
                try
                    I = bfopen4(files(fnIndex).origFilename, files(fnIndex).seriesName, NaN, bfopenOptions);

                    if isempty(I)
                        img = [];
                        return;
                    end

                    % Assign data (I.img is [Y, X, C, Z, T])
                    for subLayer = 1:files(fnIndex).noLayers
                        img(1:maxY, 1:maxX, 1:maxC, layerId, 1:maxT) = I.img(1:maxY, 1:maxX, 1:maxC, subLayer, 1:maxT);

                        % Update metadata from first load
                        if fnIndex == 1 && subLayer == 1
                            if isfield(I, 'ColorType'); imginfo{'ColorType'} = I.ColorType; end
                            if isfield(I, 'ColorMap'); imginfo{'ColorMap'} = I.ColorMap; end
                        end

                        layerId = layerId + 1;

                        % Update waitbar
                        if options.waitbar && mod(layerId, waitbarUpdateFrequency) == 0
                            if getappdata(wb, 'canceling')
                                img = [];
                                delete(wb);
                                return;
                            end
                            waitbar(layerId/maxZ, wb);
                        end
                    end

                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error loading Bio-Formats file:\n%s', err.message), 'Bio-Formats Error');
                    img = [];
                    return;
                end
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