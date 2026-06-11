classdef SelectLociSeriesDlg < handle
% SELECTLOCISERIESDLG - Controller for Bio-Formats (LOCI) series selection dialog.
%
% Manages interactive series selection from Bio-Formats compatible files. Provides
% dialog UI for selecting series, previewing images, and configuring metadata reading.
% Ported from selectLociSeries.m to support App Designer views.
%
% **Typical usage:**
%
%   .. code-block:: matlab
%
%      % Initialize controller with new reader
%      filename = 'sample_image.czi';
%      controller = utils.dlgs.SelectLociSeriesDlg(filename, [], Font, ParentFigure);
%      [seriesIdx, reader, readMeta, dims, name] = controller.run();
%
%      % Or with existing Bio-Formats reader
%      reader = bfGetReader('sample_image.czi');
%      controller = utils.dlgs.SelectLociSeriesDlg(filename, reader, Font, ParentFigure);
%      [seriesIdx, reader, readMeta, dims, name] = controller.run();
%
    
    % Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
    % Part of Microscopy Image Browser, http://mib.helsinki.fi
    % Rewritten to Controller class: 06.01.2026
    
    properties (Access = private)
        view            % Handle to the App Designer view
        filename        % Path to the Bio-Formats file
        ParentFigure       % Handle to the parent GUI
        
        % Internal Data State
        tableData       % Cell array storing table content
        reader          % Bio-Formats reader object
        dimensionOrder  % cell array with the order of dimensions of series within the dataset
        
        % Output State
        selectedSeriesIndex = 'Cancel';     % Selected series index (1-based)
        hDataset = NaN;                     % Bio-Formats reader object
        metadataSwitch = true;             % Read metadata flag
        selectedDimensions = [0 0 0 0 0];   % Dimensions [x y c z t]
        seriesRealName = {''};              % Name of the selected series
    end
    
    methods
        function obj = SelectLociSeriesDlg(filename, hDataset, Font, ParentFigure)
            % SELECTLOCISERIESDLG - Constructor for SelectLociSeriesDlg controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      controller = utils.dlgs.SelectLociSeriesDlg(filename, hDataset, Font, ParentFigure)
            %
            % Input Arguments:
            %   - **filename** — [char] path to Bio-Formats compatible file
            %   - **hDataset** — [object|empty] Bio-Formats reader object; pass ``[]`` to create new reader
            %   - **Font** — [struct] font configuration with ``.FontName`` and ``.FontSize`` fields
            %   - **ParentFigure** — [handle] parent window for dialog attachment
            %
            % Output Arguments:
            %   - **obj** — instance of SelectLociSeriesDlg controller
            %
            
            obj.filename = filename;
            if iscell(obj.filename); obj.filename = obj.filename{1}; end
            obj.ParentFigure = ParentFigure;
            
            % Load Bio-Formats library
            obj.loadBioFormatsLibrary();
            
            % Create or use existing reader
            if isempty(hDataset)
                obj.reader = bfGetReader(obj.filename);
            else
                obj.reader = hDataset;
            end
            obj.hDataset = obj.reader;
            
            % Initialize the App Designer view
            obj.view = views.SelectLociSeriesGUI();
            
            % Update font size
            if ~isempty(Font) && isstruct(Font)
                if obj.view.handles.infoLabel.FontSize ~= Font.FontSize ...
                        || ~strcmp(obj.view.handles.infoLabel.FontName, Font.FontName)
                    utils.fontSizeUpdate(obj.view.gui, Font);
                end
            end
            
            % Initialize view
            obj.initView();
            
            % Make GUI visible
            obj.view.gui.Visible = true;
        end
        
        function varargout = run(obj)
            % RUN - Display dialog and return user selection results.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [seriesIdx, reader, readMeta, dims, name] = controller.run()
            %
            % Displays the series selection dialog modally. If only one series exists,
            % automatically selects it. Waits for user to continue or cancel.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **varargout{1}** — [numeric|char] selected series index (1-based); ``'Cancel'`` if cancelled
            %   - **varargout{2}** — [object] Bio-Formats reader object
            %   - **varargout{3}** — [logical] metadata inclusion flag
            %   - **varargout{4}** — [1×5 numeric] dimensions ``[x, y, c, z, t]``
            %   - **varargout{5}** — [cell] selected series name
            %
            
            % Check if only one series exists - auto-select and return
            if size(obj.tableData, 1) == 1
                obj.onContinue();
                varargout = obj.prepareOutput();
                return;
            end
            
            % Center window and make modal
            utils.moveWindowOutside(obj.view.gui, obj.ParentFigure, 'center', 'center');
            
            % Block execution until user responds
            uiwait(obj.view.gui);
            
            % Check if view was closed abruptly
            if ~isvalid(obj.view)
                varargout{1} = 'Cancel';
                varargout{2} = NaN;
                varargout{3} = 1;
                varargout{4} = [0 0 0 0 0];
                varargout{5} = {''};
                return;
            end
            
            % Prepare and return outputs
            varargout = obj.prepareOutput();
            
            % Cleanup
            delete(obj.view);
        end
    end
    
    methods (Access = private)
        function loadBioFormatsLibrary(~)
            % LOADBIOFORMATSLIBRARY - Load Bio-Formats Java library into MATLAB classpath.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.loadBioFormatsLibrary()
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   (none)
            %
            utils.ensureJavaLibraries({'bioformats'});
        end
        
        function initView(obj)
            % INITVIEW - Initialize view UI, parse Bio-Formats file, and attach callbacks.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.initView()
            %
            % Configures preview axes, parses Bio-Formats file, populates table with
            % series information, wires all UI callbacks, and selects first series.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   (none)
            %
            
            % Setup image preview axes
            obj.view.handles.imagePreview.DataAspectRatio = [1 1 1];
            obj.view.handles.imagePreview.XTick = [];
            obj.view.handles.imagePreview.YTick = [];
            
            % Center the window relative to parent
            utils.moveWindowOutside(obj.view.gui, obj.ParentFigure, 'center', 'center');

            % Parse Bio-Formats file and populate table
            try
                obj.parseBioFormatsFile();
            catch ME
                uialert(obj.view.gui, ['Error reading Bio-Formats file: ' ME.message], 'Error');
                return;
            end
            
            % Populate table
            obj.view.handles.seriesTable.Data = obj.tableData;
            
            % Setup callbacks
            obj.view.handles.seriesTable.CellSelectionCallback = @obj.onTableSelection;
            obj.view.handles.parametersCheckbox.ValueChangedFcn = @obj.onParametersCheck;
            obj.view.handles.previewCheck.ValueChangedFcn = @obj.onPreviewCheck;
            obj.view.handles.stretchContrast.ValueChangedFcn = @obj.onPreviewCheck;
            obj.view.handles.sliceNumberSlider.ValueChangingFcn = @obj.onSliceSlider;
            obj.view.handles.sliceNumberEdit.ValueChangedFcn = @obj.onSliceEdit;
            obj.view.handles.continueBtn.ButtonPushedFcn = @obj.onContinue;
            obj.view.handles.cancelBtn.ButtonPushedFcn = @obj.onCancel;
            obj.view.handles.seriesTable.KeyPressFcn = @obj.onTableKeyPress;
            obj.view.gui.WindowKeyPressFcn = @obj.onKeyPress;
            
            % Add icon
            obj.view.gui.Icon = 'mib_icon_16px.png';
            
            % Initial selection (first series)
            if size(obj.tableData, 1) > 0
                obj.processSelection(1);
            end
        end
        
        function parseBioFormatsFile(obj)
            % PARSEBIOFORMATSFILE - Extract series metadata from Bio-Formats file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.parseBioFormatsFile()
            %
            % Iterates through all series in the Bio-Formats reader, extracting
            % series name, dimensions (X, Y, C, Z, T), and dimension order string.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   (none) — updates ``tableData`` and ``dimensionOrder`` properties
            %
            numSeries = obj.reader.getSeriesCount();
            obj.tableData = cell(numSeries, 6);  % prepare data for the table
            obj.dimensionOrder = cell([numSeries 1]);

            for seriesIndex = 1:numSeries
                obj.reader.setSeries(seriesIndex - 1);
                
                % Get series name
                obj.tableData{seriesIndex, 1} = char(obj.reader.getMetadataStore().getImageName(seriesIndex - 1));
                
                % Get dimensions [X Y C Z T]
                obj.tableData{seriesIndex, 2} = obj.reader.getSizeX();
                obj.tableData{seriesIndex, 3} = obj.reader.getSizeY();
                obj.tableData{seriesIndex, 4} = obj.reader.getSizeC();  % color layers
                obj.tableData{seriesIndex, 5} = obj.reader.getSizeZ();
                obj.tableData{seriesIndex, 6} = obj.reader.getSizeT();  % time layers

                % update dimension order
                obj.dimensionOrder{seriesIndex} = char(obj.reader.getDimensionOrder()); % convert from java.lang.String to char
            end
        end
        
        function processSelection(obj, rowIndices)
            % PROCESSSELECTION - Update state for selected series and refresh preview.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.processSelection(rowIndices)
            %
            % Updates ``selectedSeriesIndex``, ``selectedDimensions``, ``seriesRealName``,
            % UI labels, and slice slider limits. Loads and displays preview image.
            %
            % Input Arguments:
            %   - **rowIndices** — [numeric] 1-based row indices from seriesTable
            %
            % Output Arguments:
            %   (none)
            %
            if isempty(obj.tableData) || rowIndices(1) < 1; return; end
            
            % Update selected series
            obj.selectedSeriesIndex = rowIndices;
            rowIndex = rowIndices(1);
            obj.reader.setSeries(rowIndex - 1);
            
            % Get dimensions [x y c z t]
            obj.selectedDimensions = cell2mat(obj.tableData(rowIndices, 2:6));
            obj.seriesRealName = obj.tableData(rowIndices, 1);
            
            % Update slice slider
            maxZ = max([1; obj.selectedDimensions(:,4)]);
            obj.view.handles.sliceNumberEdit.Enable = false;
            obj.view.handles.sliceNumberSlider.Enable = false;
            % update values and limits
            obj.view.handles.sliceNumberEdit.Value = 1;
            obj.view.handles.sliceNumberSlider.Value = 1;
            if maxZ > 1
                obj.view.handles.sliceNumberEdit.Enable = true;
                obj.view.handles.sliceNumberSlider.Enable = true;
                obj.view.handles.sliceNumberEdit.Limits = [1, maxZ+.001];
                obj.view.handles.sliceNumberSlider.Limits = [1, maxZ+.001];
            end
            
            % Get pixel size information
            omeMeta = obj.reader.getMetadataStore();
            try
                if ~isempty(omeMeta.getPixelsPhysicalSizeX(rowIndex - 1))
                    pixSizeX = double(omeMeta.getPixelsPhysicalSizeX(rowIndex - 1).value(ome.units.UNITS.MICROM));
                    pixSizeY = double(omeMeta.getPixelsPhysicalSizeY(rowIndex - 1).value(ome.units.UNITS.MICROM));
                else
                    pixSizeX = 1;
                    pixSizeY = 1;
                end
            catch
                pixSizeX = 1;
                pixSizeY = 1;
            end
            
            % Update selected series text
            obj.view.handles.selectedSeriesText.Text = obj.seriesRealName;
            obj.view.handles.selectedSeriesText.Tooltip = obj.seriesRealName;
            obj.view.handles.selectedSeriesText2.Text = sprintf('%d, pixsize, x/y = %f, %f um', ...
                rowIndex, pixSizeX, pixSizeY);
            
            % Update image preview
            obj.updateImagePreview();
        end
        
        function updateImagePreview(obj, sliceNumber)
            % UPDATEIMAGEPREVIEW - Load and display preview image for selected series and slice.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateImagePreview(sliceNumber)
            %
            % Loads image from selected series and slice using Bio-Formats reader.
            % Applies optional contrast stretching, handles grayscale/RGB/multichannel
            % formats, and resizes to fit preview axes.
            %
            % Input Arguments:
            %   - **sliceNumber** — *(optional)* [numeric] Z-slice to display;
            %     defaults to current slider value
            %
            % Output Arguments:
            %   (none)
            %
            if nargin < 2
                sliceNumber = round(obj.view.handles.sliceNumberSlider.Value); 
            end
            
            % Update image preview display
            if ~obj.view.handles.previewCheck.Value; return; end
            
            % Load and display preview image
            try
                bfopenOptions.dimensionOrder = obj.dimensionOrder{obj.selectedSeriesIndex(1)};
                % returned as [xyczt];
                templateImage = io.BioFormats.bfopen5(obj.reader, obj.selectedSeriesIndex(1), sliceNumber, bfopenOptions);
                
                %templateImage = imresize(templateImage.img, obj.view.handles.imagePreview.Position(3)/size(templateImage.img, 1));

                templateImage = imresize(squeeze(templateImage.img), [obj.view.handles.imagePreview.Position(3) obj.view.handles.imagePreview.Position(4)]);
                %templateImage = imresize(templateImage.img, [400 400]);
                
                % Handle grayscale vs color
                noColors =  size(templateImage, 3);
                if noColors == 1
                    imagesc(obj.view.handles.imagePreview, templateImage);
                    colormap(obj.view.handles.imagePreview, 'gray');
                else
                    if noColors == 2
                        templateImage = cat(3, templateImage, zeros(size(templateImage, 1), size(templateImage, 2)));
                    elseif noColors > 3
                        templateImage = templateImage(:,:,1:3);
                    end
                    if obj.view.handles.stretchContrast.Value
                        templateImage = double(templateImage);
                        minVec = min(templateImage, [], 1:3);
                        maxVec = max(templateImage,[],1:3);
                        templateImage = uint8(((templateImage - minVec) ./ (maxVec - minVec))*255);
                    end
                    imagesc(obj.view.handles.imagePreview, templateImage);
                end
            catch ME
                % Preview failed - ignore
                warning('Preview update failed: %s', ME.message);
            end
        end
        
        function out = prepareOutput(obj)
            % PREPAREOUTPUT - Assemble output values from dialog state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      out = obj.prepareOutput()
            %
            % Packages ``selectedSeriesIndex``, ``hDataset``, ``metadataSwitch``,
            % ``selectedDimensions``, and ``seriesRealName`` into cell array.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **out** — cell array ``{seriesIdx, reader, readMeta, dims, name}``
            %
            out{1} = obj.selectedSeriesIndex;
            out{2} = obj.hDataset;
            out{3} = obj.metadataSwitch;
            out{4} = obj.selectedDimensions;
            out{5} = obj.seriesRealName;
        end
        
        % ----------------------
        % View Callbacks
        % ----------------------
        
        function onTableSelection(obj, ~, event)
            % ONTABLESELECTION - UITable selection callback; extract and process row.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onTableSelection(source, event)
            %
            % Input Arguments:
            %   - **source** — [handle] table widget (unused)
            %   - **event** — [struct] table event with ``Indices`` field
            %
            % Output Arguments:
            %   (none)
            %
            if isempty(event.Indices); return; end
            
            rowIndex = unique(event.Indices(:, 1));
            obj.processSelection(rowIndex);
        end
        
        function onParametersCheck(obj, src, ~)
            % ONPARAMETERSCHECK - Metadata checkbox callback; update flag.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onParametersCheck(source, event)
            %
            % Input Arguments:
            %   - **source** — [handle] checkbox widget
            %   - **event** — [struct] checkbox event (unused)
            %
            % Output Arguments:
            %   (none)
            %
            obj.metadataSwitch = src.Value;
        end
        
        function onPreviewCheck(obj, ~, ~)
            % ONPREVIEWCHECK - Preview or contrast checkbox callback; refresh display.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onPreviewCheck(source, event)
            %
            % Input Arguments:
            %   - **source** — [handle] checkbox widget (unused)
            %   - **event** — [struct] checkbox event (unused)
            %
            % Output Arguments:
            %   (none)
            %
            obj.updateImagePreview();
        end
        
        function onSliceSlider(obj, src, event)
            % ONSLICESLIDER - Slice slider callback; throttle updates and refresh preview.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onSliceSlider(source, event)
            %
            % Updates preview at most every 100 ms to avoid excessive rendering.
            %
            % Input Arguments:
            %   - **source** — [handle] slider widget
            %   - **event** — [struct] slider event with ``Value`` field
            %
            % Output Arguments:
            %   (none)
            %
            persistent lastUpdate;
            if isempty(lastUpdate), lastUpdate = tic; end

            if strcmp(obj.selectedSeriesIndex, 'Cancel')
                src.Value = 1;
                return;
            end
            % Only update every 100ms
            if toc(lastUpdate) > 0.1
                sliceNumber = round(event.Value);
                obj.view.handles.sliceNumberEdit.Value = max([1 sliceNumber]);
                obj.updateImagePreview(sliceNumber);
                lastUpdate = tic;
            end
        end
        
        function onSliceEdit(obj, src, ~)
            % ONSLICEEDIT - Slice edit field callback; validate and sync with slider.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onSliceEdit(source, event)
            %
            % Validates slice value is within valid range, syncs slider to edit field,
            % and updates preview display.
            %
            % Input Arguments:
            %   - **source** — [handle] edit field widget
            %   - **event** — [struct] edit event (unused)
            %
            % Output Arguments:
            %   (none)
            %
            if strcmp(obj.selectedSeriesIndex, 'Cancel')
                src.Value = 1;
                return;
            end
            
            value = max([1 round(src.Value)]);
            maxSlice = obj.selectedDimensions(4);
            
            if value > maxSlice
                value = maxSlice;
                src.Value = value;
            end
            
            obj.view.handles.sliceNumberSlider.Value = value;
            obj.updateImagePreview();
        end
        
        function onTableKeyPress(obj, ~, event)
            % ONTABLEKEYPRESS - Table key press callback; forward to global key handler.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onTableKeyPress(source, event)
            %
            % Fixes return key behavior in table and delegates to ``onKeyPress``.
            %
            % Input Arguments:
            %   - **source** — [handle] table widget (unused)
            %   - **event** — [struct] keyboard event
            %
            % Output Arguments:
            %   (none)
            %
            if strcmp(event.Key, 'return')
                % Fix for return key shifting cell index
                obj.reader.setSeries(obj.selectedSeriesIndex(1) - 1);
                drawnow;
            end
            obj.onKeyPress([], event);
        end
        
        function onKeyPress(obj, ~, event)
            % ONKEYPRESS - Window key press callback; handle escape and return keys.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onKeyPress(source, event)
            %
            % Keyboard shortcuts: Escape cancels, Return/Enter continues dialog.
            %
            % Input Arguments:
            %   - **source** — [handle] figure window (unused)
            %   - **event** — [struct] keyboard event with ``Key`` field
            %
            % Output Arguments:
            %   (none)
            %
            if strcmp(event.Key, 'escape')
                obj.onCancel();
            elseif strcmp(event.Key, 'return')
                obj.onContinue();
            end
        end
        
        function onContinue(obj, ~, ~)
            % ONCONTINUE - Continue button callback; resume execution.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onContinue(source, event)
            %
            % Input Arguments:
            %   - **source** — [handle] button widget (unused)
            %   - **event** — [struct] button event (unused)
            %
            % Output Arguments:
            %   (none)
            %
            uiresume(obj.view.gui);
        end
        
        function onCancel(obj, ~, ~)
            % ONCANCEL - Cancel button callback; set state and resume execution.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onCancel(source, event)
            %
            % Sets ``selectedSeriesIndex`` to ``'Cancel'`` and resumes execution.
            %
            % Input Arguments:
            %   - **source** — [handle] button widget (unused)
            %   - **event** — [struct] button event (unused)
            %
            % Output Arguments:
            %   (none)
            %
            obj.selectedSeriesIndex = 'Cancel';
            uiresume(obj.view.gui);
        end
    end
end
