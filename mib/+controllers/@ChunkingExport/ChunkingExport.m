classdef ChunkingExport < handle
% CHUNKINGEXPORT - Splits the current dataset into a Z×X×Y tile grid and saves tiles to disk.
%
% Each tile is saved as a separate image file.  Labels (segmentation model) and
% mask layers can optionally be exported alongside the images.
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
            obj.BatchOpt.ImageFormat{2} = {'Amira Mesh binary (*.am)', 'NRRD Data Format (*.nrrd)', 'TIF format uncompressed (*.tif)', 'Hierarchical Data Format with XML header (*.xml)'};
            obj.BatchOpt.ModelFormat    = {'Matlab format (*.model)'};
            obj.BatchOpt.ModelFormat{2} = {'Matlab format (*.model)', 'Amira Mesh binary (*.am)', 'NRRD Data Format (*.nrrd)', 'TIF format (*.tif)', 'Hierarchical Data Format with XML header (*.xml)'};
            obj.BatchOpt.HDF5SubFormat    = {'matlab.hdf5'};
            obj.BatchOpt.HDF5SubFormat{2} = {'matlab.hdf5', 'bdv.hdf5'};
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
            obj.BatchOpt.mibBatchTooltip.ImageFormat      = 'Output format for image tiles (.am .nrrd .tif .xml)';
            obj.BatchOpt.mibBatchTooltip.ModelFormat      = 'Output format for label tiles (.model .am .nrrd .tif .xml)';
            obj.BatchOpt.mibBatchTooltip.HDF5SubFormat    = 'HDF5 sub-format when ImageFormat is .xml (matlab.hdf5 or bdv.hdf5)';
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
            obj.view.handles.ImageFormat.ValueChangedFcn       = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.ModelFormat.ValueChangedFcn       = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.ChunkModel.ValueChangedFcn        = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.ChunkMask.ValueChangedFcn         = @(h,~) obj.updateBatchOptFromGUI(h);
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh the GUI from the current dataset state.
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            getDataOpt.blockModeSwitch = 0;
            [height, width, stacks] = dataset.getDatasetDimensions('image', 3, getDataOpt);
            pixSize = dataset.image.pixSize;

            obj.view.handles.InfoLabel.Text = sprintf('xmin-xmax: 1 - %d\nymin-ymax: 1 - %d\nzmin-zmax: 1 - %d', width, height, stacks);
            obj.view.handles.PixSizeLabel.Text = sprintf('X: %g\nY: %g\nZ: %g', pixSize.x, pixSize.y, pixSize.z);

            obj.view.handles.ChunkModel.Enable = dataset.modelExist;
            obj.view.handles.ChunkMask.Enable  = dataset.maskExist;
            if ~dataset.modelExist; obj.BatchOpt.ChunkModel = false; end
            if ~dataset.maskExist;  obj.BatchOpt.ChunkMask  = false; end

            obj.BatchOpt.OutputDirectory = obj.mibModel.currentDirectory;
            [~, sourceFn] = fileparts(obj.mibModel.I{id}.image.filename);
            obj.BatchOpt.FilenameTemplate = [sourceFn '_chop'];

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        function helpBtn_Callback(obj)
            % HELPBTN_CALLBACK - show documentation

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingExport.helpBtn_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'home', 'home-choppedimages.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-choppedimages.html', '-browser');
            end

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
            getDataOpt.blockModeSwitch = 0;
            [height, width, stacks] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, getDataOpt);

            xStep = ceil(width  / tilesX);
            yStep = ceil(height / tilesY);
            zStep = ceil(stacks / tilesZ);

            pixSize    = obj.mibModel.I{id}.image.pixSize;
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

                        cropt.y = [yMin, yMax];
                        cropt.x = [xMin, xMax];
                        cropt.z = [zMin, zMax];
                        cropt.blockModeSwitch = 0;

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

                        logText = sprintf('Chop: [y1:y2,x1:x2,:,z1:z2,t]: %d:%d,%d:%d,:,%d:%d,%d', ...
                            yMin, yMax, xMin, xMax, zMin, zMax, timePnt);
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
                        imgTile.save(imageFilename, saveOpts);

                        % ---- Save labels (segmentation model)
                        if exportLabels
                            labelsFilename = fullfile(outputDir, ...
                                sprintf('Labels_%s_Z%.2d-X%.2d-Y%.2d%s', fnTemplate, zTile, xTile, yTile, labelsExt));

                            labelsData = cell2mat(obj.mibModel.getData3D('labels', timePnt, 3, NaN, cropt));
                            materialNames  = obj.mibModel.I{id}.labels.materialNames;
                            materialColors = obj.mibModel.I{id}.labels.materialColors;
                            boundingBox    = imgTile.boundingBox;

                            switch labelsExt
                                case '.model'
                                    imOut = labelsData;
                                    modelVariable = 'imOut';
                                    annotationsCopy = copy(obj.mibModel.I{id}.annotations);
                                    annotationsCopy.crop([xMin, yMin, NaN, NaN, zMin, NaN]);
                                    if annotationsCopy.getLabelsNumber() > 1
                                        [labelText, labelValue, labelPosition] = annotationsCopy.getLabels();
                                        save(labelsFilename, 'imOut', 'materialNames', 'materialColors', ...
                                            'boundingBox', 'modelVariable', 'labelText', 'labelValue', 'labelPosition', ...
                                            '-mat', '-v7.3');
                                    else
                                        save(labelsFilename, 'imOut', 'materialNames', 'materialColors', ...
                                            'boundingBox', 'modelVariable', '-mat', '-v7.3');
                                    end

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
                                    labelsImg.filename = labelsFilename;
                                    tifOpts = struct('Format', 'TIF format (*.tif)', ...
                                        'overwrite', true, 'showWaitbar', false, 'silent', true, ...
                                        'Saving3DPolicy', '3D stack', 'pixSize', pixSize, ...
                                        'ParentFigure', obj.mibModel.mibGUI, 'mibPath', obj.mibModel.mibPath);
                                    labelsImg.save(labelsFilename, tifOpts);

                                case '.xml'
                                    labelsImg = core.MibImage(labelsData(:,:,:,1), tileMeta);
                                    labelsImg.filename = labelsFilename;
                                    xmlOpts = struct('Format', 'Hierarchical Data Format with XML header (*.xml)', ...
                                        'overwrite', true, 'showWaitbar', false, 'silent', true, ...
                                        'layerType', 'labels', 'pixSize', pixSize, ...
                                        'ParentFigure', obj.mibModel.mibGUI, 'mibPath', obj.mibModel.mibPath);
                                    labelsImg.save(labelsFilename, xmlOpts);
                            end
                        end

                        % ---- Save mask
                        if exportMask
                            maskFilename = fullfile(outputDir, ...
                                sprintf('Mask_%s_Z%.2d-X%.2d-Y%.2d.mask', fnTemplate, zTile, xTile, yTile));
                            maskImg = cell2mat(obj.mibModel.getData3D('mask', timePnt, 3, 0, cropt));
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
