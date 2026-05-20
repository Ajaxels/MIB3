classdef HDF5HeaderLoader < io.loaders.BaseImageLoader
% HDF5HEADERLOADER - Loader for HDF5 files with XML headers, based on.
%
% io.loaders.BaseImageLoader base class

    % This loader handles HDF5 files referenced by XML headers.
    % It supports two HDF5 formats:
    %   - MATLAB HDF5 format (matlab.hdf5)
    %   - BigDataViewer HDF5 format (bdv.hdf5)
    % The XML header contains metadata and references to HDF5 datasets.

    methods
        function obj = HDF5HeaderLoader(options)
            % HDF5HEADERLOADER - Constructor for HDF5HeaderLoader class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.HDF5HeaderLoader(options)
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
            %   - **obj** — instance of the HDF5HeaderLoader class
            %
            % **Example 1** — create loader with options:
            %
            %   .. code-block:: matlab
            %
            %      options.waitbar = true;
            %      options.mibPath = 'c:\\mib';
            %      loader = io.loaders.HDF5HeaderLoader(options);

            % default Options settings
            obj.Options = struct();
            obj.Options.Font = struct('Name', 'Helvetica', 'Size', 12);

            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function [imginfo, metaStr] = parseXMLHeader(obj, filename)
            % PARSEXMLHEADER - Parse XML header for HDF5 formats (BigDataViewer, MATLAB HDF5).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [imginfo, metaStr] = obj.parseXMLHeader(filename)
            %
            % This method reads and parses XML header files that reference HDF5
            % datasets. It extracts metadata including dimensions, pixel sizes,
            % channel information, and dataset paths. Primarily used for Fiji
            % BigDataViewer format but also supports MATLAB HDF5 with XML headers.
            %
            % Input Arguments:
            %   - **filename** — [char] full path to XML header file
            %
            % Output Arguments:
            %   - **imginfo** — dictionary with metadata containing fields:
            %
            %     - ``Format`` — HDF5 format type (``'bdv.hdf5'`` or ``'matlab.hdf5'``)
            %     - ``Filename`` — full path to HDF5 data file
            %     - ``Height`` — image height in pixels
            %     - ``Width`` — image width in pixels
            %     - ``Depth`` — number of z-slices
            %     - ``Colors`` — number of color channels
            %     - ``Time`` — number of time points
            %     - ``ColorType`` — ``'grayscale'`` or ``'truecolor'``
            %     - ``ImageDescription`` — optional description text
            %     - ``Datasetname`` — HDF5 dataset path (optional)
            %     - ``channelNames`` — cell array of channel names
            %     - ``lutColors`` — color LUT for channels (optional)
            %     - ``modelMaterialNames`` — material names cell array (optional)
            %     - ``modelMaterialColors`` — material colors [N×3] RGB (optional)
            %     - ``pixSize`` — structure with voxel dimensions
            %     - ``ReturnedLevel`` — pyramid level (default: ``1``)
            %
            %   - **metaStr** — structure with parsed XML content
            %
            % **Example 1** — parse XML header and get dataset info:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.HDF5HeaderLoader();
            %      [imginfo, metaStr] = loader.parseXMLHeader('dataset.xml');
            %      fprintf('Format: %s, Size: %d x %d x %d\n', imginfo{"Format"}, ...
            %          imginfo{"Width"}, imginfo{"Height"}, imginfo{"Depth"});

            % Check input
            if nargin < 2
                error('HDF5HeaderLoader:parseXMLHeader:MissingFilename', ...
                    'The filename parameter is required');
            end

            % Initialize output structures
            metaStr = struct();
            imginfo = dictionary();

            % Initialize default pixel size
            pixSize.x = 1;
            pixSize.y = 1;
            pixSize.z = 1;
            pixSize.units = 'um';
            pixSize.t = 1;
            pixSize.tunits = 'sec';

            % Get file directory
            [dirName, ~, ~] = fileparts(filename);

            % Initialize default metadata fields
            imginfo{"ImageDescription"} = '';
            imginfo{"XResolution"} = [];
            imginfo{"YResolution"} = [];
            imginfo{"ResolutionUnit"} = 'Inch';

            % Parse XML file
            try
                metaStr = xml2struct(filename);
            catch err
                error('HDF5HeaderLoader:parseXMLHeader:XMLParseError', ...
                    'Cannot parse XML file: %s\nError: %s', filename, err.message);
            end

            % Get dataset name (root element name)
            datasetName = fieldnames(metaStr);
            datasetName = datasetName{1};

            % Get HDF5 filename from XML
            fileH5 = metaStr.(datasetName).SequenceDescription.ImageLoader.hdf5.Text;
            fullfileH5 = fullfile(dirName, fileH5);

            % Extract format type
            imginfo{"Format"} = metaStr.(datasetName).SequenceDescription.ImageLoader.Attributes.format;

            % Get number of color channels
            imginfo{"Colors"} = numel(metaStr.(datasetName).SequenceDescription.ViewSetups.ViewSetup);

            % Get optional ImageDescription field
            if isfield(metaStr.(datasetName).SequenceDescription.ViewSetups, 'ImageDescription')
                imginfo{"ImageDescription"} = metaStr.(datasetName).SequenceDescription.ViewSetups.ImageDescription.Text;
            end

            % Get optional Datasetname field
            if isfield(metaStr.(datasetName).SequenceDescription.ImageLoader, 'Datasetname')
                imginfo{"Datasetname"} = metaStr.(datasetName).SequenceDescription.ImageLoader.Datasetname.Text;
            end

            % Get materials of the model (for segmented datasets)
            if isfield(metaStr.(datasetName).SequenceDescription.ViewSetups, 'Materials')
                materialFieldNames = fieldnames(metaStr.(datasetName).SequenceDescription.ViewSetups.Materials);
                material_list = cell([numel(materialFieldNames), 1]);
                color_list = zeros(numel(materialFieldNames), 3);

                for matId = 1:numel(materialFieldNames)
                    material_list{matId} = metaStr.(datasetName).SequenceDescription.ViewSetups.Materials.(materialFieldNames{matId}).Name.Text;
                    color_list(matId, :) = str2num(metaStr.(datasetName).SequenceDescription.ViewSetups.Materials.(materialFieldNames{matId}).Color.Text); %#ok<ST2NM>
                end

                imginfo{"modelMaterialNames"} = material_list;
                imginfo{"modelMaterialColors"} = color_list;
            end

            % Convert ViewSetup to cell if only single entry
            if ~iscell(metaStr.(datasetName).SequenceDescription.ViewSetups.ViewSetup)
                ViewSetup{1} = metaStr.(datasetName).SequenceDescription.ViewSetups.ViewSetup;
            else
                ViewSetup = metaStr.(datasetName).SequenceDescription.ViewSetups.ViewSetup;
            end

            % Extract channel names
            if isfield(ViewSetup{1}, 'name')
                imginfo{"channelNames"} = cellfun(@(x) x.name.Text, ViewSetup', 'UniformOutput', false);
            else
                imginfo{"channelNames"} = cellfun(@(x) x.id.Text, ViewSetup', 'UniformOutput', false);
            end

            % Set color type
            if imginfo{"Colors"} > 1
                imginfo{"ColorType"} = 'truecolor';
            else
                imginfo{"ColorType"} = 'grayscale';
            end

            % Add optional color channel LUT
            if isfield(ViewSetup{1}, 'color')
                colorText = cellfun(@(x) x.color.Text, ViewSetup', 'UniformOutput', false);
                colorTextVal = zeros(numel(colorText), 3);
                for i = 1:numel(colorText)
                    colorTextVal(i, :) = str2num(colorText{i}); %#ok<ST2NM>
                end
                imginfo{"lutColors"} = colorTextVal;
            end

            % Get number of time points
            t2 = str2double(metaStr.(datasetName).SequenceDescription.Timepoints.last.Text) + 1;
            imginfo{"Time"} = t2;

            % Store HDF5 filename
            imginfo{"Filename"} = fullfileH5;

            % Extract pixel size information
            if isfield(ViewSetup{1}, 'voxelSize')
                units = ViewSetup{1}.voxelSize.unit.Text;

                % Convert micrometer symbol to 'um'
                if strcmp(units, sprintf('\xB5m'))
                    units = 'um';
                end

                pixSize.units = units;
                voxels = str2num(ViewSetup{1}.voxelSize.size.Text); %#ok<ST2NM>
                pixSize.x = voxels(1);
                pixSize.y = voxels(2);
                pixSize.z = voxels(3);
            end

            imginfo{"pixSize"} = pixSize;

            % Extract image dimensions
            xyzVal = str2num(ViewSetup{1}.size.Text); %#ok<ST2NM>

            % Store dimensions (note: order depends on format)
            %if strcmp(imginfo{"Format"}, 'bdv.hdf5')
                imginfo{"Height"} = xyzVal(1);
                imginfo{"Width"} = xyzVal(2);
            %else
            %    imginfo{"Height"} = xyzVal(1);
            %    imginfo{"Width"} = xyzVal(2);
            %end

            imginfo{"Depth"} = xyzVal(3);
            imginfo{"ReturnedLevel"} = 1;  % Default pyramid level
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % LOADMETADATA - Load metadata for HDF5 files with XML headers.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [imginfo, files] = obj.loadMetadata(filenames, options)
            %
            % This method parses XML headers to extract HDF5 dataset metadata.
            % It supports both MATLAB HDF5 and BigDataViewer formats. The XML
            % header contains dataset paths, dimensions, pixel sizes, and other
            % metadata required for loading.
            %
            % Input Arguments:
            %   - **filenames** — cell array with filenames of XML header files
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
            %   - **files** — structure array with file information for each file:
            %
            %     - ``filename`` — [char] full filename (XML header)
            %     - ``objecttype`` — [char] type: ``'hdf5_image'`` or ``'bdv.hdf5'``
            %     - ``extension`` — [char] file extension ``'.xml'``
            %     - ``height`` — [numeric] image height
            %     - ``width`` — [numeric] image width
            %     - ``color`` — [numeric] number of color channels
            %     - ``noLayers`` — [numeric] number of z-slices
            %     - ``time`` — [numeric] number of time points
            %     - ``imgClass`` — [char] image class
            %     - ``dim_xyzct`` — [numeric array] dimensions [x, y, z, c, t]
            %     - ``seriesName`` — [char] HDF5 dataset path
            %     - ``level`` — [numeric] pyramid level (for BDV)
            %
            % **Example 1** — load metadata from HDF5 files with XML headers:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.HDF5HeaderLoader();
            %      options.waitbar = true;
            %      filenames = {'dataset1.xml', 'dataset2.xml'};
            %      [imginfo, files] = loader.loadMetadata(filenames, options);
            %      fprintf('HDF5 dataset: %d x %d x %d\n', imginfo{"Width"}, imginfo{"Height"}, imginfo{"Depth"});

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
            pwb = [];
            if options.waitbar && ~isempty(obj.ParentFigure)
                pwb = core.PoolWaitbar(noFiles, ...
                    sprintf('Loading HDF5 metadata\n(press Cancel when metadata is the same for all files)'), ...
                    obj.ParentFigure, 'Metadata import', true);
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', [], ...
                'dim_xyzct', [], 'seriesName', []);

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    imginfo = dictionary();
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.HDF5HeaderLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.HDF5HeaderLoader');
                    return;
                end

                % Check for cancel button
                if ~isempty(pwb) && pwb.getCancelState()
                    % Use metadata from first file for all remaining files
                    files(fnIndex:noFiles) = files(1);
                    [files.filename] = filenames{:}; % update filenames
                    fnIndex = noFiles;
                    continue;
                end

                % Extract file parts
                [~, ~, ext] = fileparts(filenames{fnIndex});
                ext = lower(ext);
                files(fnIndex).extension = ext;
                files(fnIndex).filename = cell2mat(filenames(fnIndex));

                % Parse XML header using internal parseXMLHeader method
                try
                    imginfoTemp = obj.parseXMLHeader(filenames{fnIndex});
                catch err
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('Error in io.loaders.HDF5HeaderLoader!\n\nCannot parse XML header:\n%s\n\nError: %s', ...
                        filenames{fnIndex}, err.message), ...
                        'XML parsing error', 'Error in io.loaders.HDF5HeaderLoader');
                    imginfo = dictionary();
                    return;
                end

                % Store basic file information
                files(fnIndex).filename = imginfoTemp{'Filename'};
                files(fnIndex).objecttype = imginfoTemp{"Format"};
                files(fnIndex).color = imginfoTemp{"Colors"};
                files(fnIndex).level = imginfoTemp{"ReturnedLevel"};

                % Set color type
                if fnIndex == 1
                    imginfo{"ColorType"} = imginfoTemp{"ColorType"};
                else
                    % Check ColorType consistency
                    if ~strcmp(imginfo{"ColorType"}, imginfoTemp{"ColorType"})
                        imginfo = dictionary();
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        utils.dlgs.showErrorDialog(options.ParentFigure, ...
                            sprintf('!!! Error !!!\n\nThe files have dissimilar ColorType'), ...
                            'Mixed colors', 'Error in io.loaders.HDF5HeaderLoader');
                        return;
                    end
                end

                % Handle time dimension (when 0, set to 1)
                if imginfoTemp{"Time"} == 0
                    imginfoTemp{"Time"} = 1;
                end
                files(fnIndex).time = imginfoTemp{"Time"};

                % Store dataset name if present
                if isKey(imginfoTemp, "Datasetname")
                    files(fnIndex).seriesName = imginfoTemp{"Datasetname"};
                    imginfoTemp = remove(imginfoTemp, "Datasetname");
                else
                    files(fnIndex).seriesName = '';
                end

                % Handle MATLAB HDF5 format
                if strcmpi(imginfoTemp{"Format"}, 'matlab.hdf5')
                    % Get HDF5 file info
                    infoHDF5 = h5info(imginfoTemp{"Filename"}, files(fnIndex).seriesName);

                    % Read a single point to determine data class
                    try
                        I = h5read(imginfoTemp{"Filename"}, files(fnIndex).seriesName, ...
                            [1 1 1 1 1], [1 1 1 1 1]);
                        imgClass = class(I);
                    catch
                        % Try without time dimension
                        I = h5read(imginfoTemp{"Filename"}, files(fnIndex).seriesName, ...
                            [1 1 1 1], [1 1 1 1]);
                        imgClass = class(I);
                    end

                    if fnIndex == 1
                        imginfo{"imgClass"} = imgClass;
                    end
                    files(fnIndex).imgClass = imgClass;
                    files(fnIndex).dim_xyzct = [imginfoTemp{"Width"}, imginfoTemp{"Height"}, ...
                        imginfoTemp{"Depth"}, imginfoTemp{"Colors"}, imginfoTemp{"Time"}];

                    % Extract pixel size
                    if fnIndex == 1 && isKey(imginfoTemp, "pixSize")
                        pixSize = imginfoTemp{"pixSize"};
                        imginfoTemp = remove(imginfoTemp, "pixSize");
                    end

                % Handle BigDataViewer HDF5 format
                elseif strcmpi(imginfoTemp{"Format"}, 'bdv.hdf5')
                    % Get HDF5 file info
                    info = h5info(imginfoTemp{"Filename"});

                    % Find first timepoint
                    offsetIndex = find(ismember({info.Groups.Name}, '/t00000'));% + 1;

                    % Get number of pyramid levels
                    noLevels = numel(info.Groups(offsetIndex).Groups(1).Groups);

                    if fnIndex == 1
                        imginfo{"Levels"} = noLevels;

                        % Extract pixel size
                        if isKey(imginfoTemp, "pixSize")
                            pixSize = imginfoTemp{"pixSize"};
                            imginfoTemp = remove(imginfoTemp, "pixSize");
                        end

                        % Select pyramid level if multiple available
                        if noLevels > 1
                            prompt = sprintf('The dataset contains %d images\nchoose the one to take\n(enter 1 to get image in the original size):', noLevels);
                            dlgOptions.Type = 'spinner';
                            dlgOptions.WindowHeight = 140;
                            dlgOptions.mibPath = obj.Options.mibPath;
                            defAns = struct('Value', 1, 'Limits', [1 noLevels], 'Step', 1, 'Round', true, 'ValueDisplayFormat', '%d');
                            level = utils.dlgs.inputSingleDlg(obj.Options.ParentFigure, prompt, defAns, 'Select image', dlgOptions);
                            if isempty(level)
                                if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                                imginfo = dictionary();
                                return;
                            end

                            % Update dimensions and pixel sizes for binned datasets
                            xyzVal = info.Groups(offsetIndex).Groups(1).Groups(level).Datasets.Dataspace.Size;
                            pixSize.x = pixSize.x * (imginfoTemp{"Height"} / xyzVal(2));
                            pixSize.y = pixSize.y * (imginfoTemp{"Width"} / xyzVal(1));
                            pixSize.z = pixSize.z * (imginfoTemp{"Depth"} / xyzVal(3));
                            imginfoTemp{"Height"} = xyzVal(2);
                            imginfoTemp{"Width"} = xyzVal(1);
                            imginfoTemp{"Depth"} = xyzVal(3);
                            imginfoTemp{"ReturnedLevel"} = level;
                        end
                    end

                    % Detect data type
                    dataType = info.Groups(offsetIndex).Groups(1).Groups(imginfoTemp{"ReturnedLevel"}).Datasets.Datatype.Type;
                    switch dataType
                        case {'H5T_STD_I16LE', 'H5T_STD_U16LE'}
                            imgClass = 'uint16';
                        case {'H5T_STD_I8LE', 'H5T_STD_U8LE'}
                            imgClass = 'uint8';
                        otherwise
                            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                            utils.dlgs.showErrorDialog(options.ParentFigure, ...
                                sprintf('Oops!\n\nPlease check image class "%s" and implement it!', dataType), ...
                                'Unsupported data type', 'Error in io.loaders.HDF5HeaderLoader');
                            imginfo = dictionary();
                            return;
                    end

                    if fnIndex == 1
                        imginfo{"imgClass"} = imgClass;
                    end
                    files(fnIndex).imgClass = imgClass;
                    files(fnIndex).dim_xyzct = [imginfoTemp{"Width"}, imginfoTemp{"Height"}, ...
                        imginfoTemp{"Depth"}, imginfoTemp{"Colors"}, imginfoTemp{"Time"}];

                else
                    % Unknown format
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    utils.dlgs.showErrorDialog(options.ParentFigure, ...
                        sprintf('!!! Error !!!\n\nCannot detect the HDF5 format!'), ...
                        'Unknown format', 'Error in io.loaders.HDF5HeaderLoader');
                    imginfo = dictionary();
                    return;
                end

                % Store dimensions
                files(fnIndex).height = imginfoTemp{"Height"};
                files(fnIndex).width = imginfoTemp{"Width"};
                files(fnIndex).noLayers = imginfoTemp{"Depth"};

                % Store metadata from first file
                if fnIndex == 1
                    % Copy all fields from imginfoTemp to imginfo
                    tempKeys = keys(imginfoTemp);
                    for keyIdx = 1:numel(tempKeys)
                        imginfo{tempKeys{keyIdx}} = imginfoTemp{tempKeys{keyIdx}};
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

            % Handle dimension mismatches and bounding box
            imginfo = obj.handleDimensionMismatches(files, imginfo);

            % Set number of entries (required by MibDataset.loadModel)
            imginfo{"numEntries"} = noFiles;

            % Generate slice names from filenames
            imginfo = obj.generateSliceNames(files, imginfo);
            imginfo = obj.generateSliceSizes(files, imginfo);

            % Finalize image info
            imginfo = obj.finalizeImgInfo(imginfo, files, filenames{1});

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % LOADIMAGES - Load image data from HDF5 files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.loadImages(files, imginfo, options)
            %
            % This method loads actual image data from HDF5 files using h5read.
            % It supports both MATLAB HDF5 and BigDataViewer formats, handles
            % dimension permutation, and supports custom region loading.
            %
            % Input Arguments:
            %   - **files** — structure array from loadMetadata with file information:
            %
            %     - ``filename`` — [char] full filename (XML header)
            %     - ``objecttype`` — [char] ``'hdf5_image'`` or ``'bdv.hdf5'``
            %     - ``extension`` — [char] file extension ``'.xml'``
            %     - ``height`` — [numeric] image height
            %     - ``width`` — [numeric] image width
            %     - ``color`` — [numeric] number of color channels
            %     - ``noLayers`` — [numeric] number of z-slices
            %     - ``time`` — [numeric] number of time points
            %     - ``imgClass`` — [char] image class
            %     - ``dim_xyzct`` — [numeric array] dimensions
            %     - ``seriesName`` — [char] HDF5 dataset path
            %     - ``transMatrix`` — [numeric array] permutation matrix (optional)
            %     - ``backgroundColor`` — [numeric] background color (optional)
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
            %
            % **Example 1** — load images from HDF5 file with XML header:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.HDF5HeaderLoader();
            %      options.waitbar = true;
            %      [imginfo, files] = loader.loadMetadata({'dataset.xml'}, options);
            %      [img, imginfo] = loader.loadImages(files, imginfo, options);
            %      fprintf('Loaded HDF5 dataset: %s\n', mat2str(size(img)));

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

            % Initialize waitbar
            pwb = [];
            if options.waitbar && ~isempty(obj.ParentFigure)
                pwb = core.PoolWaitbar(maxZ, 'Please wait...', obj.ParentFigure, 'Loading HDF5 images...', true);
                if ~isempty(pwb); pwb.setIncrement(waitbarUpdateFrequency); end
            end

            % Process each file
            for fnIndex = 1:noFiles
                % Check for cancel button
                if ~isempty(pwb) && pwb.getCancelState()
                    pwb.deletePoolWaitbar();
                    img = [];
                    return;
                end

                % Calculate dimensions for this file
                maxY = min(height, files(fnIndex).height);
                maxX = min(width, files(fnIndex).width);
                maxC = min(color, files(fnIndex).color);
                maxT = min(time, files(fnIndex).time);

                % Load HDF5 data based on format
                if strcmp(files(fnIndex).objecttype, 'bdv.hdf5')
                    % BigDataViewer format
                    opt.level = imginfo{"ReturnedLevel"};
                    opt.ParentFigure = obj.Options.ParentFigure;
                    try
                        imgIn = obj.loadBigDataViewerFormat(files(fnIndex).filename, opt, imginfo);
                    catch err
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        utils.dlgs.showErrorDialog(options.ParentFigure, ...
                            sprintf('Error loading BigDataViewer HDF5:\n%s\n\nError: %s', ...
                            imginfo{"Filename"}, err.message), ...
                            'HDF5 loading error', 'Error in io.loaders.HDF5HeaderLoader');
                        img = [];
                        return;
                    end

                    % Store data
                    img(1:maxY, 1:maxX, layerid:layerid+files(fnIndex).noLayers-1, 1:maxC, 1:maxT) = ...
                        imgIn(1:maxY, 1:maxX, 1:files(fnIndex).noLayers, 1:maxC, 1:maxT);
                    clear imgIn;

                elseif strcmp(files(fnIndex).objecttype, 'hdf5_image') || strcmp(files(fnIndex).objecttype, 'matlab.hdf5')
                    % MATLAB HDF5 format
                    try
                        hdf5image = h5read(files(fnIndex).filename, files(fnIndex).seriesName);
                    catch err
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        utils.dlgs.showErrorDialog(options.ParentFigure, ...
                            sprintf('Error loading MATLAB HDF5:\n%s\n\nError: %s', ...
                            files(fnIndex).filename, err.message), ...
                            'HDF5 loading error', 'Error in io.loaders.HDF5HeaderLoader');
                        img = [];
                        return;
                    end

                    % Check if data is numerical
                    if iscell(hdf5image)
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        assignin('base', 'hdf5image', hdf5image);
                        utils.dlgs.showErrorDialog(options.ParentFigure, ...
                            sprintf('mibGetImages: cannot read this dataset!\n\nIt was exported as ''hdf5image'' to the main MATLAB workspace.'), ...
                            'Error!', 'Error in io.loaders.HDF5HeaderLoader');
                        img = [];
                        return;
                    end

                    % Convert single to unsigned integers if needed
                    if isa(hdf5image, 'single')
                        maxVal = max(hdf5image(:));
                        if maxVal <= 1  % Data squeezed between 0 and 1
                            hdf5image = uint8(hdf5image * 255);
                            if layerid == 1; img = uint8(img); end
                        elseif maxVal <= 255
                            hdf5image = uint8(hdf5image);
                            if layerid == 1; img = uint8(img); end
                        elseif maxVal <= 65535
                            hdf5image = uint16(hdf5image);
                            if layerid == 1; img = uint16(img); end
                        else
                            hdf5image = uint32(hdf5image);
                            if layerid == 1; img = uint32(img); end
                        end

                        if ~options.silentMode
                            uiconfirm(options.ParentFigure, ...
                                sprintf('mibGetImages: the dataset was converted to %s format!', class(hdf5image)), ...
                                'Warning!', 'Icon', 'warning');
                        end
                        imginfo{"MaxInt"} = double(intmax(class(hdf5image)));
                    end

                    % XML from MIB2, requires permutation
                    if size(hdf5image,3) == files(fnIndex).color && size(hdf5image, 4) == files(fnIndex).noLayers
                        hdf5image = permute(hdf5image, [1 2 4 3 5]);
                    end

                    % Reshape dataset if needed (apply transMatrix)
                    if isfield(files(fnIndex), 'transMatrix')
                        hdf5image = permute(hdf5image, files(fnIndex).transMatrix);
                    end

                    % Store data
                    img(1:maxY, 1:maxX, layerid:layerid+files(fnIndex).noLayers-1, 1:maxC, 1:maxT) = ...
                        hdf5image;
                    clear hdf5image;
                end

                % Update waitbar
                if ~isempty(pwb) && mod(layerid, waitbarUpdateFrequency) == 0
                    if pwb.getCancelState()
                        pwb.deletePoolWaitbar();
                        img = [];
                        return;
                    end
                    pwb.increment();
                end

                layerid = layerid + files(fnIndex).noLayers;
            end

            % Check for cancel after loading
            if ~isempty(pwb) && pwb.getCancelState()
                pwb.deletePoolWaitbar();
                img = [];
                return;
            end

            % Update imginfo with final dimensions
            imginfo{'Height'} = height;
            imginfo{'Width'} = width;
            imginfo{'Depth'} = maxZ;
            imginfo{'Time'} = maxT;

            [img, imginfo] = obj.finalizeImageLoading(img, imginfo, options);

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
        end

        function [img, imginfo] = loadBigDataViewerFormat(obj, filename, options, imginfo)
            % LOADBIGDATAVIEWERFORMAT - Read BigDataViewer format HDF5 files from Fiji.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.loadBigDataViewerFormat(filename, options, imginfo)
            %
            % This method reads HDF5 files in BigDataViewer format, which uses
            % a hierarchical structure with time points, color channels, and
            % pyramid levels. It supports loading complete datasets or custom
            % regions with specified coordinates.
            %
            % Format description: http://fiji.sc/BigDataViewer#About_the_BigDataViewer_data_format
            %
            % Input Arguments:
            %   - **filename** — [char] path to HDF5 file (``xml`` or ``h5``)
            %   - **options** — *(optional)* struct with fields:
            %
            %     - ``y`` — [numeric array] [ymin, ymax] height coordinates to load
            %     - ``x`` — [numeric array] [xmin, xmax] width coordinates to load
            %     - ``z`` — [numeric array] [zmin, zmax] depth coordinates to load
            %     - ``c`` — [numeric array] indices of color channels to load
            %     - ``t`` — [numeric array] [tmin, tmax] time range to load
            %     - ``level`` — [numeric] magnification level (``1`` for unbinned)
            %     - ``waitbar`` — [logical] show waitbar; default: ``true``
            %     - ``ParentFigure`` — handle to parent window for dialogs
            %
            %   - **imginfo** — *(optional)* dictionary with metadata from XML file
            %
            % Output Arguments:
            %   - **img** — loaded dataset [height, width, color, depth, time]
            %   - **imginfo** — updated dictionary with dataset parameters:
            %
            %     - ``Width`` — image width
            %     - ``Height`` — image height
            %     - ``Depth`` — number of z-slices
            %     - ``Colors`` — number of color channels
            %     - ``Time`` — number of time points
            %     - ``imgClass`` — image class (``uint8``, ``uint16``)
            %     - ``ColorType`` — ``'grayscale'`` or ``'truecolor'``
            %     - ``Format`` — ``'bdv.hdf5'``
            %     - ``Levels`` — number of pyramid levels
            %     - ``ReturnedLevel`` — selected pyramid level
            %
            % **Example 1** — load complete BigDataViewer dataset:
            %
            %   .. code-block:: matlab
            %
            %      loader = io.loaders.HDF5HeaderLoader();
            %      [img, imginfo] = loader.loadBigDataViewerFormat('dataset.h5');
            %
            % **Example 2** — load custom region with downsampling:
            %
            %   .. code-block:: matlab
            %
            %      options.x = [50 500];
            %      options.y = [50 500];
            %      options.level = 2;
            %      [img, imginfo] = loader.loadBigDataViewerFormat('dataset.h5', options);

            % Initialize
            if nargin < 4; imginfo = dictionary(); end
            if nargin < 3; options = struct(); end
            if nargin < 2
                error('HDF5HeaderLoader:loadBigDataViewerFormat:MissingFilename', ...
                    'The filename parameter is required');
            end

            img = [];
            if ~isfield(options, 'waitbar'); options.waitbar = true; end
            if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end

            % Initialize progress dialog
            pwb = [];   wb = [];
            if options.waitbar && ~isempty(obj.ParentFigure)
                pwb = core.PoolWaitbar(1, sprintf('Loading HDF5 file structure\nPlease wait...'), ...
                    obj.ParentFigure, 'Loading HDF5...', false, true);
                if ~isempty(pwb); wb = pwb.getWaitbarHandle(); end
            end

            % Get HDF5 file structure
            info = h5info(filename);
            offsetIndex = find(ismember({info.Groups(:).Name}, '/t00000') == 1);

            % Populate imginfo if empty
            if isempty(imginfo) || numEntries(imginfo) == 0
                % Initialize default pixel size
                pixSize.x = 1;
                pixSize.y = 1;
                pixSize.z = 1;
                pixSize.units = 'um';
                pixSize.t = 1;
                pixSize.tunits = 'sec';

                % Get number of color channels
                groupNames = {info.Groups.Name};
                setupsId = strfind(groupNames, '/s');
                imginfo{"Colors"} = sum(cell2mat(setupsId));
                imginfo{"channelNames"} = arrayfun(@(x) cellstr(x.Name), info.Groups(2:offsetIndex-1));

                % Set color type
                if imginfo{"Colors"} > 1
                    imginfo{"ColorType"} = 'truecolor';
                else
                    imginfo{"ColorType"} = 'grayscale';
                end

                % Get number of time points
                imginfo{"Time"} = sum(cell2mat(strfind({info.Groups(:).Name}, '/t')));
                imginfo{"ImageDescription"} = '';
                imginfo{"XResolution"} = [];
                imginfo{"YResolution"} = [];
                imginfo{"ResolutionUnit"} = 'Inch';
                imginfo{"Filename"} = filename;
                imginfo{"pixSize"} = pixSize;
                imginfo{"Format"} = 'bdv.hdf5';

                % Get number of pyramid levels
                noLevels = numel(info.Groups(offsetIndex).Groups(1).Groups);

                % Select pyramid level
                if isfield(options, 'level')
                    if options.level(1) < 1 || options.level(1) > noLevels
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        error('HDF5HeaderLoader:loadBigDataViewerFormat:InvalidLevel', ...
                            'The level value (%d) is out of range! It should be between 1 and %d', ...
                            options.level, noLevels);
                    end
                    imginfo{"ReturnedLevel"} = options.level;
                else
                    prompt = sprintf('The dataset contains %d images\nchoose the one to take\n(enter 1 to get image in the original size):', noLevels);
                    dlgOptions.Type = 'spinner';
                    dlgOptions.WindowHeight = 140;
                    dlgOptions.mibPath = obj.Options.mibPath;
                    defAns = struct('Value', 1, 'Limits', [1 noLevels], 'Step', 1, 'Round', true, 'ValueDisplayFormat', '%d');
                    level = utils.dlgs.inputSingleDlg(obj.Options.ParentFigure, prompt, defAns, 'Select image', dlgOptions);
                    if isempty(level)
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        return;
                    end

                    imginfo{"ReturnedLevel"} = level;
                    if imginfo{"ReturnedLevel"} < 1 || imginfo{"ReturnedLevel"} > noLevels
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        error('HDF5HeaderLoader:loadBigDataViewerFormat:InvalidLevel', ...
                            'Wrong number! The number should be between 1 and %d', noLevels);
                    end
                end

                % Get dimensions
                xyzVal = info.Groups(offsetIndex).Groups(1).Groups(imginfo{"ReturnedLevel"}).Datasets.Dataspace.Size;
                imginfo{"Height"} = xyzVal(2);
                imginfo{"Width"} = xyzVal(1);
                imginfo{"Depth"} = xyzVal(3);
                imginfo{"Levels"} = noLevels;

                if imginfo{"Time"} == 0; imginfo{"Time"} = 1; end

                % Detect data type
                dataType = info.Groups(offsetIndex).Groups(1).Groups(imginfo{"ReturnedLevel"}).Datasets.Datatype.Type;
                switch dataType
                    case {'H5T_STD_I16LE', 'H5T_STD_U16LE'}
                        imginfo{"imgClass"} = 'uint16';
                    case {'H5T_STD_I8LE', 'H5T_STD_U8LE'}
                        imginfo{"imgClass"} = 'uint8';
                    otherwise
                        if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                        error('HDF5HeaderLoader:loadBigDataViewerFormat:UnsupportedDataType', ...
                            'Unsupported image class (%s)! Please implement.', dataType);
                end
            end

            % Get data type for later typecast
            dataType = info.Groups(offsetIndex).Groups(1).Groups(imginfo{"ReturnedLevel"}).Datasets.Datatype.Type;

            % Define region to load
            % X coordinates (width)
            if isfield(options, 'x')
                if options.x(1) < 1 || options.x(1) > imginfo{"Width"} || ...
                   options.x(2) < 1 || options.x(2) > imginfo{"Width"}
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    error('HDF5HeaderLoader:loadBigDataViewerFormat:InvalidX', ...
                        'The X value [%d:%d] is out of range! It should be between 1 and %d', ...
                        options.x(1), options.x(2), imginfo{"Width"});
                end
                x = options.x;
            else
                x = [1 imginfo{"Width"}];
            end

            % Y coordinates (height)
            if isfield(options, 'y')
                if options.y(1) < 1 || options.y(1) > imginfo{"Height"} || ...
                   options.y(2) < 1 || options.y(2) > imginfo{"Height"}
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    error('HDF5HeaderLoader:loadBigDataViewerFormat:InvalidY', ...
                        'The Y value [%d:%d] is out of range! It should be between 1 and %d', ...
                        options.y(1), options.y(2), imginfo{"Height"});
                end
                y = options.y;
            else
                y = [1 imginfo{"Height"}];
            end

            % Z coordinates (depth)
            if isfield(options, 'z')
                if options.z(1) < 1 || options.z(1) > imginfo{"Depth"} || ...
                   options.z(2) < 1 || options.z(2) > imginfo{"Depth"}
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    error('HDF5HeaderLoader:loadBigDataViewerFormat:InvalidZ', ...
                        'The Z value [%d:%d] is out of range! It should be between 1 and %d', ...
                        options.z(1), options.z(2), imginfo{"Depth"});
                end
                z = options.z;
            else
                z = [1 imginfo{"Depth"}];
            end

            % Color channels
            if isfield(options, 'c')
                if min(options.c) < 1 || max(options.c) > imginfo{"Colors"}
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    error('HDF5HeaderLoader:loadBigDataViewerFormat:InvalidC', ...
                        'The C value is out of range! It should be between 1 and %d', ...
                        imginfo{"Colors"});
                end
                c = options.c;
            else
                c = 1:imginfo{"Colors"};
            end

            % Time points
            if isfield(options, 't')
                if options.t(1) < 1 || options.t(1) > imginfo{"Time"} || ...
                   options.t(2) < 1 || options.t(2) > imginfo{"Time"}
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                    error('HDF5HeaderLoader:loadBigDataViewerFormat:InvalidT', ...
                        'The T value [%d:%d] is out of range! It should be between 1 and %d', ...
                        options.t(1), options.t(2), imginfo{"Time"});
                end
                t = options.t;
            else
                t = [1 imginfo{"Time"}];
            end

            % Calculate dimensions
            width = diff(x) + 1;
            height = diff(y) + 1;
            depth = diff(z) + 1;
            level = imginfo{"ReturnedLevel"};

            % Allocate dataset
            dataset = zeros([width, height, depth, numel(c), diff(t)+1], imginfo{"imgClass"});

            % Update progress dialog
            if ~isempty(wb)
                wb.Indeterminate = 'off';
                wb.Value = 0.05;
                wb.Message = sprintf('Loading HDF5 images\nPlease wait...');
            end

            % Load data
            timeCount = 0;
            for timePnt = t(1):t(2)
                timeIndex = timePnt + offsetIndex - 1;
                timeCount = timeCount + 1;

                % Load each color channel
                for ch = c
                    groupName = info.Groups(timeIndex).Groups(ch).Groups(level).Name;
                    datasetName = info.Groups(timeIndex).Groups(ch).Groups(level).Datasets.Name;
                    datasetPath = [groupName '/' datasetName];
                    % Determine if we need full dataset or can use hyperslab
                    needFullDataset = (x(1) ~= 1) || (x(2) ~= imginfo{"Width"}) || ...
                                      (y(1) ~= 1) || (y(2) ~= imginfo{"Height"}) || ...
                                      (z(1) ~= 1) || (z(2) ~= imginfo{"Depth"});

                    % Strategy 1: Try standard h5read with hyperslab
                    readSuccess = false;
                    try
                        if needFullDataset
                            dummy = h5read(filename, datasetPath, ...
                                [x(1), y(1), z(1)], [width, height, depth]);
                        else
                            dummy = h5read(filename, datasetPath);
                        end
                        readSuccess = true;
                    catch ME1
                        % Strategy 2: If filter error, try reading full dataset then crop
                        if contains(ME1.message, 'H5Z__filter_scaleoffset') || contains(ME1.message, 'filter')
                            try
                                % Read entire dataset (bypasses some filter issues)
                                dummy_full = h5read(filename, datasetPath);
                                % Extract requested region
                                dummy = dummy_full(x(1):x(2), y(1):y(2), z(1):z(2));
                                clear dummy_full;
                                readSuccess = true;
                            catch ME2
                                % Strategy 3: Use low-level API to read full dataset
                                try
                                    fileID = H5F.open(filename, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
                                    datasetID = H5D.open(fileID, datasetPath);

                                    % Read entire dataset using low-level API
                                    dummy_full = H5D.read(datasetID);

                                    H5D.close(datasetID);
                                    H5F.close(fileID);

                                    % HDF5 returns data in [z,y,x] order, permute to [x,y,z]
                                    dummy_full = permute(dummy_full, [3 2 1]);

                                    % Extract requested region
                                    dummy = dummy_full(x(1):x(2), y(1):y(2), z(1):z(2));
                                    clear dummy_full;
                                    readSuccess = true;
                                catch ME3
                                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                                    error('HDF5HeaderLoader:loadBigDataViewerFormat:ReadError', ...
                                        ['Failed to read HDF5 dataset using all strategies.\n' ...
                                         'Dataset: %s\n' ...
                                         'Strategy 1 (h5read hyperslab): %s\n' ...
                                         'Strategy 2 (h5read full + crop): %s\n' ...
                                         'Strategy 3 (H5D.read full + crop): %s'], ...
                                        datasetPath, ME1.message, ME2.message, ME3.message);
                                end
                            end
                        else
                            % Re-throw if not a filter error
                            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
                            rethrow(ME1);
                        end
                    end

                    % Typecast if necessary
                    switch dataType
                        case 'H5T_STD_U16LE'
                        case 'H5T_STD_U8LE'
                        case 'H5T_STD_I16LE'
                            dummy2 = typecast(dummy(:), 'uint16');
                            dummy = reshape(dummy2, size(dummy));
                        case 'H5T_STD_I8LE'
                            dummy2 = typecast(dummy(:), 'uint8');
                            dummy = reshape(dummy2, size(dummy));
                    end

                    dataset(:, :, :, ch, timePnt) = dummy;
                end

                % Update progress
                if ~isempty(wb)
                    wb.Value = (timePnt - t(1)) / (diff(t) + 1);
                end
            end

            % Permute to MIB dimension order [y, x, z, c, t]
            img = permute(dataset, [2 1 3 4 5]);

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
        end
    end
end
