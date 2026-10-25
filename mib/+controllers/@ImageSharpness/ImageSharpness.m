classdef ImageSharpness < handle
% IMAGESHARPNESS - Controller for the Sharpness and noise dialog: resolution, astigmatism, noise and focus scores of image regions.
%
% Measures the resolution of selected image regions with two independent
% Fourier methods and reports noise and relative focus scores:
%
%   - FFT cutoff resolution, astigmatism (direction-resolved power
%     spectrum), noise standard deviation and signal-to-noise ratio, see
%     :func:`controllers.ImageSharpness.computeFftResolution`;
%   - decorrelation analysis resolution (Descloux et al. 2019), see
%     :func:`controllers.ImageSharpness.computeDecorrelationResolution`;
%   - normalised gradient energy and Laplacian variance, see
%     :func:`controllers.ImageSharpness.computeSharpnessScores`.
%
% Regions are the shown area, the whole slice, every ROI, every connected
% object of the selection or mask layer, or a rectangle drawn on the image. Each
% analysed region adds one row to the results table; rows accumulate over
% runs and datasets so different images can be compared, and survive closing
% the dialog for the rest of the MIB session
% (``mibModel.sessionSettings.ImageSharpness``).
%
% Launch as GUI tool (the controller handle is needed to draw rectangles on
% the image)::
%
%   obj.mibController.startController('controllers.ImageSharpness', obj.mibController);
%
% Analyse an image region from code, without the dialog::
%
%   result = controllers.ImageSharpness.analyseRegion(img, [5 5]);
%

