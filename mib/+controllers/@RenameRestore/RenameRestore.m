classdef RenameRestore < handle
% RENAMERESTORE - Controller for restoring shuffled datasets to their original order.
%
% Reads a ``*.mibShuffle`` project file produced by :class:`controllers.RenameShuffle`
% and reconstructs labels, masks, annotations, and/or measurements in the
% original input directories.
%
% Usage:
%   .. code-block:: matlab
%
%      obj.mibController.startController('controllers.RenameRestore');

    properties
        mibModel            % handle to MibModel
        view                % handle to RenameRestoreGUI (set by core.ChildView)
        listener            % cell array of listener handles
        inputFilename = []  % path to a ``.mibShuffle`` project file
        Settings = struct() % project settings loaded from the project file
    end

    events
        CloseEvent          % fired when the window closes
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static guarded listener callback.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ViewListner_Callback2(src, evnt)
            %
            % Routes ``UpdateGuiWidgets`` and ``NewDataset`` model events to
            % :meth:`updateWidgets`. Deletes stale listeners when the controller
            % or its view has been destroyed.
            %
            % Input Arguments:
            %   - **obj** - :class:`controllers.RenameRestore` instance.
            %   - **evnt** - event data from the model.
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
        % --- External method file declarations ---
        gui_Callbacks(obj, source, event)

        % ---------------------------------------------------------------
        function obj = RenameRestore(mibModel)
            % RENAMERESTORE - Construct the rename-and-restore controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = controllers.RenameRestore(mibModel)
            %
            % Input Arguments:
            %   - **mibModel** - handle to :class:`models.MibModel`.

            obj.mibModel = mibModel;
            obj.inputFilename = fullfile(obj.mibModel.currentDirectory, 'Shuffled', 'Shuffled.mibShuffle');

            guiName = 'views.RenameRestoreGUI';
            obj.view = core.ChildView(obj, guiName);

            obj.view.handles.projectFilenameEdit.Value   = obj.inputFilename;
            obj.view.handles.projectFilenameEdit.Tooltip = obj.inputFilename;

            obj.addCallbacks();

            Font = obj.mibModel.preferences.System.Font;

            if obj.view.handles.closeBtn.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeBtn.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj,src,evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj,src,evnt));
            obj.view.gui.Visible = 'on';
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and release listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()

            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Load project details if the project file exists.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()

            if exist(obj.inputFilename, 'file') ~= 0
                obj.updateProjectDetails();
            end
        end

        % ---------------------------------------------------------------
        function updateProjectDetails(obj)
            % UPDATEPROJECTDETAILS - Populate the directory lists from Settings.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateProjectDetails()

            if isempty(fieldnames(obj.Settings)); return; end
            h = obj.view.handles;

            h.randomDirsList.Items = obj.Settings.outputDirName;
            if ~isempty(obj.Settings.outputDirName)
                h.randomDirsList.Value = obj.Settings.outputDirName{1};
            end

            h.destinationDirsList.Items = obj.Settings.inputDirName;
            if ~isempty(obj.Settings.inputDirName)
                h.destinationDirsList.Value = obj.Settings.inputDirName{1};
            end

            h.numImagesText.Text = sprintf('Total number of images: %d', numel(obj.Settings.InputImagesCombined));
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire every widget to the central gui_Callbacks dispatcher.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()
            %
            % Also creates context menus for the two directory listboxes.

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            h  = obj.view.handles;
            cb = @(src,evt) obj.gui_Callbacks(src, evt);

            h.closeBtn.ButtonPushedFcn              = cb;
            h.helpBtn.ButtonPushedFcn               = cb;
            h.selectSettingsFileBtn.ButtonPushedFcn = cb;
            h.restoreBtn.ButtonPushedFcn            = cb;
            h.resaveProjectBtn.ButtonPushedFcn      = cb;

            h.projectFilenameEdit.ValueChangedFcn      = cb;
            h.includeModelCheck.ValueChangedFcn         = cb;
            h.includeMaskCheck.ValueChangedFcn         = cb;
            h.includeAnnotationsCheck.ValueChangedFcn  = cb;
            h.includeMeasurementsCheck.ValueChangedFcn = cb;

            % Context menu for the shuffled-directories list
            contextMenu1 = uicontextmenu(obj.view.gui);
            menuItem = uimenu(contextMenu1, 'Text', 'Update directory');
            menuItem.Tag = 'randomDirsList_updateDir';
            menuItem.MenuSelectedFcn = cb;
            menuItem = uimenu(contextMenu1, 'Text', 'Update parent folder for selected directories');
            menuItem.Tag = 'randomDirsList_updateParentDir';
            menuItem.MenuSelectedFcn = cb;
            menuItem = uimenu(contextMenu1, 'Text', 'Copy path to clipboard', 'Separator', 'on');
            menuItem.Tag = 'randomDirsList_clipboard';
            menuItem.MenuSelectedFcn = cb;
            menuItem = uimenu(contextMenu1, 'Text', 'Open directory in file explorer');
            menuItem.Tag = 'randomDirsList_fileexplorer';
            menuItem.MenuSelectedFcn = cb;
            h.randomDirsList.ContextMenu = contextMenu1;

            % Context menu for the destination-directories list
            contextMenu2 = uicontextmenu(obj.view.gui);
            menuItem = uimenu(contextMenu2, 'Text', 'Update directory');
            menuItem.Tag = 'destinationDirsList_updateDir';
            menuItem.MenuSelectedFcn = cb;
            menuItem = uimenu(contextMenu2, 'Text', 'Update parent folder for selected directories');
            menuItem.Tag = 'destinationDirsList_updateParentDir';
            menuItem.MenuSelectedFcn = cb;
            menuItem = uimenu(contextMenu2, 'Text', 'Copy path to clipboard', 'Separator', 'on');
            menuItem.Tag = 'destinationDirsList_clipboard';
            menuItem.MenuSelectedFcn = cb;
            menuItem = uimenu(contextMenu2, 'Text', 'Open directory in file explorer');
            menuItem.Tag = 'destinationDirsList_fileexplorer';
            menuItem.MenuSelectedFcn = cb;
            h.destinationDirsList.ContextMenu = contextMenu2;
        end

        % ---------------------------------------------------------------
        function projectFilenameEdit_Callback(obj)
            % PROJECTFILENAMEEDIT_CALLBACK - Validate the typed project filename and load it.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.projectFilenameEdit_Callback()

            filename = obj.view.handles.projectFilenameEdit.Value;
            if exist(filename, 'file') == 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('There is no file with the following filename:\n%s', filename), ...
                    'Wrong filename');
                obj.view.handles.projectFilenameEdit.Value = obj.inputFilename;
                return;
            end
            obj.inputFilename = filename;
            obj.view.handles.projectFilenameEdit.Tooltip = obj.inputFilename;

            loadedData = load(obj.inputFilename, '-mat');
            if ~isfield(loadedData, 'Settings')
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'Something is wrong with the project file!', 'Project file error');
                return;
            end
            obj.Settings = loadedData.Settings;
            obj.updateWidgets();
        end

        % ---------------------------------------------------------------
        function selectSettingsFileBtn_Callback(obj)
            % SELECTSETTINGSFILEBN_CALLBACK - Browse for a ``.mibShuffle`` project file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.selectSettingsFileBtn_Callback()

            filename = obj.inputFilename;
            if exist(filename, 'file') == 0
                filename = obj.mibModel.currentDirectory;
            end

            [selectedFilename, selectedPath] = uigetfile( ...
                {'*.mibShuffle', 'MIB shuffle project files (*.mibShuffle)'; ...
                 '*.*', 'All Files (*.*)'}, ...
                'Select a project file', filename);
            if isequal(selectedFilename, 0); return; end

            obj.inputFilename = fullfile(selectedPath, selectedFilename);
            obj.view.handles.projectFilenameEdit.Value   = obj.inputFilename;
            obj.view.handles.projectFilenameEdit.Tooltip = obj.inputFilename;

            loadedData = load(obj.inputFilename, '-mat');
            if ~isfield(loadedData, 'Settings')
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'Something is wrong with the project file!', 'Project file error');
                return;
            end
            obj.Settings = loadedData.Settings;
            obj.updateWidgets();
        end

        % ---------------------------------------------------------------
        function copyShowDirectory(obj, listId, parameter)
            % COPYSHOWDIRECTORY - Copy the selected directory path to clipboard or open in explorer.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.copyShowDirectory(listId, parameter)
            %
            % Input Arguments:
            %   - **listId** - ``'randomDirsList'`` or ``'destinationDirsList'``.
            %   - **parameter** - ``'clipboard'`` or ``'fileexplorer'``.

            directoryName = char(obj.view.handles.(listId).Value);
            if isempty(directoryName); return; end

            switch parameter
                case 'clipboard'
                    clipboard('copy', directoryName);

                case 'fileexplorer'
                    if isfolder(directoryName)
                        if ispc
                            system(sprintf('explorer.exe "%s"', directoryName));
                        elseif ismac
                            system(sprintf('open %s &', directoryName));
                        else
                            try
                                unix(sprintf('caja %s &', directoryName));
                            catch
                                unix(sprintf('xterm -e cd %s &', directoryName));
                            end
                        end
                    else
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            sprintf('Wrong directory!\n\n%s', directoryName), 'Directory not found');
                    end
            end
        end

        % ---------------------------------------------------------------
        function updateDir(obj, parameter)
            % UPDATEDIR - Replace the selected directory path in Settings and the listbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateDir(parameter)
            %
            % Input Arguments:
            %   - **parameter** - ``'randomDirsList'`` or ``'destinationDirsList'``.

            if isempty(fieldnames(obj.Settings)); return; end

            h = obj.view.handles;
            if isempty(h.(parameter).Items); return; end
            currentDirectoryName = char(h.(parameter).Value);
            if isempty(currentDirectoryName); return; end
            selectionIndex = find(strcmp(h.(parameter).Items, currentDirectoryName), 1);

            if exist(currentDirectoryName, 'dir') == 0
                currentDirectoryName = obj.mibModel.currentDirectory;
            end
            newDirectoryName = uigetdir(currentDirectoryName, 'Select directory');
            if isequal(newDirectoryName, 0); return; end

            switch parameter
                case 'randomDirsList'
                    obj.Settings.outputDirName{selectionIndex} = newDirectoryName;
                case 'destinationDirsList'
                    obj.Settings.inputDirName{selectionIndex}  = newDirectoryName;
            end
            obj.updateProjectDetails();
        end

        % ---------------------------------------------------------------
        function resaveProject(obj)
            % RESAVEPROJECT - Save the Settings (with updated paths) to a new project file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.resaveProject()

            if isempty(fieldnames(obj.Settings))
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'Please select the project file first!', 'The project is missing');
                return;
            end

            [selectedFile, selectedPath] = uiputfile( ...
                {'*.mibShuffle', 'MIB shuffle project files (*.mibShuffle)'; ...
                 '*.*', 'All Files (*.*)'}, ...
                'Select new project filename', obj.inputFilename);
            if isequal(selectedFile, 0); return; end

            filenameOut = fullfile(selectedPath, selectedFile);
            Settings    = obj.Settings;
            save(filenameOut, 'Settings');
        end

        % ---------------------------------------------------------------
        function updateParentDir(obj, parameter)
            % UPDATEPARENTDIR - Replace the parent folder for all directories in a list.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateParentDir(parameter)
            %
            % Prompts for a new parent folder and rebuilds every path in the list
            % by replacing the old parent while keeping each subdirectory name.
            %
            % Input Arguments:
            %   - **parameter** - ``'randomDirsList'`` or ``'destinationDirsList'``.

            if isempty(fieldnames(obj.Settings)); return; end

            h = obj.view.handles;
            currentItems = h.(parameter).Items;
            if isempty(currentItems); return; end
            currentParent = fileparts(currentItems{1});
            if exist(currentParent, 'dir') == 0
                currentParent = obj.mibModel.currentDirectory;
            end

            newParent = uigetdir(currentParent, 'Select new parent folder for all directories');
            if isequal(newParent, 0); return; end

            for idx = 1:numel(currentItems)
                [~, subdirName] = fileparts(currentItems{idx});
                switch parameter
                    case 'randomDirsList'
                        obj.Settings.outputDirName{idx} = fullfile(newParent, subdirName);
                    case 'destinationDirsList'
                        obj.Settings.inputDirName{idx}  = fullfile(newParent, subdirName);
                end
            end
            obj.updateProjectDetails();
        end

        % ---------------------------------------------------------------
        function restoreBtn_Callback(obj)
            % RESTOREBN_CALLBACK - Execute the restore operation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.restoreBtn_Callback()
            %
            % Reads shuffled model/mask/annotation/measurement files from the
            % randomized directories and reconstructs them in the original
            % (destination) directories using the mapping stored in Settings.

            h = obj.view.handles;
            includeModels       = h.includeModelCheck.Value;
            includeMasks        = h.includeMaskCheck.Value;
            includeAnnotations  = h.includeAnnotationsCheck.Value;
            includeMeasurements = h.includeMeasurementsCheck.Value;

            filename = obj.inputFilename;
            if exist(filename, 'file') == 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('There is no file with the following filename:\n%s', filename), ...
                    'Wrong filename');
                return;
            end

            % Validate that all shuffled directories exist
            for dirId = 1:numel(obj.Settings.outputDirName)
                if exist(obj.Settings.outputDirName{dirId}, 'dir') == 0
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('The specified directory with shuffled images was not found!\n\n%s\n\nMost likely it was renamed or copied somewhere; use the right-click menu to update it.', ...
                        obj.Settings.outputDirName{dirId}), 'Directory not found');
                    return;
                end
            end
            for dirId = 1:numel(obj.Settings.inputDirName)
                if exist(obj.Settings.inputDirName{dirId}, 'dir') == 0
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('The specified destination directory was not found!\n\n%s\n\nMost likely it was renamed or copied somewhere; use the right-click menu to update it.', ...
                        obj.Settings.inputDirName{dirId}), 'Directory not found');
                    return;
                end
            end

            progressDlg = uiprogressdlg(obj.view.gui, 'Value', 0, ...
                'Message', sprintf('Loading models\nPlease wait...'), ...
                'Title', 'Restore shuffled images');

            InputModels = {};

            % Build required extension list and validate presence
            checkExtensions = {};
            if includeModels;       checkExtensions = [checkExtensions, {'.model'}]; end
            if includeMasks;        checkExtensions = [checkExtensions, {'.mask'}]; end
            if includeAnnotations;  checkExtensions = [checkExtensions, {'.ann'}]; end
            if includeMeasurements; checkExtensions = [checkExtensions, {'.measure'}]; end

            for dirId = 1:numel(obj.Settings.outputDirName)
                fileList = dir(obj.Settings.outputDirName{dirId});
                fileList = {fileList.name};
                [~,~,extensionVector] = cellfun(@fileparts, fileList, 'UniformOutput', false);

                for extIdx = 1:numel(checkExtensions)
                    currentExtension = checkExtensions{extIdx};
                    if sum(ismember(extensionVector, currentExtension)) ~= 1
                        if strcmp(currentExtension, '.ann')
                            extraInfo = '';
                        else
                            extensionName = currentExtension(2:end);
                            extraInfo = sprintf('\n\nIf you have multiple files they can be combined:\n1. Combine all images in the folder\n2. Load the %ss (Shift-click to select multiple)\n3. Save the combined %s\n4. Remove all other %s files from the directory', ...
                                extensionName, extensionName, extensionName);
                        end
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            sprintf('The *%s file is missing or there are more than one *%s file!\n\nPlease make sure there is a single *%s file in each directory%s', ...
                            currentExtension, currentExtension, currentExtension, extraInfo), ...
                            'File validation error');
                        delete(progressDlg);
                        return;
                    end
                end

                % Collect filenames for each file type
                for fileIdx = 1:numel(fileList)
                    [~,~,ext] = fileparts(fileList{fileIdx});
                    if includeModels && ismember(ext, {'.model'})
                        inputModelFilenames{dirId} = fullfile(obj.Settings.outputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                        InputModels{dirId} = load(inputModelFilenames{dirId}, '-mat'); %#ok<AGROW>
                    end
                    if includeMasks && ismember(ext, {'.mask'})
                        inputMaskFilenames{dirId} = fullfile(obj.Settings.outputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                    end
                    if includeAnnotations && ismember(ext, {'.ann'})
                        inputAnnotationsFilenames{dirId} = fullfile(obj.Settings.outputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                    end
                    if includeMeasurements && ismember(ext, {'.measure'})
                        inputMeasurementsFilenames{dirId} = fullfile(obj.Settings.outputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                    end
                end
            end

            progressDlg.Value   = 0.5;
            progressDlg.Message = sprintf('Generating restored models\nPlease wait...');

            if includeModels
                if isempty(InputModels)
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        'Directories with shuffled images should contain .model files!', 'No models');
                    delete(progressDlg);
                    return;
                end

                modelVariable       = InputModels{1}.modelVariable;
                modelMaterialColors = InputModels{1}.modelMaterialColors;
                modelMaterialNames  = InputModels{1}.modelMaterialNames;
                modelType           = InputModels{1}.modelType;

                imageHeight = size(InputModels{1}.(InputModels{1}.modelVariable), 1);
                imageWidth  = size(InputModels{1}.(InputModels{1}.modelVariable), 2);

                indexShift = 0;
                for dirId = 1:numel(obj.Settings.inputDirName)
                    outputIndices = find(obj.Settings.inputIndices == dirId);
                    mibModel = zeros([imageHeight, imageWidth, numel(outputIndices)], ...
                        class(InputModels{1}.(InputModels{1}.modelVariable))); %#ok<PROP>
                    labelPosition = [];
                    labelText     = {};
                    labelValue    = [];

                    for sliceIndex = 1:numel(outputIndices)
                        outputDirId = 0;
                        sliceNumber = [];
                        while isempty(sliceNumber)
                            outputDirId = outputDirId + 1;
                            sliceNumber = find(obj.Settings.OutputIndicesSorted{outputDirId} == sliceIndex + indexShift);
                        end
                        mibModel(:,:,sliceIndex) = InputModels{outputDirId}.(InputModels{outputDirId}.modelVariable)(:,:,sliceNumber); %#ok<PROP>

                        if isfield(InputModels{outputDirId}, 'labelPosition')
                            labelIndices = find(InputModels{outputDirId}.labelPosition(:,1) == sliceNumber);
                            currentPosition = InputModels{outputDirId}.labelPosition(labelIndices,:);
                            currentPosition(:,1) = sliceIndex;
                            labelPosition = [labelPosition; currentPosition]; %#ok<AGROW>
                            labelText     = [labelText; InputModels{outputDirId}.labelText(labelIndices,:)]; %#ok<AGROW>
                            labelValue    = [labelValue; InputModels{outputDirId}.labelValue(labelIndices,:)]; %#ok<AGROW>
                        end
                    end
                    indexShift = indexShift + numel(outputIndices);

                    dateTag       = char(datetime('now', 'format', 'yyMMdd'));
                    modelFilename = fullfile(obj.Settings.inputDirName{dirId}, ...
                        sprintf('Labels_RestoreRand_%s.model', dateTag));

                    if isempty(labelPosition)
                        save(modelFilename, 'mibModel','modelVariable','modelMaterialColors','modelMaterialNames','modelType', '-mat', '-v7.3');
                    else
                        save(modelFilename, 'mibModel','modelVariable','modelMaterialColors','modelMaterialNames','modelType', ...
                            'labelPosition', 'labelText', 'labelValue', '-mat', '-v7.3');
                    end
                    clear mibModel;
                end
            end

            if includeMasks
                progressDlg.Value   = 0.8;
                progressDlg.Message = sprintf('Generating the mask files\nPlease wait...');

                for dirId = 1:numel(obj.Settings.outputDirName)
                    InputModels{dirId} = load(inputMaskFilenames{dirId}, '-mat'); %#ok<AGROW>
                end

                imageHeight = size(InputModels{1}.maskImg, 1);
                imageWidth  = size(InputModels{1}.maskImg, 2);

                indexShift = 0;
                for dirId = 1:numel(obj.Settings.inputDirName)
                    outputIndices = find(obj.Settings.inputIndices == dirId);
                    maskImg = zeros([imageHeight, imageWidth, numel(outputIndices)], ...
                        class(InputModels{1}.maskImg));

                    for sliceIndex = 1:numel(outputIndices)
                        outputDirId = 0;
                        sliceNumber = [];
                        while isempty(sliceNumber)
                            outputDirId = outputDirId + 1;
                            sliceNumber = find(obj.Settings.OutputIndicesSorted{outputDirId} == sliceIndex + indexShift);
                        end
                        maskImg(:,:,sliceIndex) = InputModels{outputDirId}.maskImg(:,:,sliceNumber);
                    end
                    indexShift = indexShift + numel(outputIndices);

                    dateTag      = char(datetime('now', 'format', 'yyMMdd'));
                    maskFilename = fullfile(obj.Settings.inputDirName{dirId}, ...
                        sprintf('Mask_RestoreRand_%s.mask', dateTag));
                    save(maskFilename, 'maskImg', '-mat', '-v7.3');
                end
            end

            if includeAnnotations
                progressDlg.Value   = 0.9;
                progressDlg.Message = sprintf('Generating the annotation files\nPlease wait...');

                for dirId = 1:numel(obj.Settings.outputDirName)
                    InputModels{dirId} = load(inputAnnotationsFilenames{dirId}, '-mat'); %#ok<AGROW>
                end

                for dirId = 1:numel(obj.Settings.inputDirName)
                    outputIndices = find(obj.Settings.inputIndices == dirId);
                    labelPosition = [];
                    labelText     = {};
                    labelValue    = [];

                    for sliceIndex = 1:numel(outputIndices)
                        randomDirId       = obj.Settings.outputIndices(outputIndices(sliceIndex));
                        randomSliceNumber = find(obj.Settings.OutputIndicesSorted{randomDirId} == outputIndices(sliceIndex));
                        annotationIndices = find(InputModels{randomDirId}.labelPosition(:,1) == randomSliceNumber);

                        if ~isempty(annotationIndices)
                            currentPosition = InputModels{randomDirId}.labelPosition(annotationIndices,:);
                            currentPosition(:,1) = sliceIndex;
                            labelPosition = [labelPosition; currentPosition]; %#ok<AGROW>
                            labelText     = [labelText; InputModels{randomDirId}.labelText(annotationIndices)]; %#ok<AGROW>
                            labelValue    = [labelValue; InputModels{randomDirId}.labelValue(annotationIndices)]; %#ok<AGROW>
                        end
                    end

                    dateTag            = char(datetime('now', 'format', 'yyMMdd'));
                    annotationFilename = fullfile(obj.Settings.inputDirName{dirId}, ...
                        sprintf('Annotations_RestoreRand_%s.ann', dateTag));
                    save(annotationFilename, 'labelPosition', 'labelText', 'labelValue', '-mat', '-v7.3');
                end
            end

            if includeMeasurements
                progressDlg.Value   = 0.9;
                progressDlg.Message = sprintf('Generating the measurement files\nPlease wait...');

                for dirId = 1:numel(obj.Settings.outputDirName)
                    InputModels{dirId} = load(inputMeasurementsFilenames{dirId}, '-mat'); %#ok<AGROW>
                    if ~isfield(InputModels{dirId}, 'Data')
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            sprintf('The measurement file does not contain a ''Data'' variable:\n%s\n\nPlease regenerate the measurement file.', ...
                            inputMeasurementsFilenames{dirId}), 'Invalid measurement file');
                        delete(progressDlg);
                        return;
                    end
                end

                for dirId = 1:numel(obj.Settings.inputDirName)
                    outputIndices = find(obj.Settings.inputIndices == dirId);
                    Data = [];

                    for sliceIndex = 1:numel(outputIndices)
                        randomDirId       = obj.Settings.outputIndices(outputIndices(sliceIndex));
                        randomSliceNumber = find(obj.Settings.OutputIndicesSorted{randomDirId} == outputIndices(sliceIndex));
                        if isempty(InputModels{randomDirId}.Data); continue; end
                        measureIndices    = find([InputModels{randomDirId}.Data.Z] == randomSliceNumber);

                        if ~isempty(measureIndices)
                            currentData = InputModels{randomDirId}.Data(measureIndices);
                            [currentData.Z] = deal(sliceIndex);
                            Data = [Data, currentData]; %#ok<AGROW>
                        end
                    end

                    dateTag              = char(datetime('now', 'format', 'yyMMdd'));
                    measurementsFilename = fullfile(obj.Settings.inputDirName{dirId}, ...
                        sprintf('Measure_RestoreRand_%s.measure', dateTag));

                    for measureIdx = 1:numel(Data)
                        Data(measureIdx).n = measureIdx;
                    end
                    save(measurementsFilename, 'Data', '-mat', '-v7.3');
                end
            end

            progressDlg.Value   = 1;
            progressDlg.Message = sprintf('Finishing\nPlease wait...');
            disp('MIB: the models from shuffled datasets were restored!');
            delete(progressDlg);
        end

    end
end
