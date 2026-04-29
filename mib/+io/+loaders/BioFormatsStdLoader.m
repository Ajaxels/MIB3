classdef BioFormatsStdLoader < io.loaders.BaseImageLoader
% BIOFORMATSSTDLOADER - Loader for microscopy files using Bio-Formats, based on.
%
% io.loaders.BaseImageLoader base class
%
% This loader handles a wide variety of microscopy file formats via the
% Bio-Formats library. It supports:
% - Standard loading of multi-series datasets
% - Metadata extraction (pixel sizes, channels, time points)
% - Custom region loading (cropping)
% - Memoization for faster metadata access via loci.formats.Memoizer

    methods
        function obj = BioFormatsStdLoader(options)
            % BIOFORMATSSTDLOADER - Constructor for BioFormatsStdLoader class.
            %
            % Syntax:
            %   function obj = BioFormatsStdLoader(options)
            %
            % Input Arguments:
            %   - **options** — [*optional,* struct] options structure
            %   - .waitbar - [logical] show or not the waitbar
            %   - .mibPath - [char] path to MIB directory
            %   - .customSections - [logical] load custom sections only
            %   - .customSectionsSettings - [struct] custom section parameters
            %   - .imgStretch - [logical] stretch uint32 images to uint16
            %   - .silentMode - [logical] do not ask user questions
            %   - .verbose - [logical] show timing information
            %   - .Font - [struct] font settings for dialogs
            %   - .ParentFigure - handle of the main MIB window to be a parent for uiprogressdlg
            %   - .bioFormatsMemoizerMemoDir - [char] path to memo directory
            %   - .BioFormatsIndices - [numeric] specific series indices to load (0 for all)
            %
            % Output Arguments:
            %   - **obj** — instance of the BioFormatsStdLoader class
            %
            % Usage:
            %   Example 1::
            %
            %       options.waitbar = true;
            %       options.bioFormatsMemoizerMemoDir = 'c:\temp';
            %       loader = io.loaders.BioFormatsStdLoader(options);
            %

            % default Options settings
            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
            obj.initBaseProps(options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - Load metadata for files using Bio-Formats.
            %
            % Syntax:
            %   function [imginfo, files] = loadMetadata(obj, filenames, options)
            %
            % This method uses loci.formats.Memoizer with bfGetReader to extract
            % metadata efficiently. It handles multi-series selection, pixel size
            % extraction from OME metadata, and sets up the file structure for loading.
            %
            % Input Arguments:
            %   - **filenames** — cell array with filenames
            %   - **options** — [*struct]* options for metadata loading
            %   - .waitbar - [logical] show or not the waitbar
            %   - .customSections - [logical] load part of the dataset
            %   - .Font - [struct] font settings for dialogs
            %   - .BioFormatsIndices - [numeric] specific series to load (0 for all)
            %   - .bioFormatsMemoizerMemoDir - [char] memo directory path
            %
            % Output Arguments:
            %   - **imginfo** — dictionary with image metadata
            %   - "Height" - image height in pixels
            %   - "Width" - image width in pixels
            %   - "Colors" - number of color channels
            %   - "Depth" - number of z-slices
            %   - "Time" - number of time points
            %   - "imgClass" - image class (uint8, uint16, etc.)
            %   - "ColorType" - 'grayscale', 'truecolor', or 'indexed'
            %   - "ImageDescription" - description with BoundingBox info
            %   - "Format" - HDF5 format type ('matlab.hdf5' or 'bdv.hdf5')
            %   - "Levels" - number of pyramid levels (for BDV only)
            %   - "ReturnedLevel" - selected pyramid level (for BDV only)
            %   - "pixSize" - structire with pixel sizes, .x, .y, .z, .t, .units, .tunits
            %   - other format-specific metadata fields
            %   - **files** — structure array with file information
            %
            % Usage:
            %   Example 1::
            %
            %       loader = io.loaders.BioFormatsStdLoader();
            %       filenames = {'image.czi'};
            %       [imginfo, files] = loader.loadMetadata(filenames, options);
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
            if ~isfield(options, 'bioFormatsMemoizerMemoDir'); options.bioFormatsMemoizerMemoDir = 'c:\temp'; end
            if ~isfield(options, 'BioFormatsIndices'); options.BioFormatsIndices = []; end

            noFiles = numel(filenames);

            % Initialize waitbar if requested
            wb = [];
            if options.waitbar
                wb = obj.createProgressDialog('Metadata import', ...
                    sprintf('Loading Bio-Formats metadata\nPlease wait...'), false);
            end

            % Pre-allocate files structure array
            % We use layerId to track individual series as separate "files"
            layerId = 1;
            % init the output struct
            files(noFiles) = struct();

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.BioFormatsStdLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.BioFormatsStdLoader');
                    imginfo = dictionary();
                    return;
                end

                % Extract file parts
                [dirId, fnId, ext] = fileparts(filenames{fnIndex});
                ext = lower(ext);

                % Initialize Bio-Formats reader with Memoizer
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

                        filesTemp.hDataset = loci.formats.Memoizer(bfGetReader(), 0, java.io.File(options.bioFormatsMemoizerMemoDir));
                        filesTemp.hDataset.setId(filenames{fnIndex});
                        numSeries = filesTemp.hDataset.getSeriesCount();
                    catch err
                        if ~isempty(wb); delete(wb); end
                        utils.dlgs.showErrorDialog(options.ParentFigure, ...
                            sprintf('Error in io.loaders.BioFormatsStdLoader!\n\nMemoizer can not be initialized for :\n%s', filenames{fnIndex}), ...
                            'BioFormats memoizer', 'Error in io.loaders.BioFormatsStdLoader');
                        imginfo = dictionary();
                        return;
                    end

                    % Series selection
                    if numSeries > 1
                        if isempty(options.BioFormatsIndices)
                            % User selection via selectLociSeries
                            controller = utils.dlgs.SelectLociSeriesDlg( ...
                                filenames{fnIndex}, filesTemp.hDataset, options.Font, options.ParentFigure);
                            [filesTemp.seriesIndex, filesTemp.hDataset, metaSwitch, ...
                                filesTemp.dim_xyczt, filesTemp.seriesRealName] = controller.run();
                        else
                            if options.BioFormatsIndices == 0
                                filesTemp.seriesIndex = 1:numSeries;
                                metaSwitch = true;
                            else
                                % index is too large
                                if max(options.BioFormatsIndices) > numSeries; return; end
                                filesTemp.seriesIndex = options.BioFormatsIndices;
                                metaSwitch = true;
                            end

                            filesTemp.dim_xyczt = zeros(numel(filesTemp.seriesIndex), 5);
                            filesTemp.seriesRealName = cell(numel(filesTemp.seriesIndex), 1);

                            for i = 1:numel(filesTemp.seriesIndex)
                                filesTemp.hDataset.setSeries(filesTemp.seriesIndex(i) - 1);
                                filesTemp.dim_xyczt(i, 1) = filesTemp.hDataset.getSizeX();
                                filesTemp.dim_xyczt(i, 2) = filesTemp.hDataset.getSizeY();
                                filesTemp.dim_xyczt(i, 3) = filesTemp.hDataset.getSizeC();
                                filesTemp.dim_xyczt(i, 4) = filesTemp.hDataset.getSizeZ();
                                filesTemp.dim_xyczt(i, 5) = filesTemp.hDataset.getSizeT();
                                filesTemp.seriesRealName{i} = char(filesTemp.hDataset.getMetadataStore().getImageName(i-1));
                            end
                        end
                    else
                        % Single series - no selection needed
                        filesTemp.seriesIndex = 1;
                        filesTemp.hDataset.setSeries(filesTemp.seriesIndex - 1);
                        metaSwitch = true;
                        filesTemp.dim_xyczt(1, 1) = filesTemp.hDataset.getSizeX();
                        filesTemp.dim_xyczt(1, 2) = filesTemp.hDataset.getSizeY();
                        filesTemp.dim_xyczt(1, 3) = filesTemp.hDataset.getSizeC();
                        filesTemp.dim_xyczt(1, 4) = filesTemp.hDataset.getSizeZ();
                        filesTemp.dim_xyczt(1, 5) = filesTemp.hDataset.getSizeT();
                        filesTemp.seriesRealName{1} = char(filesTemp.hDataset.getMetadataStore().getImageName(0));
                    end
                    % Get OME metadata
                    omeMeta = filesTemp.hDataset.getMetadataStore();
                else % reading second, third, etc file
                    filesTemp.hDataset = loci.formats.Memoizer(bfGetReader(), 0, java.io.File(options.bioFormatsMemoizerMemoDir));
                    filesTemp.hDataset.setId(filenames{fnIndex});
                    filesTemp.hDataset.setSeries(filesTemp.seriesIndex(1)-1);

                    noSeriesTemp = numel(filesTemp.seriesIndex);

                    filesTemp.dim_xyczt(1:noSeriesTemp, 1) = filesTemp.hDataset.getSizeX();
                    filesTemp.dim_xyczt(1:noSeriesTemp, 2) = filesTemp.hDataset.getSizeY();
                    filesTemp.dim_xyczt(1:noSeriesTemp, 3) = filesTemp.hDataset.getSizeC();    % number of color layers
                    filesTemp.dim_xyczt(1:noSeriesTemp, 4) = filesTemp.hDataset.getSizeZ();
                    filesTemp.dim_xyczt(1:noSeriesTemp, 5) = filesTemp.hDataset.getSizeT();    % number of time layers
                    %filesTemp.seriesRealName{1} = char(filesTemp.hDataset.getMetadataStore().getImageName(0));
                end

                % Get dimension order
                filesTemp.dimensionOrder = char(filesTemp.hDataset.getDimensionOrder());

                if strcmp(filesTemp.seriesIndex, 'Cancel')
                    if ~isempty(wb); delete(wb); end
                    imginfo = dictionary();
                    return;
                end

                if ~isfloat(filesTemp.seriesIndex)
                    % Close readers on error
                    if ~isempty(filesTemp.hDataset)
                        filesTemp.hDataset.close();
                    end
                    if ~isempty(wb); delete(wb); end
                    imginfo = dictionary();
                    return;
                end

                % Create individual file entries for each selected series
                for fileSubIndex = 1:numel(filesTemp.seriesIndex)
                    files(layerId).filename = cell2mat(filenames(fnIndex));
                    files(layerId).origFilename = files(layerId).filename;
                    files(layerId).objecttype = 'bioformats';
                    files(layerId).extension = ext;
                    files(layerId).seriesName = filesTemp.seriesIndex(fileSubIndex);
                    files(layerId).dim_xyczt = filesTemp.dim_xyczt;
                    files(layerId).dimensionOrder = filesTemp.dimensionOrder;
                    files(layerId).bioFormatsMemoizerMemoDir = options.bioFormatsMemoizerMemoDir;
                    files(layerId).seriesRealName = filesTemp.seriesRealName{fileSubIndex};

                    % Dimensions
                    files(layerId).height = filesTemp.dim_xyczt(fileSubIndex, 2);
                    files(layerId).width = filesTemp.dim_xyczt(fileSubIndex, 1);
                    % Handle Z and T dimensions
                    if filesTemp.dim_xyczt(fileSubIndex, 4) == 1 && filesTemp.dim_xyczt(fileSubIndex, 5) > 1
                        files(layerId).noLayers = max([filesTemp.dim_xyczt(fileSubIndex, 4), filesTemp.dim_xyczt(fileSubIndex, 5)]);
                        files(layerId).time = 1;
                    else
                        files(layerId).noLayers = filesTemp.dim_xyczt(fileSubIndex, 4);
                        files(layerId).time = filesTemp.dim_xyczt(fileSubIndex, 5);
                    end
                    files(layerId).color = filesTemp.dim_xyczt(fileSubIndex, 3);

                    % Image class
                    bpp = filesTemp.hDataset.getBitsPerPixel();
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
                    if numel(filesTemp.seriesIndex) > 1
                        files(layerId).filename = fullfile(path, [name '__' files(layerId).seriesRealName ext]);
                    end

                    layerId = layerId + 1;
                end

                % Close reader
                filesTemp.hDataset.close();

                % Update pixel size from OME (first file/series only)
                if fnIndex == 1
                    if metaSwitch
                        try
                            omeXML = char(omeMeta.dumpXML());    % to xml
                            omeXML = strrep(omeXML, sprintf('\xB5'), 'u');     % mu, replace utf-8 characters
                            omeXML = strrep(omeXML, sprintf('\xC5'), 'A');      % Angstrem
                            omeXML(omeXML==65533) = 'u';      % mu, replace utf-8 characters
    
                            dummyXMLFilename = fullfile(dirId, 'delete_me.xml');    % save xml to a file
                            fid = fopen(dummyXMLFilename, 'w');
                            if fid == -1
                                dummyXMLFilename = fullfile(tempdir, 'delete_me.xml');
                                fid = fopen(dummyXMLFilename, 'w');
                            end
                            fprintf(fid, '%s', omeXML);
                            fclose(fid);
                            meta = xml2struct(dummyXMLFilename);           % load and convert xml to structure
                            delete(dummyXMLFilename);           % delete dummy xml file
                            imginfo{'meta'} = meta.OME;
                        catch err
                            continue
                        end
                    end

                    try
                        xVal = double(omeMeta.getPixelsPhysicalSizeX(filesTemp(fnIndex).seriesIndex(1)-1).value(ome.units.UNITS.MICROMETER));
                        if isempty(xVal)
                            pixSize.x = 1;   % in um
                            pixSize.y = 1;   % in um
                        else
                            pixSize.x = xVal;   % in um
                            pixSize.y = double(omeMeta.getPixelsPhysicalSizeY(filesTemp.seriesIndex(fileSubIndex)-1).value(ome.units.UNITS.MICROM));   % in um
                        end

                        zVal = omeMeta.getPixelsPhysicalSizeZ(filesTemp(fnIndex).seriesIndex(1)-1);
                        if isempty(zVal)
                            pixSize.z = pixSize.y;   % in um
                        else
                            % pixSize.z = double(omeMeta.getPixelsPhysicalSizeZ(filesTemp.seriesIndex(fileSubIndex)-1).value(ome.units.UNITS.MICROM));   % in um
                            pixSize.z = double(zVal.value(ome.units.UNITS.MICROMETER));
                        end

                        tVal = omeMeta.getPixelsTimeIncrement(filesTemp(fnIndex).seriesIndex(1)-1);
                        if ~isempty(tVal)
                            pixSize.t = double(tVal.value(ome.units.UNITS.SECOND));   % in seconds
                        end

                        % stage coordinates from the stage center
                        % stageCenterX = double(omeMeta.getStageLabelX(filesTemp.seriesIndex(fileSubIndex)-1).value(ome.units.UNITS.MICROM));
                        % from the image center
                        stageCenterX = double(omeMeta.getPlanePositionX(filesTemp.seriesIndex(fileSubIndex)-1, 0).value(ome.units.UNITS.MICROM));
                        if isempty(stageCenterX); stageCenterX = 0; end
                        stageCenterY = double(omeMeta.getPlanePositionY(filesTemp.seriesIndex(fileSubIndex)-1, 0).value(ome.units.UNITS.MICROM));
                        if isempty(stageCenterY); stageCenterY = 0; end
                        stageCenterZ = double(omeMeta.getPlanePositionZ(filesTemp.seriesIndex(fileSubIndex)-1, 0).value(ome.units.UNITS.MICROM));
                        if isempty(stageCenterZ); stageCenterZ = 0; end
                        % add xMin xMax yMin yMax zMin zMax to use them later for calculation of the bounding box
                        % files(fnIndex).xMin = stageCenterX - files(fnIndex).dim_xyczt(1)/2*pixSize.x;
                        % files(fnIndex).xMax = stageCenterX + files(fnIndex).dim_xyczt(1)/2*pixSize.x;
                        % files(fnIndex).yMin = stageCenterY - files(fnIndex).dim_xyczt(2)/2*pixSize.y;
                        % files(fnIndex).yMax = stageCenterY + files(fnIndex).dim_xyczt(2)/2*pixSize.y;
                        % files(fnIndex).zMin = stageCenterZ - files(fnIndex).dim_xyczt(4)/2*pixSize.z;
                        % files(fnIndex).zMax = stageCenterZ + files(fnIndex).dim_xyczt(4)/2*pixSize.z;
                        % add ImageDescription
                        files(fnIndex).boundingBoxVector = [0 0 0 0 0 0];  % [xMin xMax yMin yMax zMin zMax]
                        files(fnIndex).boundingBoxVector(1) = stageCenterX - files(fnIndex).dim_xyczt(1)/2*pixSize.x; % xMin
                        files(fnIndex).boundingBoxVector(2) = stageCenterX + files(fnIndex).dim_xyczt(1)/2*pixSize.x; % xMax
                        files(fnIndex).boundingBoxVector(3) = stageCenterY - files(fnIndex).dim_xyczt(2)/2*pixSize.y; % yMin
                        files(fnIndex).boundingBoxVector(4) = stageCenterY + files(fnIndex).dim_xyczt(2)/2*pixSize.y; % yMax
                        files(fnIndex).boundingBoxVector(5) = stageCenterZ - files(fnIndex).dim_xyczt(4)/2*pixSize.z; % zMin
                        files(fnIndex).boundingBoxVector(6) = stageCenterZ + files(fnIndex).dim_xyczt(4)/2*pixSize.z; % zMax
                        %bbString = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f ', bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
                        %img_info('ImageDescription') = bbString;
                    catch err
                        continue
                    end
                end

                % fix X and Y for dm4
                if strcmp(ext, '.dm4') && pixSize.x ~= pixSize.y
                    pixSize.z = pixSize.x;
                    pixSize.x = pixSize.y;
                end

                % Update waitbar
                if ~isempty(wb)
                    if mod(fnIndex, ceil(noFiles/50)) == 0
                        wb.Value = fnIndex/noFiles;
                    end
                end
            end

            % update pixSize
            imginfo{"pixSize"} = pixSize;

            % get colors for the color channels
            colorsVec = [files.color];
            maxColorChannel = max(colorsVec);
            indexOfDataset = find(colorsVec==maxColorChannel,1);     % index with largest number of colors
            indexOfDataset = files(indexOfDataset).seriesName-1;
            if ~isempty(omeMeta.getChannelColor(indexOfDataset, 0))
                rgb = zeros(maxColorChannel, 3);
                for colCh=1:maxColorChannel
                    if isempty(omeMeta.getChannelColor(indexOfDataset, colCh-1)); continue; end
                    rgb(colCh, 1) = omeMeta.getChannelColor(indexOfDataset, colCh-1).getRed();
                    rgb(colCh, 2) = omeMeta.getChannelColor(indexOfDataset, colCh-1).getGreen();
                    rgb(colCh, 3) = omeMeta.getChannelColor(indexOfDataset, colCh-1).getBlue();
                end
                imginfo{'lutColors'} = rgb/255;
            elseif ~isempty(omeMeta.getChannelExcitationWavelength(indexOfDataset, 0)) && ~isempty(omeMeta.getChannelEmissionWavelength(indexOfDataset, 0))
                rgb = zeros(maxColorChannel, 3);
                for colCh=1:maxColorChannel
                    Wavelength = double(omeMeta.getChannelEmissionWavelength(indexOfDataset, colCh-1).value());
                    %Wavelength = double(omeMeta.getChannelExcitationWavelength(indexOfDataset, colCh-1).value());
                    rgb(colCh, :) = io.BioFormats.wavelength2rgb(Wavelength);
                end
                imginfo{'lutColors'} = rgb/255;
            end

            % Set metadata for first file
            if ~isempty(files)
                imginfo{'imgClass'} = files(1).imgClass;
                if files(1).color > 1
                    imginfo{'ColorType'} = 'multichannel';
                else
                    imginfo{'ColorType'} = 'grayscale';
                end
            end

            % Handle custom sections
            if options.customSections
                [files, imginfo, cancelled] = obj.handleCustomSections(files, imginfo, options);
                if cancelled
                    imginfo = dictionary();
                    if ~isempty(wb); delete(wb); end
                    return;
                end
            end

            % Generate slice names
            imginfo = obj.generateSliceNames(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if ~isempty(wb); delete(wb); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % LOADIMAGES - Load image data using Bio-Formats.
            %
            % Syntax:
            %   function [img, imginfo] = loadImages(obj, files, imginfo, options)
            %
            % This method uses bfopen4 (MIB wrapper around bfopen) to load images.
            % It supports loading multiple series and concatenating them along Z.
            %
            % Input Arguments:
            %   - **files** — structure array from loadMetadata
            %   - **imginfo** — dictionary from loadMetadata
            %   - **options** — [*struct]* options for image loading
            %
            % Output Arguments:
            %   - **img** — loaded image dataset
            %   - **imginfo** — updated dictionary
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

            % Pre-allocate image array: [Y, X, Z, C, T]
            if isfield(files, 'backgroundColor')
                img = zeros([height, width, maxZ, color, time],imgClass)+files(1).backgroundColor;
            else
                img = zeros([height, width, maxZ, color, time], imgClass);
            end

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            layerId = 1;
            noFiles = numel(files);

            % Initialize waitbar
            wb = [];
            if options.waitbar
                wb = obj.createProgressDialog('Loading images with BioFormats', ...
                    sprintf('Please wait...'), true);
            end

            for fnIndex = 1:noFiles
                % Check for cancel button
                if ~isempty(wb) && wb.CancelRequested
                    delete(wb);
                    img = [];
                    return;
                end

                maxY = min(height, files(fnIndex).height);
                maxX = min(width, files(fnIndex).width);
                maxC = min(color, files(fnIndex).color);
                maxT = min(time, files(fnIndex).time);

                % Setup options for bfopen5
                bfopenOptions = struct();
                bfopenOptions.bioFormatsMemoizerMemoDir = files(fnIndex).bioFormatsMemoizerMemoDir;
                if ~isempty(wb)
                    bfopenOptions.waitbarHandle = wb;
                    bfopenOptions.waitbarUpdateFrequency = waitbarUpdateFrequency;
                end
                if isfield(files(fnIndex), 'dimensionOrder')
                    bfopenOptions.dimensionOrder = files(fnIndex).dimensionOrder;
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
                    I = io.BioFormats.bfopen5(files(fnIndex).origFilename, files(fnIndex).seriesName, NaN, bfopenOptions);
                    if isempty(I)
                        img = [];
                        return;
                    end

                    % Assign data (I.img is [Y, X, Z, C, T])
                    for subLayer = 1:files(fnIndex).noLayers
                        img(1:maxY, 1:maxX, layerId, 1:maxC, 1:maxT) = I.img(1:maxY, 1:maxX, subLayer, 1:maxC, 1:maxT);

                        % Update metadata from first load
                        if fnIndex == 1 && subLayer == 1
                            if isfield(I, 'ColorType'); imginfo{'ColorType'} = I.ColorType; end
                            if isfield(I, 'ColorMap'); imginfo{'ColorMap'} = I.ColorMap; end
                        end

                        layerId = layerId + 1;

                        % Update waitbar
                        if ~isempty(wb) && mod(layerId, waitbarUpdateFrequency) == 0
                            if ~isempty(wb) && wb.CancelRequested
                                img = [];
                                delete(wb);
                                return;
                            end
                            wb.Value = layerId/maxZ;
                        end
                    end

                catch err
                    if ~isempty(wb); delete(wb); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('io.loaders.BioFormatsStdLoader:\n\nError loading Bio-Formats file\n%s', err.message), 'Bio-Formats Error', 'Error in io.loaders.BioFormatsStdLoader');
                    img = [];
                    return;
                end
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
