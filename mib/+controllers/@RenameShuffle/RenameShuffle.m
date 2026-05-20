classdef RenameShuffle < handle
% RENAMESHUFFLE - Controller for randomizing and shuffling image datasets across directories.
%
% Copies images from one or more input directories into randomized output
% subdirectories, assigning shuffled filenames. Optionally copies associated
% label, mask, annotation, and measurement files. Saves a ``*.mibShuffle``
% project file that records the full mapping, enabling the reverse operation
% via :class:`controllers.RenameRestore`.
%
% Usage:
%   .. code-block:: matlab
%
%      obj.mibController.startController('controllers.RenameShuffle');

    properties
        mibModel        % handle to MibModel
        view            % handle to RenameShuffleGUI (set by core.ChildView)
        listener        % cell array of listener handles
        inputDirs = {}  % cell array of input directory paths
        outputDir = []  % output directory path
    end

    events
        CloseEvent      % fired when the window closes
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
            %   - **obj** — :class:`controllers.RenameShuffle` instance.
            %   - **evnt** — event data from the model.
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
        function obj = RenameShuffle(mibModel)
            % RENAMESHUFFLE - Construct the rename-and-shuffle controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = controllers.RenameShuffle(mibModel)
            %
            % Input Arguments:
            %   - **mibModel** — handle to :class:`models.MibModel`.

            obj.mibModel = mibModel;
            obj.outputDir = fullfile(obj.mibModel.currentDirectory, 'Shuffled');

            guiName = 'views.RenameShuffleGUI';
            obj.view = core.ChildView(obj, guiName);

            obj.view.handles.dirEdit.Value = obj.outputDir;
            obj.view.handles.randomSeed.Value = mod(round(posixtime(datetime('now'))), 1e6);

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
            % UPDATEWIDGETS - Refresh the input directories listbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()

            if ~isempty(obj.inputDirs)
                obj.view.handles.inputDirsList.Items = obj.inputDirs;
            else
                obj.view.handles.inputDirsList.Items = {};
            end
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire every widget to the central gui_Callbacks dispatcher.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            h  = obj.view.handles;
            cb = @(src,evt) obj.gui_Callbacks(src, evt);

            h.closeBtn.ButtonPushedFcn          = cb;
            h.selectDirBtn.ButtonPushedFcn       = cb;
            h.addDirBtn.ButtonPushedFcn          = cb;
            h.removeDirBtn.ButtonPushedFcn       = cb;
            h.randomBtn.ButtonPushedFcn          = cb;
            h.helpBtn.ButtonPushedFcn            = cb;

            h.dirEdit.ValueChangedFcn                  = cb;
            h.includeModelCheck.ValueChangedFcn        = cb;
            h.includeMaskCheck.ValueChangedFcn         = cb;
            h.includeAnnotationsCheck.ValueChangedFcn  = cb;
            h.includeMeasurementsCheck.ValueChangedFcn = cb;
        end

        % ---------------------------------------------------------------
        function addDirBtn_Callback(obj)
            % ADDDIRBT_CALLBACK - Add one or more input directories to the list.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addDirBtn_Callback()

            folderName = uigetfile_n_dir(obj.mibModel.currentDirectory, 'Select directory');
            if isequal(folderName, 0); return; end
            obj.inputDirs = [obj.inputDirs; folderName'];
            obj.updateWidgets();
            if ~isempty(obj.inputDirs)
                obj.view.handles.inputDirsList.Value = obj.inputDirs{end};
            end
        end

        % ---------------------------------------------------------------
        function removeDirBtn_Callback(obj)
            % REMOVEDIRBN_CALLBACK - Remove the selected input directory from the list.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.removeDirBtn_Callback()

            if isempty(obj.inputDirs); return; end
            selectedItem = obj.view.handles.inputDirsList.Value;
            obj.inputDirs(ismember(obj.inputDirs, selectedItem)) = [];
            obj.updateWidgets();
            if ~isempty(obj.inputDirs)
                obj.view.handles.inputDirsList.Value = obj.inputDirs{end};
            end
        end

        % ---------------------------------------------------------------
        function selectDirBtn_Callback(obj)
            % SELECTDIRBN_CALLBACK - Browse for the output directory.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.selectDirBtn_Callback()

            folderName = obj.outputDir;
            if exist(folderName, 'dir') == 0
                folderName = fileparts(folderName);
            end
            folderName = uigetdir(folderName, 'Select output directory');
            if isequal(folderName, 0); return; end

            obj.view.handles.dirEdit.Value = folderName;
            obj.outputDir = folderName;
        end

        % ---------------------------------------------------------------
        function dirEdit_Callback(obj)
            % DIREDIT_CALLBACK - Validate the typed output directory path.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.dirEdit_Callback()
            %
            % Prompts the user to create the directory when it does not exist.

            folderName = obj.view.handles.dirEdit.Value;
            if exist(folderName, 'dir') == 0
                answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('The target directory:\n%s\nis missing!\n\nCreate?', folderName), ...
                    'Create Directory', 'Create', 'Cancel', 'Cancel');
                if strcmp(answer, 'Cancel')
                    obj.view.handles.dirEdit.Value = obj.outputDir;
                    return;
                end
                mkdir(folderName);
            end
            obj.outputDir = folderName;
        end

        % ---------------------------------------------------------------
        function randomBtn_Callback(obj)
            % RANDOMBN_CALLBACK - Execute the rename-and-shuffle operation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.randomBtn_Callback()
            %
            % Collects images from all input directories, copies them with
            % shuffled names into randomized output subdirectories, optionally
            % copies labels/masks/annotations/measurements, optionally writes
            % an Excel mapping file, and saves a ``*.mibShuffle`` project file.

            h = obj.view.handles;

            outputDirectory    = obj.outputDir;
            filenameTemplate   = h.filenameTemplate.Value;
            outputDirNum       = h.outputDirNumEdit.Value;
            includeModels      = h.includeModelCheck.Value;
            includeMasks       = h.includeMaskCheck.Value;
            includeAnnotations = h.includeAnnotationsCheck.Value;
            includeMeasurements = h.includeMeasurementsCheck.Value;
            filenameExtension  = lower(h.filenameExtension.Value);

            Settings = struct;
            Settings.inputDirName            = h.inputDirsList.Items;
            Settings.InputImagesCombined     = [];
            Settings.InputImagesSliceNumber  = [];
            Settings.inputIndices            = [];
            Settings.outputDirName           = cell([outputDirNum, 1]);
            Settings.OutputImagesCombined    = {};
            Settings.outputIndices           = [];
            Settings.OutputIndicesSorted     = {};
            Settings.randomSeed              = h.randomSeed.Value;

            rng(Settings.randomSeed, 'twister');

            inputModelFilenames = [];
            InputModels = {};

            if isempty(Settings.inputDirName); return; end

            progressDlg = uiprogressdlg(obj.view.gui, 'Value', 0, ...
                'Message', sprintf('Checking input files\nPlease wait...'), ...
                'Title', 'Randomize images', ...
                'Cancelable', 'on');

            for dirId = 1:numel(Settings.inputDirName)
                fileList = dir(Settings.inputDirName{dirId});
                fnames   = {fileList.name};
                fileList = fnames(~[fileList.isdir]);
                excludeFiles = zeros([numel(fileList), 1]);

                for fileIdx = 1:numel(fileList)
                    [~,~,ext] = fileparts(fileList{fileIdx});
                    if ~strcmpi(ext, ['.' filenameExtension])
                        excludeFiles(fileIdx) = 1;
                    end
                    if includeModels && ismember(ext, {'.model'})
                        inputModelFilenames{dirId} = fullfile(Settings.inputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                        InputModels{dirId} = load(inputModelFilenames{dirId}, '-mat'); %#ok<AGROW>
                    end
                    if includeMasks && ismember(ext, {'.mask'})
                        inputMaskFilenames{dirId} = fullfile(Settings.inputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                    end
                    if includeAnnotations && ismember(ext, {'.ann'})
                        inputAnnotationsFilenames{dirId} = fullfile(Settings.inputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                    end
                    if includeMeasurements && ismember(ext, {'.measure'})
                        inputMeasurementsFilenames{dirId} = fullfile(Settings.inputDirName{dirId}, fileList{fileIdx}); %#ok<AGROW>
                    end
                end

                fileList(excludeFiles == 1) = [];
                fileList = fullfile(Settings.inputDirName{dirId}, fileList);
                Settings.InputImagesCombined    = [Settings.InputImagesCombined, fileList];
                Settings.InputImagesSliceNumber = [Settings.InputImagesSliceNumber, 1:numel(fileList)];
                Settings.inputIndices           = [Settings.inputIndices; zeros([numel(fileList),1]) + dirId];
            end
            Settings.outputIndices = randi(outputDirNum, [numel(Settings.InputImagesCombined), 1]);

            progressDlg.Value   = 0.1;
            progressDlg.Message = sprintf('Creating output directories\nPlease wait...');
            if progressDlg.CancelRequested; delete(progressDlg); return; end

            overwrite = 0;
            for dirId = 1:outputDirNum
                Settings.outputDirName(dirId) = {fullfile(outputDirectory, sprintf('Subset_%.3d', dirId))};
                if exist(Settings.outputDirName{dirId}, 'file') == 0
                    mkdir(Settings.outputDirName{dirId});
                else
                    if overwrite == 0
                        answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                            sprintf('The output directory already exists!\nAll files in the output directory will be removed!'), ...
                            'Overwrite directory', 'Remove files and continue', 'Cancel', 'Cancel');
                        if strcmp(answer, 'Cancel'); delete(progressDlg); return; end
                        overwrite = 1;
                    end
                    delete(fullfile(Settings.outputDirName{dirId}, '*.*'));
                end
            end

            progressDlg.Value   = 0.2;
            progressDlg.Message = sprintf('Copying the files\nPlease wait...');
            if progressDlg.CancelRequested; delete(progressDlg); return; end

            randomFilenameNumbers = randperm(numel(Settings.InputImagesCombined));
            noFiles = numel(Settings.InputImagesCombined);
            for imgId = 1:noFiles
                [~,~,ext] = fileparts(Settings.InputImagesCombined{imgId});
                Settings.OutputImagesCombined(imgId) = {fullfile( ...
                    Settings.outputDirName{Settings.outputIndices(imgId)}, ...
                    sprintf('%s_%.4d%s', filenameTemplate, randomFilenameNumbers(imgId), ext))};
                copyfile(Settings.InputImagesCombined{imgId}, Settings.OutputImagesCombined{imgId});
                progressDlg.Value = 0.2 + 0.25 * imgId / noFiles;
                if progressDlg.CancelRequested; delete(progressDlg); return; end
            end

            for dirId = 1:outputDirNum
                currentDirIndices = find(Settings.outputIndices == dirId);
                [~, sortedIndices] = sort(randomFilenameNumbers(currentDirIndices));
                currentDirIndices  = currentDirIndices(sortedIndices);
                Settings.OutputIndicesSorted{dirId} = currentDirIndices;
            end

            if includeModels
                progressDlg.Value   = 0.5;
                progressDlg.Message = sprintf('Generating the model files\nPlease wait...');

                imageHeight = size(InputModels{1}.(InputModels{1}.modelVariable), 1);
                imageWidth  = size(InputModels{1}.(InputModels{1}.modelVariable), 2);

                modelMaterialColors  = InputModels{1}.modelMaterialColors;
                modelMaterialNames   = InputModels{1}.modelMaterialNames;
                modelType            = InputModels{1}.modelType;

                for dirId = 1:outputDirNum
                    currentDirIndices = Settings.OutputIndicesSorted{dirId};
                    mibModel = zeros([imageHeight, imageWidth, numel(currentDirIndices)], ...
                        class(InputModels{1}.(InputModels{1}.modelVariable))); %#ok<PROP>
                    labelPosition = [];
                    labelText     = {};
                    labelValue    = [];

                    for sliceIndex = 1:numel(currentDirIndices)
                        inputDirIndex = Settings.inputIndices(currentDirIndices(sliceIndex));
                        modelVariable = InputModels{inputDirIndex}.modelVariable;
                        sliceNumber   = Settings.InputImagesSliceNumber(currentDirIndices(sliceIndex));
                        mibModel(:,:,sliceIndex) = InputModels{inputDirIndex}.(modelVariable)(:,:,sliceNumber); %#ok<PROP>

                        if isfield(InputModels{inputDirIndex}, 'labelPosition')
                            labelIndices = find(InputModels{inputDirIndex}.labelPosition(:,1) == sliceNumber);
                            currentPosition = InputModels{inputDirIndex}.labelPosition(labelIndices,:);
                            currentPosition(:,1) = sliceIndex;
                            labelPosition = [labelPosition; currentPosition]; %#ok<AGROW>
                            labelText     = [labelText; InputModels{inputDirIndex}.labelText(labelIndices,:)]; %#ok<AGROW>
                            labelValue    = [labelValue; InputModels{inputDirIndex}.labelValue(labelIndices,:)]; %#ok<AGROW>
                        end
                    end

                    modelFilename = fullfile(Settings.outputDirName{dirId}, ...
                        sprintf('Labels_%s_%.3d.model', filenameTemplate, dirId));
                    modelVariable = 'mibModel';
                    if isempty(labelPosition)
                        save(modelFilename, 'mibModel','modelVariable','modelMaterialColors','modelMaterialNames','modelType', '-mat', '-v7.3');
                    else
                        save(modelFilename, 'mibModel','modelVariable','modelMaterialColors','modelMaterialNames','modelType', ...
                            'labelPosition', 'labelText', 'labelValue', '-mat', '-v7.3');
                    end
                end
                clear mibModel;
            end
            if progressDlg.CancelRequested; delete(progressDlg); return; end

            if includeMasks
                progressDlg.Value   = 0.7;
                progressDlg.Message = sprintf('Generating the mask files\nPlease wait...');

                for dirId = 1:numel(Settings.inputDirName)
                    InputModels{dirId} = load(inputMaskFilenames{dirId}, '-mat'); %#ok<AGROW>
                end

                imageHeight = size(InputModels{1}.maskImg, 1);
                imageWidth  = size(InputModels{1}.maskImg, 2);

                for dirId = 1:outputDirNum
                    currentDirIndices = Settings.OutputIndicesSorted{dirId};
                    maskImg = zeros([imageHeight, imageWidth, numel(currentDirIndices)], ...
                        class(InputModels{1}.maskImg));

                    for sliceIndex = 1:numel(currentDirIndices)
                        inputDirIndex = Settings.inputIndices(currentDirIndices(sliceIndex));
                        sliceNumber   = Settings.InputImagesSliceNumber(currentDirIndices(sliceIndex));
                        maskImg(:,:,sliceIndex) = InputModels{inputDirIndex}.maskImg(:,:,sliceNumber);
                    end

                    maskFilename = fullfile(Settings.outputDirName{dirId}, ...
                        sprintf('%s_%.3d.mask', filenameTemplate, dirId));
                    save(maskFilename, 'maskImg', '-mat', '-v7.3');
                end
            end
            if progressDlg.CancelRequested; delete(progressDlg); return; end

            if includeAnnotations
                progressDlg.Value   = 0.8;
                progressDlg.Message = sprintf('Generating the annotation files\nPlease wait...');

                for dirId = 1:numel(Settings.inputDirName)
                    InputModels{dirId} = load(inputAnnotationsFilenames{dirId}, '-mat'); %#ok<AGROW>
                end

                for dirId = 1:outputDirNum
                    currentDirIndices = Settings.OutputIndicesSorted{dirId};
                    labelPosition = [];
                    labelText     = {};
                    labelValue    = [];

                    for sliceIndex = 1:numel(currentDirIndices)
                        inputDirIndex = Settings.inputIndices(currentDirIndices(sliceIndex));
                        sliceNumber   = Settings.InputImagesSliceNumber(currentDirIndices(sliceIndex));
                        annotationIndices = find(InputModels{inputDirIndex}.labelPosition(:,1) == sliceNumber);

                        if ~isempty(annotationIndices)
                            currentPosition = InputModels{inputDirIndex}.labelPosition(annotationIndices,:,:,:);
                            currentPosition(:,1) = sliceIndex;
                            labelPosition = [labelPosition; currentPosition]; %#ok<AGROW>
                            labelText     = [labelText; InputModels{inputDirIndex}.labelText(annotationIndices)]; %#ok<AGROW>
                            labelValue    = [labelValue; InputModels{inputDirIndex}.labelValue(annotationIndices)]; %#ok<AGROW>
                        end
                    end

                    annotationFilename = fullfile(Settings.outputDirName{dirId}, ...
                        sprintf('%s_%.3d.ann', filenameTemplate, dirId));
                    save(annotationFilename, 'labelPosition','labelText','labelValue', '-mat', '-v7.3');
                end
            end
            if progressDlg.CancelRequested; delete(progressDlg); return; end

            if includeMeasurements
                progressDlg.Value   = 0.9;
                progressDlg.Message = sprintf('Generating the measurements files\nPlease wait...');

                for dirId = 1:numel(Settings.inputDirName)
                    InputModels{dirId} = load(inputMeasurementsFilenames{dirId}, '-mat'); %#ok<AGROW>
                end

                for dirId = 1:outputDirNum
                    currentDirIndices = Settings.OutputIndicesSorted{dirId};
                    Data = [];

                    for sliceIndex = 1:numel(currentDirIndices)
                        inputDirIndex = Settings.inputIndices(currentDirIndices(sliceIndex));
                        sliceNumber   = Settings.InputImagesSliceNumber(currentDirIndices(sliceIndex));
                        measureIndices = find([InputModels{inputDirIndex}.Data.Z] == sliceNumber);

                        if ~isempty(measureIndices)
                            currentData = InputModels{inputDirIndex}.Data(measureIndices);
                            [currentData.Z] = deal(sliceIndex);
                            Data = [Data, currentData]; %#ok<AGROW>
                        end
                    end

                    if ~isempty(Data)
                        for measureIdx = 1:numel(Data)
                            Data(measureIdx).n = measureIdx;
                        end
                        measurementsFilename = fullfile(Settings.outputDirName{dirId}, ...
                            sprintf('%s_%.3d.measure', filenameTemplate, dirId));
                        save(measurementsFilename, 'Data', '-mat', '-v7.3');
                    end
                end
            end
            if progressDlg.CancelRequested; delete(progressDlg); return; end

            if h.generateExcelCheck.Value
                progressDlg.Value   = 0.95;
                progressDlg.Message = sprintf('Generating Excel file\nPlease wait...');

                filenameOut = fullfile(outputDirectory, sprintf('%s.xls', filenameTemplate));
                if exist(filenameOut, 'file') == 2; delete(filenameOut); end
                warning('off', 'MATLAB:xlswrite:AddSheet');

                spreadsheet = {'Rename and Shuffle parameters'};
                spreadsheet(1,5) = {sprintf('Random seed: %d', Settings.randomSeed)};
                spreadsheet(2,1) = {'Note! MIB opens images sorted in alphabetical order'};
                spreadsheet(4,1) = {'Slice No.'}; spreadsheet(4,2) = {'Original filename'};
                spreadsheet(4,3) = {'->'}; spreadsheet(4,4) = {'Slice No.'};
                spreadsheet(4,5) = {'Renamed and Shuffled filename'};

                noFiles = numel(Settings.InputImagesCombined);
                spreadsheet(6:6+noFiles-1, 1) = num2cell(Settings.InputImagesSliceNumber');
                spreadsheet(6:6+noFiles-1, 2) = Settings.InputImagesCombined';
                spreadsheet(6:6+noFiles-1, 3) = repmat({'->'}, [noFiles, 1]);

                sliceNumbers = zeros([noFiles, 1]);
                for dirId = 1:numel(Settings.OutputIndicesSorted)
                    [~, sortedInd] = sort(Settings.OutputIndicesSorted{dirId});
                    sliceNumbers(Settings.outputIndices == dirId) = sortedInd;
                end
                spreadsheet(6:6+noFiles-1, 4) = num2cell(sliceNumbers);
                spreadsheet(6:6+noFiles-1, 5) = Settings.OutputImagesCombined';

                rowOffset = 6 + noFiles + 2;
                spreadsheet(rowOffset,1) = {'Slice No.'}; spreadsheet(rowOffset,2) = {'Renamed and Shuffled filename'};
                spreadsheet(rowOffset,3) = {'->'}; spreadsheet(rowOffset,4) = {'Slice No.'};
                spreadsheet(rowOffset,5) = {'Original filename'};

                rowOffset = rowOffset + 2;
                shiftRow = 0;
                for dirId = 1:numel(Settings.OutputIndicesSorted)
                    noSlices = numel(Settings.OutputIndicesSorted{dirId});
                    sliceVec = 1:noSlices;
                    spreadsheet(rowOffset+shiftRow:rowOffset+shiftRow+noSlices-1, 1) = num2cell(sliceVec');
                    shiftRow = shiftRow + noSlices;
                end
                allSortedIndices = cell2mat(Settings.OutputIndicesSorted');
                spreadsheet(rowOffset:rowOffset+noFiles-1, 2) = Settings.OutputImagesCombined(allSortedIndices)';
                spreadsheet(rowOffset:rowOffset+noFiles-1, 3) = repmat({'->'}, [noFiles, 1]);
                spreadsheet(rowOffset:rowOffset+noFiles-1, 4) = num2cell(Settings.InputImagesSliceNumber(allSortedIndices)');
                spreadsheet(rowOffset:rowOffset+noFiles-1, 5) = Settings.InputImagesCombined(allSortedIndices)';

                xlswrite2(filenameOut, spreadsheet, 'Results', 'A1');
                fprintf('Rename and shuffle: exporting parameters in the Excel format: done\n%s\n', filenameOut);
            end

            progressDlg.Value   = 0.99;
            progressDlg.Message = sprintf('Finishing\nPlease wait...');

            projectFilename = fullfile(outputDirectory, sprintf('%s.mibShuffle', filenameTemplate));
            save(projectFilename, 'Settings');

            progressDlg.Value = 1;
            disp('MIB: the datasets were shuffled!');
            delete(progressDlg);
        end

    end
end
