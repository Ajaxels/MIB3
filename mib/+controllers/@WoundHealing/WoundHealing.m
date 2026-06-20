% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% Part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 25.04.2023

classdef WoundHealing < handle
% WOUNDHEALING - Controller for the Wound Healing Assay and Stitching dialog.
%
% Provides grid stitching of zero-overlap image collections and wound
% healing assay analysis using the cellMigration algorithm
% (Reyes-Aldasoro et al., Electronics Letters, 2008).
%
% .. note::
%    The wound healing analysis requires ``cellMigration.m`` to be on the
%    MATLAB path.  It is available in the MIB2 distribution under
%    ``Tools/CellMigration/``.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.WoundHealing');
%
% Launch in batch mode (runs Stitch)::
%
%   BatchOpt.Extension = 'tif';
%   BatchOpt.NoRows    = {3, [1 Inf], 'on'};
%   BatchOpt.NoColumns = {3, [1 Inf], 'on'};
%   BatchOpt.SelectedDirectories = {'C:\dir1', 'C:\dir2', ...};
%   obj.mibController.startController('controllers.WoundHealing', [], BatchOpt);
%
% Trigger return of possible options::
%
%   obj.mibController.startController('controllers.WoundHealing', [], NaN);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.WoundHealingGUI)
        mibGUI
        % handle to main MIB figure (used as parent for dialogs)
        listener
        % cell array of listener handles
        BatchOpt
        % structure compatible with batch processing; field names match widget Tags
        %
        % - ``.Extension``           — [edit field] filename extension for input images
        % - ``.NoRows``              — [spinner] number of rows in the stitching grid
        % - ``.NoColumns``           — [spinner] number of columns in the stitching grid
        % - ``.SelectedDirectories`` — cell array of input directory paths
        % - ``.OutputDirectory``     — output directory path for stitched images
        % - ``.ConvertToGrayscale``  — [checkbox] convert stitched image to grayscale
        % - ``.PixelSize``           — [spinner] pixel size (µm) for wound healing analysis
        % - ``.TimeStep``            — [spinner] time step (h) between images
        % - ``.DownsampleImages``    — [spinner] % to downsample wound result images
        % - ``.ShowInteractivePlot`` — [checkbox] show live plot during analysis
        % - ``.showWaitbar``         — [checkbox] show progress bar
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static listener guard; safe even when view is invalid.
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
        % -----------------------------------------------------------
        function obj = WoundHealing(mibModel, varargin)
            % WOUNDHEALING - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = WoundHealing(mibModel)
            %       obj = WoundHealing(mibModel, [], BatchOpt)
            %       obj = WoundHealing(mibModel, [], NaN)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            %% BatchOpt defaults
            obj.BatchOpt.Extension = 'tif';
            obj.BatchOpt.NoRows = {3, [1 Inf], 'on'};
            obj.BatchOpt.NoColumns = {3, [1 Inf], 'on'};
            obj.BatchOpt.SelectedDirectories = {};
            obj.BatchOpt.OutputDirectory = obj.mibModel.currentDirectory;
            obj.BatchOpt.ConvertToGrayscale = true;
            obj.BatchOpt.PixelSize = {1, [0 Inf], 'off'};
            obj.BatchOpt.TimeStep = {1, [0 Inf], 'off'};
            obj.BatchOpt.DownsampleImages = {50, [0 100], 'on'};
            obj.BatchOpt.ShowInteractivePlot = true;
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Tools';
            obj.BatchOpt.mibBatchActionName  = 'Wound Healing Assay';
            obj.BatchOpt.mibBatchTooltip.Extension           = 'Filename extension for input images (e.g. tif, jpg)';
            obj.BatchOpt.mibBatchTooltip.NoRows              = 'Number of rows in the stitching grid';
            obj.BatchOpt.mibBatchTooltip.NoColumns           = 'Number of columns in the stitching grid';
            obj.BatchOpt.mibBatchTooltip.SelectedDirectories = 'Cell array with input directory paths (one per grid tile)';
            obj.BatchOpt.mibBatchTooltip.OutputDirectory     = 'Output directory path for stitched images';
            obj.BatchOpt.mibBatchTooltip.ConvertToGrayscale  = 'Convert stitched images to grayscale';
            obj.BatchOpt.mibBatchTooltip.PixelSize           = 'Pixel size (µm) for wound healing analysis';
            obj.BatchOpt.mibBatchTooltip.TimeStep            = 'Time step (h) between images for wound healing analysis';
            obj.BatchOpt.mibBatchTooltip.DownsampleImages    = '% to downsample result images showing the detected wound';
            obj.BatchOpt.mibBatchTooltip.ShowInteractivePlot = 'Display interactive plot with results during analysis';
            obj.BatchOpt.mibBatchTooltip.showWaitbar         = 'Show or not the progress bar';

            %% Batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if ~isstruct(BatchOptIn)
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 2nd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.stitchButton_Callback();
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.WoundHealingGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.PixelSize.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.PixelSize.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.updateWidgets();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.addCallbacks();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            obj.view.handles.Extension.ValueChangedFcn           = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.NoRows.ValueChangedFcn              = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.NoColumns.ValueChangedFcn           = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.ConvertToGrayscale.ValueChangedFcn  = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.PixelSize.ValueChangedFcn           = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.TimeStep.ValueChangedFcn            = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.DownsampleImages.ValueChangedFcn    = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.ShowInteractivePlot.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.OutputDir.ValueChangedFcn           = @(h,e) obj.updateOutputPath(e.Value);

            obj.view.handles.SelectDirectories.ButtonPushedFcn   = @(~,~) obj.selectDirectoriesButton_Callback();
            obj.view.handles.OutputButton.ButtonPushedFcn        = @(~,~) obj.selectOutputDirectoryButton_Callback();
            obj.view.handles.Stitch.ButtonPushedFcn              = @(~,~) obj.stitchButton_Callback();
            obj.view.handles.WoundHealing.ButtonPushedFcn        = @(~,~) obj.woundHealingButton_Callback();
            obj.view.handles.Help.ButtonPushedFcn                = @(~,~) obj.helpButton_Callback();
            obj.view.handles.Close.ButtonPushedFcn               = @(~,~) obj.closeWindow();
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Destroy view and fire CloseEvent.
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            % sync non-standard fields that updateGUIFromBatchOpt_Shared cannot handle
            if ~isempty(obj.BatchOpt.SelectedDirectories)
                obj.view.handles.SelectedDirectories.Value = obj.BatchOpt.SelectedDirectories;
            end
            obj.view.handles.OutputDir.Value = obj.BatchOpt.OutputDirectory;
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        % -----------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to mibBatchController via SyncBatch event.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open plugin documentation in browser.
            
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'tools', 'tools-wound.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/tools/tools-wound.html', '-browser');
            end
        end

        % -----------------------------------------------------------
        function selectDirectoriesButton_Callback(obj)
            % SELECTDIRECTORIESBUTTON_CALLBACK - Select input directories via multi-select dialog.
            %
            % Uses ``uigetfile_n_dir`` to pick one or more directories in a single
            % Java-based dialog.  The selection replaces the current list.
            startPath = obj.mibModel.currentDirectory;
            if ~isempty(obj.BatchOpt.SelectedDirectories)
                startPath = obj.BatchOpt.SelectedDirectories{1};
            end

            selectedDirs = uigetfile_n_dir(startPath, 'Select directories');
            if isempty(selectedDirs); return; end

            obj.BatchOpt.SelectedDirectories = selectedDirs;
            obj.view.handles.SelectedDirectories.Value = selectedDirs;
        end

        % -----------------------------------------------------------
        function selectOutputDirectoryButton_Callback(obj)
            % SELECTOUTPUTDIRECTORYBUTTON_CALLBACK - Choose output directory via dialog.
            selectedPath = uigetdir(obj.BatchOpt.OutputDirectory, 'Select output directory');
            if selectedPath == 0; return; end
            obj.BatchOpt.OutputDirectory = selectedPath;
            obj.view.handles.OutputDir.Value = selectedPath;
        end

        % -----------------------------------------------------------
        function updateOutputPath(obj, value)
            % UPDATEOUTPUTPATH - Validate and store output directory from the edit field.
            if ~isfolder(value)
                mkdir(value);
                if ~isfolder(value)
                    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                        sprintf('Cannot create output directory:\n%s', value), 'Error');
                    return;
                end
            end
            obj.BatchOpt.OutputDirectory = value;
        end

        % -----------------------------------------------------------
        function stitchButton_Callback(obj)
            % STITCHBUTTON_CALLBACK - Stitch a grid of images from selected directories.
            %
            % Each selected directory must contain images corresponding to one tile
            % position.  Directories are ordered left-to-right, top-to-bottom.
            % All directories must contain the same number of files (time points).
            %
            % Saves stitched images and a time-stamp log to ``OutputDirectory``.

            if obj.BatchOpt.showWaitbar
                progressBar = uiprogressdlg(obj.mibModel.getProgressBarParent(), 'Value', 0, 'Cancelable', 'on', ...
                    'Message', 'Please wait...', 'Title', 'Stitching');
            end

            numberOfColumns = obj.BatchOpt.NoColumns{1};
            numberOfRows    = obj.BatchOpt.NoRows{1};
            expectedTiles   = numberOfRows * numberOfColumns;

            if numel(obj.BatchOpt.SelectedDirectories) < expectedTiles
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
                    {sprintf('Need %d directories for a %d×%d grid.\n%d currently selected.', ...
                        expectedTiles, numberOfRows, numberOfColumns, ...
                        numel(obj.BatchOpt.SelectedDirectories))}, ...
                    'Not enough directories', dlgOpt);
                return;
            end

            % gather file lists for all tile directories
            fileLists = cell([expectedTiles, 1]);
            for dirIndex = 1:expectedTiles
                fileLists{dirIndex} = dir(fullfile(obj.BatchOpt.SelectedDirectories{dirIndex}, ...
                    ['*.' obj.BatchOpt.Extension]));
            end
            numberOfFiles = numel(fileLists{1});
            if numberOfFiles == 0
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    sprintf('No *.%s files found in:\n%s', obj.BatchOpt.Extension, ...
                        obj.BatchOpt.SelectedDirectories{1}), 'No files found');
                return;
            end

            % read one image to obtain per-tile dimensions and class
            firstFilename = fullfile(fileLists{1}(1).folder, fileLists{1}(1).name);
            sampleImage = imread(firstFilename);
            imageHeight = size(sampleImage, 1);
            imageWidth  = size(sampleImage, 2);
            colorCount  = size(sampleImage, 3);
            imageClass  = class(sampleImage);

            % prompt for JPG parameters once before the loop
            jpgQuality = 90;
            if strcmpi(obj.BatchOpt.Extension, 'jpg')
                answer = utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', ...
                    {'Quality (0-100):'}, ...
                    {struct('Spinner', true, 'Value', 90, 'Limits', [0 100], 'Step', 1, 'Round', true)}, ...
                    'JPG Parameters');
                if isempty(answer)
                    if obj.BatchOpt.showWaitbar; delete(progressBar); end
                    return;
                end
                jpgQuality = answer{1};
            end

            timeVector = cell([numberOfFiles, 1]);

            for fileIndex = 1:numberOfFiles
                if obj.BatchOpt.showWaitbar
                    if progressBar.CancelRequested; delete(progressBar); return; end
                    progressBar.Value   = (fileIndex - 1) / numberOfFiles;
                    progressBar.Message = sprintf('Stitching file %d of %d', fileIndex, numberOfFiles);
                end

                stitchedImage = zeros([imageHeight * numberOfColumns, imageWidth * numberOfRows, colorCount], imageClass);
                rowOffset = 1;
                tileIndex = 1;

                for rowId = 1:numberOfRows
                    colOffset = 1;
                    if rowId == 1
                        % record file modification date as time stamp
                        firstInfo = imfinfo(fullfile(fileLists{1}(fileIndex).folder, fileLists{1}(fileIndex).name));
                        timeVector{fileIndex} = firstInfo.FileModDate;
                    end
                    for colId = 1:numberOfColumns
                        tileFilename = fullfile(fileLists{tileIndex}(fileIndex).folder, ...
                            fileLists{tileIndex}(fileIndex).name);
                        tileImage = imread(tileFilename);
                        stitchedImage(rowOffset:rowOffset+imageHeight-1, colOffset:colOffset+imageWidth-1, :) = tileImage;
                        colOffset = colOffset + imageWidth - 1;
                        tileIndex = tileIndex + 1;
                    end
                    rowOffset = rowOffset + imageHeight - 1;
                end

                if obj.BatchOpt.ConvertToGrayscale
                    stitchedImage = cast(mean(stitchedImage, 3), imageClass);
                end

                [~, outputBasename, outputExtension] = fileparts(fileLists{1}(fileIndex).name);
                outputFilename = fullfile(obj.BatchOpt.OutputDirectory, ...
                    [outputBasename, '_stitched', outputExtension]);

                switch lower(obj.BatchOpt.Extension)
                    case 'jpg'
                        imwrite(stitchedImage, outputFilename, 'Quality', jpgQuality);
                    otherwise
                        imwrite(stitchedImage, outputFilename);
                end
            end

            % write time-stamp log
            [~, timestampBasename] = fileparts(fileLists{1}(1).name);
            timestampFilename = fullfile(obj.BatchOpt.OutputDirectory, ...
                [timestampBasename, '_TimeStamps.txt']);
            fid = fopen(timestampFilename, 'w');
            fprintf(fid, 'Time stamps from the original files in Greenwich Mean Time (GMT)\n');
            for i = 1:numel(timeVector)
                fprintf(fid, '%s\n', timeVector{i});
            end
            fclose(fid);

            if obj.BatchOpt.showWaitbar; delete(progressBar); end
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------
        function woundHealingButton_Callback(obj)
            % WOUNDHEALINGBUTTON_CALLBACK - Run wound healing assay on selected directories.
            %
            % Detects the wound width in each image using ``cellMigration`` and
            % exports results as ``.mat`` and ``.xlsx`` files.  Annotated images are
            % saved under a ``snapshots/`` subfolder of each input directory.
            %
            % Requires ``cellMigration.m`` on the MATLAB path.
            % Reference: C.C. Reyes-Aldasoro et al., Electronics Letters, 44(13), 2008.

            if obj.BatchOpt.showWaitbar
                progressBar = uiprogressdlg(obj.mibModel.getProgressBarParent(), 'Value', 0, ...
                    'Message', 'Please wait...', 'Title', 'Wound healing assay');
            end

            if numel(obj.BatchOpt.SelectedDirectories) < 1
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                return;
            end

            pixelSize = obj.BatchOpt.PixelSize{1};
            timeStep  = obj.BatchOpt.TimeStep{1};

            for dirIndex = 1:numel(obj.BatchOpt.SelectedDirectories)
                inputPath = obj.BatchOpt.SelectedDirectories{dirIndex};

                if obj.BatchOpt.showWaitbar
                    progressBar.Value   = 0;
                    progressBar.Message = sprintf('Directory %d/%d\n%s\nPlease wait...', ...
                        dirIndex, numel(obj.BatchOpt.SelectedDirectories), inputPath);
                end

                fileList = dir(fullfile(inputPath, ['*.' obj.BatchOpt.Extension]));

                results.minVec = zeros([numel(fileList), 1]);
                results.maxVec = zeros([numel(fileList), 1]);
                results.avVec  = zeros([numel(fileList), 1]);
                timeVector     = 0:timeStep:timeStep * (numel(fileList) - 1);

                for fileIndex = 1:numel(fileList)
                    filename = fullfile(fileList(fileIndex).folder, fileList(fileIndex).name);
                    [migrationStats, resultImage] = cellMigration(filename);
                    if isempty(migrationStats) || ~isfield(migrationStats, 'minimumDist'); continue; end

                    results.minVec(fileIndex) = migrationStats.minimumDist * pixelSize;
                    results.maxVec(fileIndex) = migrationStats.maxDist     * pixelSize;
                    results.avVec(fileIndex)  = migrationStats.avDist      * pixelSize;

                    % save annotated result image
                    snapshotDir = fullfile(fileList(fileIndex).folder, 'snapshots');
                    if fileIndex == 1 && ~isfolder(snapshotDir)
                        mkdir(snapshotDir);
                    end
                    outputFilename = fullfile(snapshotDir, ['Wound_' fileList(fileIndex).name]);
                    if obj.BatchOpt.DownsampleImages{1} ~= 100
                        resultImage = imresize(resultImage, obj.BatchOpt.DownsampleImages{1} / 100);
                    end
                    imwrite(resultImage, outputFilename);

                    if obj.BatchOpt.ShowInteractivePlot
                        figure(2);
                        plot(timeVector, results.minVec, timeVector, results.maxVec, timeVector, results.avVec);
                        title(sprintf('Directory %d/%d: %s', dirIndex, ...
                            numel(obj.BatchOpt.SelectedDirectories), inputPath), 'Interpreter', 'none');
                        yMin = min(results.minVec(results.minVec > 0));
                        yMax = max(results.maxVec);
                        if ~isempty(yMin) && ~isempty(yMax) && yMax > yMin
                            set(gca, 'ylim', [yMin, yMax]);
                        end
                        legend('MinVector', 'MaxVector', 'AverageVector');
                        xlabel('Time, h');
                        ylabel('Wound width, \mum');
                        grid;
                    end

                    if obj.BatchOpt.showWaitbar
                        progressBar.Value = fileIndex / numel(fileList);
                    end
                end

                % final summary plot for this directory
                figure(2);
                plot(timeVector, results.minVec, timeVector, results.maxVec, timeVector, results.avVec);
                title(sprintf('Directory %d/%d: %s', dirIndex, ...
                    numel(obj.BatchOpt.SelectedDirectories), inputPath), 'Interpreter', 'none');
                legend('MinVector', 'MaxVector', 'AverageVector');
                yMin = min(results.minVec(results.minVec > 0));
                yMax = max(results.maxVec);
                if ~isempty(yMin) && ~isempty(yMax) && yMax > yMin
                    set(gca, 'ylim', [yMin, yMax]);
                end
                xlabel('Time, h');
                ylabel('Wound width, \mum');
                grid;

                % save results as .mat
                [~, pathBasename] = fileparts(inputPath);
                matFilename = fullfile(inputPath, sprintf('WoundAssayResults_%s.mat', pathBasename));
                save(matFilename, 'results');

                % export to Excel
                excelData = cell(3 + numel(fileList), 6);
                excelData{1, 1} = 'Wound healing assay results';
                excelData{2, 1} = 'Directory name:';  excelData{2, 2} = inputPath;
                excelData{2, 3} = 'PixelSize:';       excelData{2, 4} = pixelSize;
                excelData{2, 5} = 'TimeStep:';        excelData{2, 6} = timeStep;
                excelData{3, 1} = 'Image index';
                excelData{3, 2} = 'Image name';
                excelData{3, 3} = 'Time point';
                excelData{3, 4} = 'Min';
                excelData{3, 5} = 'Average';
                excelData{3, 6} = 'Max';
                for pointIndex = 1:numel(fileList)
                    row = 3 + pointIndex;
                    excelData{row, 1} = pointIndex;
                    excelData{row, 2} = fileList(pointIndex).name;
                    excelData{row, 3} = timeVector(pointIndex);
                    excelData{row, 4} = results.minVec(pointIndex);
                    excelData{row, 5} = results.avVec(pointIndex);
                    excelData{row, 6} = results.maxVec(pointIndex);
                end
                xlsFilename = fullfile(inputPath, sprintf('WoundAssayResults_%s.xlsx', pathBasename));
                if isfile(xlsFilename); delete(xlsFilename); end
                writecell(excelData, xlsFilename, 'Sheet', 'WoundAssay');
            end

            if obj.BatchOpt.showWaitbar; delete(progressBar); end
        end

    end
end
