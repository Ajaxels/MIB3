classdef MibImgLoader < io.loaders.BaseImageLoader
    % classdef MibImgLoader
    % Loader for mibImg files (MAT-files with specific structure), based on
    % io.loaders.BaseImageLoader base class
    %
    % This loader handles .mibImg files which are standard MATLAB .mat files
    % containing a 'res' structure with image data and metadata.

    methods
        function obj = MibImgLoader(options)
            % function obj = MibImgLoader(options)
            % Constructor for MibImgLoader class
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
            %   obj: instance of the MibImgLoader class
            %
            % Example:
            %   @code
            %   options.waitbar = true;
            %   loader = io.loaders.MibImgLoader(options);
            %   @endcode

            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options)
            % function [imginfo, files] = loadMetadata(obj, filenames, options)
            % Load metadata for mibImg files
            %
            % This method inspects .mibImg (MAT) files to extract dataset metadata.
            % It reads the 'res' structure to determine dimensions, data type, and
            % dimension ordering.
            %
            % Parameters:
            %   filenames: cell array with filenames of mibImg files
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
            %   loader = io.loaders.MibImgLoader();
            %   filenames = {'dataset.mibImg'};
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
                    'Message', sprintf('Loading mibImg metadata\n(press Cancel when metadata is the same for all files)'), ...
                    'Cancelable', 'on');
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', [], ...
                'dim_xyczt', []);

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error in io.loaders.MibImgLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists', 'Error in io.loaders.MibImgLoader');
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
                files(fnIndex).objecttype = 'mibImg';

                % Read mibImg (MAT file) content
                try
                    % Use matfile for efficient partial loading if possible 
                    resObj = matfile(files(fnIndex).filename);
                    % We need to check structure contents without loading everything if possible
                    % Legacy code: res2 = load(files(fn_index).filename, 'options', '-mat');

                    % Load 'options' field to get dimension order
                    fileOpts = resObj.options; 
                    if isempty(fileOpts)
                        if options.waitbar; delete(wb); end
                        utils.dlgs.showErrorDialog(options.parentGUI, ...
                            sprintf('Error in io.loaders.MibImgLoader!\n\nInvalid mibImg file:\n%s\n\nmissing options structure', files(fnIndex).filename), ...
                            'Missing options field', 'Error in io.loaders.MibImgLoader');
                        imginfo = dictionary();
                        return;
                    end

                    dimOrder = fileOpts.dimOrder; % e.g., 'yxzct'
                    hDim = find(dimOrder == 'y');
                    wDim = find(dimOrder == 'x');
                    zDim = find(dimOrder == 'z');
                    cDim = find(dimOrder == 'c');
                    tDim = find(dimOrder == 't');
                    
                    % it seems that MIB2 does not correctly
                    % saves res.options.dimOrder, at least for images C-channel encodes Z
                    if size(resObj.(resObj.imgVariable), cDim) > 5
                        % most likely z and c channel swapped
                        cDim = find(dimOrder == 'z');
                        zDim = find(dimOrder == 'c');
                    end

                    files(fnIndex).height = size(resObj.(resObj.imgVariable), hDim);
                    files(fnIndex).width = size(resObj.(resObj.imgVariable), wDim);
                    files(fnIndex).noLayers = size(resObj.(resObj.imgVariable), zDim);
                    files(fnIndex).color = size(resObj.(resObj.imgVariable), cDim);
                    files(fnIndex).time = size(resObj.(resObj.imgVariable), tDim);
                    files(fnIndex).imgClass = class(resObj.(resObj.imgVariable));
                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error reading mibImg file:\n%s', err.message), 'mibImg Error', 'Error in io.loaders.MibImgLoader');
                    imginfo = dictionary();
                    return;
                end

                % Metadata for first file
                if fnIndex == 1
                    imginfo{'imgClass'} = files(fnIndex).imgClass;
                    if files(fnIndex).color > 1
                        imginfo{'ColorType'} = 'multichannel';
                    else
                        imginfo{'ColorType'} = 'grayscale';
                    end
                    imginfo{'ImageDescription'} = ''; 
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
            % Load image data from mibImg files
            %
            % This method loads the 'res' structure and extracts the image data,
            % handling dimension permutation if necessary (to ensure YXCZT order).
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

            if maxZ == 0; return; end

            % Prepare image class
            imgClass = files(1).imgClass;

            % Pre-allocate image array: [Y, X, Z, C, T]
            img = zeros(height, width, maxZ, color, time, imgClass);

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            layerId = 1;
            noFiles = numel(files);

            % Initialize uiprogressdlg
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Loading mibImg images...',...
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

                % Load mibImg data
                try
                    res = load(files(fnIndex).filename, '-mat');

                    % Check dimension order and permute if needed
                    if isfield(res, 'options') && isfield(res.options, 'dimOrder')
                        dimOrder = res.options.dimOrder;

                        hDim = find(dimOrder == 'y');
                        wDim = find(dimOrder == 'x');
                        zDim = find(dimOrder == 'z');
                        cDim = find(dimOrder == 'c');
                        tDim = find(dimOrder == 't');
                        
                        if hDim~=1 || wDim~=2 || zDim~=3 || cDim~=4 || tDim~=5
                            if size(res.(res.imgVariable), cDim) < 6
                                % it seems that MIB2 does not correctly
                                % saves res.options.dimOrder, at least for images C-channel encodes Z
                                % Permute to YXZCT
                                res.(res.imgVariable) = permute(res.(res.imgVariable), [hDim wDim zDim cDim tDim]);
                            end
                        end
                    end

                    % Assign data
                    img(1:maxY, 1:maxX, layerId:layerId+files(fnIndex).noLayers-1, 1:maxC, 1) = ...
                        res.(res.imgVariable);

                catch err
                    if options.waitbar; delete(wb); end
                     utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error loading mibImg file:\n%s', err.message), 'mibImg Error', 'Error in io.loaders.MibImgLoader');
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