% Updates
%

    properties
        mibModel
        % handle to MibModel
        mibController
        % handle to MibController, used to draw rectangles on the image axes
        view
        % handle to the view (views.ImageSharpnessGUI)
        mibGUI
        % handle to main MIB figure (used as parent for dialogs)
        listener
        % cell array of listener handles
        BatchOpt
        % structure with the dialog settings; field names match widget Tags
        results
        % struct array, one element per row of the results table, see calculate
        drawnRectangle
        % struct of the last drawn rectangle: .position [x1 y1 x2 y2] in data
        % pixels of the shown orientation, .orientation, .id; empty when none
        plotRowIndex
        % index into results of the row shown in the plot tabs; empty when none
        drawnAxes
        % cell array of the plot axes already drawn for plotRowIndex, see updatePlots
        selectedRows
        % indices of the results table rows the context menu acts on
        exportChoices
        % logical vector, the outputs ticked in the last export dialog, see exportResults
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

        % signatures of the static methods in separate files
        result = analyseRegion(regionImage, pixelSize, options)
        periodicImage = preprocessRegion(regionImage)
        result = computeFftResolution(periodicImage, pixelSize, options)
        result = computeDecorrelationResolution(periodicImage, pixelSize, options)
        result = computeSharpnessScores(regionImage, smoothingSigma)
        drawResultPlot(axesHandle, row, plotName)
        merged = mergeResults(firstResults, secondResults)
    end

    methods
        % -----------------------------------------------------------
        function obj = ImageSharpness(mibModel, varargin)
            % IMAGESHARPNESS - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = ImageSharpness(mibModel)
            %      obj = ImageSharpness(mibModel, mibController)
            %
            % Input Arguments:
            %   - **mibModel** - [models.MibModel] handle to the model
            %   - **mibController** *(optional)* - [controllers.MibController]
            %     needed to draw a rectangle on the image; without it the
            %     ``Drawn rectangle`` region is unavailable
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;
            if nargin > 1 && ~isempty(varargin{1}); obj.mibController = varargin{1}; end

            obj.BatchOpt.RegionSource{1} = 'Shown area';
            obj.BatchOpt.RegionSource{2} = {'Drawn rectangle', 'Mask layer', 'ROIs', 'Selection layer', 'Shown area', 'Whole slice'};
            obj.BatchOpt.ColorChannel = {'Ch 1', {'Ch 1'}};
            obj.BatchOpt.UseFft = true;
            obj.BatchOpt.UseDecorrelation = true;
            obj.BatchOpt.UseSharpness = true;
            obj.BatchOpt.SnrThreshold = {1, [0.05 100], 'off'};
            obj.BatchOpt.NumberOfSectors = {36, [8 72], 'on'};
            obj.BatchOpt.SuppressScanLines = true;
            obj.BatchOpt.SlowDetector = false;
            obj.BatchOpt.SmoothingSigma = {1, [0 10], 'off'};
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            obj.BatchOpt.mibBatchTooltip.RegionSource = 'Area to analyse: pick a region with isotropic texture; each ROI and each object of the selection or mask gives its own result';
            obj.BatchOpt.mibBatchTooltip.ColorChannel = 'Color channel to analyse';
            obj.BatchOpt.mibBatchTooltip.UseFft = 'Resolution where the power spectrum meets the noise floor, per direction; gives the astigmatism';
            obj.BatchOpt.mibBatchTooltip.UseDecorrelation = 'Single-image resolution estimate by decorrelation analysis; robust to noise, no direction';
            obj.BatchOpt.mibBatchTooltip.UseSharpness = 'Unitless focus scores; compare only images of the same specimen';
            obj.BatchOpt.mibBatchTooltip.SnrThreshold = 'Signal-to-noise power ratio that defines the FFT cutoff; lower values give finer resolution values';
            obj.BatchOpt.mibBatchTooltip.NumberOfSectors = 'Number of directions over 0-180 degrees for the astigmatism analysis';
            obj.BatchOpt.mibBatchTooltip.SuppressScanLines = 'Ignore the horizontal and vertical FFT axes, where scan-line noise of scanned images appears';
            obj.BatchOpt.mibBatchTooltip.SlowDetector = 'Tick when the detector is slow for the scan speed and smears the noise along the scan lines; the table notes such images';
            obj.BatchOpt.mibBatchTooltip.SmoothingSigma ='Gaussian smoothing in pixels before the focus scores; reduces the effect of noise';

            % restore the settings and results of the previous use in this session
            if isfield(obj.mibModel.sessionSettings, 'ImageSharpness')
                stored = obj.mibModel.sessionSettings.ImageSharpness;
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, stored.BatchOpt);
                obj.results = stored.results;
                if isfield(stored, 'exportChoices'); obj.exportChoices = stored.exportChoices; end
            end

            obj.view = core.ChildView(obj, 'views.ImageSharpnessGUI');
            utils.applyThemeColors(obj.view.gui);
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');
            utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);

            obj.updateWidgets();
            obj.addCallbacks();
            obj.updateResultsTable();
            % plots of the last row measured on the active dataset, if any
            activeRows = obj.activeDatasetRows();
            if ~isempty(activeRows); obj.updatePlots(activeRows(end)); end
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire widget callbacks and tooltips after view creation.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
            batchWidgets = {'RegionSource', 'ColorChannel', 'UseFft', 'UseDecorrelation', 'UseSharpness', ...
                'SnrThreshold', 'NumberOfSectors', 'SuppressScanLines', 'SlowDetector', 'SmoothingSigma'};
            for widgetId = 1:numel(batchWidgets)
                widgetName = batchWidgets{widgetId};
                obj.view.handles.(widgetName).ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
                obj.view.handles.(widgetName).Tooltip = obj.BatchOpt.mibBatchTooltip.(widgetName);
            end
            obj.view.handles.calculateButton.ButtonPushedFcn = @(~,~) obj.runButtonPushed();
            obj.view.handles.clearButton.ButtonPushedFcn     = @(~,~) obj.clearResults();
            obj.view.handles.saveButton.ButtonPushedFcn      = @(~,~) obj.saveResults();
            obj.view.handles.loadButton.ButtonPushedFcn      = @(~,~) obj.loadResults();
            obj.view.handles.saveButton.Tooltip = 'Save the results table to a .mibSharp file, to open it again later with Load';
            obj.view.handles.loadButton.Tooltip = 'Open a .mibSharp file and add its measurements to the table, or replace them';
            obj.view.handles.exportButton.ButtonPushedFcn    = @(~,~) obj.exportResults();
            obj.view.handles.helpButton.ButtonPushedFcn      = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn     = @(~,~) obj.closeWindow();
            obj.view.handles.resultsTable.CellSelectionCallback = @(~,e) obj.resultsTableSelection(e);
            obj.view.handles.plotTabGroup.SelectionChangedFcn = @(~,~) obj.updatePlots();
            obj.view.handles.clearButton.Tooltip = 'Remove all rows from the results table';
            obj.view.handles.exportButton.Tooltip = 'Save the results, export them to MATLAB, or write a Word or PDF report';

            % context menu of the results table, created here and not in the mlapp
            tableMenu = uicontextmenu(obj.view.gui);
            uimenu(tableMenu, 'Text', 'Jump to area', 'Tag', 'jumpToAreaMenu', ...
                'MenuSelectedFcn', @(~,~) obj.jumpToArea());
            uimenu(tableMenu, 'Text', 'Remove measurement', 'Tag', 'removeMeasurementMenu', ...
                'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.removeMeasurements());
            tableMenu.ContextMenuOpeningFcn = @(~,e) obj.tableMenuOpening(e);
            obj.view.handles.resultsTable.ContextMenu = tableMenu;
        end

        % -----------------------------------------------------------
        function tableMenuOpening(obj, event)
            % TABLEMENUOPENING - Choose the rows the context menu acts on and enable its items.
            %
            % A right-click on a row outside the current selection makes that
            % row the target; inside the selection, the whole selection is
            % the target. Without rows both items are disabled.
            clickedRow = [];
            if isprop(event, 'InteractionInformation') && isprop(event.InteractionInformation, 'Row')
                clickedRow = event.InteractionInformation.Row;
            end
            if ~isempty(clickedRow) && ~ismember(clickedRow, obj.selectedRows)
                obj.selectedRows = clickedRow;
            end
            obj.selectedRows = obj.selectedRows(obj.selectedRows >= 1 & obj.selectedRows <= numel(obj.results));
            menuItems = event.ContextObject.ContextMenu.Children;
            set(menuItems, 'Enable', ~isempty(obj.selectedRows));
        end

        % -----------------------------------------------------------
        function removeMeasurements(obj)
            % REMOVEMEASUREMENTS - Remove the selected rows from the results table.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageSharpness.removeMeasurements: triggered\n');
            end
            if isempty(obj.selectedRows); return; end
            obj.results(obj.selectedRows) = [];
            obj.selectedRows = [];
            obj.storeSession();
            obj.updateResultsTable();
            obj.updatePlots([]);
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Keep settings and results for this session, destroy view and fire CloseEvent.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageSharpness.closeWindow: triggered\n');
            end
            obj.storeSession();
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function storeSession(obj)
            % STORESESSION - Keep settings and results in mibModel.sessionSettings.ImageSharpness.
            %
            % RAM only: the stored values survive closing the dialog but not
            % restarting MIB. ``id`` is not stored; it is taken from the active
            % dataset on the next start.
            storedBatchOpt = obj.BatchOpt;
            if isfield(storedBatchOpt, 'id'); storedBatchOpt = rmfield(storedBatchOpt, 'id'); end
            obj.mibModel.sessionSettings.ImageSharpness = struct('BatchOpt', storedBatchOpt, ...
                'results', obj.results, 'exportChoices', obj.exportChoices);
        end

        % ---------------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageSharpness.figureKeyPress: triggered\n');
            end
            if isempty(event.Character); return; end

            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh the color channel list and widgets from the active dataset.
            %
            % The channel list follows the number of colors of the active
            % dataset. The previously used channel is kept when it exists,
            % otherwise the channel selected in the Selection panel is used.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            numberOfColors = obj.mibModel.I{obj.BatchOpt.id}.image.colors;
            channelList = arrayfun(@(x) sprintf('Ch %d', x), 1:numberOfColors, 'UniformOutput', false);
            if ~ismember(obj.BatchOpt.ColorChannel{1}, channelList)
                selectedChannel = obj.mibModel.I{obj.BatchOpt.id}.selectedColorChannel;
                selectedChannel = min(max(selectedChannel, 1), numberOfColors);
                obj.BatchOpt.ColorChannel{1} = channelList{selectedChannel};
            end
            obj.BatchOpt.ColorChannel{2} = channelList;
            if isempty(obj.mibController)
                % no access to the image axes
                obj.BatchOpt.RegionSource{2}(strcmp(obj.BatchOpt.RegionSource{2}, 'Drawn rectangle')) = [];
            end
            if ~ismember(obj.BatchOpt.RegionSource{1}, obj.BatchOpt.RegionSource{2})
                % not available here, or a name stored by an earlier version in this session
                obj.BatchOpt.RegionSource{1} = 'Shown area';
            end
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.updateRegionInfo();
            if ~isempty(obj.view.handles.resultsTable.Data)    % the table is filled after the first updateWidgets
                obj.markActiveDatasetRows();
            end
        end

        % -----------------------------------------------------------
        function rows = activeDatasetRows(obj)
            % ACTIVEDATASETROWS - Indices of the results rows measured on the active dataset.
            %
            % Rows are matched by file name (``row.datasetName``), as the
            % buffer that held a file can be reused for another one; two
            % buffers holding files of the same name share their rows.
            rows = [];
            if isempty(obj.results); return; end
            [~, datasetName, extension] = fileparts(obj.mibModel.I{obj.mibModel.getActiveId()}.image.filename);
            rows = find(strcmp({obj.results.datasetName}, [datasetName extension]));
        end

        % -----------------------------------------------------------
        function markActiveDatasetRows(obj)
            % MARKACTIVEDATASETROWS - Highlight the rows of the active dataset and clear plots of other datasets.
            %
            % Called after every table update and from updateWidgets, which
            % runs when the buffer is switched (``UpdateGuiWidgets``). The
            % table keeps the rows of all datasets for comparison; when the
            % row shown in the plot tabs belongs to another dataset, the plots
            % are cleared, and clicking any row shows it again.
            resultsTable = obj.view.handles.resultsTable;
            removeStyle(resultsTable);
            activeRows = obj.activeDatasetRows();
            if ~isempty(activeRows)
                % bold alone was too weak, especially when most rows are bold;
                % the tint follows the light or dark theme (utils.themeColors)
                palette = utils.themeColors(obj.view.gui);
                addStyle(resultsTable, uistyle('FontWeight', 'bold', 'BackgroundColor', palette.fieldBlue), ...
                    'row', activeRows);
            end
            if ~isempty(obj.plotRowIndex) && ~ismember(obj.plotRowIndex, activeRows)
                obj.updatePlots([]);
            end
        end

        % -----------------------------------------------------------
        function updateRegionInfo(obj)
            % UPDATEREGIONINFO - Label the action button for the region and show the drawn rectangle under the region list.
            %
            % ``calculateButton`` is the single action button of the dialog: ``Draw``
            % for the ``Drawn rectangle`` region (draw, then analyse), ``Calculate``
            % for all other regions, see runButtonPushed.
            infoText = '';
            isRectangle = strcmp(obj.BatchOpt.RegionSource{1}, 'Drawn rectangle');
            if isRectangle
                obj.view.handles.calculateButton.Text = 'Draw';
                obj.view.handles.calculateButton.Tooltip = 'Draw a rectangle on the image, or adjust the previous one, and double-click inside it to analyse the area';
            else
                obj.view.handles.calculateButton.Text = 'Calculate';
                obj.view.handles.calculateButton.Tooltip = 'Analyse the selected region of the current slice and add the results to the table';
            end
            if isRectangle
                if isempty(obj.drawnRectangle)
                    infoText = 'Press Draw to define the rectangle';
                else
                    position = obj.drawnRectangle.position;
                    infoText = sprintf('x: %d-%d, y: %d-%d (%d x %d px)', position(1), position(3), ...
                        position(2), position(4), position(3)-position(1)+1, position(4)-position(2)+1);
                end
            end
            obj.view.handles.regionInfoLabel.Text = infoText;
        end

        % -----------------------------------------------------------
        function runButtonPushed(obj)
            % RUNBUTTONPUSHED - Action button: draw and analyse a rectangle, or analyse the selected region.
            %
            % For ``Drawn rectangle`` every press starts drawRectangle, which
            % offers the previous rectangle for adjustment and analyses the
            % area once it is confirmed; for the other regions it runs
            % calculate directly.
            if strcmp(obj.BatchOpt.RegionSource{1}, 'Drawn rectangle')
                obj.drawRectangle();
            else
                obj.calculate();
            end
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageSharpness.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            if strcmp(event.Source.Tag, 'RegionSource'); obj.updateRegionInfo(); end
        end

        % -----------------------------------------------------------
        function resultsTableSelection(obj, event)
            % RESULTSTABLESELECTION - Remember the selected rows and plot the first of them.
            if isempty(event.Indices); return; end
            obj.selectedRows = unique(event.Indices(:, 1))';
            obj.updatePlots(event.Indices(1, 1));
        end

        % -----------------------------------------------------------
        function clearResults(obj)
            % CLEARRESULTS - Remove all rows from the results table and clear the plots, after confirmation.
            %
            % Asks first, because the rows may hold measurements of several
            % datasets that cannot be recalculated without opening them again.
            % Does nothing when the table is empty or the user cancels.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageSharpness.clearResults: triggered\n');
            end
            if isempty(obj.results); return; end
            answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                sprintf('Remove all %d rows from the results table?', numel(obj.results)), ...
                'Clear results', 'Clear', 'Cancel', 'Cancel');
            if ~strcmp(answer, 'Clear'); return; end
            obj.results = [];
            obj.storeSession();
            obj.updateResultsTable();
            obj.updatePlots([]);
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageSharpness.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'image', 'image-tools-sharpness.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/image-tools-sharpness.html');
        end

        % signatures of the methods in separate files
        calculate(obj)
        regions = getRegions(obj)
        drawRectangle(obj)
        updateResultsTable(obj)
        updatePlots(obj, rowIndex)
        exportResults(obj)
        jumpToArea(obj)
        completed = writeReport(obj, baseFileName, formats, progressDialog)
        saveResults(obj)
        loadResults(obj)
    end
end
