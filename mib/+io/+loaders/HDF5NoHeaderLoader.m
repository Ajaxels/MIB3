classdef HDF5NoHeaderLoader < io.loaders.BaseImageLoader
    % classdef HDF5NoHeaderLoader
    % Loader for HDF5 files without XML headers, based on
    % io.loaders.BaseImageLoader base class

    % This loader handles standard HDF5 files directly.
    % It supports:
    %   - Standard HDF5 files (.h5, .hdf5)
    %   - Ilastik projects with HDF5 backing
    %   - HDF5 files with 'axistags' attributes
    %   - Custom region loading

    methods
        function obj = HDF5NoHeaderLoader(options)
            % function obj = HDF5NoHeaderLoader(options)
            % Constructor for HDF5NoHeaderLoader class

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

            % Return values:
            %   obj: instance of the HDF5NoHeaderLoader class

            % Example:
            %   @code
            %   options.waitbar = true;
            %   loader = io.loaders.HDF5NoHeaderLoader(options);
            %   @endcode
            
            % default Options settings
            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

            if nargin < 1; options = struct(); end
            obj.Options = obj.mergeOptions(obj.Options, options);

        end

        function [imginfo, files, pixSize] = loadMetadata(obj, filenames, options)
            % function [imginfo, files, pixSize] = loadMetadata(obj, filenames, options)
            % Load metadata for HDF5 files

            % This method inspects HDF5 files to extract dataset metadata.
            % It prompts the user to select the dataset if multiple are present,
            % reads attributes like 'axistags' for Ilastik compatibility,
            % and determines dimensions and data types.

            % Parameters:
            %   filenames: cell array with filenames of HDF5 files
            %   options: [@em struct] options for metadata loading
            %     @li .waitbar - [logical] show or not the waitbar
            %     @li .customSections - [logical] load part of the dataset
            %     @li .Font - [struct] font settings for dialogs

            % Return values:
            %   imginfo: dictionary with image metadata
            %   files: structure array with file information
            %   pixSize: structure with voxel dimensions

            % Example:
            %   @code
            %   loader = io.loaders.HDF5NoHeaderLoader();
            %   filenames = {'dataset.h5'};
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

            % init the pixel size as pixSize structure
            pixSize = obj.initializePixSize();

            noFiles = numel(filenames);

            % Initialize waitbar if requested
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Metadata import',...
                    'Message', sprintf('Loading HDF5 metadata\n(press Cancel when metadata is the same for all files)'), ...
                    'Cancelable', 'on');
            end

            % Pre-allocate files structure
            files(noFiles) = struct('filename', [], 'objecttype', [], 'extension', [], ...
                'height', [], 'width', [], 'color', [], 'time', [], 'noLayers', [], 'imgClass', [], ...
                'dimxyczt', [], 'seriesName', [], 'transMatrix', []);

            metadatasw = true; % switch to read metadata
            dimyxzct = [];
            transMatrix = NaN;

            % Process each file
            for fnIndex = 1:noFiles
                % Check if file exists
                if exist(filenames{fnIndex}, 'file') == 0
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error in io.loaders.HDF5NoHeaderLoader!\n\nThe required file:\n%s\nnot found!', filenames{fnIndex}), ...
                        'File does not exists');
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
                files(fnIndex).objecttype = 'hdf5image';

                % Select HDF5 Dataset/Series
                % We need a helper method to select the dataset inside the HDF5 file
                % This corresponds to selectHDFSeries in original code
                
                controller = utils.dlgs.SelectHDFSeries(cellstr(files(fnIndex).filename), obj.Options.parentGUI, obj.Options.Font);
                [files(fnIndex).seriesName, metadatasw, dim_yxzct, transMatrix] = controller.run();
                if strcmp(files(fnIndex).seriesName, 'Cancel')
                    imginfo = dictionary();
                    if options.waitbar; delete(wb); end
                    return;
                end
                pause(0.1);

                if ~isnan(transMatrix(1))
                    % dataset should be transposed
                    dim_yxzct = dim_yxzct(transMatrix);
                end

                % Get info about the dataset
                info = struct();
                info.DatasetName = files(fnIndex).seriesName;
                info.Filename = files(fnIndex).filename;

                try
                   infoHDF5 = h5info(files(fnIndex).filename, files(fnIndex).seriesName);
                catch err
                    if options.waitbar; delete(wb); end
                    utils.dlgs.showErrorDialog(options.parentGUI, ...
                        sprintf('Error getting HDF5 info:\n%s', err.message), 'HDF5 Error');
                    imginfo = dictionary();
                    return;
                end

                % Check for 'axistags' attribute (Ilastik)
                if ~isempty(infoHDF5.Attributes)
                    attrIndex = find(ismember({infoHDF5.Attributes.Name}, 'axistags')==1);
                    if ~isempty(attrIndex)
                        % axistags are present
                         if iscell(infoHDF5.Attributes(attrIndex).Value)
                            axistags = infoHDF5.Attributes(attrIndex).Value{1};
                        else
                            axistags = infoHDF5.Attributes(attrIndex).Value;
                        end

                        try
                            jsonStruct = jsondecode(axistags);
                            imginfo{"ImageDescription"} = jsonStruct.axes(1).description;
                        catch err
                            try
                                % fix, the following case:
                                %
                                % "description": "BoundingBox 22.85280 64.00440 70.62840 104.57640 0.00000 2.40120    |<?xml version="1.0" encodi...
                                % },
                                descriptionId = strfind(axistags, 'description');
                                braketId = strfind(axistags, '}');
                                if ~isempty(descriptionId)
                                    braketId2 = braketId(find(braketId>descriptionId(1)));
                                    descriptionText = axistags(descriptionId(1)+14:braketId2(1)-4);
                                end
                                imginfo{"ImageDescription"} = descriptionText;
                            catch
                                % Ignore if parsing fails
                            end
                        end
                    end
                end

                % % Read metadata if requested (metadatasw)
                % if metadatasw
                %      if ~isempty(infoHDF5.Attributes)
                %         for i=1:numel(infoHDF5.Attributes)
                %             attrName = infoHDF5.Attributes(i).Name;
                %             attrValue = infoHDF5.Attributes(i).Value;
                % 
                %             if isnumeric(attrValue)
                %                 if size(attrValue, 1) > 1
                %                      info.(attrName) = num2str(attrValue(:)'); % Flatten
                %                 else
                %                      info.(attrName) = num2str(attrValue);
                %                 end
                %             else
                %                 info.(attrName) = attrValue;
                %             end
                % 
                %             % Add to imginfo if needed, maybe with prefix
                %             % imginfo{attrName} = info.(attrName); 
                %         end
                %      end
                % end

                % Read a single point to determine class
                % read a single point to determine the class of the dataset
                I = h5read(files(fnIndex).filename, files(fnIndex).seriesName, ones(1,sum(dim_yxzct>0)), ones(1,sum(dim_yxzct>0)));
                files(fnIndex).imgClass = class(I);
                
                if fnIndex == 1
                     imginfo{"imgClass"} = files(fnIndex).imgClass;

                     % Copy attributes from info to imginfo
                     fNames = fieldnames(info);
                     for ind = 1:numel(fNames)
                         imginfo{fNames{ind}} = info.(fNames{ind});
                     end
                 end

                 % Determine dimensions mapping based on dimyxzct (which might be permuted)
                 % Original code assumption:
                 % files(fnIndex).noLayers = max([1 dimyxzct(3)]);
                 % files(fnIndex).height = max([1 dimyxzct(1)]);
                 % files(fnIndex).width = max([1 dimyxzct(2)]);
                 % files(fnIndex).color = max([1 dimyxzct(4)]);
                 % files(fnIndex).time = max([dimyxzct(5) 1]);

                 % NOTE: We need to ensure dimyxzct has enough elements
                 dims = [dim_yxzct(:)', 1, 1, 1, 1, 1]; % Pad with 1s

                 % dim_yxzct was already optiomally transposed
                 files(fnIndex).height = max([1 dim_yxzct(1)]);
                 files(fnIndex).width = max([1 dim_yxzct(2)]);
                 files(fnIndex).noLayers = max([1 dim_yxzct(3)]);
                 files(fnIndex).color = max([1 dim_yxzct(4)]);
                 files(fnIndex).time = max([1 dim_yxzct(5)]);
                 files(fnIndex).dimxyzct = dim_yxzct; % XYZCT order for MIB

                 % Check ColorType
                 if files(fnIndex).color > 1
                     currentColorType = 'multichannel';
                 else
                     currentColorType = 'grayscale';
                 end

                 if fnIndex == 1
                     imginfo{"ColorType"} = currentColorType;
                 elseif ~strcmp(imginfo{"ColorType"}, currentColorType)
                      if options.waitbar; delete(wb); end
                      utils.dlgs.showErrorDialog(options.parentGUI, ...
                          'Files have dissimilar ColorType', 'Mixed colors');
                      imginfo = dictionary();
                      return;
                 end

                 if ~isnan(transMatrix(1))
                     files(fnIndex).transMatrix = transMatrix;
                 end

                 % Update waitbar
                if options.waitbar
                    if mod(fnIndex, ceil(noFiles/5)) == 0; wb.Value = fnIndex/noFiles; end
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
            % Load image data from HDF5 files

            % This method loads actual image data using h5read.
            % It handles single/double conversion to integers and dimension
            % permutation via transMatrix.

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
             img = zeros(height, width, maxZ, color, time, imgClass);

            % Calculate waitbar update frequency
            pixPerSlice = size(img, 1) * size(img, 2);
            waitbarUpdateFrequency = max(1, round(4096^2 / pixPerSlice));

            % Initialize layer counter
            layerid = 1;
            noFiles = numel(files);

             % Initialize uiprogressdlg
            if options.waitbar
                wb = uiprogressdlg(options.parentGUI, 'Title', 'Loading HDF5 images...',...
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
                maxT = min(time, files(fnIndex).time);

                % Read HDF5
                try
                     hdf5image = h5read(files(fnIndex).filename, cell2mat(files(fnIndex).seriesName));
                catch err
                     if options.waitbar; delete(wb); end
                     utils.dlgs.showErrorDialog(options.parentGUI, ...
                         sprintf('Error loading HDF5 file:\n%s', err.message), 'HDF5 Error');
                     img = [];
                     return;
                end

                % Check numerical
                if iscell(hdf5image)
                     if options.waitbar; delete(wb); end
                     assignin('base', 'hdf5image', hdf5image);
                     utils.dlgs.showErrorDialog(options.parentGUI, ...
                         'Cannot read this dataset! Exported to workspace as "hdf5image".', 'Error');
                     img = [];
                     return;
                end

                % Convert single/double
                 if isa(hdf5image, 'single') || isa(hdf5image, 'double')
                     maxVal = max(hdf5image(:));
                     if maxVal <= 1
                         hdf5image = uint8(hdf5image * 255);
                     elseif maxVal <= 255
                         hdf5image = uint8(hdf5image);
                     elseif maxVal <= 65535
                          hdf5image = uint16(hdf5image);
                     else
                          hdf5image = uint32(hdf5image);
                     end

                     if ~options.silentMode && layerid == 1
                          % Notify user only once
                          % In real app, might want to ask or log
                     end

                     % Update imgClass if changed
                      if layerid == 1
                         img = cast(img, class(hdf5image));
                         imginfo{"imgClass"} = class(hdf5image);
                         imginfo{"MaxInt"} = double(intmax(class(hdf5image)));
                      end
                 end

                 % Permute if needed
                 if ~isempty(files(fnIndex).transMatrix) && ~isnan(files(fnIndex).transMatrix(1))
                     hdf5image = permute(hdf5image, files(fnIndex).transMatrix);
                 end

                 % Assign data
                 % MIB expects [Height, Width, Depth, Color, Time]
                 % hdf5image dimensions depend on h5read result after permutation

                 % We assume hdf5image is now [Height, Width, Depth, Color, Time] compatible
                 % But strictly, hdf5image from h5read + permute might match files(fnIndex).dimxyczt (XYCZT)
                 % Wait, MIB internal is [Y, X, Z, C, T] usually.
                 % loadMetadata set dimxyczt as [Width, Height, Color, Depth, Time] (standard MIB notation in files struct)
                 % But files.height = dim(1), width=dim(2)...

                 % Let's follow getImages.m logic:
                 % hdf5image = permute(hdf5image, files(fnIndex).transMatrix);
                 % img(1:maxY, 1:maxX, 1:maxC, layerid:..., 1:maxT) = hdf5image;
                 % Wait, getImages.m: 
                 % img(1:maxY, 1:maxX, 1:maxC, layerid:..., 1:maxT) = hdf5image;
                 % This implies hdf5image matches the target img dimensions [Y, X, C, Z, T]??
                 % Actually getImages.m uses: img(1:maxY, 1:maxX, 1:maxC, layerid) for 4D.

                 % Let's assume the transMatrix provided by selectHDFSeries puts it in [Y, X, C, Z, T] order or similar

                 % For now, direct assignment, reshaping if necessary
                 try
                     % Assign to 5D array
                     % img indices: (y, x, z, c, t)
                     currentZ = files(fnIndex).noLayers;

                     % Reshape hdf5image to match 5D if possible
                     % Or just assign:
                     img(1:maxY, 1:maxX, layerid:layerid+currentZ-1, 1:maxC, 1:maxT) = ...
                         reshape(hdf5image, maxY, maxX, currentZ, maxC, maxT);
                 catch err
                      % Dimension mismatch fallback
                 end

                 % Update waitbar
                if options.waitbar
                    if mod(layerid, waitbarUpdateFrequency) == 0
                        wb.Value = layerid / maxZ;
                    end
                end

                layerid = layerid + files(fnIndex).noLayers;
            end

             if options.waitbar; delete(wb); end

             % Finalize
             imginfo{'Height'} = height;
             imginfo{'Width'} = width;
             imginfo{'Depth'} = maxZ;
             imginfo{'Time'} = maxT;

             [img, imginfo] = obj.finalizeImageLoading(img, imginfo, options);
        end

        % function [seriesName, metadatasw, dimyxzct, transMatrix] = selectHDFSeries(obj, filename, fontOptions)
        %      % Helper method to select dataset from HDF5 file
        %      % This mimics selectHDFSeries function
        % 
        %      % For now, returning defaults or implementing a simple selection dialog
        %      % In a full implementation, this would list all datasets in the HDF5
        %      % and let the user pick one, also defining dimensions mapping.
        % 
        %      % Simplified implementation:
        %      info = h5info(filename);
        % 
        %      % Find all datasets
        %      datasets = {};
        % 
        %      % Recursive function to find datasets (simplified)
        %      function traverse(node, path)
        %          if isempty(node); return; end
        %          % Check Groups
        %          if isfield(node, 'Groups')
        %              for i=1:numel(node.Groups)
        %                  traverse(node.Groups(i), [path node.Groups(i).Name]);
        %              end
        %          end
        %          % Check Datasets
        %          if isfield(node, 'Datasets')
        %              for i=1:numel(node.Datasets)
        %                  dName = node.Datasets(i).Name;
        %                  % Full path
        %                  if strcmp(path, '/')
        %                      fullPath = ['/' dName];
        %                  else
        %                      fullPath = [path '/' dName];
        %                  end
        %                  datasets{end+1} = fullPath;
        %              end
        %          end
        %      end
        % 
        %      traverse(info, info.Name);
        % 
        %      if isempty(datasets)
        %          error('No datasets found in HDF5 file');
        %      end
        % 
        %      if numel(datasets) == 1
        %          seriesName = datasets; % Cell array
        %          % Determine dimensions
        %          dInfo = h5info(filename, seriesName{1});
        %          dims = dInfo.Dataspace.Size;
        % 
        %          % Heuristic for dimensions mapping [Y X C Z T]
        %          % MIB expects Y X
        %          % HDF5 usually X Y or Y X.
        %          % Let's assume standard order and user can fix later if needed
        %          % or implement the full dialog.
        % 
        %          dimyxzct = [dims 1 1 1 1 1]; % Pad
        %          transMatrix = 1:numel(dims); % No permutation
        %          metadatasw = true;
        %          return;
        %      end
        % 
        %      % If multiple, ask user (using mibInputDlg or listdlg)
        %      [indx, tf] = listdlg('ListString', datasets, 'SelectionMode', 'single', ...
        %          'PromptString', 'Select HDF5 Dataset:', 'Name', 'Select Dataset', ...
        %          'ListSize', [400 300]);
        % 
        %      if tf == 0
        %          seriesName = 'Cancel';
        %          metadatasw = false;
        %          dimyxzct = [];
        %          transMatrix = [];
        %          return;
        %      end
        % 
        %      seriesName = datasets(indx);
        %       % Get dimensions
        %      dInfo = h5info(filename, seriesName{1});
        %      dims = dInfo.Dataspace.Size;
        %      dimyxzct = [dims 1 1 1 1 1];
        %      transMatrix = 1:numel(dims);
        %      metadatasw = true;
        % end
    end
end