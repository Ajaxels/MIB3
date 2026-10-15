classdef ImageConverter < handle
    % @type ImageConverter class is a template class for using with
    % GUI developed using appdesigner of Matlab
    %
    % @code
    % obj.startController('ImageConverter'); // as GUI tool
    % @endcode
    % or 
    % @code 
    % // a code below was used for mibImageArithmeticController
    % BatchOpt.Parameter = 'test';  // fill edit boxes as strings
    % BatchOpt.Checkbox = true;     // fill checkboxes with logicals: true/false
    % BatchOpt.Popup = {'value'};        // value for the popups as a cell
    % BatchOpt.Radio = {'Radio1'};          // selection of radio buttons, as cell with the handle of the target radio button
    % BatchOpt.showWaitbar = true;  // show or not the waitbar
    % obj.startController('ImageConverter', [], BatchOpt); // start ImageConverter in the batch mode
    % @endcode
    % or
    % @code
    % // trigger return of the possible Options using returnBatchOpt function
    % // using notify SyncBatch event
    % obj.startController('ImageConverter', [], NaN);
    % @endcode
    
	% Updates
	% 
    
    properties
        mibModel
        % handles to mibModel
        view
        % handle to the view / ImageConverterGUI
        listener
        % a cell array with handles to listeners
        BatchOpt
        % a structure compatible with batch operation
        % name of each field should be displayed in a tooltip of GUI
        % it is recommended that the Tags of widgets match the name of the
        % fields in this structure
        % .Parameter - [editbox], char/string 
        % .Checkbox - [checkbox], logical value true or false
        % .Dropdown{1} - [dropdown],  cell string for the dropdown
        % .Dropdown{2} - [optional], an array with possible options
        % .Radio - [radiobuttons], cell string 'Radio1' or 'Radio2'...
        % .ParameterNumeric{1} - [numeric editbox], cell with a number 
        % .ParameterNumeric{2} - [optional], vector with limits [min, max]
        % .ParameterNumeric{3} - [optional], string 'on' - to round the value, 'off' to do not round the value
    end
    
    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end
    
    methods (Static)
