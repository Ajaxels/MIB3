classdef ChunkingExport < handle
% CHUNKINGEXPORT - Splits the current dataset into a Z×X×Y tile grid and saves tiles to disk.
%
% Each tile is saved as a separate image file.  Labels (segmentation model) and
% mask layers can optionally be exported alongside the images.
%
% A pyramidal dataset (Virtual or BigData OME-Zarr) can be chunked at any level
% of its pyramid (``BatchOpt.ZarrPyramidLevel``): the tile grid is laid out on
% that level, and the tiles carry its voxel size and a bounding box on its grid,
% so ``ChunkingImport`` (Fuse into existing) puts a model segmented on these
% tiles back into the matching level of the BigData model.
%
% Tiles can be written as OME-Zarr v3 stores; their pyramid, chunking and
% compression are the ``BatchOpt.Zarr*`` fields, edited with the settings
% button next to the level dropdown (``io.savers.Zarr3Saver.optionsDialog``).
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to ChunkingExportGUI
        listener
        % cell array of listener handles
        BatchOpt
        % struct compatible with batch processing
    end

    events
        CloseEvent
        % fired when window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Guard: clean up listeners and return silently if view closed.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods

        % ---------------------------------------------------------------
        function obj = ChunkingExport(mibModel, varargin)
            % CHUNKINGEXPORT - constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = ChunkingExport(mibModel)
            %       obj = ChunkingExport(mibModel, mibController, BatchOpt)
            %       obj = ChunkingExport(mibModel, mibController, NaN)
            %
            % Input Arguments:
            %   - **mibModel** - handle to MibModel
            %   - **varargin{1}** - *(optional)* handle to MibController
            %   - **varargin{2}** - *(optional)* BatchOpt struct or NaN (batch mode)
            %
            % Usage:
            %   Example 1::
            %
            %     obj.mibController.startController('controllers.ChunkingExport');
            %

            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();

            % ---- BatchOpt defaults
            obj.BatchOpt.TilesX = {2, [1, Inf], 'on'};
            obj.BatchOpt.TilesY = {1, [1, Inf], 'on'};
            obj.BatchOpt.TilesZ = {1, [1, Inf], 'on'};
            obj.BatchOpt.OutputDirectory = obj.mibModel.currentDirectory;
            [~, sourceFn] = fileparts(obj.mibModel.I{id}.image.filename);
            obj.BatchOpt.FilenameTemplate = [sourceFn '_chop'];
            obj.BatchOpt.ImageFormat    = {'Amira Mesh binary (*.am)'};
            obj.BatchOpt.ImageFormat{2} = {'Amira Mesh binary (*.am)', 'NRRD Data Format (*.nrrd)', 'TIF format uncompressed (*.tif)', 'Hierarchical Data Format with XML header (*.xml)', 'OME-Zarr v3 (*.zarr3)'};
            obj.BatchOpt.ModelFormat    = {'Matlab format (*.model)'};
            obj.BatchOpt.ModelFormat{2} = {'Matlab format (*.model)', 'Amira Mesh binary (*.am)', 'NRRD Data Format (*.nrrd)', 'TIF format (*.tif)', 'Hierarchical Data Format with XML header (*.xml)', 'OME-Zarr v3 (*.zarr3)'};
            obj.BatchOpt.HDF5SubFormat    = {'matlab.hdf5'};
            obj.BatchOpt.HDF5SubFormat{2} = {'matlab.hdf5', 'bdv.hdf5'};
            % pyramid level to chunk; updateWidgets trims the list to the levels of the dataset
            obj.BatchOpt.ZarrPyramidLevel{2} = arrayfun(@(x) sprintf('s%d', x), 0:9, 'UniformOutput', false);
            obj.BatchOpt.ZarrPyramidLevel(1) = obj.BatchOpt.ZarrPyramidLevel{2}(1);
            % OME-Zarr tile settings, edited with zarrSettingsButton_Callback
            obj.BatchOpt.ZarrLevels = {0, [0 12], 'on'};
            obj.BatchOpt.ZarrChunkSize = '128, 128, 4';
            obj.BatchOpt.ZarrShardFactors = '4, 4, 1';
            obj.BatchOpt.ZarrCompression    = {'zstd'};
            obj.BatchOpt.ZarrCompression{2} = {'zstd', 'gzip', 'none'};
            obj.BatchOpt.ZarrCompressionLevel = {0, [0 22], 'on'};
            obj.BatchOpt.ZarrDownsampleMethod    = {'bilinear'};
            obj.BatchOpt.ZarrDownsampleMethod{2} = {'bilinear', 'nearest', 'bicubic', 'median', 'mode'};
            obj.BatchOpt.ZarrDownsampleStrategy    = {'Anisotropy-preserving'};
            obj.BatchOpt.ZarrDownsampleStrategy{2} = {'XY only', 'Anisotropy-preserving'};
            obj.BatchOpt.ChunkModel  = false;
            obj.BatchOpt.ChunkMask   = false;
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
            obj.BatchOpt.mibBatchActionName  = 'Chunk dataset...';
            obj.BatchOpt.mibBatchTooltip.TilesX           = 'Number of tiles along X (columns)';
            obj.BatchOpt.mibBatchTooltip.TilesY           = 'Number of tiles along Y (rows)';
            obj.BatchOpt.mibBatchTooltip.TilesZ           = 'Number of tiles along Z (slices)';
            obj.BatchOpt.mibBatchTooltip.OutputDirectory  = 'Destination directory for tile files';
            obj.BatchOpt.mibBatchTooltip.FilenameTemplate = 'Filename prefix; tiles are appended as _Z##-X##-Y##';
            obj.BatchOpt.mibBatchTooltip.ImageFormat      = 'Output format for image tiles (.am .nrrd .tif .xml .zarr3)';
            obj.BatchOpt.mibBatchTooltip.ModelFormat      = 'Output format for label tiles (.model .am .nrrd .tif .xml .zarr3)';
            obj.BatchOpt.mibBatchTooltip.HDF5SubFormat    = 'HDF5 sub-format when ImageFormat is .xml (matlab.hdf5 or bdv.hdf5)';
            obj.BatchOpt.mibBatchTooltip.ZarrPyramidLevel = sprintf('[Pyramidal datasets only] Pyramid level to chunk, s0 = full resolution;\nthe number of tiles applies to this level');
            obj.BatchOpt.mibBatchTooltip.ZarrLevels       = '[Zarr tiles] Number of pyramid levels of each tile, 0 = auto';
            obj.BatchOpt.mibBatchTooltip.ZarrChunkSize    = '[Zarr tiles] Chunk size as Y, X, Z';
            obj.BatchOpt.mibBatchTooltip.ZarrShardFactors = '[Zarr tiles] Chunks per shard file as Y, X, Z; 0, 0, 0 = no sharding';
            obj.BatchOpt.mibBatchTooltip.ZarrCompression  = '[Zarr tiles] Compression of the chunks';
            obj.BatchOpt.mibBatchTooltip.ZarrCompressionLevel = '[Zarr tiles] Compression level: zstd 1-22, gzip 1-9; 0 = codec default (zstd 3, gzip 5)';
            obj.BatchOpt.mibBatchTooltip.ZarrDownsampleMethod   = '[Zarr tiles] Downsampling of the image pyramid; models always use nearest, or mode when selected';
            obj.BatchOpt.mibBatchTooltip.ZarrDownsampleStrategy = '[Zarr tiles] "XY only" or "Anisotropy-preserving" (also halves Z once voxels are near-isotropic)';
            obj.BatchOpt.mibBatchTooltip.ChunkModel       = 'Export the labels (segmentation model) layer';
            obj.BatchOpt.mibBatchTooltip.ChunkMask        = 'Export the mask layer';
            obj.BatchOpt.mibBatchTooltip.showWaitbar      = 'Show progress bar during export';

            % ---- Batch-mode path
            if nargin == 3
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput)
                    obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                    obj.chunkBtn_Callback(true);
                    notify(obj, 'CloseEvent');
                elseif isnan(BatchOptInput)
                    obj.returnBatchOpt();
                else
                    utils.dlgs.showErrorDialog([], ...
                        'A BatchOpt struct is required as the 3rd parameter.', ...
                        'ChunkingExport: init error');
                    notify(obj.mibModel, 'StopProtocol');
                end
                return;
            end

            % ---- GUI path
            guiName = 'views.ChunkingExportGUI';
            obj.view = core.ChildView(obj, guiName);
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
            obj.addCallbacks();

            % update font size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.ChunkButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.ChunkButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            % position GUI
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();
            % make GUI visible
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and clean up listeners.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire GUI widget callbacks.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.handles.CloseButton.ButtonPushedFcn     = @(~,~) obj.closeWindow();
            obj.view.handles.SelectDirButton.ButtonPushedFcn = @(~,~) obj.selectDirBtn_Callback();
            obj.view.handles.ChunkButton.ButtonPushedFcn    = @(~,~) obj.chunkBtn_Callback();
            obj.view.handles.HelpButton.ButtonPushedFcn      = @(~,~) obj.helpBtn_Callback();

            obj.view.handles.OutputDirectory.ValueChangedFcn  = @(hObject,~) obj.dirEdit_Callback(hObject);
            obj.view.handles.TilesX.ValueChangedFcn  = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.TilesY.ValueChangedFcn  = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.TilesZ.ValueChangedFcn  = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.FilenameTemplate.ValueChangedFcn  = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.ImageFormat.ValueChangedFcn       = @(h,~) obj.format_Callback(h);
            obj.view.handles.ModelFormat.ValueChangedFcn       = @(h,~) obj.format_Callback(h);
            obj.view.handles.ChunkModel.ValueChangedFcn        = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.ChunkMask.ValueChangedFcn         = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.ZarrPyramidLevel.ValueChangedFcn  = @(h,~) obj.ZarrPyramidLevel_Callback(h);
            obj.view.handles.zarrSettingsButton.ButtonPushedFcn = @(~,~) obj.zarrSettingsButton_Callback();
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh the GUI from the current dataset state.
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            % the level dropdown lists the levels of this dataset; s0 only without a pyramid
            isPyramidal = ~isempty(dataset.image.pyramid.levelNames);
            if isPyramidal
                levelItems = arrayfun(@(x) sprintf('s%d', x), 0:size(dataset.image.pyramid.levelImageSizes, 1)-1, 'UniformOutput', false);
            else
                levelItems = {'s0'};
            end
            if ~ismember(obj.BatchOpt.ZarrPyramidLevel{1}, levelItems)
                obj.BatchOpt.ZarrPyramidLevel{1} = levelItems{1};
            end
            obj.BatchOpt.ZarrPyramidLevel{2} = levelItems;
            obj.view.handles.ZarrPyramidLevel.Enable = matlab.lang.OnOffSwitchState(isPyramidal);
            obj.updateLevelInfo();

            obj.view.handles.ChunkModel.Enable = dataset.modelExist;
            obj.view.handles.ChunkMask.Enable  = dataset.maskExist;
            if ~dataset.modelExist; obj.BatchOpt.ChunkModel = false; end
            if ~dataset.maskExist;  obj.BatchOpt.ChunkMask  = false; end

            obj.BatchOpt.OutputDirectory = obj.mibModel.currentDirectory;
            [~, sourceFn] = fileparts(obj.mibModel.I{id}.image.filename);
            obj.BatchOpt.FilenameTemplate = [sourceFn '_chop'];

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.view.handles.zarrSettingsButton.Enable = ...
                contains(obj.BatchOpt.ImageFormat{1}, 'zarr') || contains(obj.BatchOpt.ModelFormat{1}, 'zarr');
        end

        % ---------------------------------------------------------------
        function updateLevelInfo(obj)
            % UPDATELEVELINFO - Show the dimensions and voxel size of the pyramid level to be chunked.
            %
            % The number of tiles applies to the selected level, so the dialog
            % shows that level rather than the full-resolution dataset.

            id = obj.mibModel.getActiveId();
            [~, levelSize, ~, levelPixSize] = obj.getLevelGeometry(id);
            obj.view.handles.InfoLabel.Text = sprintf('xmin-xmax: 1 - %d\nymin-ymax: 1 - %d\nzmin-zmax: 1 - %d', ...
                levelSize(2), levelSize(1), levelSize(3));
            obj.view.handles.PixSizeLabel.Text = sprintf('X: %g\nY: %g\nZ: %g', levelPixSize.x, levelPixSize.y, levelPixSize.z);
        end

        % ---------------------------------------------------------------
        function [levelIndex, levelSize, levelScale, levelPixSize] = getLevelGeometry(obj, id)
            % GETLEVELGEOMETRY - Grid of the pyramid level selected in ``BatchOpt.ZarrPyramidLevel``.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       [levelIndex, levelSize, levelScale, levelPixSize] = obj.getLevelGeometry(id)
            %
            % A dataset without a pyramid (Standard, or Virtual from a non-pyramidal
            % file) has one grid, the full resolution, whatever the level field says.
            % On a pyramidal dataset the level name ``'sN'`` is clamped to the levels
            % present, so a protocol recorded on a deeper pyramid still runs.
            %
            % Input Arguments:
            %   - **id** - index of the dataset in ``mibModel.I``
            %
            % Output Arguments:
            %   - **levelIndex** - 1-based level index, ``1`` = full resolution
            %   - **levelSize** - ``[height, width, depth]`` of the level, pixels
            %   - **levelScale** - ``[yScale, xScale, zScale]`` of the level relative to
            %     full resolution, ``[1 1 1]`` for full resolution
            %   - **levelPixSize** - ``pixSize`` struct of the dataset with ``.x .y .z``
            %     replaced by the voxel size of the level

            dataset = obj.mibModel.I{id};
            getDataOpt.blockModeSwitch = 0;
            [height, width, depth] = dataset.getDatasetDimensions('image', 3, getDataOpt);
            levelIndex = 1;
            levelSize = [height, width, depth];
            levelScale = [1 1 1];
            levelPixSize = dataset.image.pixSize;
            if isempty(dataset.image.pyramid.levelNames); return; end

            levelIndex = str2double(obj.BatchOpt.ZarrPyramidLevel{1}(2:end)) + 1;
            if isnan(levelIndex); levelIndex = 1; end
            levelIndex = max(1, min(levelIndex, size(dataset.image.pyramid.levelImageSizes, 1)));
            levelSize = dataset.image.pyramid.levelImageSizes(levelIndex, :);
            levelScale = dataset.image.pyramid.levelScaleFactors(levelIndex, :);
            levelPixSize.y = levelPixSize.y * levelScale(1);
            levelPixSize.x = levelPixSize.x * levelScale(2);
            levelPixSize.z = levelPixSize.z * levelScale(3);
        end

        % ---------------------------------------------------------------
        function format_Callback(obj, hObject)
            % FORMAT_CALLBACK - Store the selected image or model format; the Zarr settings button follows it.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.format_Callback(%s): triggered\n', hObject.Tag);
            end
            obj.updateBatchOptFromGUI(hObject);
            obj.view.handles.zarrSettingsButton.Enable = ...
                contains(obj.BatchOpt.ImageFormat{1}, 'zarr') || contains(obj.BatchOpt.ModelFormat{1}, 'zarr');
        end

        % ---------------------------------------------------------------
        function ZarrPyramidLevel_Callback(obj, hObject)
            % ZARRPYRAMIDLEVEL_CALLBACK - Select the pyramid level to chunk.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.ZarrPyramidLevel_Callback: triggered\n');
            end
            obj.updateBatchOptFromGUI(hObject);
            obj.updateLevelInfo();
        end

        % ---------------------------------------------------------------
        function zarrSettingsButton_Callback(obj)
            % ZARRSETTINGSBUTTON_CALLBACK - Edit the settings of the OME-Zarr tiles.
            %
            % Opens the shared Zarr export dialog (``io.savers.Zarr3Saver.optionsDialog``)
            % seeded with the ``BatchOpt.Zarr*`` fields and writes the answer back.
            % The dialog takes and returns the shard as absolute sizes in one
            % direction and as chunk multipliers in the other: ``presetDefaults.ShardSize``
            % is in voxels, the returned ``ShardSize`` is in chunks, which is also
            % what ``Zarr3Saver.save`` expects and what ``ZarrShardFactors`` stores.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.zarrSettingsButton_Callback: triggered\n');
            end

            presetDefaults = struct();
            presetDefaults.Levels = obj.BatchOpt.ZarrLevels{1};
            presetDefaults.ChunkSize = str2num(obj.BatchOpt.ZarrChunkSize); %#ok<ST2NM>
            shardFactors = str2num(obj.BatchOpt.ZarrShardFactors); %#ok<ST2NM>
            presetDefaults.ShardSize = [];
            if numel(shardFactors) == 3 && all(shardFactors > 0) && numel(presetDefaults.ChunkSize) == 3
                presetDefaults.ShardSize = shardFactors(:)' .* presetDefaults.ChunkSize(:)';
            end
            presetDefaults.Compressors = struct('name', obj.BatchOpt.ZarrCompression{1}, ...
                'configuration', struct('level', obj.BatchOpt.ZarrCompressionLevel{1}));
            presetDefaults.DownsampleMethod = obj.BatchOpt.ZarrDownsampleMethod{1};
            presetDefaults.DownsampleStrategy = obj.BatchOpt.ZarrDownsampleStrategy{1};

            zarrOptions = io.savers.Zarr3Saver.optionsDialog(obj.view.gui, obj.mibModel.mibPath, false, [], presetDefaults);
            if isempty(zarrOptions); return; end

            obj.BatchOpt.ZarrLevels{1} = 0;
            if isfield(zarrOptions, 'Levels'); obj.BatchOpt.ZarrLevels{1} = zarrOptions.Levels; end
            if isfield(zarrOptions, 'ChunkSize')    % absent when the typed chunk size was not 3 numbers
                obj.BatchOpt.ZarrChunkSize = sprintf('%d, %d, %d', round(zarrOptions.ChunkSize));
            end
            obj.BatchOpt.ZarrShardFactors = '4, 4, 1';
            if isfield(zarrOptions, 'ShardSize')
                obj.BatchOpt.ZarrShardFactors = sprintf('%d, %d, %d', round(zarrOptions.ShardSize));
            end
            % a codec name means the codec default level, a struct carries the level
            obj.BatchOpt.ZarrCompressionLevel{1} = 0;
            if isstruct(zarrOptions.Compressors)
                obj.BatchOpt.ZarrCompressionLevel{1} = zarrOptions.Compressors.configuration.level;
                obj.BatchOpt.ZarrCompression{1} = zarrOptions.Compressors.name;
            else
                obj.BatchOpt.ZarrCompression{1} = zarrOptions.Compressors;
            end
            obj.BatchOpt.ZarrDownsampleMethod{1} = zarrOptions.DownsampleMethod;
            obj.BatchOpt.ZarrDownsampleStrategy{1} = zarrOptions.DownsampleStrategy;
        end

        function helpBtn_Callback(obj)
            % HELPBTN_CALLBACK - show documentation

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.helpBtn_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'home', 'home-choppedimages.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-choppedimages.html');

        end


        % ---------------------------------------------------------------
        function selectDirBtn_Callback(obj)
            % SELECTDIRBTN_CALLBACK - Open a directory picker and update the output path.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.selectDirBtn_Callback: triggered\n');
            end
            currentDir = obj.view.handles.OutputDirectory.Value;
            folder = uigetdir(currentDir, 'Select output directory');
            if isequal(folder, 0); return; end
            obj.view.handles.OutputDirectory.Value = folder;
            obj.BatchOpt.OutputDirectory = folder;
        end

        % ---------------------------------------------------------------
        function dirEdit_Callback(obj, hObject)
            % DIREDIT_CALLBACK - Validate or create the typed output directory.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.dirEdit_Callback: triggered\n');
            end
            folder = hObject.Value;
            if exist(folder, 'dir') == 0
                answer = utils.dlgs.inputQuestDlg(obj.mibModel.getProgressBarParent(), ...
                    sprintf('The target directory:\n%s\nis missing!\n\nCreate?', folder), ...
                    'Create Directory', 'Create', 'Cancel', 'Cancel');
                if strcmp(answer, 'Cancel')
                    hObject.Value = obj.BatchOpt.OutputDirectory;
                    return;
                end
                mkdir(folder);
            end
            obj.BatchOpt.OutputDirectory = folder;
        end

        % ---------------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Broadcast current BatchOpt for macro recording.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end

        % ---------------------------------------------------------------
        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - Sync a single widget change back to BatchOpt.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.updateBatchOptFromGUI(%s): triggered\n', hObject.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        % ---------------------------------------------------------------
        function chunkBtn_Callback(obj, batchModeSwitch)
            % CHUNKBTN_CALLBACK - Perform the chop-and-export operation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.chunkBtn_Callback()
            %       obj.chunkBtn_Callback(batchModeSwitch)
            %
            % Input Arguments:
            %   - **batchModeSwitch** - *(optional)* logical; ``true`` when called from batch mode
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.chunkBtn_Callback: triggered\n');
            end
            if nargin < 2; batchModeSwitch = false; end

            tilesX = obj.BatchOpt.TilesX{1};
            tilesY = obj.BatchOpt.TilesY{1};
            tilesZ = obj.BatchOpt.TilesZ{1};

            outputDir = obj.BatchOpt.OutputDirectory;
            if exist(outputDir, 'dir') == 0; mkdir(outputDir); end

            fnTemplate   = obj.BatchOpt.FilenameTemplate;
            imageFormat  = obj.BatchOpt.ImageFormat{1};
            modelsFormat = obj.BatchOpt.ModelFormat{1};
            hdf5Sub      = obj.BatchOpt.HDF5SubFormat{1};
            exportLabels = obj.BatchOpt.ChunkModel;
            exportMask   = obj.BatchOpt.ChunkMask;
            % Extract short extension from full format string, e.g. 'TIF format uncompressed (*.tif)' → '.tif'
            imageExt  = regexp(imageFormat,  '\*(\.\w+)\)', 'tokens', 'once'); imageExt  = imageExt{1};
            labelsExt = regexp(modelsFormat, '\*(\.\w+)\)', 'tokens', 'once'); labelsExt = labelsExt{1};

            id = obj.mibModel.getActiveId();

            % The tile grid is laid out on the selected pyramid level; height/width/
            % stacks, the tile ranges below and pixSize are all on that level's grid
            [levelIndex, levelSize, levelScale, pixSize] = obj.getLevelGeometry(id);
            height = levelSize(1);
            width  = levelSize(2);
            stacks = levelSize(3);
            levelText = '';
            if levelIndex > 1; levelText = sprintf(' at level s%d', levelIndex - 1); end

            % A BigData model is a pyramid of its own; read labels and mask from
            % its level with the voxel size of the image level, so both tiles
            % share one grid
            modelReadLevel = levelIndex;
            if levelIndex > 1 && (exportLabels || exportMask)
                labelsLayer = obj.mibModel.I{id}.labels;
                modelReadLevel = [];
                if isprop(labelsLayer, 'modelScaleFactors') && ~isempty(labelsLayer.modelScaleFactors)
                    modelReadLevel = find(all(abs(labelsLayer.modelScaleFactors - levelScale) ./ levelScale < 0.01, 2), 1);
                end
                if isempty(modelReadLevel)
                    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                        sprintf(['The model or mask can not be chunked at level s%d:\n' ...
                        'the model has no level with the voxel size of this image level.\n\n' ...
                        'Chunk at another level or uncheck the model and mask.'], levelIndex - 1), ...
                        'Chunk dataset');
                    notify(obj.mibModel, 'StopProtocol');
                    return;
                end
            end

            % OME-Zarr tile settings (see zarrSettingsButton_Callback)
            if strcmp(imageExt, '.zarr3') || (exportLabels && strcmp(labelsExt, '.zarr3'))
                zarrOpts = struct('silent', true, 'showWaitbar', false);
                zarrOpts.ChunkSize = str2num(obj.BatchOpt.ZarrChunkSize); %#ok<ST2NM>
                if numel(zarrOpts.ChunkSize) ~= 3
                    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                        sprintf('The Zarr chunk size should be 3 numbers (Y, X, Z), but it is "%s"', obj.BatchOpt.ZarrChunkSize), ...
                        'Chunk dataset');
                    notify(obj.mibModel, 'StopProtocol');
                    return;
                end
                shardFactors = str2num(obj.BatchOpt.ZarrShardFactors); %#ok<ST2NM>
                if numel(shardFactors) == 3 && all(shardFactors > 0); zarrOpts.ShardSize = shardFactors; end
                if obj.BatchOpt.ZarrLevels{1} > 0; zarrOpts.Levels = obj.BatchOpt.ZarrLevels{1}; end
                zarrOpts.Compressors        = obj.BatchOpt.ZarrCompression{1};
                compressionLevel = obj.BatchOpt.ZarrCompressionLevel{1};
                if strcmp(zarrOpts.Compressors, 'gzip'); compressionLevel = min(compressionLevel, 9); end
                if compressionLevel > 0 && ~strcmp(zarrOpts.Compressors, 'none')
                    zarrOpts.Compressors = struct('name', zarrOpts.Compressors, ...
                        'configuration', struct('level', compressionLevel));
                end
                zarrOpts.DownsampleMethod   = obj.BatchOpt.ZarrDownsampleMethod{1};
                zarrOpts.DownsampleStrategy = obj.BatchOpt.ZarrDownsampleStrategy{1};
            end

            xStep = ceil(width  / tilesX);
            yStep = ceil(height / tilesY);
            zStep = ceil(stacks / tilesZ);

            datasetBB  = obj.mibModel.I{id}.image.boundingBox;  % [xmin xmax ymin ymax zmin zmax]
            timePnt    = obj.mibModel.I{id}.slices{5}(1);

            totalTiles = tilesX * tilesY * tilesZ;
            if obj.BatchOpt.showWaitbar
                waitbar = uiprogressdlg(obj.mibModel.getProgressBarParent(), ...
                    'Title', 'Chop Dataset', ...
                    'Message', 'Initialising...', ...
                    'Value', 0, 'Cancelable', 'on');
            end

            index = 1;
            for zTile = 1:tilesZ
                for xTile = 1:tilesX
                    for yTile = 1:tilesY
                        if obj.BatchOpt.showWaitbar
                            waitbar.Value   = (index - 1) / totalTiles;
                            waitbar.Message = sprintf('Tile %d of %d', index, totalTiles);
                            if waitbar.CancelRequested
                                delete(waitbar);
                                return;
                            end
                        end

                        yMin = (yTile-1)*yStep + 1;
                        yMax = min((yTile-1)*yStep + yStep, height);
                        xMin = (xTile-1)*xStep + 1;
                        xMax = min((xTile-1)*xStep + xStep, width);
                        zMin = (zTile-1)*zStep + 1;
                        zMax = min((zTile-1)*zStep + zStep, stacks);

                        % Reads take full-resolution coordinates and a pyramid
                        % reader takes level voxels ceil(coordinate / scale), so
                        % level voxels a:b are asked for as (a-1)*scale+1 to
                        % (b-0.5)*scale+0.5: exact integers at full resolution, and
                        % half a level voxel inside the range otherwise, so a
                        % non-integer scale (WSI levels) can not round into the
                        % next tile
                        cropt = struct();
                        cropt.y = [(yMin-1)*levelScale(1) + 1, (yMax-0.5)*levelScale(1) + 0.5];
                        cropt.x = [(xMin-1)*levelScale(2) + 1, (xMax-0.5)*levelScale(2) + 0.5];
                        cropt.z = [(zMin-1)*levelScale(3) + 1, (zMax-0.5)*levelScale(3) + 0.5];
                        cropt.blockModeSwitch = 0;
                        modelOpt = cropt;
                        if levelIndex > 1
                            cropt.pyramidLevel = levelIndex;
                            modelOpt.pyramidLevel = modelReadLevel;
                        end

                        % Load image tile - MIB3 returns [H, W, D, C]
                        imOut = cell2mat(obj.mibModel.getData3D('image', timePnt, 3, 0, cropt));

                        % Build metadata for the tile
                        tileColors = size(imOut, 4);
                        colorType  = obj.mibModel.I{id}.image.colorType;
                        dataClass  = obj.mibModel.I{id}.image.dataClass;
                        maxInt     = obj.mibModel.I{id}.image.maxInt;
                        lutColors  = obj.mibModel.I{id}.image.lutColors;

                        tileMeta = core.MibImage.initializeImgInfo( ...
                            'Filename',   fullfile(outputDir, sprintf('%s_Z%.2d-X%.2d-Y%.2d%s', fnTemplate, zTile, xTile, yTile, imageExt)), ...
                            'Height',     yMax - yMin + 1, ...
                            'Width',      xMax - xMin + 1, ...
                            'Depth',      zMax - zMin + 1, ...
                            'Colors',     tileColors, ...
                            'imgClass',   dataClass, ...
                            'ColorType',  colorType, ...
                            'MaxInt',     maxInt, ...
                            'pixSize',    pixSize, ...
                            'lutColors',  lutColors);

                        imgTile = core.MibImage(imOut, tileMeta);

                        % Shift bounding box to tile physical position, preserving
                        % the dataset's physical origin (datasetBB may be non-zero)
                        xyzShift = [datasetBB(1) + (xMin-1)*pixSize.x, ...
                                    datasetBB(3) + (yMin-1)*pixSize.y, ...
                                    datasetBB(5) + (zMin-1)*pixSize.z];
                        imgTile.updateBoundingBox([], xyzShift);

                        logText = sprintf('Chop%s: [y1:y2,x1:x2,:,z1:z2,t]: %d:%d,%d:%d,:,%d:%d,%d', ...
                            levelText, yMin, yMax, xMin, xMax, zMin, zMax, timePnt);
                        imgTile.updateActionLog(logText);

                        % Save image tile
                        imageFilename = fullfile(outputDir, ...
                            sprintf('%s_Z%.2d-X%.2d-Y%.2d%s', fnTemplate, zTile, xTile, yTile, imageExt));
                        imgTile.filename = imageFilename;

                        saveOpts = struct();
                        saveOpts.overwrite      = true;
                        saveOpts.showWaitbar    = false;
                        saveOpts.silent         = true;
                        saveOpts.Saving3DPolicy = '3D stack';
                        saveOpts.pixSize        = pixSize;
                        saveOpts.ParentFigure   = obj.mibModel.mibGUI;
                        saveOpts.mibPath        = obj.mibModel.mibPath;

                        saveOpts.Format = imageFormat;
                        if strcmp(imageExt, '.xml') % && strcmp(hdf5Sub, 'bdv.hdf5')
                            imageFilename = strrep(imageFilename, '.xml', '.h5');
                            imgTile.filename = imageFilename;
                        end
                        if strcmp(imageExt, '.zarr3')
                            zarrFields = fieldnames(zarrOpts);
                            for fieldId = 1:numel(zarrFields)
                                saveOpts.(zarrFields{fieldId}) = zarrOpts.(zarrFields{fieldId});
                            end
                        end
                        imgTile.save(imageFilename, saveOpts);

                        % ---- Save labels (segmentation model)
                        if exportLabels
                            labelsFilename = fullfile(outputDir, ...
                                sprintf('Labels_%s_Z%.2d-X%.2d-Y%.2d%s', fnTemplate, zTile, xTile, yTile, labelsExt));

                            labelsData = cell2mat(obj.mibModel.getData3D('labels', timePnt, 3, NaN, modelOpt));
                            materialNames  = obj.mibModel.I{id}.labels.materialNames;
                            materialColors = obj.mibModel.I{id}.labels.materialColors;
                            boundingBox    = imgTile.boundingBox;

                            switch labelsExt
                                case {'.model', '.xml'}
                                    % saved as Save model does (core.MibLabels.save), so the
                                    % material names, colours, bounding box and model type
                                    % go into the fields the model loaders read
                                    labelsTile = core.MibLabels(labelsData, tileMeta);
                                    labelsTile.filename       = labelsFilename;
                                    labelsTile.materialNames  = materialNames;
                                    labelsTile.materialColors = materialColors;
                                    labelsTile.labelsVariable = 'mibModel';   % MatlabSaver default; [] would warn in MibLabels.save
                                    if ischar(obj.mibModel.I{id}.labels.labelsVariable) && ~isempty(obj.mibModel.I{id}.labels.labelsVariable)
                                        labelsTile.labelsVariable = obj.mibModel.I{id}.labels.labelsVariable;
                                    end
                                    labelsOpts = struct('Format', modelsFormat, ...
                                        'overwrite', true, 'showWaitbar', false, 'silent', true, ...
                                        'Saving3DPolicy', '3D stack', 'layerType', 'labels', ...
                                        'pixSize', pixSize, 'boundingBox', boundingBox, ...
                                        'modelType', obj.mibModel.I{id}.labels.maxMaterials, ...
                                        'ParentFigure', obj.mibModel.mibGUI, 'mibPath', obj.mibModel.mibPath);

                                    annotationsCopy = copy(obj.mibModel.I{id}.annotations);
                                    annotationsCopy.crop([cropt.x(1), cropt.y(1), NaN, NaN, cropt.z(1), NaN]);
                                    if levelIndex > 1 && annotationsCopy.getLabelsNumber() > 0
                                        % full-resolution voxel p lies in level voxel
                                        % (p-0.5)/scale+0.5; ChunkingImport inverts this
                                        % (labelPosition columns: z, x, y)
                                        annotationsCopy.labelPosition(:,1) = (annotationsCopy.labelPosition(:,1) - 0.5) / levelScale(3) + 0.5;
                                        annotationsCopy.labelPosition(:,2) = (annotationsCopy.labelPosition(:,2) - 0.5) / levelScale(2) + 0.5;
                                        annotationsCopy.labelPosition(:,3) = (annotationsCopy.labelPosition(:,3) - 0.5) / levelScale(1) + 0.5;
                                    end
                                    if annotationsCopy.getLabelsNumber() > 1   % the threshold MibDataset.saveImage uses
                                        [labelsOpts.annotations.labelText, labelsOpts.annotations.labelValue, ...
                                            labelsOpts.annotations.labelPosition] = annotationsCopy.getLabels();
                                    end
                                    labelsTile.save(labelsFilename, labelsOpts);

                                case '.am'
                                    pixStr = pixSize;
                                    pixStr.minx = boundingBox(1);
                                    pixStr.miny = boundingBox(3);
                                    pixStr.minz = boundingBox(5);
                                    io.AmiraMesh.bitmap2amiraLabels(labelsFilename, labelsData, 'binary', ...
                                        pixStr, materialColors, materialNames, 1, 1);

                                case '.nrrd'
                                    nrrdOpts = struct('overwrite', 1, 'showWaitbar', 0);
                                    io.NRRD.bitmap2nrrd(labelsFilename, labelsData, boundingBox, nrrdOpts);

                                case '.tif'
                                    labelsImg = core.MibImage(labelsData(:,:,:,1), tileMeta);
                                    labelsImg.updateBoundingBox([], xyzShift);   % the tile position, as on the image tile
                                    labelsImg.filename = labelsFilename;
                                    tifOpts = struct('Format', 'TIF format (*.tif)', ...
                                        'overwrite', true, 'showWaitbar', false, 'silent', true, ...
                                        'Saving3DPolicy', '3D stack', 'pixSize', pixSize, ...
                                        'ParentFigure', obj.mibModel.mibGUI, 'mibPath', obj.mibModel.mibPath);
                                    labelsImg.save(labelsFilename, tifOpts);

                                case '.zarr3'
                                    % saved directly: the material names and colours
                                    % go into the store's mibMaterials attribute
                                    labelsZarrOpts = zarrOpts;
                                    labelsZarrOpts.layerType = 'labels';   % nearest downsampling unless mode is selected
                                    labelsMeta = struct('pixSize', pixSize, 'boundingBox', boundingBox, ...
                                        'materialNames', {materialNames}, 'materialColors', materialColors);
                                    io.savers.Zarr3Saver().save(labelsData, labelsMeta, labelsFilename, labelsZarrOpts);
                            end
                        end

                        % ---- Save mask
                        if exportMask
                            maskFilename = fullfile(outputDir, ...
                                sprintf('Mask_%s_Z%.2d-X%.2d-Y%.2d.mask', fnTemplate, zTile, xTile, yTile));
                            maskImg = cell2mat(obj.mibModel.getData3D('mask', timePnt, 3, 0, modelOpt));
                            save(maskFilename, 'maskImg', '-mat', '-v7.3');
                        end

                        index = index + 1;
                    end
                end
            end

            if obj.BatchOpt.showWaitbar; delete(waitbar); end
            fprintf('MIB ChunkingExport: %d tiles saved to %s\n', totalTiles, outputDir);

            obj.returnBatchOpt();
        end

    end
end
