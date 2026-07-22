classdef ChunkingImport < handle
% CHUNKINGIMPORT - Reassembles a set of chopped image tiles back into a single dataset.
%
% Two modes:
%   * **New Stack** — auto-detects the tile grid from filenames (_Z##-X##-Y## pattern)
%     and assembles a new dataset.
%   * **Fuse to Existing** — positions each tile in the currently open dataset using
%     its bounding-box metadata (optional pixel offsets).


    properties
        mibModel
        % handle to MibModel
        view
        % handle to ChunkingImportGUI
        listener
        % cell array of listener handles
        filenames
        % cell array of full-path filenames selected for import
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
                    obj.updateWidgets(evnt.EventName);
            end
        end
    end

    methods

        % ---------------------------------------------------------------
        function obj = ChunkingImport(mibModel, varargin)
            % CHUNKINGIMPORT - constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = ChunkingImport(mibModel)
            %       obj = ChunkingImport(mibModel, mibController, BatchOpt)
            %       obj = ChunkingImport(mibModel, mibController, NaN)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **varargin{1}** — *(optional)* handle to MibController
            %   - **varargin{2}** — *(optional)* BatchOpt struct or NaN (batch mode)
            %
            % For batch mode, supply ``BatchOpt.InputDirectory`` and
            % ``BatchOpt.FilePattern`` to auto-discover tile files instead of
            % selecting them interactively.
            %
            % Usage:
            %   Example 1::
            %
            %     obj.mibController.startController('controllers.ChunkingImport');
            %

            obj.mibModel = mibModel;
            obj.filenames = {};

            % ---- BatchOpt defaults
            obj.BatchOpt.Mode    = {'New Stack'};
            obj.BatchOpt.Mode{2} = {'New Stack', 'Fuse to Existing'};
            obj.BatchOpt.CombineImages  = true;
            obj.BatchOpt.CombineModels  = false;
            obj.BatchOpt.CombineMasks   = false;
            obj.BatchOpt.ModelsFormat    = {'Matlab format (*.model)'};
            obj.BatchOpt.ModelsFormat{2} = { ...
                'Matlab format (*.model)', ...
                'Matlab format for MIB ver. 1 (*.mat)', ...
                'Amira mesh binary (*.am)', ...
                'NRRD for 3D Slicer (*.nrrd)', ...
                'TIF format (*.tif)', ...
                'Hierarchical Data Format with XML header (*.xml)'};
            obj.BatchOpt.OffsetX = {0, [-Inf, Inf], 'on'};
            obj.BatchOpt.OffsetY = {0, [-Inf, Inf], 'on'};
            obj.BatchOpt.OffsetZ = {0, [-Inf, Inf], 'on'};
            
            % Hidden batch-only fields for auto-discovering tiles
            obj.BatchOpt.InputDirectory = obj.mibModel.currentDirectory;
            obj.BatchOpt.FilePattern    = '*_chop*.tif';
            obj.BatchOpt.showWaitbar    = true;
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
            obj.BatchOpt.mibBatchActionName  = 'Stitch chunked datasets...';
            obj.BatchOpt.mibBatchTooltip.CombineImages  = 'Import image layer';
            obj.BatchOpt.mibBatchTooltip.CombineModels  = 'Import labels (segmentation model) layer';
            obj.BatchOpt.mibBatchTooltip.CombineMasks   = 'Import mask layer';
            obj.BatchOpt.mibBatchTooltip.ModelsFormat   = 'File extension of the label files';
            obj.BatchOpt.mibBatchTooltip.Mode           = 'New Stack: assemble tiles into a new dataset; Fuse to Existing: insert tiles using bounding-box coordinates';
            obj.BatchOpt.mibBatchTooltip.OffsetX        = '[Fuse mode] additional pixel offset in X';
            obj.BatchOpt.mibBatchTooltip.OffsetY        = '[Fuse mode] additional pixel offset in Y';
            obj.BatchOpt.mibBatchTooltip.OffsetZ        = '[Fuse mode] additional pixel offset in Z';
            obj.BatchOpt.mibBatchTooltip.InputDirectory = '[Batch only] directory containing tile files';
            obj.BatchOpt.mibBatchTooltip.FilePattern    = '[Batch only] glob pattern used to select tile files from InputDirectory';
            obj.BatchOpt.mibBatchTooltip.showWaitbar    = 'Show progress bar during import';

            % ---- Batch-mode path
            if nargin == 3
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput)
                    obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                    % Auto-discover files when batch mode is used
                    tileFiles = dir(fullfile(obj.BatchOpt.InputDirectory, obj.BatchOpt.FilePattern));
                    obj.filenames = sort(cellfun(@(n, p) fullfile(p, n), ...
                        {tileFiles.name}, {tileFiles.folder}, 'UniformOutput', false));
                    obj.combineBtn_Callback(true);
                    notify(obj, 'CloseEvent');
                elseif isnan(BatchOptInput)
                    obj.returnBatchOpt();
                else
                    utils.dlgs.showErrorDialog([], ...
                        'A BatchOpt struct is required as the 3rd parameter.', ...
                        'ChunkingImport: init error');
                    notify(obj.mibModel, 'StopProtocol');
                end
                return;
            end

            % ---- GUI path
            guiName = 'views.ChunkingImportGUI';
            obj.view = core.ChildView(obj, guiName);
            obj.addCallbacks();

            % update the font size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.CombineButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.CombineButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            % position the window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();
            % make the window visible
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and clean up listeners.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingImport.closeWindow: triggered\n');
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
            obj.view.handles.CloseButton.ButtonPushedFcn    = @(~,~) obj.closeWindow();
            obj.view.handles.SelectFilesButton.ButtonPushedFcn = @(~,~) obj.selectFilesBtn_Callback();
            obj.view.handles.CombineButton.ButtonPushedFcn  = @(~,~) obj.combineBtn_Callback();
            obj.view.handles.HelpButton.ButtonPushedFcn     = @(~,~) obj.helpBtn_Callback();

            obj.view.handles.CombineImages.ValueChangedFcn  = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.CombineModels.ValueChangedFcn  = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.CombineMasks.ValueChangedFcn   = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.ModelsFormat.ValueChangedFcn   = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.Mode.SelectionChangedFcn       = @(h,~) obj.combineModeChanged_Callback(h);
            obj.view.handles.OffsetX.ValueChangedFcn = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.OffsetY.ValueChangedFcn = @(h,~) obj.updateBatchOptFromGUI(h);
            obj.view.handles.OffsetZ.ValueChangedFcn = @(h,~) obj.updateBatchOptFromGUI(h);
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj, eventName)
            % UPDATEWIDGETS - Sync widgets; clear file list only on NewDataset.
            if nargin < 2; eventName = 'NewDataset'; end

            % Only reset the selected file list when a genuinely new dataset
            % is opened (NewDataset). UpdateGuiWidgets is fired after fuse/import
            % and must not wipe the user's file selection.
            if strcmp(eventName, 'NewDataset')
                obj.filenames = {};
                obj.BatchOpt.InputDirectory = obj.mibModel.currentDirectory;
                obj.view.handles.SelectedFilesListBox.Items = {};
            end

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);

            % Enable offset fields only in Fuse mode
            fuseMode = strcmp(obj.BatchOpt.Mode{1}, 'Fuse to Existing');
            obj.view.handles.OffsetX.Enable = fuseMode;
            obj.view.handles.OffsetY.Enable = fuseMode;
            obj.view.handles.OffsetZ.Enable = fuseMode;
        end

        % ---------------------------------------------------------------
        function combineModeChanged_Callback(obj, hObject)
            % COMBINEMODECHANGED_CALLBACK - Toggle offset fields with mode.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingImport.combineModeChanged_Callback: triggered\n');
            end
            if strcmp(hObject.SelectedObject.Tag, 'newRadio')
                obj.BatchOpt.Mode{1} = 'New Stack';
                fuseMode = false;
            else
                obj.BatchOpt.Mode{1} = 'Fuse to Existing';
                fuseMode = true;
            end
            obj.view.handles.OffsetX.Enable = fuseMode;
            obj.view.handles.OffsetY.Enable = fuseMode;
            obj.view.handles.OffsetZ.Enable = fuseMode;
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
                fprintf('controllers.ChunkingImport.updateBatchOptFromGUI: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        function helpBtn_Callback(obj)
            % HELPBTN_CALLBACK - show documentation

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingImport.helpBtn_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'home', 'home-choppedimages.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-choppedimages.html', '-browser');
            end

        end

        % ---------------------------------------------------------------
        function selectFilesBtn_Callback(obj)
            % SELECTFILESBTN_CALLBACK - Open a file picker to select tile files.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingImport.selectFilesBtn_Callback: triggered\n');
            end
            importImages = obj.view.handles.CombineImages.Value;
            importLabels = obj.view.handles.CombineModels.Value;
            importMasks  = obj.view.handles.CombineMasks.Value;

            if ~importImages && ~importLabels && ~importMasks
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'Please select at least one layer type (Images, Models, or Masks).', ...
                    'Missing layer selection');
                return;
            end

            if importImages && (importLabels || importMasks)
                inpDlgOpt.Icon = 'puffin_warning';
                answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('!!! Attention !!!\n\nSelect only image files.\nDo not select model or mask files!'), ...
                    'Attention!', 'Continue', 'Cancel', 'Continue', inpDlgOpt);
                if strcmp(answer, 'Cancel'); return; end
            end

            if importImages
                fileFormats = { ...
                    '*.am',   'Amira mesh binary (*.am)'; ...
                    '*.nrrd', 'NRRD for 3D Slicer (*.nrrd)'; ...
                    '*.tif',  'TIF format (*.tif)'; ...
                    '*.xml',  'Hierarchical Data Format with XML header (*.xml)'; ...
                    '*.*',    'All Files (*.*)'};
            elseif importMasks
                fileFormats = { ...
                    '*.mask', 'Masks (*.mask)'; ...
                    '*.*',    'All Files (*.*)'};
            else
                labelsExtTok = regexp(obj.BatchOpt.ModelsFormat{1}, '\*(\.\w+)\)', 'tokens', 'once');
                labelsExt = labelsExtTok{1};
                fileFormats = {['*' labelsExt], sprintf('Labels (*%s)', labelsExt); ...
                    '*.*', 'All Files (*.*)'};
            end

            startDir = obj.mibModel.currentDirectory;
            [fileNames, pathName] = utils.dlgs.mibUiGetFile(fileFormats, ...
                'Select tile files', startDir, 'on');
            if isequal(fileNames, 0); return; end

            fileNames = sort(fileNames);
            obj.filenames = cellfun(@(n) fullfile(pathName, n), fileNames, 'UniformOutput', false);
            if ischar(obj.filenames); obj.filenames = {obj.filenames}; end

            obj.view.handles.SelectedFilesListBox.Items = fileNames;
        end

        % ---------------------------------------------------------------
        function combineBtn_Callback(obj, batchModeSwitch)
            % COMBINEBTN_CALLBACK - Reassemble the selected tile files.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.combineBtn_Callback()
            %       obj.combineBtn_Callback(batchModeSwitch)
            %
            % Input Arguments:
            %   - **batchModeSwitch** — *(optional)* logical; ``true`` when called from batch mode
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ChunkingImport.combineBtn_Callback: triggered\n');
            end
            if nargin < 2; batchModeSwitch = false; end

            % Snapshot filenames before any listener can clear obj.filenames
            % (notify('NewDataset') triggers updateWidgets which resets obj.filenames)
            filenames = obj.filenames;

            importImages = obj.BatchOpt.CombineImages;
            importLabels = obj.BatchOpt.CombineModels;
            importMasks  = obj.BatchOpt.CombineMasks;

            if ~importImages && ~importLabels && ~importMasks
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    'Please select at least one layer type to combine.', 'Missing layers');
                return;
            end

            numberOfFiles = numel(filenames);
            if numberOfFiles < 1
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    'Please select the files and try again.', 'Missing files');
                return;
            end

            labelsExtTok = regexp(obj.BatchOpt.ModelsFormat{1}, '\*(\.\w+)\)', 'tokens', 'once');
            labelsExt = labelsExtTok{1};
            id = obj.mibModel.getActiveId();

            if strcmp(obj.BatchOpt.Mode{1}, 'New Stack')
                % --------------------------------------------------------
                % NEW STACK mode
                % --------------------------------------------------------
                % Parse grid position from filenames (_Z##-X##-Y## pattern)
                zIndex = zeros(numberOfFiles, 1);
                xIndex = zeros(numberOfFiles, 1);
                yIndex = zeros(numberOfFiles, 1);

                for fileId = 1:numberOfFiles
                    [~, baseName] = fileparts(filenames{fileId});
                    zPos = strfind(baseName, 'Z');
                    xPos = strfind(baseName, 'X');
                    yPos = strfind(baseName, 'Y');
                    zIndex(fileId) = str2double(baseName(zPos(end)+1:zPos(end)+2));
                    xIndex(fileId) = str2double(baseName(xPos(end)+1:xPos(end)+2));
                    yIndex(fileId) = str2double(baseName(yPos(end)+1:yPos(end)+2));
                end
                tilesZ = max(zIndex);
                tilesX = max(xIndex);
                tilesY = max(yIndex);

                if importImages
                    % Load metadata for each tile to get dimensions
                    tileHeight = zeros(numberOfFiles, 1);
                    tileWidth  = zeros(numberOfFiles, 1);
                    tileDepth  = zeros(numberOfFiles, 1);
                    tileColors = 1;
                    tileClass  = 'uint8';

                    for fileId = 1:numberOfFiles
                        img = io.loadImagesWrapper(filenames{fileId});   % [H, W, D, C, T]
                        tileHeight(fileId) = size(img, 1);
                        tileWidth(fileId)  = size(img, 2);
                        tileDepth(fileId)  = size(img, 3);
                        if fileId == 1
                            tileColors  = size(img, 4);
                            tileClass   = class(img);
                        end
                        clear img;
                    end

                    % Compute output dimensions
                    outHeight = 0;
                    for tileId = 1:tilesY
                        idx = find(yIndex == tileId, 1);
                        outHeight = outHeight + tileHeight(idx);
                    end
                    outWidth = 0;
                    for tileId = 1:tilesX
                        idx = find(xIndex == tileId, 1);
                        outWidth = outWidth + tileWidth(idx);
                    end
                    outDepth = 0;
                    for tileId = 1:tilesZ
                        idx = find(zIndex == tileId, 1);
                        outDepth = outDepth + tileDepth(idx);
                    end

                    imgOut = zeros([outHeight, outWidth, outDepth, tileColors], tileClass);

                    % Precompute per-axis cumulative positions.
                    % Each axis sums one representative tile per unique index so that a
                    % 2-D or 3-D grid is handled correctly (the broken formula counted
                    % every file in the same column, overcounting for multi-row grids).
                    yCumImg = [0, cumsum(arrayfun(@(ty) tileHeight(find(yIndex==ty,1)), 1:tilesY))];
                    xCumImg = [0, cumsum(arrayfun(@(tx) tileWidth(find(xIndex==tx,1)),  1:tilesX))];
                    zCumImg = [0, cumsum(arrayfun(@(tz) tileDepth(find(zIndex==tz,1)),  1:tilesZ))];

                    if obj.BatchOpt.showWaitbar
                        waitbar = uiprogressdlg(obj.mibModel.getProgressBarParent(), ...
                            'Title', 'Recombine Dataset', 'Message', 'Combining images...', ...
                            'Value', 0, 'Cancelable', 'on');
                    end

                    for fileId = 1:numberOfFiles
                        if obj.BatchOpt.showWaitbar
                            waitbar.Value   = (fileId-1) / numberOfFiles;
                            waitbar.Message = sprintf('Image tile %d of %d', fileId, numberOfFiles);
                            if waitbar.CancelRequested
                                delete(waitbar);
                                return;
                            end
                        end

                        img = io.loadImagesWrapper(filenames{fileId});   % [H, W, D, C, T]
                        img = img(:,:,:,:,1);  % take first time point

                        yMin = yCumImg(yIndex(fileId)) + 1;
                        yMax = min(yCumImg(yIndex(fileId)+1), outHeight);
                        xMin = xCumImg(xIndex(fileId)) + 1;
                        xMax = min(xCumImg(xIndex(fileId)+1), outWidth);
                        zMin = zCumImg(zIndex(fileId)) + 1;
                        zMax = min(zCumImg(zIndex(fileId)+1), outDepth);

                        imgOut(yMin:yMax, xMin:xMax, zMin:zMax, :) = img(1:(yMax-yMin+1), 1:(xMax-xMin+1), 1:(zMax-zMin+1), :);
                    end

                    if obj.BatchOpt.showWaitbar; delete(waitbar); end

                    % Replace current dataset — preserve existing model type (63 or 255 materials)
                    if obj.mibModel.I{id}.labels.maxMaterials == 63
                        newModelType = 'labels63';
                    else
                        newModelType = 'labels';
                    end
                    imgMeta = core.MibImage.initializeImgInfo( ...
                        'Height', outHeight, 'Width', outWidth, 'Depth', outDepth, ...
                        'Colors', tileColors, 'imgClass', tileClass);
                    obj.mibModel.I{id} = core.MibDataset(imgOut, imgMeta, 'Standard', newModelType);

                    notify(obj.mibModel, 'NewDataset');
                    % Restore file list cleared by the NewDataset listener
                    obj.filenames = filenames;
                end

                % After the image is in place, get final dataset dimensions
                outHeight = obj.mibModel.I{id}.image.height;
                outWidth  = obj.mibModel.I{id}.image.width;
                outDepth  = obj.mibModel.I{id}.image.depth;

                if importLabels
                    if obj.BatchOpt.showWaitbar
                        waitbar = uiprogressdlg(obj.mibModel.getProgressBarParent(), ...
                            'Title', 'Recombine Dataset', 'Message', 'Combining labels...', ...
                            'Value', 0);
                    end

                    obj.mibModel.I{id}.createModel();
                    labelsOut = zeros([outHeight, outWidth, outDepth], 'uint8');
                    materialNames  = {};
                    materialColors = [];

                    % First pass: load all label tiles, record dimensions and metadata.
                    % Cache loaded data to avoid reading each file twice.
                    tileHeightM  = zeros(numberOfFiles, 1);
                    tileWidthM   = zeros(numberOfFiles, 1);
                    tileDepthM   = zeros(numberOfFiles, 1);
                    allLabelTiles = cell(numberOfFiles, 1);

                    for fileId = 1:numberOfFiles
                        [~, baseName] = fileparts(filenames{fileId});
                        if isempty(strfind(baseName, 'Labels'))  %#ok<STREMP>
                            modelFn = fullfile(fileparts(filenames{fileId}), ['Labels_' baseName labelsExt]);
                        else
                            modelFn = fullfile(fileparts(filenames{fileId}), [baseName labelsExt]);
                        end

                        if exist(modelFn, 'file') == 0
                            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                sprintf('Label file not found:\n%s\n\nUncheck Labels or fix filenames.', modelFn), ...
                                'Missing label files');
                            if obj.BatchOpt.showWaitbar; delete(waitbar); end
                            return;
                        end

                        R = obj.loadModels(modelFn);
                        allLabelTiles{fileId} = R;
                        tileHeightM(fileId) = size(R.imOut, 1);
                        tileWidthM(fileId)  = size(R.imOut, 2);
                        tileDepthM(fileId)  = size(R.imOut, 3);

                        if isfield(R, 'materialNames')
                            if numel(R.materialNames) > numel(materialNames)
                                materialNames = R.materialNames;
                            end
                        end
                        if isfield(R, 'materialColors')
                            if fileId == 1 || size(R.materialColors, 1) > size(materialColors, 1)
                                materialColors = R.materialColors;
                            end
                        end
                    end

                    % Precompute per-axis cumulative positions using one representative
                    % tile per unique index — fixes the 2-D/3-D grid overcounting bug.
                    yCumM = [0, cumsum(arrayfun(@(ty) tileHeightM(find(yIndex==ty,1)), 1:tilesY))];
                    xCumM = [0, cumsum(arrayfun(@(tx) tileWidthM(find(xIndex==tx,1)),  1:tilesX))];
                    zCumM = [0, cumsum(arrayfun(@(tz) tileDepthM(find(zIndex==tz,1)),  1:tilesZ))];

                    % Second pass: assemble from cached tiles.
                    for fileId = 1:numberOfFiles
                        R = allLabelTiles{fileId};

                        yMin = yCumM(yIndex(fileId)) + 1;
                        yMax = min(yCumM(yIndex(fileId)+1), outHeight);
                        xMin = xCumM(xIndex(fileId)) + 1;
                        xMax = min(xCumM(xIndex(fileId)+1), outWidth);
                        zMin = zCumM(zIndex(fileId)) + 1;
                        zMax = min(zCumM(zIndex(fileId)+1), outDepth);

                        labelsOut(yMin:yMax, xMin:xMax, zMin:zMax) = R.imOut(1:(yMax-yMin+1), 1:(xMax-xMin+1), 1:(zMax-zMin+1));

                        if obj.BatchOpt.showWaitbar
                            waitbar.Value = fileId / numberOfFiles;
                        end
                    end
                    allLabelTiles = [];  % release cache

                    % Auto-generate numeric names when tiles carried none
                    if isempty(materialNames)
                        nMat = max(0, double(max(labelsOut(:))));
                        if nMat > 0
                            materialNames = arrayfun(@(x) num2str(x), 1:nMat, 'UniformOutput', false);
                        end
                    end
                    if isempty(materialColors) && ~isempty(materialNames)
                        materialColors = rand(numel(materialNames), 3);
                    end

                    setOpts.blockModeSwitch = 0;
                    obj.mibModel.setData3D(labelsOut, 'labels', NaN, 3, NaN, setOpts);
                    obj.mibModel.I{id}.labels.materialNames  = materialNames;
                    obj.mibModel.I{id}.labels.materialColors = materialColors;
                    if obj.BatchOpt.showWaitbar; delete(waitbar); end
                end

                if importMasks
                    if obj.BatchOpt.showWaitbar
                        waitbar = uiprogressdlg(obj.mibModel.getProgressBarParent(), ...
                            'Title', 'Recombine Dataset', 'Message', 'Combining masks...', ...
                            'Value', 0);
                    end

                    obj.mibModel.I{id}.clearLayer('mask');
                    obj.mibModel.I{id}.maskExist = 1;
                    maskOut = zeros([outHeight, outWidth, outDepth], 'uint8');

                    tileHeightMk = zeros(numberOfFiles, 1);
                    tileWidthMk  = zeros(numberOfFiles, 1);
                    tileDepthMk  = zeros(numberOfFiles, 1);

                    for fileId = 1:numberOfFiles
                        [~, baseName] = fileparts(filenames{fileId});
                        if isempty(strfind(baseName, 'Mask'))  %#ok<STREMP>
                            maskFn = fullfile(fileparts(filenames{fileId}), ['Mask_' baseName '.mask']);
                        else
                            maskFn = fullfile(fileparts(filenames{fileId}), [baseName '.mask']);
                        end

                        if exist(maskFn, 'file') == 0
                            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                sprintf('Mask file not found:\n%s\n\nUncheck Masks or fix filenames.', maskFn), ...
                                'Missing mask files');
                            if obj.BatchOpt.showWaitbar; delete(waitbar); end
                            return;
                        end

                        if fileId == 1
                            maskVars = whos('-file', maskFn);
                            maskVarName = maskVars(1).name;
                        end
                        info = whos('-file', maskFn, maskVarName);
                        tileHeightMk(fileId) = info.size(1);
                        tileWidthMk(fileId)  = info.size(2);
                        tileDepthMk(fileId)  = info.size(3);
                    end

                    % Precompute per-axis cumulative positions (one rep per unique index).
                    yCumMk = [0, cumsum(arrayfun(@(ty) tileHeightMk(find(yIndex==ty,1)), 1:tilesY))];
                    xCumMk = [0, cumsum(arrayfun(@(tx) tileWidthMk(find(xIndex==tx,1)),  1:tilesX))];
                    zCumMk = [0, cumsum(arrayfun(@(tz) tileDepthMk(find(zIndex==tz,1)),  1:tilesZ))];

                    for fileId = 1:numberOfFiles
                        [~, baseName] = fileparts(filenames{fileId});
                        if isempty(strfind(baseName, 'Mask'))  %#ok<STREMP>
                            maskFn = fullfile(fileparts(filenames{fileId}), ['Mask_' baseName '.mask']);
                        else
                            maskFn = fullfile(fileparts(filenames{fileId}), [baseName '.mask']);
                        end

                        R = load(maskFn, '-mat');
                        maskTile = R.(maskVarName);

                        yMin = yCumMk(yIndex(fileId)) + 1;
                        yMax = min(yCumMk(yIndex(fileId)+1), outHeight);
                        xMin = xCumMk(xIndex(fileId)) + 1;
                        xMax = min(xCumMk(xIndex(fileId)+1), outWidth);
                        zMin = zCumMk(zIndex(fileId)) + 1;
                        zMax = min(zCumMk(zIndex(fileId)+1), outDepth);

                        maskOut(yMin:yMax, xMin:xMax, zMin:zMax) = maskTile(1:(yMax-yMin+1), 1:(xMax-xMin+1), 1:(zMax-zMin+1));

                        if obj.BatchOpt.showWaitbar
                            waitbar.Value = fileId / numberOfFiles;
                        end
                    end

                    setOpts.blockModeSwitch = 0;
                    obj.mibModel.setData3D(maskOut, 'mask', NaN, 3, NaN, setOpts);
                    if obj.BatchOpt.showWaitbar; delete(waitbar); end
                end

            else
                % --------------------------------------------------------
                % FUSE TO EXISTING mode
                % --------------------------------------------------------
                if importMasks && ~importLabels && ~importImages
                    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                        'Fuse mode requires bounding-box information, which is only present in image and label files, not in mask files.', ...
                        'Fuse mode error');
                    return;
                end

                xOffset = obj.BatchOpt.OffsetX{1};
                yOffset = obj.BatchOpt.OffsetY{1};
                zOffset = obj.BatchOpt.OffsetZ{1};

                if importLabels && ~importImages
                    backupOpts.id = id;
                    obj.mibModel.backup('labels', 1, backupOpts);
                else
                    backupOpts.id = id;
                    obj.mibModel.backup('image', 1, backupOpts);
                end

                if importLabels && ~obj.mibModel.I{id}.modelExist
                    obj.mibModel.I{id}.createModel();
                end

                materialNames  = obj.mibModel.I{id}.labels.materialNames;
                materialColors = obj.mibModel.I{id}.labels.materialColors;

                pixSize = obj.mibModel.I{id}.image.pixSize;
                currBB  = obj.mibModel.I{id}.image.boundingBox;

                if obj.BatchOpt.showWaitbar
                    waitbar = uiprogressdlg(obj.mibModel.getProgressBarParent(), ...
                        'Title', 'Fuse Datasets', 'Message', 'Fusing...', ...
                        'Value', 0, 'Cancelable', 'on');
                end

                for fileId = 1:numberOfFiles
                    if obj.BatchOpt.showWaitbar
                        waitbar.Value = (fileId-1) / numberOfFiles;
                        waitbar.Message = sprintf('File %d of %d', fileId, numberOfFiles);
                        if waitbar.CancelRequested
                            delete(waitbar);
                            return;
                        end
                    end

                    if importImages
                        % Load image and check bounding box in description
                        extReg = io.ExtensionRegistryLoad();
                        loaderInfo = extReg.resolveLoader(filenames{fileId}, 'Standard', 'Default');
                        loaderOpts = struct('waitbar', 0, 'silentMode', true);
                        loader = io.LoaderFactory.create(loaderInfo, loaderOpts);
                        [imginfo, files] = loader.loadMetadata(filenames(fileId), loaderOpts);

                        % Extract bounding box — try direct key first (some loaders),
                        % then fall back to parsing ImageDescription
                        tilesBB = [];
                        if isKey(imginfo, 'BoundingBox')
                            bbVal = imginfo('BoundingBox');
                            if isnumeric(bbVal) && numel(bbVal) == 6
                                tilesBB = bbVal(:)';
                            end
                        end
                        if isempty(tilesBB) && isKey(imginfo, 'ImageDescription')
                            [bbPart, ~] = core.MibImage.splitImageDescription(char(imginfo('ImageDescription')));
                            coords = sscanf(bbPart, 'BoundingBox %f %f %f %f %f %f');
                            if numel(coords) == 6; tilesBB = coords(:)'; end
                        end
                        if isempty(tilesBB)
                            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                'Fuse mode requires BoundingBox in file metadata.', ...
                                'Missing BoundingBox');
                            if obj.BatchOpt.showWaitbar; delete(waitbar); end
                            return;
                        end

                        tilePix = imginfo('pixSize');
                        if isfield(tilePix, 'x') && ...
                                abs(tilePix.x - pixSize.x) > 1e-6 || abs(tilePix.y - pixSize.y) > 1e-6
                            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                sprintf('Pixel size mismatch!\n\nFile: %s', filenames{fileId}), ...
                                'Pixel sizes mismatch!');
                            if obj.BatchOpt.showWaitbar; delete(waitbar); end
                            return;
                        end

                        % round() tolerates floating-point rounding errors (~0.001) that
                        % would cause ceil(...+1e-9) to return xMin-1 instead of xMin
                        x1 = max(1, round((tilesBB(1)-currBB(1))/pixSize.x) + 1 + xOffset);
                        y1 = max(1, round((tilesBB(3)-currBB(3))/pixSize.y) + 1 + yOffset);
                        z1 = max(1, round((tilesBB(5)-currBB(5))/pixSize.z) + 1 + zOffset);

                        [img, ~] = loader.loadImages(files, imginfo, loaderOpts);
                        img = img(:,:,:,:,1);  % take first time point [H, W, D, C]

                        tileH = size(img, 1);
                        tileW = size(img, 2);
                        tileD = size(img, 3);

                        x2 = min(x1 + tileW - 1, obj.mibModel.I{id}.image.width);
                        y2 = min(y1 + tileH - 1, obj.mibModel.I{id}.image.height);
                        z2 = min(z1 + tileD - 1, obj.mibModel.I{id}.image.depth);

                        if x2 > obj.mibModel.I{id}.image.width || ...
                                y2 > obj.mibModel.I{id}.image.height || ...
                                z2 > obj.mibModel.I{id}.image.depth
                            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                sprintf('Bounding box exceeds dataset bounds!\n\nFile: %s', filenames{fileId}), ...
                                'Wrong bounding box!');
                            if obj.BatchOpt.showWaitbar; delete(waitbar); end
                            return;
                        end

                        setOpts.x = [x1, x2];
                        setOpts.y = [y1, y2];
                        setOpts.z = [z1, z2];
                        setOpts.blockModeSwitch = 0;
                        obj.mibModel.setData3D(img(1:(y2-y1+1), 1:(x2-x1+1), 1:(z2-z1+1), :), ...
                            'image', NaN, 3, NaN, setOpts);

                        if importLabels
                            [~, baseName] = fileparts(filenames{fileId});
                            if isempty(strfind(baseName, 'Labels'))  %#ok<STREMP>
                                modelFn = fullfile(fileparts(filenames{fileId}), ['Labels_' baseName labelsExt]);
                            else
                                modelFn = fullfile(fileparts(filenames{fileId}), [baseName labelsExt]);
                            end

                            if exist(modelFn, 'file') == 0
                                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                    sprintf('Label file not found:\n%s', modelFn), 'Missing label files');
                                if obj.BatchOpt.showWaitbar; delete(waitbar); end
                                return;
                            end

                            R = obj.loadModels(modelFn);
                            if isfield(R, 'materialNames') && numel(R.materialNames) > numel(materialNames)
                                materialNames = R.materialNames;
                            end
                            if isfield(R, 'materialColors') && size(R.materialColors, 1) > size(materialColors, 1)
                                materialColors = R.materialColors;
                            end

                            obj.mibModel.setData3D(R.imOut(1:(y2-y1+1), 1:(x2-x1+1), 1:(z2-z1+1)), ...
                                'labels', NaN, 3, NaN, setOpts);
                        end

                        if importMasks
                            [~, baseName] = fileparts(filenames{fileId});
                            maskFn = fullfile(fileparts(filenames{fileId}), ['Mask_' baseName '.mask']);
                            if exist(maskFn, 'file') == 0
                                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                    sprintf('Mask file not found:\n%s', maskFn), 'Missing mask files');
                                if obj.BatchOpt.showWaitbar; delete(waitbar); end
                                return;
                            end
                            maskData = load(maskFn, '-mat');
                            maskFields = fieldnames(maskData);
                            obj.mibModel.setData3D(maskData.(maskFields{1})(1:(y2-y1+1), 1:(x2-x1+1), 1:(z2-z1+1)), ...
                                'mask', NaN, 3, NaN, setOpts);
                        end

                    elseif importLabels
                        % Labels-only fuse (uses bounding box from the model file)
                        R = obj.loadModels(filenames{fileId});
                        if ~isfield(R, 'BoundingBox')
                            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                sprintf('BoundingBox missing in:\n%s', filenames{fileId}), 'Missing BoundingBox');
                            if obj.BatchOpt.showWaitbar; delete(waitbar); end
                            return;
                        end

                        if isfield(R, 'materialNames') && numel(R.materialNames) > numel(materialNames)
                            materialNames = R.materialNames;
                        end
                        if isfield(R, 'materialColors') && size(R.materialColors, 1) > size(materialColors, 1)
                            materialColors = R.materialColors;
                        end

                        tilesBB = R.BoundingBox;
                        modelData = R.imOut;

                        if tilesBB(1) < currBB(1) || tilesBB(2) > currBB(2) || ...
                                tilesBB(3) < currBB(3) || tilesBB(4) > currBB(4) || ...
                                tilesBB(5) < currBB(5) || tilesBB(6) > currBB(6)
                            % Model is larger — crop from left then paste at origin
                            cx1 = max(1, round((currBB(1)-tilesBB(1))/pixSize.x) + 1 + xOffset);
                            cy1 = max(1, round((currBB(3)-tilesBB(3))/pixSize.y) + 1 + yOffset);
                            cz1 = max(1, round((currBB(5)-tilesBB(5))/pixSize.z) + 1 + zOffset);
                            modelData = modelData(cy1:end, cx1:end, cz1:end);
                            modelData = modelData( ...
                                1:min(size(modelData,1), obj.mibModel.I{id}.image.height), ...
                                1:min(size(modelData,2), obj.mibModel.I{id}.image.width), ...
                                1:min(size(modelData,3), obj.mibModel.I{id}.image.depth));
                            x1 = 1; y1 = 1; z1 = 1;
                        else
                            x1 = max(1, round((tilesBB(1)-currBB(1))/pixSize.x) + 1 + xOffset);
                            y1 = max(1, round((tilesBB(3)-currBB(3))/pixSize.y) + 1 + yOffset);
                            z1 = max(1, round((tilesBB(5)-currBB(5))/pixSize.z) + 1 + zOffset);
                        end

                        x2 = x1 + size(modelData, 2) - 1;
                        y2 = y1 + size(modelData, 1) - 1;
                        z2 = z1 + size(modelData, 3) - 1;

                        if x2 > obj.mibModel.I{id}.image.width || ...
                                y2 > obj.mibModel.I{id}.image.height || ...
                                z2 > obj.mibModel.I{id}.image.depth
                            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                                sprintf('Bounding box exceeds dataset bounds!\n\nFile: %s', filenames{fileId}), ...
                                'Wrong bounding box!');
                            if obj.BatchOpt.showWaitbar; delete(waitbar); end
                            return;
                        end

                        setOpts.x = [x1, x2];
                        setOpts.y = [y1, y2];
                        setOpts.z = [z1, z2];
                        setOpts.blockModeSwitch = 0;
                        obj.mibModel.setData3D(modelData, 'labels', NaN, 3, NaN, setOpts);

                        % Add point annotations with position offset
                        if isfield(R, 'labelText')
                            R.labelPosition(:,1) = R.labelPosition(:,1) + z1 - 1;
                            R.labelPosition(:,2) = R.labelPosition(:,2) + x1 - 1;
                            R.labelPosition(:,3) = R.labelPosition(:,3) + y1 - 1;
                            if isfield(R, 'labelValues'); R.labelValue = R.labelValues; end
                            if isfield(R, 'labelValue')
                                obj.mibModel.I{id}.annotations.addLabels(R.labelText, R.labelPosition, R.labelValue);
                            else
                                obj.mibModel.I{id}.annotations.addLabels(R.labelText, R.labelPosition);
                            end
                        end
                    end
                end

                if obj.BatchOpt.showWaitbar; delete(waitbar); end
            end

            % ---- Update model material metadata and display
            if importLabels
                obj.mibModel.I{id}.labels.materialNames  = materialNames;
                obj.mibModel.I{id}.labels.materialColors = materialColors;
                obj.mibModel.showModel = true;
            end
            if importMasks
                obj.mibModel.showMask = true;
                obj.mibModel.I{id}.maskExist = 1;
            end

            notify(obj.mibModel, 'NewDataset');
            notify(obj.mibModel, 'ShowImage');

            % Restore the file selection that was cleared by the NewDataset listener
            obj.filenames = filenames;
            if ~batchModeSwitch && ~isempty(obj.view) && isvalid(obj.view.gui)
                [~, fNames, fExts] = cellfun(@fileparts, filenames, 'UniformOutput', false);
                obj.view.handles.SelectedFilesListBox.Items = strcat(fNames, fExts);
            end

            obj.returnBatchOpt();
        end

        % ---------------------------------------------------------------
        function R = loadModels(obj, filename)
            % LOADMODELS - Load model/label data from a file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       R = obj.loadModels(filename)
            %
            % Input Arguments:
            %   - **filename** — (char) full path to the label file
            %
            % Output Arguments:
            %   - **R** — struct with fields:
            %
            %     - ``.imOut`` — label volume as uint8 [H, W, D]
            %     - ``.materialNames`` — (optional) cell array of material names
            %     - ``.materialColors`` — (optional) [N×3] RGB colors 0-1
            %     - ``.BoundingBox`` — (optional) [xmin xmax ymin ymax zmin zmax]
            %     - ``.labelText``, ``.labelValue``, ``.labelPosition`` — point annotations (optional)
            %

            R = struct();
            if exist(filename, 'file') == 0
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    sprintf('File not found:\n%s', filename), 'Missing file');
                return;
            end
            [~, ~, labelExt] = fileparts(filename);

            switch labelExt
                case {'.mat', '.model'}
                    R = load(filename, '-mat');
                    % Normalise variable name to R.imOut
                    if isfield(R, 'modelVariable') && ~isfield(R, 'imOut')
                        R.imOut = R.(R.modelVariable);
                        R = rmfield(R, R.modelVariable);
                        R.modelVariable = 'imOut';
                    elseif isfield(R, 'model_var') && ~isfield(R, 'imOut')
                        R.imOut = R.(R.model_var);
                        R = rmfield(R, R.model_var);
                        R.modelVariable = 'imOut';
                    end
                    % Normalise field names to materialNames/materialColors
                    if isfield(R, 'modelMaterialNames') && ~isfield(R, 'materialNames')
                        R.materialNames = R.modelMaterialNames;
                    end
                    if isfield(R, 'modelMaterialColors') && ~isfield(R, 'materialColors')
                        R.materialColors = R.modelMaterialColors;
                    end
                    % Normalise BoundingBox field name (ChunkingExport saves as lowercase 'boundingBox')
                    if isfield(R, 'boundingBox') && ~isfield(R, 'BoundingBox')
                        R.BoundingBox = R.boundingBox;
                    end

                case '.am'
                    loaderOpts = struct('waitbar', 0, 'silentMode', true);
                    extReg = io.ExtensionRegistryLoad();
                    loaderInfo = extReg.resolveLoader(filename, 'Standard', 'Default');
                    loader = io.LoaderFactory.create(loaderInfo, loaderOpts);
                    [imginfo, ~] = loader.loadMetadata({filename}, loaderOpts);
                    % Parse material names and colors from imginfo keys
                    keysList = keys(imginfo);
                    for keyIdx = 1:numel(keysList)
                        if ~isempty(strfind(keysList{keyIdx}, 'Materials_'))
                            matName = keysList{keyIdx}(11:end);
                            materialInfo = imginfo(keysList{keyIdx});
                            if ~isempty(strfind(matName, 'Color'))  %#ok<STREMP>
                                materialColor = str2num(materialInfo); %#ok<ST2NM>
                                materialIndex = imginfo(keysList{keyIdx+1});
                                R.materialColors(materialIndex, :) = materialColor(1:3);
                                R.materialNames{materialIndex} = matName(1:end-6);
                            end
                        end
                    end
                    R.imOut = io.AmiraMesh.amiraLabels2bitmap(filename);
                    % Extract BoundingBox from Amira imginfo
                    if isKey(imginfo, 'BoundingBox')
                        bbVal = imginfo('BoundingBox');
                        if isnumeric(bbVal) && numel(bbVal) == 6
                            R.BoundingBox = bbVal(:)';
                        end
                    elseif isKey(imginfo, 'ImageDescription')
                        [bbPart, ~] = core.MibImage.splitImageDescription(char(imginfo('ImageDescription')));
                        coords = sscanf(bbPart, 'BoundingBox %f %f %f %f %f %f');
                        if numel(coords) == 6; R.BoundingBox = coords(:)'; end
                    end

                case '.nrrd'
                    img = io.loadImagesWrapper(filename);   % [H, W, D, C, T]
                    R.imOut = uint8(squeeze(img(:,:,:,1,1)));

                case {'.tif', '.xml'}
                    img = io.loadImagesWrapper(filename);   % [H, W, D, C, T]
                    R.imOut = uint8(squeeze(img(:,:,:,1,1)));
            end

            % Extract bounding box via loader metadata if not already set
            if ~isfield(R, 'BoundingBox')
                try
                    loaderOpts2 = struct('waitbar', 0, 'silentMode', true);
                    extReg2 = io.ExtensionRegistryLoad();
                    loaderInfo2 = extReg2.resolveLoader(filename, 'Standard', 'Default');
                    loader2 = io.LoaderFactory.create(loaderInfo2, loaderOpts2);
                    [imginfo2, ~] = loader2.loadMetadata({filename}, loaderOpts2);
                    % Try direct numeric key first (MatModelLoader sets this)
                    if isKey(imginfo2, 'BoundingBox')
                        bbVal = imginfo2('BoundingBox');
                        if isnumeric(bbVal) && numel(bbVal) == 6
                            R.BoundingBox = bbVal(:)';
                        end
                    end
                    % Fall back to parsing ImageDescription
                    if ~isfield(R, 'BoundingBox') && isKey(imginfo2, 'ImageDescription')
                        [bbPart, ~] = core.MibImage.splitImageDescription(char(imginfo2('ImageDescription')));
                        coords = sscanf(bbPart, 'BoundingBox %f %f %f %f %f %f');
                        if numel(coords) == 6; R.BoundingBox = coords(:)'; end
                    end
                catch
                end
            end

            % Generate default material names/colors if missing
            if isfield(R, 'imOut') && ~isfield(R, 'materialNames')
                id = obj.mibModel.getActiveId();
                numberOfMaterials = max(R.imOut(:));
                for matId = 1:numberOfMaterials
                    R.materialNames{matId} = num2str(matId);
                    if matId <= size(obj.mibModel.I{id}.labels.materialColors, 1)
                        R.materialColors(matId, :) = obj.mibModel.I{id}.labels.materialColors(matId, :);
                    else
                        R.materialColors(matId, :) = rand(1, 3);
                    end
                end
            end
        end

    end
end