%         function ViewListner_Callback(obj, src, evnt)
%             switch evnt.EventName
%                 case {'updateGuiWidgets'}
%                     obj.updateWidgets();
%             end
%         end
        
        function imOut = getPNGwithoutColormap(fn)
            % read PNG files omitting the colormap
            imOut = imread(fn);
        end

        function generatePyramidalTIF(data, writeInfo, outputType, levelsVec, compression, wb)
            % function generatePyramidalTIF(data, writeInfo, outputType, levelsVec)
            % generate pyramidal TIF file
            % 
            % Parameters:
            % data: an image at 100% magnification
            % writeInfo: an object of type matlab.io.datastore.WriteInfo with fields
            %   .ReadInfo - a structure with read-file info including Filename, FileSize and Label fields
            %   .SuggestedOutputName - a string with suggested full output path and filename
            %   .Location - a string with location path
            % outputType: a sting with the output format to be written to
            % levelsVec: a vector with levels to be exported, for example [1, 2, 3, 4]
            % compression: compression for the output images, a string one
            % of these: 
            %   - 'LZW' -	Lempel-Ziv-Welch lossless compression
            %   - 'PackBits	PackBits lossless compression
            %   - 'Deflate'	Adobe DEFLATE lossless compression
            %   - 'JPEG'	JPEG-based lossy compression
            %   - 'None'	No compression
            
            % fix writeInfo.SuggestedOutputName
            [pathOut, filenameOut] = fileparts(writeInfo.SuggestedOutputName);
            writeInfo.SuggestedOutputName = fullfile(pathOut, [char(filenameOut) '.tif']);

            % Efficient way to create a pyramid
            for levelId=1:numel(levelsVec)
                if levelId == 1
                    if levelsVec(1) == 1
                        bim{1} = blockedImage(data); 
                    else
                        scaleFactor = 1/2^(levelsVec(1)-1);
                        bim{1} = blockedImage(data).apply(@(bigimg)ImageConverter.resizeBlocks(bigimg, scaleFactor), 'DisplayWaitbar', false);
                    end
                else
                    scaleFactor = 1/2^(levelsVec(levelId) - levelsVec(levelId-1));
                    bim{levelId} = bim{levelId-1}.apply(@(bigimg)ImageConverter.resizeBlocks(bigimg, scaleFactor), 'DisplayWaitbar', false);
                end
            end
            
            writeAdapter = images.blocked.TIFF(); % Specify the TIFF adapter
            writeAdapter.Extension = 'tif';
            switch compression
                case 'None'
                    writeAdapter.Compression = Tiff.Compression.None; 
                case 'LZW'
                    writeAdapter.Compression = Tiff.Compression.LZW; 
                case 'PackBits' %	PackBits lossless compression
                    writeAdapter.Compression = Tiff.Compression.PackBits; 
                case 'Deflate'  %	Adobe DEFLATE lossless compression
                    writeAdapter.Compression = Tiff.Compression.Deflate; 
                case 'JPEG'     %	JPEG-based lossy compression
                    writeAdapter.Compression = Tiff.Compression.JPEG; 
            end

            write(bim{1}, writeInfo.SuggestedOutputName, ...
                'LevelImages', [bim{2:end}], ...
                "BlockSize", [2048 2048], ...
                "Adapter", writeAdapter, ...
                'DisplayWaitbar',false);
            if nargin > 5 && ~isempty(wb)
                wb.increment();
                if wb.getCancelState()
                    error('ImageConverter:Cancelled', 'Cancelled by user');
                end
            end
       end

        function blockedImageOut = resizeBlocks(blockedImageIn, scaleFactor)
            % function bigImageOut = resizeBlocks(bigImageIn, scaleFactor)
            % resize blockedImage (blockedImageIn) using privided scale
            % factor (scaleFactor)
            blockedImageOut = imresize(blockedImageIn.Data, scaleFactor, 'bicubic');
        end


        function processZChunk(idx, zStarts, zChunk, maxZ, imageSwitch, ...
                imageSize, imageType, imgDS, ...
                levelNames, scaleZYX, zarrPath)

            % Python imports
            pyrun(["import zarr", "import numpy as np"]);

            % allocate space for a zChunk
            zStart = zStarts(idx);
            zEnd = min(zStart + zChunk - 1, maxZ);
            if imageSwitch
                subvol = zeros([1, imageSize(2), zEnd-zStart+1, imageSize(end-1), imageSize(end)], imageType);
                for i = zStart:zEnd
                    subvol(:, :, i-zStart+1, :, :) = permute(imgDS.readimage(i), [5, 3, 4, 1, 2]); % [y,x,c]->[t,c,z,y,x]
                end
            else
                subvol = zeros([1, zEnd-zStart+1, imageSize(end-1), imageSize(end)], imageType);
                for i = zStart:zEnd
                    subvol(:, i-zStart+1, :, :) = permute(imgDS.readimage(i), [4, 3, 1, 2]); % [y,x,c]->[t,z,y,x]
                end
            end

            % Cascaded downsampling
            for lvl = 1:numel(levelNames)
                if lvl > 1
                    rel = scaleZYX(lvl,:) ./ scaleZYX(lvl-1,:);
                    subvol = ImageConverter.downsampleBlock(subvol, rel, imageSwitch);
                end

                % Z offset
                zOutStart = floor((zStart-1)/scaleZYX(lvl,1)) + 1;
                ImageConverter.writeSubvolumeToLevel(subvol, zarrPath, levelNames{lvl}, 1, zOutStart, imageSwitch);
            end
        end

        function out = downsampleBlock(chunkData, relFactors, imageSwitch)
            % DOWNSAMPLEBLOCK - downsample a 5D block ([T C Z Y X]) by relative factors.
            %
            % Input Arguments:
            %   - **chunkData** - numeric array ``[T C Z Y X]``, input block to downsample
            %   - **relFactors** - ``1x3`` numeric array, relative downsampling factors ``[Z_factor Y_factor X_factor]``
            %   - **imageSwitch** - logical; ``true`` for image ``[t,c,z,y,x]``, ``false`` for labels ``[t,z,y,x]``
            %
            % Output Arguments:
            %   - **out** - numeric array ``[T C newZ newY newX]``, downsampled block, same class as input
            arguments
                chunkData {mustBeNumeric}
                relFactors (1,3) {mustBePositive, mustBeFinite}
                imageSwitch logical = true
            end

            chunkSize = size(chunkData);
            Z = chunkSize(end-2);
            Y = chunkSize(end-1);
            X = chunkSize(end);
            T = chunkSize(1);

            newZ = max(floor(Z / relFactors(1)), 1);
            newY = max(floor(Y / relFactors(2)), 1);
            newX = max(floor(X / relFactors(3)), 1);

            % Choose interpolation method
            interpMethod = 'cubic';
            if ~imageSwitch % labels
                interpMethod = 'nearest';
            end

            if imageSwitch  % images
                C = chunkSize(2);
                out = zeros([T, C, newZ, newY, newX], class(chunkData));
                % Downsample each time point and channel separately
                if newZ > 1 % 3D chunkData
                    for t = 1:T
                        for c = 1:C
                            out(t,c,:,:,:) = imresize3(squeeze(chunkData(t,c,:,:,:)), [newZ, newY, newX], interpMethod);
                        end
                    end
                else % 2D block
                    for t = 1:T
                        for c = 1:C
                            out(t,c,:,:,:) = imresize(squeeze(chunkData(t,c,1,:,:)), [newY, newX], interpMethod);
                        end
                    end
                end
            else        % labels
                out = zeros([T, newZ, newY, newX], class(chunkData));
                % Downsample each time point and channel separately
                if newZ > 1 % 3D chunkData
                    for t = 1:T
                        out(t,:,:,:) = imresize3(squeeze(chunkData(t,:,:,:)), [newZ, newY, newX], interpMethod);
                    end
                else
                    for t = 1:T
                        out(t,:,:,:) = imresize(squeeze(chunkData(t,1,:,:)), [newY, newX], interpMethod);
                    end
                end
            end
        end

        function writeSubvolumeToLevel(block_tczyx, zarrPath, levelName, tIndex, zStart, imageSwitch)
            % WRITESUBVOLUMETOLEVEL - write a 5D subvolume to a specified Zarr multiscale level.
            %
            % Input Arguments:
            %   - **block_tczyx** - numeric array ``[T C Z Y X]``, the subvolume to write
            %   - **zarrPath** - [char] path to the root Zarr store
            %   - **levelName** - [char] name of the multiscale level (e.g., ``'s0'``, ``'s1'``)
            %   - **tIndex** - time index (1-based) in the Zarr dataset
            %   - **zStart** - starting Z index (1-based) in the Zarr dataset
            %   - **imageSwitch** - logical; ``true`` for image ``[t,c,z,y,x]``, ``false`` for labels ``[t,z,y,x]``
            arguments
                block_tczyx {mustBeNumeric}
                zarrPath (1,:) char
                levelName (1,:) char
                tIndex (1,1) {mustBeInteger, mustBePositive}
                zStart (1,1) {mustBeInteger, mustBeNonnegative}
                imageSwitch logical = true
            end

            storePath = fullfile(zarrPath, levelName);

            if imageSwitch  % images
                [T, C, Z, Y, X] = size(block_tczyx);
                pyrun(...
                    "arr=zarr.open(storePath, mode='r+');"+...
                    "arr[t0:t0+1, 0:C, z0:z0+Z, 0:Y, 0:X] = block", ...
                    storePath=storePath, block=block_tczyx, ...
                    t0=int32(tIndex-1), C=int32(C), Z=int32(Z), Y=int32(Y), X=int32(X), z0=int32(zStart-1));
            else            % labels
                [T, Z, Y, X] = size(block_tczyx);
                pyrun(...
                    "arr=zarr.open(storePath, mode='r+');"+...
                    "arr[t0:t0+1, z0:z0+Z, 0:Y, 0:X] = block", ...
                    storePath=storePath, block=block_tczyx, ...
                    t0=int32(tIndex-1), Z=int32(Z), Y=int32(Y), X=int32(X), z0=int32(zStart-1));
            end
        end

        function [levelNames, scaleFactors, levelImageTranslations, levelImageSizes] = calculateMultiscaleLevels(imageSize, voxelSize, minImageSize)
            % CALCULATEMULTISCALELEVELS - calculate multiscale levels and cumulative downsampling factors.
            %
            % First step: downsample high-resolution axes to make voxels isotropic.
            % Subsequent steps: uniform 2x downsampling until any dimension reaches ``minImageSize``.
            %
            % Input Arguments:
            %   - **imageSize** - ``[z y x]`` numeric array
            %   - **voxelSize** - ``[z y x]`` numeric array
            %   - **minImageSize** - ``[z y x]`` numeric array
            %
            % Output Arguments:
            %   - **levelNames** - ``{'s0','s1',...}``
            %   - **scaleFactors** - ``nLevels x 3`` cumulative per-axis downsampling factors
            %   - **levelImageTranslations** - ``nLevels x 3`` physical translation offsets relative to s0
            %   - **levelImageSizes** - ``nLevels x 3`` image sizes at each level
            arguments
                imageSize (1,3) {mustBeInteger, mustBePositive}
                voxelSize (1,3) {mustBePositive}
                minImageSize (1,3) {mustBeInteger, mustBePositive}
            end

            levelNames   = {'s0'};
            scaleFactors = ones(1,3);      % cumulative downsampling relative to original
            levelImageSizes   = imageSize;      % size at each level
            levelImageTranslations = zeros(1,3);     % physical offsets relative to s0

            currentSize    = imageSize;
            currentVoxel   = voxelSize;
            cumulativeFactor = ones(1,3);
            currentTranslation = zeros(1,3);

            % --- Step 1: isotropic voxel adjustment ---
            factor   = ones(1,3);
            maxVoxel = max(currentVoxel);
            for dim = 1:3
                if currentVoxel(dim) < maxVoxel
                    factor(dim) = 2;
                end
            end

            % compute translation offset from rounding
            offsetVoxels = (mod(currentSize, factor) ~= 0) .* 0.5 .* voxelSize .* cumulativeFactor;
            currentTranslation = currentTranslation + offsetVoxels;

            currentSize    = ceil(currentSize ./ factor);
            currentVoxel   = currentVoxel .* factor; %#ok<NASGU>
            cumulativeFactor = cumulativeFactor .* factor;

            levelNames{end+1}      = 's1';
            scaleFactors(end+1,:)  = cumulativeFactor;
            levelImageSizes(end+1,:)    = currentSize;
            levelImageTranslations(end+1,:)  = currentTranslation;

            % --- Step 2: uniform downsampling ---
            lvl = 2;
            while all(currentSize > minImageSize)
                factor = ones(1,3);
                for dim = 1:3
                    if currentSize(dim) > minImageSize(dim)
                        factor(dim) = 2;
                    end
                end

                % Stop if any dimension would go below minImageSize
                if any(currentSize ./ factor < minImageSize)
                    break;
                end

                % compute translation offset from rounding
                offsetVoxels = (mod(currentSize, factor) ~= 0) .* 0.5 .* voxelSize .* cumulativeFactor;
                currentTranslation = currentTranslation + offsetVoxels;

                currentSize    = ceil(currentSize ./ factor);
                currentVoxel   = currentVoxel .* factor; %#ok<NASGU>
                cumulativeFactor = cumulativeFactor .* factor;

                levelNames{end+1}      = sprintf('s%d', lvl);
                scaleFactors(end+1,:)  = cumulativeFactor;
                levelImageTranslations(end+1,:)  = currentTranslation;
                levelImageSizes(end+1,:)    = currentSize;

                lvl = lvl + 1;
            end
        end

        function createMultiscaleDataset(zarrPath, imageSize, imageType, levelNames, scaleXYZ, Options)
            % CREATEMULTISCALEDATASET - creates a multiscale OME-Zarr dataset including arrays and metadata.
            %
            % Input Arguments:
            %   - **zarrPath** - [char] path to the top-level Zarr folder
            %   - **imageSize** - integer ``[T, C, Z, Y, X]`` size of the original image
            %   - **imageType** - [char] data type of the image (e.g., ``'uint8'``, ``'float32'``)
            %   - **levelNames** - cell array of strings, names of the multiscale levels, e.g. ``{'s0','s1','s2'}``
            %   - **scaleXYZ** - ``[nLevels x 3]`` array of scale factors ``[Z Y X]``
            %   - **Options** - struct with additional options:
            %
            %     - ``.chunks`` - chunk size for each dimension as ``[T, C, Z, Y, X]``
            %     - ``.compressionType`` - [char] ``'blosc'``, ``'gzip'``, ``'none'``
            %     - ``.compressionLevel`` - numeric compression level (0=none, 9=best, -1=default)
            %     - ``.zarrFormat`` - int, 2 or 3 (default: 2)
            %     - ``.dataType`` - [char] ``'image'`` (``[T,C,Z,Y,X]``) or ``'labels'`` (``[T,Z,Y,X]``)
            %     - ``.shards`` - ``[t c z y x]`` sharding sizes (default: ``[]``), Zarr v3 only
            %     - ``.voxelSize`` - ``[1x3]`` physical voxel size along ``[Z Y X]`` (default: ``[1 1 1]``)
            %     - ``.voxelUnits`` - [char] units of voxel size (``'nanometers'``, ``'micrometers'``, ``'pixels'``, ...)
            %     - ``.levelTranslations`` - ``[nLevels x 3]`` physical translations per level (default: zeros)
            %     - ``.customAttributes`` - struct of extra attributes to add to root.attrs (default: empty)
            arguments
                zarrPath (1,:) char
                imageSize (1,:) double {mustBePositive}
                imageType (1,:) char
                levelNames cell
                scaleXYZ (:,3) double {mustBePositive}
                Options struct = struct()
            end

            % ------------------
            % Defaults
            % ------------------
            if ~isfield(Options,'chunks'), Options.chunks = [1 1 128 128 128]; end
            if ~isfield(Options,'shards'), Options.shards = []; end
            if ~isfield(Options,'zarrFormat'), Options.zarrFormat = 2; end
            if ~isfield(Options,'compressionType'), Options.compressionType = 'gzip'; end
            if ~isfield(Options,'compressionLevel'), Options.compressionLevel = 1; end
            if ~isfield(Options,'dataType'), Options.dataType ='image'; end
            if ~isfield(Options,'voxelSize'), Options.voxelSize = [1 1 1]; end
            if ~isfield(Options,'voxelUnits'), Options.voxelUnits = 'micrometers'; end
            if ~isfield(Options,'levelTranslations'), Options.levelTranslations = zeros(size(scaleXYZ)); end
            if ~isfield(Options,'customAttributes'), Options.customAttributes = struct(); end

            % replace slashes
            zarrPath = strrep(zarrPath,'\','/');
            % make new folder for the zarr output
            if ~isfolder(zarrPath), mkdir(zarrPath); end

            % ------------------
            % Compressor setup
            % ------------------
            pyrun("compressors = None");
            if ~strcmpi(Options.compressionType,'none')
                if Options.zarrFormat == 2
                    pyrun("import numcodecs");
                    switch lower(Options.compressionType)
                        case 'gzip'
                            pyrun("compressors = numcodecs.GZip(level=Options_clevel)", ...
                                Options_clevel=int32(Options.compressionLevel));
                        case 'blosc'
                            pyrun("compressors = numcodecs.Blosc(cname='zstd', clevel=Options_clevel, shuffle=numcodecs.Blosc.BITSHUFFLE)", ...
                                Options_clevel=int32(Options.compressionLevel));
                        otherwise
                            error('Unsupported compression type: %s', Options.compressionType);
                    end
                elseif Options.zarrFormat == 3
                    switch lower(Options.compressionType)
                        case 'gzip'
                            pyrun("from numcodecs import GZip");
                            pyrun("compressors = GZip(level=Options_clevel)", ...
                                Options_clevel=int32(Options.compressionLevel));
                        case 'blosc'
                            pyrun("from zarr.codecs import BloscCodec");
                            pyrun("compressors = BloscCodec(cname='zstd', clevel=Options_clevel, shuffle='bitshuffle')", ...
                                Options_clevel=int32(Options.compressionLevel));
                        otherwise
                            error('Unsupported compression type: %s', Options.compressionType);
                    end
                end
            end

            % ------------------
            % Create arrays + dataset metadata
            % ------------------
            datasets = [];
            for lvl = 1:numel(levelNames)
                % Compute level shape
                szLvl = max(ceil(imageSize(end-2:end) ./ scaleXYZ(lvl,:)),1);
                if strcmp(Options.dataType,'image')
                    imageShape = [imageSize(1), imageSize(2), szLvl];
                else
                    imageShape = [imageSize(1), szLvl];
                end

                storePath = fullfile(zarrPath, levelNames{lvl});

                if Options.zarrFormat == 2
                    % use open_array function as create_array is not comatible with
                    % dimension_separator parameter
                    % shape/chunks must be plain tuples: zarr-python's array
                    % creation does a bare "if chunks:" truthiness check, which
                    % raises "truth value of an array... is ambiguous" if a
                    % multi-element numpy array (what int32(...) becomes on the
                    % Python side) is passed instead.
                    pyrun("zarr.open_array(store=store, shape=tuple(imageShape), chunks=tuple(imageChunks), dtype=dtype, compressor=compressors, zarr_format=2, dimension_separator='/', mode='w')", ...
                        store=storePath, imageShape=int32(imageShape), imageChunks=int32(Options.chunks), dtype=imageType);
                    versionText = '0.4';
                elseif Options.zarrFormat == 3
                    if ~isempty(Options.shards)
                        pyrun("zarr.create_array(store=store, shape=tuple(imageShape), chunks=tuple(imageChunks), dtype=dtype, compressors=compressors, zarr_format=zarrFormat, shards=tuple(shards))", ...
                            store=storePath, imageShape=int32(imageShape), imageChunks=int32(Options.chunks), dtype=imageType, ...
                            zarrFormat=int32(Options.zarrFormat), shards=int32(Options.shards));
                    else
                        pyrun("zarr.create_array(store=store, shape=tuple(imageShape), chunks=tuple(imageChunks), dtype=dtype, compressors=compressors, zarr_format=zarrFormat)", ...
                            store=storePath, imageShape=int32(imageShape), imageChunks=int32(Options.chunks), dtype=imageType, ...
                            zarrFormat=int32(Options.zarrFormat));
                    end
                    versionText = '0.5';
                else
                    error('Unsupported zarr format type: %d', Options.zarrFormat);
                end

                % Metadata entry for this level
                scale       = Options.voxelSize .* scaleXYZ(lvl,:);   % physical voxel size
                translation = Options.levelTranslations(lvl,:);       % physical shift
                datasets = [datasets, struct( ...
                    'path', levelNames{lvl}, ...
                    'coordinateTransformations', { { ...
                        struct('type','scale','scale',scale), ...
                        struct('type','translation','translation',translation) ...
                    } } ...
                )]; %#ok<AGROW>
            end

            % ------------------
            % Root attributes
            % ------------------

            % Axes: include T,C if present
            if strcmp(Options.dataType,'image')
                axesList = { ...
                    struct('type','time','name','t','unit','seconds'), ...
                    struct('type','channel','name','c','unit',''), ...
                    struct('type','space','name','z','unit',Options.voxelUnits), ...
                    struct('type','space','name','y','unit',Options.voxelUnits), ...
                    struct('type','space','name','x','unit',Options.voxelUnits) ...
                };
            else
                axesList = { ...
                    struct('type','time','name','t','unit','seconds'), ...
                    struct('type','space','name','z','unit',Options.voxelUnits), ...
                    struct('type','space','name','y','unit',Options.voxelUnits), ...
                    struct('type','space','name','x','unit',Options.voxelUnits) ...
                };
            end

            zattrs_struct = struct( ...
                'multiscales', { { ...
                    struct( ...
                        'name', '', ...
                        'type', Options.dataType, ...
                        'version', versionText , ...
                        'axes', {axesList}, ...
                        'datasets', {datasets}, ...
                        'coordinateTransformations', {{} } ...
                    ) } } ...
            );

            % Merge custom attributes
            customFields = fieldnames(Options.customAttributes);
            for k = 1:numel(customFields)
                fn = customFields{k};
                zattrs_struct.(fn) = Options.customAttributes.(fn);
            end

            % Encode as JSON for Python
            zattrs_json = jsonencode(zattrs_struct);

            % Write to root.attrs using zarr API with explicit zarr_format
            if Options.zarrFormat == 2
                pyrun([ ...
                    "root = zarr.open_group(storePath, mode='a', zarr_format=2)" ...
                    "root.attrs.update(json.loads(attrs_json))" ...
                    ], ...
                    storePath=zarrPath, ...
                    attrs_json=zattrs_json);
            else
                pyrun([ ...
                    "root = zarr.open_group(storePath, mode='a', zarr_format=3)" ...
                    "root.attrs.update(json.loads(attrs_json))" ...
                    ], ...
                    storePath=zarrPath, ...
                    attrs_json=zattrs_json);
            end
        end

        function img = readWithLoader(loader, filename, options)
            % Read a single image file via a MIB3 loader instance
            % Returns image squeezed from MIB5D [H,W,Z,C,T] to remove singletons
            [imginfo, files] = loader.loadMetadata({filename}, options);
            if ~isa(imginfo, 'dictionary') || ~isKey(imginfo, 'Height')
                img = zeros(1, 1, 'uint8');
                return;
            end
            loadOptions = options;
            loadOptions.waitbar = false;
            [img, ~] = loader.loadImages(files, imginfo, loadOptions);
            img = squeeze(img);
        end

        function writeImageWithProgress(data, writeInfo, outputFormat, wb)
            % Write image to disk and update waitbar; throw cancel signal if requested
            % outputFormat: target extension string, e.g. 'tif', 'png', 'jpg'
            [pathOut, nameOut, ~] = fileparts(writeInfo.SuggestedOutputName);
            outputFilename = fullfile(pathOut, [nameOut '.' outputFormat]);
            imwrite(data, outputFilename);
            if ~isempty(wb)
                wb.increment();
                if wb.getCancelState()
                    error('ImageConverter:Cancelled', 'Cancelled by user');
                end
            end
        end

        function geometry = readSourceGeometry(filenames, loaderOptions)
            % READSOURCEGEOMETRY - Voxel size, origin and units of a source stack from its MIB bounding box.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      geometry = ImageConverter.readSourceGeometry(filenames)
            %      geometry = ImageConverter.readSourceGeometry(filenames, loaderOptions)
            %
            % Reads the metadata (not the pixels) of the first file, and of the last one
            % for a sequence of 2D files, through MIB's standard loaders. The bounding box
            % is taken from a numeric ``BoundingBox`` metadata key or parsed from the
            % ``BoundingBox`` entry MIB writes into ``ImageDescription``: TIF description
            % tag, AmiraMesh header, HDF5 XML header. Bounding boxes span voxel centres
            % (``max = min + (n-1)*voxel``), so:
            %
            %   - **X/Y voxel** - box extent / (width-1) of the first file; the loader
            %     ``pixSize`` when the axis is 1 voxel wide
            %   - **Z voxel**, first file is a volume - its box Z extent / (depth-1)
            %   - **Z voxel**, sequence of 2D files (one Z slice per file, as the zarr
            %     output treats them):
            %
            %     - the last file starts at a different Z (a box per slice) -
            %       (last zmin - first zmin) / (numberOfFiles-1)
            %     - every file repeats one box spanning the stack (what MIB writes when
            %       it saves a stack as a 2D sequence) - its Z extent / (numberOfFiles-1)
            %     - otherwise, or for a single file, the loader ``pixSize.z``
            %
            %   - **origin** - the first file's ``[xmin ymin zmin]``
            %
            % A file without a MIB bounding box (e.g. a TIF from another program) gives
            % an empty result, so callers keep what the user typed.
            %
            % Input Arguments:
            %   - **filenames** - cellstr of source files in conversion order
            %   - **loaderOptions** - *(optional)* struct passed to the loader;
            %     default: silent, no waitbar
            %
            % Output Arguments:
            %   - **geometry** - struct, or ``[]`` when the first file has no bounding box:
            %
            %     - ``.voxelSizeXYZ`` - [1x3 double]
            %     - ``.originXYZ`` - [1x3 double]
            %     - ``.units`` - [char] ``pixSize.units`` of the first file, e.g. ``'um'``
            %
            % Example:
            %   .. code-block:: matlab
            %
            %      files = {'C:\data\slice_001.tif', 'C:\data\slice_002.tif'};
            %      geometry = ImageConverter.readSourceGeometry(files);

            geometry = [];
            if nargin < 2 || isempty(loaderOptions)
                loaderOptions = struct('waitbar', false, 'silentMode', true, 'verbose', false);
            end
            if ~isfield(loaderOptions, 'ParentFigure'); loaderOptions.ParentFigure = []; end
            if isempty(filenames); return; end

            firstFile = sourceFileGeometry(filenames{1}, loaderOptions);
            if isempty(firstFile) || isempty(firstFile.boundingBox); return; end
            boundingBox = firstFile.boundingBox;

            voxelSize = [firstFile.pixSize.x, firstFile.pixSize.y, firstFile.pixSize.z];
            if firstFile.width > 1; voxelSize(1) = (boundingBox(2) - boundingBox(1)) / (firstFile.width - 1); end
            if firstFile.height > 1; voxelSize(2) = (boundingBox(4) - boundingBox(3)) / (firstFile.height - 1); end

            numberOfFiles = numel(filenames);
            if firstFile.depth > 1
                voxelSize(3) = (boundingBox(6) - boundingBox(5)) / (firstFile.depth - 1);
            elseif numberOfFiles > 1
                lastFile = sourceFileGeometry(filenames{end}, loaderOptions);
                if ~isempty(lastFile) && ~isempty(lastFile.boundingBox) && lastFile.boundingBox(5) ~= boundingBox(5)
                    voxelSize(3) = (lastFile.boundingBox(5) - boundingBox(5)) / (numberOfFiles - 1);
                elseif boundingBox(6) > boundingBox(5)
                    voxelSize(3) = (boundingBox(6) - boundingBox(5)) / (numberOfFiles - 1);
                end
            end

            geometry = struct('voxelSizeXYZ', voxelSize, ...
                'originXYZ', boundingBox([1 3 5]), ...
                'units', firstFile.pixSize.units);
        end

        function proceed = confirmZarrMemory(parentFig, requiredBytes, details)
            % CONFIRMZARRMEMORY - Check the estimated peak memory of a Zarr conversion before it starts.
            %
            % Both Zarr pipelines hold a slab of full-resolution slices (chunk or
            % shard Z deep) in memory, so the requirement grows with the slice size
            % and nothing else bounds it. A conversion that does not fit swaps for
            % days or fails part way, which is how a week-long run ended truncated
            % (development/bigdata/plan_imageconverter_zarr.md).
            %
            % When ``requiredBytes`` exceeds the memory available to MATLAB, the user
            % is asked to continue or cancel; without a window (batch mode) a warning
            % is printed and the conversion goes ahead, because the estimate is
            % approximate and swapping is slow, not wrong. Platforms without
            % ``memory`` (Linux, macOS) are not checked.
            %
            % Input Arguments:
            %   - **parentFig** - figure for the question, ``[]`` in batch mode
            %   - **requiredBytes** - [double] estimated peak memory, bytes
            %   - **details** - [char] what the estimate is made of, shown to the user
            %
            % Output Arguments:
            %   - **proceed** - [logical] ``false`` when the user cancelled
            proceed = true;
            try
                memoryInfo = memory;
                availableBytes = memoryInfo.MemAvailableAllArrays;
            catch
                return;   % memory() exists on Windows only
            end
            if requiredBytes <= availableBytes; return; end

            messageText = sprintf(['The conversion needs about %.1f GB of memory, but only %.1f GB is available ' ...
                '(%s).\n\nIt will be very slow and may fail. Reduce the Z chunk size (and the Z shard factor), ' ...
                'or the number of parallel workers, to need less.'], requiredBytes/1e9, availableBytes/1e9, details);
            if isempty(parentFig)
                warning('ImageConverter:notEnoughMemory', '%s', messageText);
                return;
            end
            choice = uiconfirm(parentFig, messageText, 'Not enough memory', ...
                'Options', {'Continue anyway', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            proceed = strcmp(choice, 'Continue anyway');
        end

        function [fnOut, writeStarted] = convertToZarr3Native(imgDS, BatchOpt, options)
            % CONVERTTOZARR3NATIVE - Convert a folder of image files to a native OME-Zarr pyramid.
            %
            % Streams the image stack in ``imgDS`` (one file per Z-slice) to an OME-Zarr
            % pyramid through ``io.savers.Zarr3Saver.saveStream`` - the same native (zarrMex)
            % writer, level/chunk/shard logic and bounding-box handling used by MIB's in-app
            % "Convert to BigData" and Export. No Python, in either zarr format. The voxel
            % size and the bounding box (from ``ZarrVoxelSizeXYZ`` and ``ZarrBBShiftsXYZ``)
            % go to the saver in its metadata, which writes them for v2 and v3 alike.
            %
            % ``BatchOpt.ZarrVersion`` selects the format; the output folder carries no
            % ``.zarr2``/``.zarr3`` extension to infer it from. Sharding is a v3 feature and
            % is refused when v2 is selected, rather than silently dropped.
            %
            % The store is written by ``Zarr3Saver.saveStreamResumable`` in
            % chunk-aligned Z-slab tasks: level 0 (plus the levels that keep the full
            % Z) slab by slab, then the Z-downsampled levels from the level above.
            % With a pool every worker reads and writes its own slabs, so no slice
            % is sent between processes; without one the tasks run on the client.
            % Every finished task is recorded in the store, so an interrupted
            % conversion can be resumed (``options.resume``) with the same source
            % and settings. The source is identified by the number, the first and
            % last name, the total size and the latest modification time of its
            % files.
            %
            % Memory: a task holds ``2.5 x writeDepth + 2`` rows per row it covers
            % (the slab of every full-Z level and the zarrMex copy), per process,
            % ``writeDepth`` being the chunk Z or, when sharded, the shard Z. When
            % whole slices need more than 80% of the free memory (``memory``,
            % Windows only) and the source can be read in rows (TIFF,
            % ``ImageDatastoreSliceProvider.SupportsRowReads``), the conversion runs
            % in bands of whole chunk (shard) rows of level 0 that fit
            % (``BandHeight``, see ``Zarr3Saver.saveStreamResumable``) - at least one
            % chunk row. The estimate for the chosen slab or band is then checked
            % with ``ImageConverter.confirmZarrMemory``, which still warns when one
            % chunk row is too much, or when the source cannot be read in rows.
            %
            % For labels the material names ``Material 1..N`` come from the largest
            % label value, found while streaming (``MaterialNamesFromData``) rather
            % than in a separate pass over every file.
            %
            % Input Arguments:
            %   - **imgDS** - a ``matlab.io.datastore.ImageDatastore`` of ordered Z-slices.
            %   - **BatchOpt** - the ImageConverter batch struct; reads the ``Zarr*`` fields
            %     (``ZarrVersion``, ``ZarrImageType``, ``ZarrChunkSizes``, ``ZarrUseSharding``,
            %     ``ZarrShardXFactorsXYZ``, ``ZarrCompression``, ``ZarrCompressionLevel``,
            %     ``ZarrVoxelSizeXYZ``, ``ZarrUnits``, ``ZarrBBShiftsXYZ``,
            %     ``ZarrDownsampleLimitXYZ``) and ``OutputDirectory``. ``ZarrVersion`` may
            %     be absent, meaning v3; ``ZarrCompressionLevel`` may be absent, meaning
            %     the codec default.
            %   - **options** - *(optional)* struct with ``.ParentFigure`` (progress and
            %     dialog parent), ``.mibPath``, ``.pool`` (process-based
            %     ``parallel.Pool`` whose workers write the store, ``[]`` = write on
            %     the client) and ``.resume`` (logical, continue the interrupted
            %     conversion in ``OutputDirectory``; raises
            %     ``io:Zarr3Saver:cannotResume`` when it cannot be continued).
            %
            % Output Arguments:
            %   - **fnOut** - [char] the written group path, or ``[]`` if not completed.
            %   - **writeStarted** - [logical] ``false`` when nothing was written (the
            %     memory check was declined), ``true`` once the store was created - an
            %     empty ``fnOut`` then means it was cancelled and is left incomplete.
            if nargin < 3; options = struct(); end
            parentFig = []; mibPath = ''; pool = [];
            writeStarted = false;
            if isfield(options, 'ParentFigure'); parentFig = options.ParentFigure; end
            if isfield(options, 'mibPath');      mibPath   = options.mibPath;      end
            if isfield(options, 'pool');         pool      = options.pool;         end

            zarrPath = BatchOpt.OutputDirectory;
            dataType = BatchOpt.ZarrImageType{1};   % 'image' | 'labels'

            % chunk [y x z] from the (x,y,z,c,t) UI vector
            chunks = str2num(BatchOpt.ZarrChunkSizes); %#ok<ST2NM>
            if numel(chunks) >= 3
                chunkYXZ = [chunks(2) chunks(1) chunks(3)];
            else
                chunkYXZ = [256 256 16];
            end

            % voxel size (x,y,z) + units -> pixSize
            voxel = str2num(BatchOpt.ZarrVoxelSizeXYZ); %#ok<ST2NM>
            if numel(voxel) ~= 3; voxel = [1 1 1]; end
            pixSize = struct('x', voxel(1), 'y', voxel(2), 'z', voxel(3), ...
                'units', BatchOpt.ZarrUnits{1}, 't', 1, 'tunits', 's');

            % bounding-box origin shift (x,y,z)
            bbShift = str2num(BatchOpt.ZarrBBShiftsXYZ); %#ok<ST2NM>
            if numel(bbShift) ~= 3; bbShift = [0 0 0]; end

            % auto-pyramid stop (x,y,z) -> MinLevelSize over XY
            dsLimit = str2num(BatchOpt.ZarrDownsampleLimitXYZ); %#ok<ST2NM>
            if numel(dsLimit) >= 2; minLevelSize = min(dsLimit(1), dsLimit(2)); else; minLevelSize = 256; end

            % compression: blosc -> zstd (native), gzip -> gzip, none -> none
            switch lower(BatchOpt.ZarrCompression{1})
                case 'blosc'; compressors = 'zstd';
                case 'gzip';  compressors = 'gzip';
                otherwise;    compressors = 'none';
            end
            if ~strcmp(compressors, 'none') && isfield(BatchOpt, 'ZarrCompressionLevel') && ...
                    ~isempty(BatchOpt.ZarrCompressionLevel)
                compressors = struct('name', compressors, 'configuration', ...
                    struct('level', BatchOpt.ZarrCompressionLevel{1}));
            end

            % --- slices per write: the chunk Z, or the shard Z when sharded ---
            shardYXZ = [];
            if BatchOpt.ZarrUseSharding
                shard = str2num(BatchOpt.ZarrShardXFactorsXYZ); %#ok<ST2NM>
                if numel(shard) >= 3; shardYXZ = [shard(2) shard(1) shard(3)]; end
            end
            writeDepth = min(chunkYXZ(3), numel(imgDS.Files));
            if ~isempty(shardYXZ); writeDepth = min(writeDepth * max(1, round(shardYXZ(3))), numel(imgDS.Files)); end

            % --- provider over the file stack (one file per Z-slice) ---
            provider = io.savers.ImageDatastoreSliceProvider(imgDS);
            sz = provider.OutputSize;   % [H W D C T]
            H = sz(1); W = sz(2); D = sz(3);

            % --- Zarr3Saver options (silent: ImageConverter already collected settings) ---
            saverOpts = struct();
            saverOpts.silent       = true;
            saverOpts.ChunkSize    = chunkYXZ;
            saverOpts.Compressors  = compressors;
            saverOpts.MinLevelSize = minLevelSize;
            if pixSize.z >= 1.5 * max(pixSize.x, pixSize.y)
                saverOpts.DownsampleStrategy = 'Anisotropy-preserving';
            else
                saverOpts.DownsampleStrategy = 'XY only';
            end
            if strcmp(dataType, 'labels')
                saverOpts.DownsampleMethod = 'nearest';
                saverOpts.layerType        = 'labels';
                % a folder of raw label slices has no material names; without them
                % the Materials panel would show none - name them Material 1..N
                saverOpts.MaterialNamesFromData = true;
            else
                saverOpts.DownsampleMethod = 'bilinear';
            end
            if ~isempty(shardYXZ); saverOpts.ShardSize = shardYXZ; end

            % The output folder carries no .zarr2/.zarr3 extension, so the format
            % has to be stated rather than inferred from the path. Absent field
            % means v3, which is what every caller predating v2 support expects.
            saverOpts.ZarrFormat = 3;
            if isfield(BatchOpt, 'ZarrVersion') && ~isempty(BatchOpt.ZarrVersion)
                requestedVersion = str2double(BatchOpt.ZarrVersion{1}(end));
                if ismember(requestedVersion, [2, 3]); saverOpts.ZarrFormat = requestedVersion; end
            end

            % --- stream to disk ---
            % MIB boundingBox [xmin xmax ymin ymax zmin zmax]; physical extent =
            % (dim-1)*voxel, origin shifted by bbShift. Passed in the metadata rather
            % than patched afterwards: patchMetadata reads zarr.json and so skips v2.
            boundingBox = [bbShift(1), bbShift(1) + (W-1)*voxel(1), ...
                           bbShift(2), bbShift(2) + (H-1)*voxel(2), ...
                           bbShift(3), bbShift(3) + (D-1)*voxel(3)];
            % --- whole slices, or bands of rows when they do not fit; see the help above ---
            sampleValue = cast(0, provider.DataClass);
            if islogical(sampleValue); bytesPerValue = 1; else; bytesPerValue = numel(typecast(sampleValue, 'uint8')); end
            rowBytes = W * sz(4) * bytesPerValue;
            numberOfProcesses = 1;
            if ~isempty(pool); numberOfProcesses = pool.NumWorkers; end
            bytesPerRow = rowBytes * (2.5 * writeDepth + 2) * numberOfProcesses;   % per row of a slab or band
            rowsPerTask = H;
            try
                memoryInfo = memory;
                availableBytes = memoryInfo.MemAvailableAllArrays;
            catch
                availableBytes = Inf;   % memory() exists on Windows only
            end
            if H * bytesPerRow > 0.8 * availableBytes && provider.SupportsRowReads
                % bands of whole chunk (shard) rows of level 0 that fit in 80% of the free memory
                rowAlign = chunkYXZ(1);
                if ~isempty(shardYXZ); rowAlign = rowAlign * max(1, round(shardYXZ(1))); end
                rowsPerTask = max(rowAlign, floor(0.8 * availableBytes / bytesPerRow / rowAlign) * rowAlign);
                if rowsPerTask < H; saverOpts.BandHeight = rowsPerTask; end
            end
            requiredBytes = rowsPerTask * bytesPerRow;
            memoryDetails = sprintf('slice %d x %d x %d (%s), %d slices per write, %d process(es)', ...
                H, W, sz(4), provider.DataClass, writeDepth, numberOfProcesses);
            if rowsPerTask < H
                memoryDetails = sprintf('%s, bands of %d rows', memoryDetails, rowsPerTask);
            end
            if ~ImageConverter.confirmZarrMemory(parentFig, requiredBytes, memoryDetails)
                fnOut = [];
                return;
            end

            % the source as a resume has to find it again: a changed, added or
            % removed file refuses the resume
            sourceFiles = imgDS.Files;
            totalBytes = 0;
            latestModification = 0;
            for fileIndex = 1:numel(sourceFiles)
                fileInfo = dir(sourceFiles{fileIndex});
                if isempty(fileInfo)
                    error('ImageConverter:missingSourceFile', 'The source file is missing:\n%s', sourceFiles{fileIndex});
                end
                totalBytes = totalBytes + fileInfo.bytes;
                latestModification = max(latestModification, fileInfo.datenum);
            end
            saverOpts.SourceFingerprint = struct('numberOfFiles', numel(sourceFiles), ...
                'firstFile', sourceFiles{1}, 'lastFile', sourceFiles{end}, ...
                'totalBytes', totalBytes, 'latestModification', latestModification);
            saverOpts.Resume = isfield(options, 'resume') && options.resume;

            writeStarted = true;
            saver = io.savers.Zarr3Saver(struct('ParentFigure', parentFig, 'mibPath', mibPath));
            metadata = struct('pixSize', pixSize, 'boundingBox', boundingBox);
            fnOut = saver.saveStreamResumable(provider, metadata, zarrPath, saverOpts, pool);
        end

    end

    methods
        function obj = ImageConverter(mibModel, varargin)
            obj.mibModel = mibModel;    % assign model
            
            %% fill the BatchOpt structure with default values
            % fields of the structure should correspond to the starting
            % text in the each widget tooltip.
            % For example, this demo template has an edit box, where the
            % tooltip starts with "Parameter:...". Text Parameter
            % indicates field of the BatchOpt structure that defines value
            % for this widget
            
            obj.BatchOpt.InputDirectory = obj.mibModel.currentDirectory;
            obj.BatchOpt.OutputDirectory = fullfile(obj.mibModel.currentDirectory, 'FileConvert');
            obj.BatchOpt.InputImageFormatExtension = {'tif'};
            obj.BatchOpt.InputImageFormatExtension{2} = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false);
            obj.BatchOpt.BioFormatsReader = false;
            obj.BatchOpt.BioFormatsInputImageFormatExtension = {'dm4'};
            obj.BatchOpt.BioFormatsInputImageFormatExtension{2} = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'BioFormats', false);
            obj.BatchOpt.BioFormatsIndex{1} = 1;
            obj.BatchOpt.BioFormatsIndex{2} = [0 Inf];
            obj.BatchOpt.BioFormatsIndex{3} = 'on';
            obj.BatchOpt.IncludeSubfolders = false;
            obj.BatchOpt.OutputImageFormatExtension = {'tif'};
            obj.BatchOpt.OutputImageFormatExtension{2} = {'png', 'jpg', 'jpeg', 'tif', 'tiff', 'xml', 'zarr'};
            obj.BatchOpt.DiscardColormap = false;
            obj.BatchOpt.PyramidalTIFgenerate = false;
            obj.BatchOpt.PyramidalTIFcompression = {'None'};
            obj.BatchOpt.PyramidalTIFcompression{2} = {'None', 'LZW', 'PackBits', 'Deflate', 'JPEG'};
            obj.BatchOpt.PyramidalTIFlevels = '1, 2, 3, 4';
            obj.BatchOpt.Prefix = '';
            obj.BatchOpt.Suffix = '';
            obj.BatchOpt.ParallelProcessing = false;
            obj.BatchOpt.ParallelWorkersNumber{1} = 1;
            obj.BatchOpt.ParallelWorkersNumber{2} = [0 obj.mibModel.cpuParallelLimitMax];
            obj.BatchOpt.ParallelWorkersNumber{3} = 'on';
            % Zarr settings
            obj.BatchOpt.ZarrVersion = {'Zarr v2'};
            obj.BatchOpt.ZarrVersion{2} = {'Zarr v2', 'Zarr v3'};
            obj.BatchOpt.ZarrImageType = {'image'};
            obj.BatchOpt.ZarrImageType{2} = {'image', 'labels'};
            % chunk Z 16: memory of the conversion grows with chunk Z x full slice,
            % and 256x256x16 uint8 = 1 MiB chunks; shard Z factor 1 keeps every
            % write shard-aligned (development/bigdata/plan_imageconverter_zarr.md)
            obj.BatchOpt.ZarrChunkSizes = '256, 256, 16, 1, 1';
            obj.BatchOpt.ZarrUseSharding = false;
            obj.BatchOpt.ZarrShardXFactorsXYZ = '4, 4, 1, 1, 1';
            obj.BatchOpt.ZarrDownsampleLimitXYZ = '512, 512, 256';
            obj.BatchOpt.ZarrCompression = {'blosc'};
            obj.BatchOpt.ZarrCompression{2} = {'blosc','gzip','none'};
            obj.BatchOpt.ZarrCompressionLevel{1} = 1;
            obj.BatchOpt.ZarrCompressionLevel{2} = [0 9];
            obj.BatchOpt.ZarrCompressionLevel{3} = 'on';
            obj.BatchOpt.ZarrVoxelSizeXYZ = '0.013, 0.013, 0.030';
            obj.BatchOpt.ZarrBBShiftsXYZ = '0, 0, 0';
            obj.BatchOpt.ZarrUnits = {'micrometers'};
            obj.BatchOpt.ZarrUnits{2} = {'nanometers', 'micrometers', 'millimeters', 'pixels'};
            obj.BatchOpt.showWaitbar = true;
            
            %% part below is only valid for use of the plugin from MIB batch controller
            % comment it if intended use not from the batch mode
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Plugins';    % section name for the Batch
            obj.BatchOpt.mibBatchActionName = 'Convert image files';           % name of the plugin
            % tooltips that will accompany the BatchOpt
            obj.BatchOpt.mibBatchTooltip.InputDirectory = 'Directory with input images';
            obj.BatchOpt.mibBatchTooltip.OutputDirectory = 'Output directory for results';
            obj.BatchOpt.mibBatchTooltip.InputImageFormatExtension = 'Extension of the input images';
            obj.BatchOpt.mibBatchTooltip.BioFormatsReader = 'Use BioFormats reader to read various microscopy formats';
            obj.BatchOpt.mibBatchTooltip.BioFormatsInputImageFormatExtension = 'Extension of input images for BioFormats reader';
            obj.BatchOpt.mibBatchTooltip.BioFormatsIndex = 'Index of a series to read in a BioFormats-compatible file';
            obj.BatchOpt.mibBatchTooltip.OutputImageFormatExtension = 'Extension of the output images';
            obj.BatchOpt.mibBatchTooltip.IncludeSubfolders = 'Include subfolders';
            obj.BatchOpt.mibBatchTooltip.DiscardColormap = 'Discard colormap during processing of PNG files';
            obj.BatchOpt.mibBatchTooltip.PyramidalTIFgenerate = 'Tick to enable generation of pyramidal TIF files, where each level has x2 downsampled resolution relative to the previous one';
            obj.BatchOpt.mibBatchTooltip.PyramidalTIFcompression = 'Specify compression for the generated TIF files';
            obj.BatchOpt.mibBatchTooltip.PyramidalTIFlevels = 'Specify output levels of the pyramid as numbers, for example "1,2,3,4"';
            obj.BatchOpt.mibBatchTooltip.Prefix = 'Prefix to the output filename';
            obj.BatchOpt.mibBatchTooltip.Suffix = 'Suffix to the output filename';
            obj.BatchOpt.mibBatchTooltip.ParallelProcessing = 'Use parallel processing during image conversion';
            obj.BatchOpt.mibBatchTooltip.ParallelWorkersNumber = 'Number of workers to use for parallel processing';

            obj.BatchOpt.mibBatchTooltip.ZarrVersion = 'Version of Zarr';
            obj.BatchOpt.mibBatchTooltip.ZarrImageType = 'Image type: image or model, image has 5 dimensions (width, height, depth, colors, time), while model only 4 (width, height, depth, time)';
            obj.BatchOpt.mibBatchTooltip.ZarrChunkSizes = 'Vector of chunk sizes, 5 values (x,y,z,c,d) for images and 4 values (x,y,z,t) for models';
            obj.BatchOpt.mibBatchTooltip.ZarrUseSharding = 'Select to enable merging of chunks into large files';
            obj.BatchOpt.mibBatchTooltip.ZarrShardXFactorsXYZ = 'Vector of shard x-factors defining how many chunks are merged into a single shard file, 5 values (x,y,z,c,d) for images and 4 values (x,y,z,t) for models';
            obj.BatchOpt.mibBatchTooltip.ZarrDownsampleLimitXYZ = 'Target size for image downsampling during calculation of pyramid of magnifications, the scale factors are calculated automatically';
            obj.BatchOpt.mibBatchTooltip.ZarrCompression = 'Compression algorithm or do not use compression, when none';
            obj.BatchOpt.mibBatchTooltip.ZarrCompressionLevel{1} = 'Compression level from 0 (no compression), 1 (fastest, least compression) to 9 (slowest, best compression)';
            obj.BatchOpt.mibBatchTooltip.ZarrVoxelSizeXYZ = 'Image voxel sizes as X, Y, Z';
            obj.BatchOpt.mibBatchTooltip.ZarrBBShiftsXYZ = 'Translate the image by providing image shifts for each dimension, as X, Y, Z';
            obj.BatchOpt.mibBatchTooltip.ZarrUnits = 'Image units';
            
            obj.BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not waitbar');

            %% add here a code for the batch mode, for example
            % when the BatchOpt structure is provided the controller will
            % use it as the parameters, and performs the function in the
            % headless mode without GUI
            if nargin == 3
                BatchOptIn = varargin{2};
                if isstruct(BatchOptIn) == 0 
                    if isnan(BatchOptIn)     % when varargin{2} == NaN return possible settings
                        obj.returnBatchOpt();   % obtain Batch parameters
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent'); 
                    return
                end
                % add/update BatchOpt with the provided fields in BatchOptIn
                % combine fields from input and default structures
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                
                obj.Convert();
                notify(obj, 'CloseEvent');
                return;
            end

            if isfield(obj.mibModel.sessionSettings, 'ImageConverter')
               obj.BatchOpt = obj.mibModel.sessionSettings.ImageConverter;
            end
            
            guiName = 'ImageConverterGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            
            % Set the window title-bar icon.  Use a plugin-specific 16 px icon
            % when present, otherwise fall back to the shared MIB application icon.
            pluginDir   = fileparts(mfilename('fullpath'));
            localIcon   = fullfile(pluginDir, 'icon_16px.png');
            fallbackIcon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            if isfile(localIcon)
                obj.view.gui.Icon = localIcon;
            elseif isfile(fallbackIcon)
                obj.view.gui.Icon = fallbackIcon;
            end

			% move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            
            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.InputDirectory.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.InputDirectory.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            infoText = ['Use the tool to convert image files from one format to another<br>' ...
                '<b>TIF->XML</b> convertion is only implemented for Zeiss Atlas Fibics TIF files<br>' ...
                'to make sure that the XML files are generated at the same location as images:<br>' ...
                '<ul style="font-family: Sans-serif; font-size: 9pt;">' ...
                '<li><em>Incude subfolders</em> is selected</li>' ...
                '<li><em>Output directory</em> is directing to the parent folder of the one selected as the <em>Input directory</em></li>' ...
                '<li>add prefix or suffix</li>' ...
                '</ul>'];
            infoHtml = sprintf('<p style="font-family: Sans-serif; font-size: 9pt;">%s</p>', infoText);
            % the info page and the Convert/Close buttons carry colors of the current theme;
            % set them now and again on a theme switch
            obj.view.gui.ThemeChangedFcn = @(src, evnt) imageConverterThemeChanged(obj, infoHtml);
            imageConverterThemeChanged(obj, infoHtml);
            % a new source refills the Zarr voxel size / shifts / units from its
            % bounding box (the .mlapp wires these widgets to updateBatchOptFromGUI only)
            obj.view.handles.InputDirectory.ValueChangedFcn = @(src, evnt) obj.inputSourceChanged(evnt);
            obj.view.handles.InputImageFormatExtension.ValueChangedFcn = @(src, evnt) obj.inputSourceChanged(evnt);
            obj.view.handles.IncludeSubfolders.ValueChangedFcn = @(src, evnt) obj.inputSourceChanged(evnt);
			obj.updateWidgets();

			% update widgets from the BatchOpt structure
            %obj.view = utils.updateBatchOptFromGUI_Shared(obj.view, obj.BatchOpt);
            
			% obj.view.gui.WindowStyle = 'modal';     % make window modal
			
			% add listner to obj.mibModel and call controller function as a callback
            %obj.listener{1} = addlistener(obj.mibModel, 'updateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
        end
        
        function closeWindow(obj)
            % closing ImageConverter window

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.closeWindow: triggered\n');
            end
            % store the current settings
            obj.mibModel.sessionSettings.ImageConverter = obj.BatchOpt;
            % closing
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end
            
            % delete listeners, otherwise they stay after deleting of the
            % controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end
            
            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end
        
        function updateWidgets(obj)
            % function updateWidgets(obj)
            % update widgets of this window
            
            % when elements GIU needs to be updated, update obj.BatchOpt
            % structure and after that update elements of GUI by the
            % following function
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.updateOutputFormat();
            obj.zarrVersionValueChanged();
            obj.useShardingCallback();
            obj.parallelProcessingCallback();
        end
        
        function updateBatchOptFromGUI(obj, event)
            % function updateBatchOptFromGUI(obj, event)
            %
            % update obj.BatchOpt from widgets of GUI
            % use an external function (+utils\updateBatchOptFromGUI_Shared.m) that is common for all tools
            % compatible with the Batch mode
            %
            % Parameters:
            % event: event from the callback

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        function updateOutputFormat(obj, event)
            % function updateOutputFormat(obj, event)
            % callback for change of the output format dropdown

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.updateOutputFormat: triggered\n');
            end
            if nargin > 1
                obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            end

            %if strcmp(obj.view.handles.OutputImageFormatExtension.Value, 'zarr')
            if strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'zarr')
                obj.view.handles.ExportSettingsPanel.Visible = 'off';
                obj.view.handles.ZarrSettingsPanel.Visible = 'on';
                if nargin > 1; obj.prefillZarrGeometry(); end   % switched to zarr by the user
            else
                obj.view.handles.ZarrSettingsPanel.Visible = 'off';
                obj.view.handles.ExportSettingsPanel.Visible = 'on';
            end

        end

        function inputSourceChanged(obj, event)
            % INPUTSOURCECHANGED - Callback for the input directory, extension and
            % subfolder widgets: store the value, then refill the Zarr voxel size,
            % bounding box shift and units from the new source.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.inputSourceChanged(%s): triggered\n', event.Source.Tag);
            end
            obj.updateBatchOptFromGUI(event);
            obj.prefillZarrGeometry();
        end

        function prefillZarrGeometry(obj)
            % PREFILLZARRGEOMETRY - Fill the Zarr voxel size, bounding box shift and
            % units from the MIB bounding box of the source files.
            %
            % Runs only for the Zarr output with MIB's standard reader. The files are
            % listed exactly as ``Convert`` lists them (``InputDirectory``,
            % ``InputImageFormatExtension``, ``IncludeSubfolders``) and measured by
            % ``ImageConverter.readSourceGeometry``, which reads the metadata of at
            % most two files. Sources without a MIB bounding box leave the fields as
            % they are, so values typed for such data are kept. Units other than
            % nm/um/mm/px leave the units field unchanged.
            if ~strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'zarr') || obj.BatchOpt.BioFormatsReader
                return;
            end
            try
                fileStore = imageDatastore(obj.BatchOpt.InputDirectory, ...
                    'FileExtensions', lower(['.' obj.BatchOpt.InputImageFormatExtension{1}]), ...
                    'IncludeSubfolders', obj.BatchOpt.IncludeSubfolders);
                filenames = fileStore.Files;
            catch
                return;   % no matching files (yet)
            end
            loaderOptions = struct('waitbar', false, 'silentMode', true, 'verbose', false, ...
                'mibPath', obj.mibModel.mibPath, 'ParentFigure', obj.view.gui);
            geometry = ImageConverter.readSourceGeometry(filenames, loaderOptions);
            if isempty(geometry); return; end

            obj.view.handles.ZarrVoxelSizeXYZ.Value = sprintf('%.6g, %.6g, %.6g', geometry.voxelSizeXYZ);
            obj.updateBatchOptFromGUI(struct('Source', obj.view.handles.ZarrVoxelSizeXYZ));
            obj.view.handles.ZarrBBShiftsXYZ.Value = sprintf('%.6g, %.6g, %.6g', geometry.originXYZ);
            obj.updateBatchOptFromGUI(struct('Source', obj.view.handles.ZarrBBShiftsXYZ));

            switch lower(strrep(geometry.units, char(181), 'u'))   % 'µm' -> 'um'
                case {'nm', 'nanometers'};                   unitsName = 'nanometers';
                case {'um', 'micrometers', 'micron', 'microns'}; unitsName = 'micrometers';
                case {'mm', 'millimeters'};                  unitsName = 'millimeters';
                case {'px', 'pixel', 'pixels'};              unitsName = 'pixels';
                otherwise;                                   unitsName = '';
            end
            if ~isempty(unitsName)
                obj.view.handles.ZarrUnits.Value = unitsName;
                obj.updateBatchOptFromGUI(struct('Source', obj.view.handles.ZarrUnits));
            end
        end
        
        function returnBatchOpt(obj, BatchOptOut)
            % return structure with Batch Options and possible configurations
            % via the notify 'SyncBatch' event
            % Parameters:
            % BatchOptOut: a local structure with Batch Options generated
            % during Continue callback. It may contain more fields than
            % obj.BatchOpt structure
            % 
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end  % remove id field
            % trigger SyncBatch event to send BatchOptOut to mibBatchController 
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end
        
        function selectDirectory(obj, event)
            % function selectDirectory(obj, event)
            % select input/output directory

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.selectDirectory(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'SelectInputDirectory'
                    selpath = uigetdir(obj.BatchOpt.InputDirectory, 'Select input directory');
                    if selpath == 0; return; end
                    obj.view.handles.InputDirectory.Value = selpath;
                    event2.Source = obj.view.handles.InputDirectory;
                    obj.updateBatchOptFromGUI(event2);
                    obj.view.handles.OutputDirectory.Value = fullfile(selpath, 'FileConvert');
                    event2.Source = obj.view.handles.OutputDirectory;
                    obj.updateBatchOptFromGUI(event2);
                    obj.prefillZarrGeometry();
                case 'SelectOutputDirectory'
                    if exist(obj.BatchOpt.OutputDirectory, 'dir') == 7
                        defDir = obj.BatchOpt.OutputDirectory;
                    else
                        defDir = obj.BatchOpt.InputDirectory;
                    end
                    selpath = uigetdir(defDir, 'Select output directory');
                    if selpath == 0; return; end
                    obj.view.handles.OutputDirectory.Value = selpath;
                    event2.Source = obj.view.handles.OutputDirectory;
                    obj.updateBatchOptFromGUI(event2);
            end
            
            % the two following commands are fix of sending the DeepMIB
            % window behind main MIB window
            drawnow;
            figure(obj.view.gui);
        end
        
        function BioFormatsReader_ValueChanged(obj, event)
            % function BioFormatsReader_ValueChanged(obj, event)
            % callback for press of BioFormats reader checkbox
            % toggles between standard and BioFormats readers

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.BioFormatsReader_ValueChanged: triggered\n');
            end
            obj.updateBatchOptFromGUI(event);
            if obj.view.handles.BioFormatsReader.Value     % use BioFormats reader
                obj.view.handles.InputImageFormatExtension.Enable = 'off';
                obj.view.handles.BioFormatsInputImageFormatExtension.Enable = 'on';
                obj.view.handles.BioFormatsIndex.Enable = 'on';
            else        % use standard reader
                obj.view.handles.InputImageFormatExtension.Enable = 'on';
                obj.view.handles.BioFormatsInputImageFormatExtension.Enable = 'off';
                obj.view.handles.BioFormatsIndex.Enable = 'off';
            end
        end

        function parallelProcessingCallback(obj, event)
            % function parallelProcessingCallback(obj, event)
            % callback on press of the parallel processing checkbox

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.parallelProcessingCallback: triggered\n');
            end
            obj.BatchOpt.ParallelProcessing = obj.view.handles.ParallelProcessing.Value;
            if obj.BatchOpt.ParallelProcessing % enable parallel processing
                obj.view.handles.ParallelWorkersNumber.Enable = 'on';
            else % disable parallel processing
                obj.view.handles.ParallelWorkersNumber.Enable = 'off';
            end
        end

        function zarrVersionValueChanged(obj, event)
            % function zarrVersionValueChanged(obj, event)
            % callback on change of the zarr version

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.zarrVersionValueChanged: triggered\n');
            end
            if strcmp(obj.view.handles.ZarrVersion.Value, 'Zarr v2')
                obj.view.handles.ZarrUseSharding.Value = false;
            else
                obj.view.handles.ZarrUseSharding.Value = obj.BatchOpt.ZarrUseSharding;
            end
            obj.BatchOpt.ZarrVersion{1} = obj.view.handles.ZarrVersion.Value;
            obj.useShardingCallback();

        end

        function useShardingCallback(obj, event)
            % function useShardingCallback(obj, event)
            % callback on selection of sharding for Zarr3
            
            if nargin < 2; event = []; end

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.useShardingCallback: triggered\n');
            end
            if obj.view.handles.ZarrUseSharding.Value
                if ~strcmp(obj.view.handles.ZarrVersion.Value, 'Zarr v3')
                    obj.view.handles.ZarrUseSharding.Value = false;
                    uialert(obj.view.gui, ...
                        sprintf('!!! Warning !!!\n\nSharding is available only for Zarr version 3!'), ...
                        'Not available', 'Icon', 'warning');
                    return;
                end
                obj.view.handles.ZarrShardXFactorsXYZ.Enable = true;
                obj.BatchOpt.ZarrUseSharding = true;
            else
                obj.view.handles.ZarrShardXFactorsXYZ.Enable = false;
                obj.BatchOpt.ZarrUseSharding = false;
            end
        
        end

        % ------------------------------------------------------------------
        % % Additional functions and callbacks
        function helpButton_Callback(obj)

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'plugins', 'file-processing', 'image-converter.html');
            utils.openHelpPage(helpFilPath, 'http://mib.helsinki.fi/help/main3/plugins/file-processing/image-converter.html');

        end
        
        function Convert(obj)
            % start main calculation of the plugin

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('ImageConverter.Convert: triggered\n');
            end
            if strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'xml')
                selection = uiconfirm(obj.view.gui, ...
                    sprintf('!!! Warning !!!\n\nThis mode is only implemented for extraction of metadata from Zeiss Atlas Fibics TIF files to XML documents!'), ...
                    'Warning!', 'Icon', 'warning');
                if strcmp(selection, 'Cancel'); return; end
                
                % parallel processing is not available as the function
                % always works with the same temp file
                obj.BatchOpt.ParallelProcessing = false;
                obj.view.handles.ParallelProcessing.Value = false;
            end
            
            % check for existence of zarr dataset at destination: the output
            % directory IS the zarr store, and the native writer replaces the whole
            % folder, so a folder holding anything else must never be used.
            % An interrupted native conversion (it leaves .mib_resume.json, see
            % io.savers.Zarr3Saver.saveStreamResumable) can be resumed instead; in
            % batch mode it is resumed whenever possible.
            resumeConversion = false;
            if strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'zarr')
                parentFig = [];
                if ~isempty(obj.view) && isvalid(obj.view.gui); parentFig = obj.view.gui; end
                zarrPath = obj.BatchOpt.OutputDirectory;
                zarrPath = strrep(zarrPath, '\', '/');
                % v3 / v2 group metadata, v2 attributes, level folders (native '0', python 's0')
                isZarrStore = isfile(fullfile(zarrPath, 'zarr.json')) || isfile(fullfile(zarrPath, '.zgroup')) || ...
                    isfile(fullfile(zarrPath, '.zattrs')) || isfolder(fullfile(zarrPath, '0')) || ...
                    isfolder(fullfile(zarrPath, 's0'));
                isResumable = isZarrStore && isfile(fullfile(zarrPath, '.mib_resume.json')) && ~io.zarr.Config.isPython();
                if isZarrStore
                    if isempty(parentFig)
                        resumeConversion = isResumable;
                    elseif isResumable
                        choice = uiconfirm(parentFig, ...
                            sprintf(['The output directory holds an interrupted Zarr conversion:\n%s\n\n' ...
                            'Resume it, or overwrite it and start again?'], zarrPath), ...
                            'Interrupted conversion', ...
                            'Options', {'Resume', 'Overwrite', 'Cancel'}, ...
                            'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
                        if strcmp(choice, 'Cancel'); return; end
                        resumeConversion = strcmp(choice, 'Resume');
                    else
                        choice = uiconfirm(parentFig, ...
                            sprintf('!!! Warning !!!\n\nA Zarr dataset already exists in\n%s\n\nWould you like to overwrite it?', zarrPath), ...
                            'Zarr file exists!', ...
                            'Options',{'Overwrite', 'Cancel'}, ...
                            'DefaultOption',2,'CancelOption', 2, 'Icon', 'warning');
                        if strcmp(choice, 'Cancel')
                            return;
                        end
                    end
                end
                if isZarrStore && ~resumeConversion
                    if obj.BatchOpt.showWaitbar && ~isempty(parentFig)
                        wb = uiprogressdlg(parentFig, 'Title','Removing files',...
                            'Message', 'Please wait...', 'Indeterminate', 'on');
                    end
                    rmdir(zarrPath, 's');
                    mkdir(zarrPath);
                    if obj.BatchOpt.showWaitbar && ~isempty(parentFig); delete(wb); end
                elseif ~isZarrStore && isfolder(zarrPath) && numel(dir(zarrPath)) > 2   % more than '.' and '..'
                    utils.dlgs.showErrorDialog(parentFig, ...
                        sprintf(['The output directory is not empty:\n%s\n\nThe Zarr dataset is written into the ' ...
                        'output directory itself and replaces its content. Please select an empty or a new directory.'], zarrPath), ...
                        'Output directory is not empty');
                    return;
                end
            end

            % init python environment (legacy Python zarr pipeline / xml extraction).
            % The native zarrMex backend needs no Python for either zarr format, so
            % starting an interpreter there would be pure start-up cost.
            isNativeZarr = strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'zarr') && ...
                ~io.zarr.Config.isPython();
            if ~isNativeZarr && isempty(obj.mibModel.pythonEnv)
                % execution mode from preferences (default OutOfProcess); see
                % External directories -> Python execution mode
                pythonExecutionMode = 'OutOfProcess';
                if isfield(obj.mibModel.preferences.ExternalDirs, 'PythonExecutionMode') && ...
                        ~isempty(obj.mibModel.preferences.ExternalDirs.PythonExecutionMode)
                    pythonExecutionMode = obj.mibModel.preferences.ExternalDirs.PythonExecutionMode;
                end
                [obj.mibModel.pythonEnv, pythonErrorMessage] = utils.initPythonEnv( ...
                    obj.mibModel.preferences.ExternalDirs.PythonInstallationPath, pythonExecutionMode);
                if ~isempty(pythonErrorMessage)
                    utils.dlgs.showErrorDialog(obj.view.gui, pythonErrorMessage, 'Image converter');
                    return;
                end
            end

            t1 = tic;
            wb = [];
            if obj.BatchOpt.showWaitbar
                wb = core.PoolWaitbar(1, sprintf('Making data store\nPlease wait...'), obj.view.gui, 'Image converter', true);
                %wb = core.PoolWaitbar(1, sprintf('Making data store\nPlease wait...'), obj.view.gui, 'Image converter');
            end
            
            if exist(obj.BatchOpt.OutputDirectory, 'dir') == 0
                mkdir(obj.BatchOpt.OutputDirectory);
            end
            
            try
                if ~obj.BatchOpt.BioFormatsReader    % standard reader
                    if strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'xml')
                        % use datastore instead of imageDatastore as we are
                        % interested to process only metadata and reading of
                        % the whole image is not needed
                        imgDS = datastore(obj.BatchOpt.InputDirectory, ...
                            'FileExtensions', lower(['.' obj.BatchOpt.InputImageFormatExtension{1}]), ...
                            'Type', 'file', ...
                            'IncludeSubfolders', obj.BatchOpt.IncludeSubfolders, ...
                            'ReadFcn', @readMetaDataFromFibicsTIFs);
                    else
                        if strcmp(obj.BatchOpt.InputImageFormatExtension{1}, 'png') && obj.BatchOpt.DiscardColormap
                            imgDS = imageDatastore(obj.BatchOpt.InputDirectory, ...
                                'FileExtensions', lower(['.' obj.BatchOpt.InputImageFormatExtension{1}]), ...
                                'IncludeSubfolders', obj.BatchOpt.IncludeSubfolders, ...
                                'ReadFcn', @(fn)ImageConverter.getPNGwithoutColormap(fn));
                        else
                            standardLoaderOptions = struct('waitbar', false, 'silentMode', true, ...
                                'mibPath', obj.mibModel.mibPath, 'verbose', false);
                            standardLoaderInfo = obj.mibModel.extensionRegistryLoad.resolveLoader( ...
                                ['file.' obj.BatchOpt.InputImageFormatExtension{1}], 'Standard', 'Default');
                            standardLoader = io.LoaderFactory.create(standardLoaderInfo, standardLoaderOptions);
                            imgDS = imageDatastore(obj.BatchOpt.InputDirectory, ...
                                'FileExtensions', lower(['.' obj.BatchOpt.InputImageFormatExtension{1}]), ...
                                'IncludeSubfolders', obj.BatchOpt.IncludeSubfolders, ...
                                'ReadFcn', @(fn) ImageConverter.readWithLoader(standardLoader, fn, standardLoaderOptions));
                        end
                    end
                else    % BioFormats reader
                    bioFormatsLoaderOptions = struct('waitbar', false, 'silentMode', true, ...
                        'BioFormatsIndices', obj.BatchOpt.BioFormatsIndex{1}, ...
                        'bioFormatsMemoizerMemoDir', tempdir(), 'verbose', false);
                    bioFormatsLoaderInfo = obj.mibModel.extensionRegistryLoad.resolveLoader( ...
                        ['file.' obj.BatchOpt.BioFormatsInputImageFormatExtension{1}], 'Standard', 'BioFormats');
                    bioFormatsLoader = io.LoaderFactory.create(bioFormatsLoaderInfo, bioFormatsLoaderOptions);
                    imgDS = imageDatastore(obj.BatchOpt.InputDirectory, ...
                        'FileExtensions', lower(['.' obj.BatchOpt.BioFormatsInputImageFormatExtension{1}]), ...
                        'IncludeSubfolders', obj.BatchOpt.IncludeSubfolders, ...
                        'ReadFcn', @(fn) ImageConverter.readWithLoader(bioFormatsLoader, fn, bioFormatsLoaderOptions));
                end
            catch err
                if obj.BatchOpt.showWaitbar; delete(wb); end
                warndlg(err.message, 'Directory selection error');
                return;
            end
            
            if obj.BatchOpt.showWaitbar
                noFiles = numel(imgDS.Files);
                wb.updateText(sprintf('Processing %d files\nPlease wait...', noFiles));
                wb.increaseMaxNumberOfIterations(noFiles);
                drawnow;
            end

            if strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'xml')
                try 
                    writeall(imgDS, obj.BatchOpt.OutputDirectory, ...
                        'FilenamePrefix', obj.BatchOpt.Prefix, 'FilenameSuffix', obj.BatchOpt.Suffix, ...
                        'UseParallel', obj.BatchOpt.ParallelProcessing, ...
                        'WriteFcn', @(data, writeInfo, outputType) extractToXMLMetaFromFibicsTIFs(data, writeInfo, outputType, wb));
                catch err
                    if obj.BatchOpt.showWaitbar; delete(wb); end
                    if strcmp(err.identifier, 'ImageConverter:Cancelled'); return; end
                    warndlg(sprintf('%s, \n\nHINT: add filename prefix of suffix and try again', err.message), 'Directory selection error');
                    return;
                end
            elseif strcmp(obj.BatchOpt.OutputImageFormatExtension{1}, 'zarr')
                if ~obj.BatchOpt.showWaitbar; wb = []; end
                obj.generateZarr(imgDS, wb, resumeConversion);
                obj.returnBatchOpt();
                return;
            elseif obj.BatchOpt.PyramidalTIFgenerate
                try
                    levelsVec = str2num(obj.BatchOpt.PyramidalTIFlevels); %#ok<ST2NM> 
                    compressionType = obj.BatchOpt.PyramidalTIFcompression{1};
                    writeall(imgDS, obj.BatchOpt.OutputDirectory, ...
                            'FilenamePrefix', obj.BatchOpt.Prefix, 'FilenameSuffix', obj.BatchOpt.Suffix, ...
                            'UseParallel', obj.BatchOpt.ParallelProcessing, ...
                            'WriteFcn', @(data, writeInfo, outputType) ImageConverter.generatePyramidalTIF(data, writeInfo, outputType, levelsVec, compressionType, wb));
                catch err
                    if obj.BatchOpt.showWaitbar; delete(wb); end
                    if strcmp(err.identifier, 'ImageConverter:Cancelled'); return; end
                    errordlg(sprintf('!!! Error !!!\n\n%s\n\n%s', err.identifier, err.message), 'Convert to pyramidal TIFs');
                    return;
                end
            else
                try
                    outputFormat = obj.BatchOpt.OutputImageFormatExtension{1};
                    sourceFiles = imgDS.Files;
                    noSourceFiles = numel(sourceFiles);
                    if obj.BatchOpt.ParallelProcessing
                        parforArg = obj.BatchOpt.ParallelWorkersNumber{1};
                        parfor (fileIdx = 1:noSourceFiles, parforArg)
                            [~, nameOut, ~] = fileparts(sourceFiles{fileIdx});
                            outputFilename = fullfile(obj.BatchOpt.OutputDirectory, ...
                                [obj.BatchOpt.Prefix nameOut obj.BatchOpt.Suffix '.' outputFormat]);
                            imwrite(imgDS.readimage(fileIdx), outputFilename);
                            if ~isempty(wb); wb.increment(); end %#ok<PFBNS>
                        end
                    else
                        for fileIdx = 1:noSourceFiles
                            [~, nameOut, ~] = fileparts(sourceFiles{fileIdx});
                            outputFilename = fullfile(obj.BatchOpt.OutputDirectory, ...
                                [obj.BatchOpt.Prefix nameOut obj.BatchOpt.Suffix '.' outputFormat]);
                            imwrite(imgDS.readimage(fileIdx), outputFilename);
                            if ~isempty(wb)
                                wb.increment();
                                if wb.getCancelState(); break; end
                            end
                        end
                    end
                catch err
                    if obj.BatchOpt.showWaitbar; delete(wb); end
                    errordlg(sprintf('!!! Error !!!\n\n%s\n\n%s', err.identifier, err.message), 'Missing files');
                    return;
                end
            end
            if obj.BatchOpt.showWaitbar; delete(wb); end
            
            fprintf('Image conversion finished, elapsed time: %f seconds\n', toc(t1));
            % for batch need to generate an event and send the BatchOptLoc
            % structure with it to the macro recorder / mibBatchController
            obj.returnBatchOpt();
        end
        
        function generateZarrNative(obj, imgDS, wb, resumeConversion)
            % GENERATEZARRNATIVE - Native (zarrMex) Zarr generation via io.savers.Zarr3Saver.
            %
            % The same in-app pyramid/bounding-box/voxel logic (no Python), used
            % whenever io.zarr.Config = native, for Zarr v2 and v3 alike; only the
            % python backend takes the legacy pipeline. The store is written in
            % resumable slab tasks (``Zarr3Saver.saveStreamResumable``), by the pool
            % workers with Parallel processing.
            %
            % ``resumeConversion`` continues the interrupted conversion in the
            % output directory. When it cannot be continued (source or settings
            % changed) the GUI explains why and stops, so the user can choose
            % Overwrite; in batch mode the conversion starts again from scratch.
            %
            % Input Arguments:
            %   - **imgDS** - ``matlab.io.datastore.ImageDatastore``, one file per Z-slice
            %   - **wb** - ``core.PoolWaitbar`` or ``[]``
            %   - **resumeConversion** - *(optional)* [logical], default false
            if nargin < 4; resumeConversion = false; end
            parentFig = [];
            if ~isempty(obj.view) && isvalid(obj.view.gui); parentFig = obj.view.gui; end

            pool = [];
            if obj.BatchOpt.ParallelProcessing
                pool = obj.getParallelPool(wb);
            end
            % Zarr3Saver shows its own progress dialog - release the plugin's first
            if ~isempty(wb); delete(wb); end

            t2 = tic;
            converterOptions = struct('ParentFigure', parentFig, 'mibPath', obj.mibModel.mibPath, ...
                'pool', pool, 'resume', resumeConversion);
            try
                try
                    [fnOut, writeStarted] = ImageConverter.convertToZarr3Native(imgDS, obj.BatchOpt, converterOptions);
                catch err
                    if ~strcmp(err.identifier, 'io:Zarr3Saver:cannotResume') || ~isempty(parentFig); rethrow(err); end
                    fprintf('%s\nStarting the conversion again.\n', err.message);
                    converterOptions.resume = false;
                    [fnOut, writeStarted] = ImageConverter.convertToZarr3Native(imgDS, obj.BatchOpt, converterOptions);
                end
            catch err
                if strcmp(err.identifier, 'io:Zarr3Saver:cannotResume')
                    % nothing was changed; the user can still overwrite
                    utils.dlgs.showErrorDialog(parentFig, sprintf('%s\n\nUse Overwrite to convert again from the start.', ...
                        err.message), 'Cannot resume');
                    return;
                end
                % the store is left flagged incomplete (mibIncomplete); never report success
                utils.dlgs.showErrorDialog(parentFig, ...
                    sprintf(['The Zarr conversion failed:\n%s\n\nThe dataset in\n%s\nis incomplete; ' ...
                    'MIB warns about it when it is opened. After fixing the cause, run Convert again and ' ...
                    'choose Resume to continue it.'], err.message, obj.BatchOpt.OutputDirectory), ...
                    'Zarr conversion failed');
                return;
            end
            t2 = toc(t2);
            if isempty(fnOut)
                if writeStarted
                    cancelText = sprintf(['Zarr conversion cancelled.\n\nThe incomplete dataset is left in\n%s\n' ...
                        'Run Convert again and choose Resume to continue it.'], obj.BatchOpt.OutputDirectory);
                    fprintf('%s\n', cancelText);
                    if ~isempty(parentFig); uialert(parentFig, cancelText, 'Cancelled', 'Icon', 'warning'); end
                end
                return;
            end

            zarrVersion = obj.BatchOpt.ZarrVersion{1};   % e.g. 'Zarr v3'
            fprintf('Native %s written to: %s\nElapsed time is %f seconds\n', zarrVersion, fnOut, t2);
            if ~isempty(parentFig)
                uialert(parentFig, sprintf('Native %s written to:\n%s\n\nElapsed time is %.1f seconds', ...
                    zarrVersion, fnOut, t2), 'Zarr conversion done!', 'Icon', 'success');
            end
        end

        function pool = getParallelPool(obj, wb)
            % GETPARALLELPOOL - Parallel pool with ``BatchOpt.ParallelWorkersNumber`` workers.
            %
            % Reuses the current pool when it has that many workers, otherwise
            % (re)starts it, showing the progress in ``wb`` (a ``core.PoolWaitbar`` or
            % ``[]``). Returns ``[]`` for fewer than one worker, meaning: no pool.
            pool = [];
            numberOfWorkers = obj.BatchOpt.ParallelWorkersNumber{1};
            if numberOfWorkers < 1; return; end
            pool = gcp('nocreate');
            if ~isempty(pool) && pool.NumWorkers == numberOfWorkers; return; end

            if ~isempty(wb)
                wbText = wb.getText();
                wb.updateText(sprintf('Starting the parallel pool\nPlease wait...'));
            end
            if ~isempty(pool); delete(pool); end
            pool = parpool(numberOfWorkers);
            if ~isempty(wb); wb.updateText(wbText); end
        end

        function generateZarr(obj, imgDS, wb, resumeConversion)
            % GENERATEZARR - Convert the image stack in ``imgDS`` to an OME-Zarr pyramid.
            %
            % With the native backend (default) the work is done by
            % ``generateZarrNative``, which can resume an interrupted conversion
            % (``resumeConversion``); the python backend runs the pipeline below,
            % which cannot resume:
            % ``createMultiscaleDataset`` declares every level, then Z-slabs of
            % ``zChunk`` slices (the shard depth when parallel and sharded) are
            % read, downsampled and written by ``processZChunk``, serially or as
            % ``parfeval`` jobs.
            %
            % The root attributes carry ``mibIncomplete = true`` until every slab is
            % written, so an interrupted store is recognised by the Zarr loaders. A
            % failed slab (in the serial loop, or any ``parfeval`` job, e.g. a worker
            % killed for lack of memory) ends the conversion with an error that names
            % the failed Z ranges; success is reported only when every slab was
            % written. The peak memory is checked first with
            % ``ImageConverter.confirmZarrMemory``.
            %
            % Input Arguments:
            %   - **imgDS** - ``matlab.io.datastore.ImageDatastore``, one file per Z-slice
            %   - **wb** - ``core.PoolWaitbar`` or ``[]``
            %   - **resumeConversion** - *(optional)* [logical], native backend only, default false
            if nargin < 4; resumeConversion = false; end

            % Native (zarrMex) backend writes both Zarr formats directly via
            % io.savers.Zarr3Saver (shared pyramid + bounding box + voxel logic).
            % Only the python backend falls through to the legacy pipeline below.
            if ~io.zarr.Config.isPython()
                obj.generateZarrNative(imgDS, wb, resumeConversion);
                return;
            end

            % define usage of parallel computing
            parforArg = 0;      % number of workers, 0 = a single core without parallel
            if obj.BatchOpt.ParallelProcessing
                pool = obj.getParallelPool(wb);
                if ~isempty(pool); parforArg = pool.NumWorkers; end
            end

            zarrPath = obj.BatchOpt.OutputDirectory;
            zarrPath = strrep(zarrPath, '\', '/');
            % get settings
            % output filename
            % zarr format 2 or 3
            Options.zarrFormat = str2double(obj.BatchOpt.ZarrVersion{1}(end));
            % data type, image (5d) or labels (4d) 
            Options.dataType = obj.BatchOpt.ZarrImageType{1};
            % chunk sizes
            Options.chunks = str2num(obj.BatchOpt.ZarrChunkSizes); %#ok<ST2NM>
            if strcmp(Options.dataType, 'image') && numel(Options.chunks)~=5 || strcmp(Options.dataType, 'labels') && numel(Options.chunks)~=4
                if ~isempty(wb); delete(wb); end
                uialert(obj.view.gui, sprintf('!!! Error !!!\nThe Chunk sizes (x,y,z,c,t) parameter should contain:\n  - 5 numbers for Image type: "image"\n  - 4 numbers for Image type: "labels"'), 'Wrong parameters');
                return;
            end
            Options.chunks = flip(Options.chunks); % convert from (x,y,z) to (z,y,x)
            % shard sizes, only for zarr3
            
            Options.shards = [];
            if Options.zarrFormat == 3 && obj.BatchOpt.ZarrUseSharding
                Options.shards = str2num(obj.BatchOpt.ZarrShardXFactorsXYZ); %#ok<ST2NM>
                if ~isempty(Options.shards)
                    Options.shards = flip(Options.shards); 
                    Options.shards = Options.chunks .* Options.shards; % calculate the shards size
                    if numel(Options.shards) ~= 5
                        if ~isempty(wb); delete(wb); end
                        uialert(obj.view.gui, sprintf('!!! Error !!!\nThe Shard sizes (x,y,z,c,t) parameter should contain 5 numbers'), 'Wrong parameters');
                        return;
                    end
                end
            end
            % minimal size of images during downsampling to calculate
            % number of downsampling steps
            downsampleImageLimit = str2num(obj.BatchOpt.ZarrDownsampleLimitXYZ); %#ok<ST2NM>
            if numel(downsampleImageLimit) ~= 3
                if ~isempty(wb); delete(wb); end
                uialert(obj.view.gui, sprintf('!!! Error !!!\nThe Downsample limitXYZ (x,y,z) parameter should contain 3 numbers'), 'Wrong parameters');
                return;
            end
            downsampleImageLimit = flip(downsampleImageLimit); % convert from (x,y,z) to (z,y,x)
            % compression settings
            Options.compressionType = lower(obj.BatchOpt.ZarrCompression{1}); % none, gzip, blosc
            Options.compressionLevel = obj.BatchOpt.ZarrCompressionLevel{1};  % compression level
            if Options.zarrFormat == 3 && strcmp(Options.compressionType, 'gzip')
                if ~isempty(wb); delete(wb); end
                uialert(obj.view.gui, sprintf('!!! Error !!!\nUnfortunately, GZip compression is not implemented for Zarr version 3.\nUse Blosc compression instead!'), 'Wrong compression');
                return;
            end

            % voxel sizes
            voxelSize = str2num(obj.BatchOpt.ZarrVoxelSizeXYZ); %#ok<ST2NM>
            if numel(voxelSize) ~= 3
                if ~isempty(wb); delete(wb); end
                uialert(obj.view.gui, sprintf('!!! Error !!!\nThe voxel size (x,y,z) parameter should contain 3 numbers'), 'Wrong parameters');
                return;
            end
            voxelSize = flip(voxelSize); % convert from (x,y,z) to (z,y,x)
            voxelUnits = obj.BatchOpt.ZarrUnits{1}; % nanometers, micrometers, millimeters, pixels
            % image translation, i.e. shift of bounding box
            boundingBoxShiftsZYX = str2num(obj.BatchOpt.ZarrBBShiftsXYZ); %#ok<ST2NM>
            if numel(boundingBoxShiftsZYX) ~= 3
                if ~isempty(wb); delete(wb); end
                uialert(obj.view.gui, sprintf('!!! Error !!!\nThe bounding box shifts (x,y,z) parameter should contain 3 numbers'), 'Wrong parameters');
                return;
            end
            boundingBoxShiftsZYX = flip(boundingBoxShiftsZYX); % convert from (x,y,z) to (z,y,x)

            t2 = tic;
            % read the first image to get image class and image size
            I = imgDS.readimage(1);
            imageType = class(I);
            currentImageSize = size(I); % [y, x, c] 

            imageSwitch = true;
            if strcmp(Options.dataType, 'image')
                imageSize = ones([1,5]);
                imageSize(5) = currentImageSize(2); % zarr X
                imageSize(4) = currentImageSize(1); % zarr Y
                imageSize(3) = numel(imgDS.Files);  % zarr Z
                if ndims(currentImageSize) > 2 %#ok<ISMAT>
                    imageSize(2) = currentImageSize(3); % zarr C
                end
            else % labels
                imageSwitch = false;
                imageSize = ones([1,4]);
                imageSize(4) = currentImageSize(2); % zarr X
                imageSize(3) = currentImageSize(1); % zarr Y
                imageSize(2) = numel(imgDS.Files);  % zarr Z
            end

            imgDS.reset(); % reset image store
            
            % calculate downsampling scales to bring:
            % - first to isotropic
            % - downsample until reaching downsampleImageLimit
            % note: levelImageTranslations is introduced due to rounding during unevendownsampling steps
            [levelNames, scaleZYX, levelImageTranslations, levelImageSizes] = ImageConverter.calculateMultiscaleLevels(imageSize(end-2:end), voxelSize, downsampleImageLimit);

            % bring the bounding box shifts
            levelImageTranslations = levelImageTranslations+boundingBoxShiftsZYX;

            %% Init python
            % execution mode from preferences (default OutOfProcess); see
            % External directories -> Python execution mode
            pythonExecutionMode = 'OutOfProcess';
            if isfield(obj.mibModel.preferences.ExternalDirs, 'PythonExecutionMode') && ...
                    ~isempty(obj.mibModel.preferences.ExternalDirs.PythonExecutionMode)
                pythonExecutionMode = obj.mibModel.preferences.ExternalDirs.PythonExecutionMode;
            end
            [obj.mibModel.pythonEnv, pythonErrorMessage] = utils.initPythonEnv( ...
                obj.mibModel.preferences.ExternalDirs.PythonInstallationPath, pythonExecutionMode);
            if ~isempty(pythonErrorMessage)
                if ~isempty(wb); delete(wb); end
                utils.dlgs.showErrorDialog(obj.view.gui, pythonErrorMessage, 'Image converter');
                return;
            end
            % import zarr and numpy
            pyrun(["import zarr", ...
                "import json", ...
                "import numpy as np"]);

            maxZ = imageSize(end-2);
            maxT = imageSize(1);
            % Z is 3rd from the end: chunks are [t c z y x] for images, [t z y x] for labels
            zChunk = Options.chunks(end-2);
            % for parallel processing the whole depth of a shard should be
            % read for processing
            if parforArg > 0 && ~isempty(Options.shards)
                zChunk = Options.shards(end-2);
            end

            % memory check: each process holds a zChunk-deep slab of full slices
            % about 4 times (the slab, permute copies, the copy passed to Python,
            % the downsampling intermediates)
            firstImageInfo = whos('I');
            sliceBytes = firstImageInfo.bytes;
            numberOfProcesses = max(parforArg, 1);
            parentFig = [];
            if ~isempty(obj.view) && isvalid(obj.view.gui); parentFig = obj.view.gui; end
            memoryDetails = sprintf('slice %s (%s), %d slices per slab, %d process(es)', ...
                strjoin(string(currentImageSize), ' x '), imageType, zChunk, numberOfProcesses);
            if ~ImageConverter.confirmZarrMemory(parentFig, 4 * min(zChunk, maxZ) * sliceBytes * numberOfProcesses, memoryDetails)
                if ~isempty(wb); delete(wb); end
                return;
            end
            clear I;

            %% CREATE DATASETS + TOP LEVEL METADATA
            Options.voxelSize = voxelSize;
            Options.voxelUnits = voxelUnits;
            Options.levelTranslations = levelImageTranslations;   % the field createMultiscaleDataset reads
            % flag removed after the last slab; the Zarr loaders warn while it is set
            Options.customAttributes = struct('mibIncomplete', true);
            ImageConverter.createMultiscaleDataset(zarrPath, imageSize, imageType, levelNames, scaleZYX, Options);

            %% Implementation with parfor loop
            % for tIdx = 1:maxT
            %     zStarts = 1:zChunk:maxZ;
            %     if ~isempty(wb); wb.updateMaxNumberOfIterations(numel(zStarts)); end
            % 
            %     parfor (idx = 1:numel(zStarts), parforArg)
            %         if ~isempty(wb) && parforArg == 0 && wb.getCancelState()
            %             continue;  % skip all operations
            %         end
            % 
            %         %for idx = 1:numel(zStarts)
            %         pyrun(["import zarr", ...
            %             "import numpy as np"]);
            %         % allocate space for a zChunk
            %         zStart = zStarts(idx);
            %         zEnd = min(zStart + zChunk - 1, maxZ);
            %         if imageSwitch
            %             subvol = zeros([1, imageSize(2), zEnd-zStart+1, imageSize(end-1), imageSize(end)], imageType);
            %             % read zChunk
            %             for i = zStart:zEnd
            %                 subvol(:, :, i-zStart+1, :, :) = permute(imgDS.readimage(i), [5, 3, 4, 1, 2]); % [y,x,c]->[t,c,z,y,x]
            %             end
            %         else % labels
            %             subvol = zeros([1, zEnd-zStart+1, imageSize(end-1), imageSize(end)], imageType);
            %             % read zChunk
            %             for i = zStart:zEnd
            %                 subvol(:, i-zStart+1, :, :) = permute(imgDS.readimage(i), [4, 3, 1, 2]); % [y,x,c]->[t,z,y,x]
            %             end
            %         end
            % 
            %         % Cascaded downsampling
            %         for lvl = 1:numel(levelNames)
            %             if lvl > 1
            %                 rel = scaleZYX(lvl,:) ./ scaleZYX(lvl-1,:);
            %                 try
            %                     subvol = downsampleBlock(subvol, rel, imageSwitch);
            %                 catch err
            %                     err
            %                 end
            %             end
            % 
            %             % Z offset
            %             zOutStart = floor((zStart-1)/scaleZYX(lvl,1)) + 1;
            %             writeSubvolumeToLevel(subvol, zarrPath, levelNames{lvl}, 1, zOutStart, imageSwitch);
            %         end
            % 
            %         % check for Cancel press, the parfor loop can not be broken
            %         % so fast-forward to end
            %         if ~isempty(wb)
            %             wb.increment();
            %             % if wb.getCancelState; continue; end % skip all operations
            %         end
            %     end
            % end
            
            %% implementation with parfeval
            % open parallel pool
            
            % pool = gcp('nocreate');
            % %delete(pool);
            % if isempty(pool)
            %     pool = parpool(parforArg); %#ok<NASGU>
            % end
            zStarts = 1:zChunk:maxZ;
            failedSlabs = {};    % 'Z z1-z2: message' of the slab that failed
            isCancelled = false;
            for tIdx = 1:maxT
                if isCancelled; break; end
                if ~isempty(wb); wb.updateMaxNumberOfIterations(numel(zStarts)); end
                if parforArg == 0 % standard for-loop
                    for idx = 1:numel(zStarts)
                        try
                            ImageConverter.processZChunk(idx, zStarts, zChunk, maxZ, imageSwitch, ...
                                imageSize, imageType, imgDS, ...
                                levelNames, scaleZYX, zarrPath);
                        catch err
                            % a failed slab ends the run: the next one would most
                            % likely fail the same way (e.g. out of memory)
                            failedSlabs{end+1} = sprintf('Z %d-%d: %s', zStarts(idx), ...
                                min(zStarts(idx) + zChunk - 1, maxZ), err.message); %#ok<AGROW>
                            break;
                        end
                        if ~isempty(wb)
                            wb.increment();
                            % PoolWaitbar.increment() only updates the dialog's Value
                            % property via a DataQueue callback; without an explicit
                            % drawnow the App Designer uiprogressdlg never gets a
                            % chance to actually repaint during this tight, single-
                            % threaded loop, so the bar visibly never moves on a job
                            % that finishes in a second or two.
                            drawnow limitrate;
                            if wb.getCancelState()
                                isCancelled = true;
                                break;
                            end
                        end
                    end
                    if ~isempty(failedSlabs); break; end
                else  % parallel processing loop
                    % submit jobs
                    futures = parallel.FevalFuture.empty(numel(zStarts),0);
                    for idx = 1:numel(zStarts)
                        futures(idx) = parfeval(@ImageConverter.processZChunk, 0, ...
                            idx, zStarts, zChunk, maxZ, imageSwitch, ...
                            imageSize, imageType, imgDS, ...
                            levelNames, scaleZYX, zarrPath);
                    end

                    % collect in submission order (the jobs run concurrently anyway),
                    % so a failure is tied to its Z range; poll to keep Cancel responsive
                    for idx = 1:numel(futures)
                        while ~wait(futures(idx), 'finished', 1)
                            drawnow limitrate;
                            if ~isempty(wb) && wb.getCancelState(); break; end
                        end
                        if ~isempty(wb) && wb.getCancelState()
                            cancel(futures);   % cancel remaining futures
                            isCancelled = true;
                            break;
                        end
                        if ~isempty(futures(idx).Error)
                            % e.g. a worker killed for lack of memory: stop, the
                            % remaining slabs would most likely fail the same way
                            failedSlabs{end+1} = sprintf('Z %d-%d: %s', zStarts(idx), ...
                                min(zStarts(idx) + zChunk - 1, maxZ), futures(idx).Error.message); %#ok<AGROW>
                            disp(getReport(futures(idx).Error));  % show the real error
                            break;
                        end
                        if ~isempty(wb)
                            wb.increment();        % update progress bar safely here
                            drawnow limitrate;
                        end
                    end
                    if ~isempty(failedSlabs); break; end
                end

            end

            parentFig = [];
            if ~isempty(obj.view) && isvalid(obj.view.gui); parentFig = obj.view.gui; end
            if ~isempty(failedSlabs)
                % the incomplete flag stays set: never report success after a failure
                if ~isempty(wb); delete(wb); end
                if parforArg > 0; cancel(futures); end
                failureText = sprintf(['The Zarr conversion failed at\n%s\n\n' ...
                    'The dataset in\n%s\nis incomplete; MIB warns about it when it is opened.'], ...
                    strjoin(failedSlabs, newline), zarrPath);
                fprintf('%s\n', failureText);
                utils.dlgs.showErrorDialog(parentFig, failureText, 'Zarr conversion failed');
                return;
            end
            if isCancelled
                delete(wb);
                cancelText = sprintf(['Zarr conversion cancelled.\n\nThe incomplete dataset is left in\n%s\n' ...
                    'MIB warns about it when it is opened.'], zarrPath);
                fprintf('%s\n', cancelText);
                if ~isempty(parentFig); uialert(parentFig, cancelText, 'Cancelled', 'Icon', 'warning'); end
                return;
            end

            % every slab written: drop the incomplete flag from the root attributes
            pyrun(["root = zarr.open_group(storePath, mode='a')", ...
                "attrs = dict(root.attrs)", ...
                "attrs.pop('mibIncomplete', None)", ...
                "root.attrs.put(attrs)"], storePath=zarrPath);

            t2 = toc(t2);
            if ~isempty(wb); delete(wb); end
            scalesText = 'Level    Scales (ZYX)    Image sizes(ZYX)';
            for scaleId = 1:numel(levelNames)
                scalesText = sprintf('%s\n%s     -> %d x %d x %d       ->  %d %d %d', scalesText, levelNames{scaleId}, scaleZYX(scaleId, :), levelImageSizes(scaleId, :));
            end
            reportText = sprintf('Multiscale Zarr written to: %s\n\n%s\n\nElapsed time is %f seconds', zarrPath, scalesText, t2);
            if ~isempty(parentFig); uialert(parentFig, reportText, 'Zarr conversion done!', 'Icon', 'success'); end
            
            fprintf('Multiscale Zarr written to: %s\nElapsed time is %f seconds\n', zarrPath, t2);
        end
        
    end
end

function imageConverterThemeChanged(obj, infoHtml)
% IMAGECONVERTERTHEMECHANGED - ThemeChangedFcn of the ImageConverter window: remap the
% standard dialog colors (Convert, Close) and rewrite the info page, whose colors are set
% for the theme at the time it is written (see utils.themeHtmlStyle).
utils.applyThemeColors(obj.view.gui);
hInfo = obj.view.handles.infoText;
hInfo.HTMLSource = [utils.themeHtmlStyle(obj.view.gui, hInfo.Parent.BackgroundColor), infoHtml];
end

function fileGeometry = sourceFileGeometry(filename, loaderOptions)
% SOURCEFILEGEOMETRY - Bounding box, size and pixel size of one file from its metadata only.
% Used by ImageConverter.readSourceGeometry for the first and last file of a stack.
% Returns [] when the file cannot be read; .boundingBox is [] when the file has no MIB
% bounding box (a numeric BoundingBox key, or a "BoundingBox" entry in ImageDescription).
% A prefill runs from widget callbacks, so any failure (unreadable file, a loader that
% returns an empty dictionary, missing keys) means "no geometry", never an error.
fileGeometry = [];
try
    extReg = io.ExtensionRegistryLoad();
    loader = io.LoaderFactory.create(extReg.resolveLoader(filename, 'Standard', 'Default'), loaderOptions);
    imgInfo = loader.loadMetadata({filename}, loaderOptions);
    if ~isa(imgInfo, 'dictionary') || ~isConfigured(imgInfo) || ...
            ~all(isKey(imgInfo, ["Width", "Height", "Depth", "pixSize"]))
        return;
    end

    boundingBox = [];
    if isKey(imgInfo, 'BoundingBox')
        bbValue = imgInfo{'BoundingBox'};
        if isnumeric(bbValue) && numel(bbValue) == 6; boundingBox = double(bbValue(:)'); end
    end
    if isempty(boundingBox) && isKey(imgInfo, 'ImageDescription')
        [bbPart, ~] = core.MibImage.splitImageDescription(char(imgInfo{'ImageDescription'}));
        coords = sscanf(bbPart, 'BoundingBox %f %f %f %f %f %f');
        if numel(coords) == 6; boundingBox = coords(:)'; end
    end

    fileGeometry = struct('boundingBox', boundingBox, ...
        'width', imgInfo{'Width'}, 'height', imgInfo{'Height'}, 'depth', imgInfo{'Depth'}, ...
        'pixSize', imgInfo{'pixSize'});
catch
    fileGeometry = [];
end
end
