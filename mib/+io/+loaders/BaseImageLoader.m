classdef (Abstract) BaseImageLoader < handle
% BASEIMAGELOADER - Abstract base class for image format loaders.
%
% Base class providing common functionality shared across all image format loaders
% in MIB. Defines the interface that all loaders must implement and provides utility
% methods for handling custom sections, bounding box calculations, and slice name
% generation. Child classes (BioFormatsStdLoader, HDF5HeaderLoader, etc.) extend
% this class to implement format-specific metadata and image loading logic.
    
    properties
        Options struct  % Options structure passed during construction
        mibPath  (1,:) char = ''
        % Path to MIB installation directory.
        % Used for resource lookup and dialog icons.
        % Set from options.mibPath at construction time; empty in standalone use.
        ParentFigure = []
        % Handle to the main MIB application window.
        % Required as parent for uiprogressdlg progress bars.
        % Set from options.ParentFigure at construction time; empty in standalone use.
    end
    
    methods (Abstract)
        [imginfo, files] = loadMetadata(obj, filenames, options)
        % LOADMETADATA - Load metadata for image files (abstract method).
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [imginfo, files] = obj.loadMetadata(filenames, options)
        %
        % This abstract method must be implemented by child classes to extract
        % format-specific metadata from image files.
        %
        % Input Arguments:
        %   - **filenames** — [cell] cell array with filenames of images to load
        %   - **options** — *(optional)* [struct] options for metadata loading
        %
        % Output Arguments:
        %   - **imginfo** — [dictionary] image metadata, including ``pixSize`` structure
        %   - **files** — [struct array] file information and dimensions

        [img, imginfo] = loadImages(obj, files, imginfo, options)
        % LOADIMAGES - Load image data from files (abstract method).
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [img, imginfo] = obj.loadImages(files, imginfo, options)
        %
        % This abstract method must be implemented by child classes to load
        % actual image data using format-specific readers.
        %
        % Input Arguments:
        %   - **files** — [struct array] from ``loadMetadata`` with file information
        %   - **imginfo** — [dictionary] from ``loadMetadata`` with image metadata
        %   - **options** — *(optional)* [struct] options for image loading
        %
        % Output Arguments:
        %   - **img** — [matrix] loaded image dataset ``[height, width, colors, depth]``
        %   - **imginfo** — [dictionary] updated with final metadata
    end
    
    methods (Access = protected)
        function initBaseProps(obj, options)
            % INITBASEPROPS - Extract mibPath and ParentFigure from options struct into properties.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.initBaseProps(options)
            %
            % Call this at the end of every concrete loader constructor after
            % ``obj.Options`` has been set.
            %
            % Input Arguments:
            %   - **options** — *(optional)* struct with recognized fields:
            %
            %     - ``.mibPath`` — [char] path to MIB installation directory
            %     - ``.ParentFigure`` — handle to main MIB window for ``uiprogressdlg``
            %
            %     Both fields are optional; absent or empty values are silently ignored.
            %
            % Output Arguments:
            %   (none)
            %
            if nargin < 2 || isempty(options); return; end
            if isfield(options, 'mibPath') && ~isempty(options.mibPath)
                obj.mibPath = options.mibPath;
            end
            if isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
                obj.ParentFigure = options.ParentFigure;
            end
        end

        function wb = createProgressDialog(obj, title, message, cancelable, indeterminate)
            % CREATEPROGRESSDIALOG - Create a uiprogressdlg attached to obj.ParentFigure, or return [].
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      wb = obj.createProgressDialog(title, message, cancelable, indeterminate)
            %
            % When no valid parent is available (standalone or headless use),
            % an empty array is returned.
            %
            % Input Arguments:
            %   - **title** — [char] dialog title bar text
            %   - **message** — [char] dialog body message
            %   - **cancelable** — *(optional)* [logical] show Cancel button; default: ``false``
            %   - **indeterminate** — *(optional)* [logical] indeterminate spinner mode; default: ``false``
            %
            % Output Arguments:
            %   - **wb** — ``matlab.ui.dialog.ProgressDialog`` handle, or ``[]`` when no
            %     parent figure is available. Callers must guard all ``wb`` access
            %     with ``if ~isempty(wb) ... end``
            %
            if nargin < 4; cancelable    = false; end
            if nargin < 5; indeterminate = false; end

            wb = [];
            if isempty(obj.ParentFigure); return; end
            try
                if ~isvalid(obj.ParentFigure); return; end
            catch; return; end

            try
                args = {'Title', title, 'Message', message};
                if indeterminate
                    args = [args, {'Indeterminate', 'on'}];
                elseif cancelable
                    args = [args, {'Cancelable', 'on'}];
                end
                wb = uiprogressdlg(obj.ParentFigure, args{:});
            catch
                wb = [];
            end
        end

        function [files, imginfo, cancelled] = handleCustomSections(~, files, imginfo, options)
            % HANDLECUSTOMSECTIONS - Handle custom section loading dialog and adjustments.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [files, imginfo, cancelled] = obj.handleCustomSections(files, imginfo, options)
            %
            % This method displays a dialog for selecting a custom region to load
            % and adjusts the files structure, pixel size, and metadata accordingly.
            % It supports XY binning, Z range selection, and file subsampling.
            %
            % Input Arguments:
            %   - **files** — structure array with file information:
            %
            %     - ``.filename`` — [char] full filename
            %     - ``.width`` — [numeric] image width
            %     - ``.height`` — [numeric] image height
            %     - ``.noLayers`` — [numeric] number of image frames
            %
            %   - **imginfo** — dictionary with image metadata; key ``'pixSize'``
            %     holds a structure with voxel dimensions:
            %
            %     - ``.x`` — [numeric] pixel width in physical units
            %     - ``.y`` — [numeric] pixel height in physical units
            %     - ``.z`` — [numeric] slice thickness in physical units
            %     - ``.units`` — [char] physical units label
            %
            %   - **options** — struct with settings:
            %
            %     - ``.customSections`` — [logical] load custom region
            %     - ``.customSectionsSettings`` — *(optional)* [struct] saved region bounds
            %     - ``.xMin`` — [numeric] min X coordinate
            %     - ``.xMax`` — [numeric] max X coordinate
            %     - ``.yMin`` — [numeric] min Y coordinate
            %     - ``.yMax`` — [numeric] max Y coordinate
            %     - ``.zMin`` — [numeric] min Z coordinate
            %     - ``.zMax`` — [numeric] max Z coordinate
            %     - ``.xyStep`` — [numeric] XY binning step
            %     - ``.mibPath`` — [char] path to MIB directory
            %     - ``.ParentFigure`` — handle to the parent window
            %     - ``.waitbar`` — [logical] show or hide the waitbar
            %
            % Output Arguments:
            %   - **files** — updated structure array with custom section parameters
            %     (``.xMin``, ``.xMax``, ``.yMin``, ``.yMax``, ``.zMin``, ``.zMax``, ``.xyStep``
            %     added/updated; dimensions `` `.width` ``, `` `.height` ``, `` `.noLayers` `` adjusted)
            %   - **imginfo** — updated dictionary with adjusted ``'pixSize'`` structure
            %   - **cancelled** — [logical] ``true`` if user cancelled the dialog
            %
            % **Example 1** — load custom section with user dialog:
            %
            %   .. code-block:: matlab
            %
            %      [files, imginfo, cancelled] = obj.handleCustomSections(files, imginfo, options);
            %      if cancelled; return; end
            %
            
            cancelled = false;
            
            if ~options.customSections
                return;
            end
            
            % Calculate maximum dimensions across all files
            maxWidthSeries = max([files.width]);
            maxHeightSeries = max([files.height]);
            maxDepthSeries = max([files.noLayers]);
            
            % Define dialog prompts
            prompts = {sprintf('X min'); sprintf('X max (%d px)', maxWidthSeries); ...
                sprintf('Y min'); sprintf('Y max (%d px)', maxHeightSeries); ...
                sprintf('Z min'); sprintf('Z max (%d px)', maxDepthSeries); ...
                'XY step (not for BioFormats)'; 'Load each Nth file'};
            
            % Set default values from settings or use max dimensions
            if isfield(options, 'customSectionsSettings')
                defAns = {
                    struct('Spinner', true, 'Value', options.customSectionsSettings.xMin, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.xMax, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.yMin, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.yMax, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.zMin, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.zMax, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', options.customSectionsSettings.xyStep, 'Limits', [1 Inf], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 Inf], 'Round', true)};
            else
                defAns = {
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', maxWidthSeries, 'Limits', [1 maxWidthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', maxHeightSeries, 'Limits', [1 maxHeightSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', maxDepthSeries, 'Limits', [1 maxDepthSeries], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 Inf], 'Round', true), ...
                    struct('Spinner', true, 'Value', 1, 'Limits', [1 Inf], 'Round', true)};
            end
            
            % Show dialog
            dlgTitle = 'Define region to load';
            header = 'Provide image range to load';
            dlgOptions.Columns = 2;
            dlgOptions.WindowWidth = 640;
            dlgOptions.WindowHeight = 220;
            dlgOptions.mibPath = obj.mibPath;

            parentFig = obj.ParentFigure;
            if isempty(parentFig) && isfield(options, 'ParentFigure')
                parentFig = options.ParentFigure;
            end
            answer = utils.dlgs.inputUniversalDlg(parentFig, header, prompts, defAns, dlgTitle, dlgOptions);
            
            if isempty(answer)
                if options.waitbar; delete(options.waitbar); end
                cancelled = true;
                return;
            end
            
            pixSize = imginfo("pixSize");

            % Extract user selections
            xMin = answer{1};
            xMax = answer{2};
            yMin = answer{3};
            yMax = answer{4};
            zMin = answer{5};
            zMax = answer{6};
            xyStep = answer{7};
            fileLoadStep = answer{8};
            
            % Adjust files if loading every Nth file
            if fileLoadStep > 1
                files = files(1:fileLoadStep:numel(files));
            end
            
            % Correct pixel size for XY binning
            if xyStep > 1
                pixSize.x = pixSize.x * xyStep;
                pixSize.y = pixSize.y * xyStep;
            end
            
            % Update files structure with custom section parameters
            for i = 1:numel(files)
                files(i).xMin = max(xMin, 1);
                files(i).xMax = min(xMax, maxWidthSeries);
                files(i).yMin = max(yMin, 1);
                files(i).yMax = min(yMax, maxHeightSeries);
                files(i).zMin = max(zMin, 1);
                files(i).zMax = min(zMax, maxDepthSeries);
                files(i).xyStep = xyStep;
                files(i).height = ceil((files(i).yMax - files(i).yMin + 1) / xyStep);
                files(i).width = ceil((files(i).xMax - files(i).xMin + 1) / xyStep);
                files(i).noLayers = files(i).zMax - files(i).zMin + 1;
            end
            % update pixSize in imginfo dictionary
            imginfo("pixSize") = pixSize;
        end
        
        function imginfo = handleDimensionMismatches(~, files, imginfo)
            % HANDLEDIMENSIONMISMATCHES - Handle dimension mismatches and recalculate bounding box.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imginfo = obj.handleDimensionMismatches(files, imginfo)
            %
            % This method updates the ``ImageDescription`` field with correct bounding
            % box coordinates when files have different dimensions or when custom
            % sections are loaded. It ensures spatial consistency across the dataset.
            %
            % Input Arguments:
            %   - **files** — structure array with file information:
            %
            %     - ``.width`` — [numeric] image width
            %     - ``.height`` — [numeric] image height
            %     - ``.noLayers`` — [numeric] number of layers
            %     - ``.xMin``, ``.xMax``, ``.yMin``, ``.yMax`` — *(optional)* [numeric] region coordinates
            %     - ``.zMin``, ``.zMax`` — *(optional)* [numeric] slice range
            %
            %   - **imginfo** — dictionary with image metadata:
            %
            %     - ``'ImageDescription'`` — [char] description with ``BoundingBox`` info
            %     - ``'pixSize'`` — structure with voxel dimensions (``.x``, ``.y``, ``.z``)
            %
            % Output Arguments:
            %   - **imginfo** — updated dictionary with recalculated ``BoundingBox`` in ``'ImageDescription'``
            %
            % **Example 1** — recalculate bounding box for mismatched dimensions:
            %
            %   .. code-block:: matlab
            %
            %      imginfo = obj.handleDimensionMismatches(files, imginfo);
            %
            
            % get pixSize
            pixSize = imginfo{"pixSize"};

            % Check if dimension mismatch exists
            if numel(unique([files.width])) > 1 || numel(unique([files.height])) > 1
                if isfield(files, 'xMin')  % custom sections - recalculate bounding box
                    bbStart = strfind(imginfo{"ImageDescription"}, 'BoundingBox');
                    if ~isempty(bbStart)
                        brakePnt = strfind(imginfo{"ImageDescription"}, '|');
                        if isempty(brakePnt)
                            brakePnt = numel(imginfo{"ImageDescription"}) + 1;
                        end
                        try
                            brakePnt = brakePnt(1);
                            bbString = imginfo{"ImageDescription"};
                            bb = str2num(bbString(bbStart+11:brakePnt-1)); %#ok<ST2NM>
                        catch err
                            bb = [0 0 0 0 0 0];
                        end
                    else
                        bb = [0 0 0 0 0 0];
                    end
                    
                    if isfield(files, 'xMin')  % custom sections
                        bb(1) = bb(1) + (files(1).xMin - 1) * pixSize.x;  % xMin
                        bb(2) = bb(1) + (files(1).xMax - files(1).xMin) * pixSize.x;  % xMax
                        bb(3) = bb(3) + (files(1).yMin - 1) * pixSize.y;  % yMin
                        bb(4) = bb(3) + (files(1).yMax - files(1).yMin) * pixSize.y;  % yMax
                        bb(5) = bb(5) + (files(1).zMin - 1) * pixSize.z;  % zMin
                        bb(6) = bb(5) + (files(1).zMax - files(1).zMin) * pixSize.z;  % zMax
                    else
                        bb(2) = max([files.width]) * pixSize.x - bb(1);
                        bb(4) = max([files.height]) * pixSize.y - bb(3);
                        bb(6) = sum([files.noLayers]) * pixSize.z - bb(5);
                    end
                    
                    str2 = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f ', bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
                    currtext = imginfo{"ImageDescription"};
                    bbinfoexist = strfind(currtext, 'BoundingBox');
                    
                    if bbinfoexist == 1
                        spaces = strfind(currtext, ' ');
                        if ~isempty(spaces)
                            imginfo{"ImageDescription"} = [str2 currtext(spaces(7):end)];
                        else
                            imginfo{"ImageDescription"} = str2;
                        end
                    else
                        imginfo{"ImageDescription"} = [str2 ' ' currtext];
                    end
                end
            elseif isfield(files, 'xMin')  % custom sections without dimension mismatch
                bb = [0 0 0 0 0 0];
                bb(1) = bb(1) + (files(1).xMin - 1) * pixSize.x;
                bb(2) = bb(1) + (files(1).xMax - files(1).xMin) * pixSize.x;
                bb(3) = bb(3) + (files(1).yMin - 1) * pixSize.y;
                bb(4) = bb(3) + (files(1).yMax - files(1).yMin) * pixSize.y;
                bb(5) = bb(5) + (files(1).zMin - 1) * pixSize.z;
                bb(6) = bb(5) + (files(1).zMax - files(1).zMin) * pixSize.z;
                
                bbString = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f ', bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
                imginfo{"ImageDescription"} = bbString;
            end
        end
        
        function imginfo = generateSliceNames(~, files, imginfo)
            % GENERATESLICENAMES - Generate slice names from filenames.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imginfo = obj.generateSliceNames(files, imginfo)
            %
            % This method creates a cell array of slice names based on the source
            % filenames. Each slice is named after the file it originated from,
            % which helps track data provenance in multi-file datasets.
            %
            % Input Arguments:
            %   - **files** — structure array with file information:
            %
            %     - ``.filename`` — [char] full filename
            %     - ``.noLayers`` — [numeric] number of layers per file
            %
            %   - **imginfo** — dictionary with image metadata
            %
            % Output Arguments:
            %   - **imginfo** — updated dictionary with ``'SliceName'`` field (cell array of slice names for each layer)
            %
            % **Example 1** — generate slice names and display the first one:
            %
            %   .. code-block:: matlab
            %
            %      imginfo = obj.generateSliceNames(files, imginfo);
            %      disp(imginfo{"SliceName"}{1});
            %
            
            if numel(files) > 1
                totalLayers = sum([files.noLayers]);
                SliceName = cell(totalLayers, 1);
                index = 1;
                for fileId = 1:numel(files)
                    [~, fnShort, ext] = fileparts(files(fileId).filename);
                    fullName = [fnShort, ext];
                    endIdx = index + files(fileId).noLayers - 1;
                    SliceName(index:endIdx) = {fullName};
                    index = endIdx + 1;
                end
                imginfo{"SliceName"} = SliceName;
            else
                [~, fnShort, ext] = fileparts(files.filename);
                imginfo{"SliceName"} = {[fnShort, ext]};
            end
        end

        function imginfo = generateSliceSizes(~, files, imginfo)
            % GENERATESLICESIZES - Generate per-slice original dimensions when sizes differ.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imginfo = obj.generateSliceSizes(files, imginfo)
            %
            % This method creates a cell array of [height, width] vectors per slice
            % when the loaded files have different spatial dimensions. When all files
            % share the same height and width, the method does nothing (SliceSize
            % stays at its default empty value), avoiding unnecessary overhead.
            %
            % Input Arguments:
            %   - **files** — structure array with file information:
            %
            %     - ``.height`` — [numeric] image height for this file
            %     - ``.width`` — [numeric] image width for this file
            %     - ``.noLayers`` — [numeric] number of layers per file
            %
            %   - **imginfo** — dictionary with image metadata
            %
            % Output Arguments:
            %   - **imginfo** — updated dictionary with ``'SliceSize'`` field
            %     (``[N×2]`` double matrix, each row ``[height, width]``) when dimensions differ;
            %     unchanged otherwise
            %
            % **Example 1** — generate slice sizes and display the first one:
            %
            %   .. code-block:: matlab
            %
            %      imginfo = obj.generateSliceSizes(files, imginfo);
            %      disp(imginfo{"SliceSize"}(1,:));  % e.g. [512, 256]
            %

            heights = [files.height];
            widths  = [files.width];
            if numel(unique(heights)) > 1 || numel(unique(widths)) > 1
                totalLayers = sum([files.noLayers]);
                SliceSize = zeros(totalLayers, 2);
                index = 1;
                for fileId = 1:numel(files)
                    endIdx = index + files(fileId).noLayers - 1;
                    SliceSize(index:endIdx, :) = repmat([files(fileId).height, files(fileId).width], [files(fileId).noLayers, 1]);
                    index = endIdx + 1;
                end
                imginfo{"SliceSize"} = SliceSize;
            end
        end

        function imginfo = finalizeImgInfo(~, imginfo, files, filename)
            % FINALIZEIMGINFO - Finalize imginfo dictionary with missing values.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imginfo = obj.finalizeImgInfo(imginfo, files, filename)
            %
            % Input Arguments:
            %   - **imginfo** — dictionary with image metadata; used/updated keys:
            %
            %     - ``'MaxInt'`` — [numeric] max value available for the data class
            %     - ``'Colors'`` — [numeric] number of color channels
            %     - ``'imgClass'`` — [char] image class (``'uint8'``, ``'uint16'``, etc.)
            %     - ``'Depth'`` — [numeric] total number of sections
            %     - ``'Height'`` — [numeric] image height
            %     - ``'Width'`` — [numeric] image width
            %     - ``'Time'`` — [numeric] number of time points
            %     - ``'Filename'`` — [char] final filename for the combined dataset
            %
            %   - **files** — structure array with file information:
            %
            %     - ``.width`` — [numeric] image width
            %     - ``.height`` — [numeric] image height
            %     - ``.noLayers`` — [numeric] number of layers
            %     - ``.color`` — [numeric] number of color channels
            %     - ``.time`` — [numeric] number of time points
            %     - ``.imgClass`` — [char] image class
            %     - ``.xMin``, ``.xMax``, ``.yMin``, ``.yMax`` — *(optional)* [numeric] region coordinates
            %     - ``.zMin``, ``.zMax`` — *(optional)* [numeric] slice range
            %
            %   - **filename** — [char] final filename to store in ``imginfo``
            %
            % Output Arguments:
            %   - **imginfo** — updated dictionary with computed/filled-in values
            %
            
            % update Max value depending on the class
            switch files(1).imgClass
                case {'single', 'double'}
                    imginfo{"MaxInt"} = realmax(files(1).imgClass);
                otherwise
                    imginfo{"MaxInt"} = double(intmax(files(1).imgClass));
            end

            % sync viewPort.max to MaxInt so 16-bit images aren't displayed
            % with a uint8 ceiling (255) when no loader has set it explicitly
            viewPort = imginfo{"viewPort"};
            viewPort.max = imginfo{"MaxInt"};
            imginfo{"viewPort"} = viewPort;

            % update the lutColors
            if isKey(imginfo, 'lutColors')
                currColors = imginfo{'lutColors'};
                numColors = size(currColors, 1); % current number of colors in LUT
                numNeeded = max([files.color]);        % required number of colors in LUT
                
                if numNeeded > numColors
                    % Use modular indexing to repeat the pattern
                    lutColors = currColors(mod(0:numNeeded-1, numColors) + 1, :);
                    imginfo{'lutColors'} = lutColors;
                end
            end

            % update other fields
            imginfo{"Colors"} = files(1).color;
            imginfo{"imgClass"} = files(1).imgClass;
            imginfo{"Depth"} = sum([files.noLayers]);
            imginfo{"Filename"} = filename;

            if isempty(imginfo{"Height"}); imginfo{"Height"} = max([files.height]); end
            if isempty(imginfo{"Width"}); imginfo{"Width"} = max([files.width]); end
            if isempty(imginfo{"Depth"}); imginfo{"Depth"} = max([files.noLayers]); end
            if isempty(imginfo{"Colors"}); imginfo{"Colors"} = max([files.color]); end
            if isempty(imginfo{"Time"}); imginfo{"Time"} = max([files.time]); end
        end

        function merged = mergeOptions(~, opts1, opts2)
            % MERGEOPTIONS - Merge two options structures, with opts2 taking precedence.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      merged = obj.mergeOptions(opts1, opts2)
            %
            % This utility method combines two options structures, where fields
            % in ``opts2`` override those in ``opts1``. This allows runtime options to
            % override constructor options.
            %
            % Input Arguments:
            %   - **opts1** — *(optional)* struct, first options structure (lower priority)
            %   - **opts2** — *(optional)* struct, second options structure (higher priority)
            %
            % Output Arguments:
            %   - **merged** — struct, merged options structure with ``opts2`` fields overriding ``opts1``
            %
            % **Example 1** — merge options with higher-priority override:
            %
            %   .. code-block:: matlab
            %
            %      opts1.waitbar = false;
            %      opts2.waitbar = true;
            %      merged = obj.mergeOptions(opts1, opts2);
            %      % merged.waitbar will be true
            %
            
            merged = opts1;
            if isempty(opts2); return; end
            
            fields = fieldnames(opts2);
            for i = 1:numel(fields)
                merged.(fields{i}) = opts2.(fields{i});
            end
        end

        function [img, imginfo] = finalizeImageLoading(obj, img, imginfo, options)
            % FINALIZEIMAGELOADING - Finalize image loading by stretching uint32 and setting color type.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.finalizeImageLoading(img, imginfo, options)
            %
            % This method handles uint32-to-uint16 conversion (when ``options.imgStretch`` is ``true``)
            % and ensures ``ColorType`` and ``Colormap`` are properly set in imginfo.
            %
            % Input Arguments:
            %   - **img** — [matrix] image data
            %   - **imginfo** — [dictionary] image information; updated keys:
            %
            %     - ``'ColorType'`` — [char] color space: ``'grayscale'`` | ``'multichannel'`` | ``'indexed'``
            %     - ``'Colormap'`` — *(optional)* [numeric] colormap for indexed images
            %     - ``'ColorTable'`` — *(optional)* [numeric] color lookup table (copied to Colormap if set)
            %     - ``'ImageDescription'`` — *(optional)* [char] image description (created if missing)
            %
            %   - **options** — [struct] settings:
            %
            %     - ``.imgStretch`` — [logical] apply uint32-to-uint16 conversion; default: ``false``
            %     - ``.ParentFigure`` — [handle] parent window for dialogs
            %
            % Output Arguments:
            %   - **img** — [matrix] processed image (may be uint16 after stretching, or ``[]`` if cancelled)
            %   - **imginfo** — [dictionary] updated with finalized color type and mapping

            % Handle uint32 to uint16 conversion
            if isa(img, 'uint32') && options.imgStretch
                [img, imginfo] = obj.stretch32bitImage(img, imginfo);
                if isempty(img); return; end
            end

            % Set color type
            if ~isKey(imginfo, "ColorType")
                if size(img, 4) == 1
                    imginfo{"ColorType"} = 'grayscale';
                else
                    imginfo{"ColorType"} = 'multichannel';
                end
            else
                if strcmp(imginfo{"ColorType"}, 'indexed')
                    if ~isKey(imginfo, "Colormap")
                        % Copy ColorTable to Colormap for indexed images
                        imginfo{"Colormap"} = imginfo{"ColorTable"};
                    end
                else
                    if size(img, 4) == 1
                        imginfo{"ColorType"} = 'grayscale';
                    else
                        imginfo{"ColorType"} = 'multichannel';
                    end
                end
            end

            % Ensure ImageDescription exists
            if ~isKey(imginfo, "ImageDescription")
                imginfo{"ImageDescription"} = '';
            end
        end

        function [img, imginfo] = stretch32bitImage(obj, img, imginfo)
            % STRETCH32BITIMAGE - Stretch uint32 image into uint16 container.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [img, imginfo] = obj.stretch32bitImage(img, imginfo)
            %
            % Prompts the user to specify min/max intensity values for the stretch operation,
            % then rescales the uint32 image to the 0–65535 range of uint16. Used when loading
            % uint32 images that need to be converted to uint16 for compatibility.
            %
            % Input Arguments:
            %   - **img** — [matrix] uint32 image data to be converted
            %   - **imginfo** — [dictionary] image metadata; updated keys:
            %
            %     - ``'MaxInt'`` — [numeric] max possible value (set to ``65535`` for uint16)
            %     - ``'imgClass'`` — [char] image class name (set to ``'uint16'``)
            %
            % Output Arguments:
            %   - **img** — [matrix] uint16 image data (rescaled), or ``[]`` if user cancels
            %   - **imginfo** — [dictionary] updated with finalized ``MaxInt`` and ``imgClass``
            %
           

            minVal = double(min(img(:)));
            maxVal = double(max(img(:)));
            if maxVal <= minVal; maxVal = minVal + 1; end     % guard against a flat image

            prompt = {sprintf('Enter minimal intensity value\n(this value will be set to 0)'); ...
                      sprintf('Enter maximal intensity value\n(this value will be set to 65535)')};
            defAns = {struct('Spinner', true, 'Value', minVal, 'Limits', [minVal maxVal-1], 'Step', 1, 'Round', true); ...
                      struct('Spinner', true, 'Value', maxVal, 'Limits', [minVal+1 maxVal], 'Step', 1, 'Round', true)};

            mibInputMultiDlgOpt.WindowWidth = 400;
            mibInputMultiDlgOpt.WindowHeight = 180;
            mibInputMultiDlgOpt.SectionsColumnWidths = {'fit', 100};
            mibInputMultiDlgOpt.mibPath = obj.mibPath;
            answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, ...
                '', prompt, defAns, 'Conversion to 16bit format', mibInputMultiDlgOpt);
            if isempty(answer); img = []; return; end
            %drawnow;  % prevent crashes

            minVal = answer{1};
            maxVal = answer{2};

            % Convert to uint16; the rescaling has to be done in a floating point
            % class, because a division of an integer array rounds the result to
            % integers and would collapse the image to a 0/65535 bitmap.
            % The conversion is done slice-by-slice to keep the peak memory low,
            % the values outside [minVal maxVal] are clipped by the uint16 cast
            scaleFactor = 65535 / (maxVal - minVal);
            imgOut = zeros(size(img), 'uint16');
            for sliceIndex = 1:size(img, 3)
                imgOut(:,:,sliceIndex,:,:) = uint16((double(img(:,:,sliceIndex,:,:)) - minVal) * scaleFactor);
            end
            img = imgOut;
            clear imgOut;

            % update imginfo dictionary
            imginfo{'MaxInt'} = double(intmax('uint16'));
            imginfo{'imgClass'} = 'uint16';

            % sync the viewPort with the new class, otherwise the display max stays
            % at the uint32 ceiling that was defined during the metadata loading
            if isKey(imginfo, 'viewPort') && ~isempty(imginfo{'viewPort'})
                viewPort = imginfo{'viewPort'};
                viewPort.min = zeros(size(viewPort.min));
                viewPort.max = zeros(size(viewPort.max)) + imginfo{'MaxInt'};
                imginfo{'viewPort'} = viewPort;
            end
        end
    end
end
