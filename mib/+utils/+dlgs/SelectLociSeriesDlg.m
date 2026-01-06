classdef SelectLociSeriesDlg < handle
    % SelectLociSeriesDlg Controller for Bio-Formats (LOCI) Series Selection Dialog
    %
    % The SelectLociSeriesDlg class manages series selection from Bio-Formats compatible files.
    % It provides an interface to select series, preview images, and configure metadata reading.
    % Logic ported from selectLociSeries.m to support App Designer views.
    %
    % Usage:
    %   % Initialize the controller for the dialog
    %   controller = utils.dlgs.SelectLociSeriesDlg(filename, hDataset, Font, parentGUI);
    %   
    %   % Run the controller to acquire user input
    %   [seriesIndex, hDataset, metaSwitch, dimxyczt, seriesRealName] = controller.run();
    %
    % Examples:
    %   % Example with new reader
    %   filename = 'sample_image.czi';
    %   controller = utils.dlgs.SelectLociSeriesDlg(filename, [], options.Font, parentGUI);
    %   [seriesIdx, reader, readMeta, dims, name] = controller.run();
    %   
    %   % Example with existing Bio-Formats reader
    %   reader = bfGetReader('sample_image.czi');
    %   controller = utils.dlgs.SelectLociSeriesDlg('sample_image.czi', reader, Font, parentGUI);
    %   [seriesIdx, reader, readMeta, dims, name] = controller.run();
    
    % Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
    % Part of Microscopy Image Browser, http://mib.helsinki.fi
    % Rewritten to Controller class: 06.01.2026
    
    properties (Access = private)
        view            % Handle to the App Designer view
        filename        % Path to the Bio-Formats file
        parentGUI       % Handle to the parent GUI
        
        % Internal Data State
        tableData       % Cell array storing table content
        reader          % Bio-Formats reader object
        
        % Output State
        selectedSeriesIndex = 'Cancel';     % Selected series index (1-based)
        hDataset = NaN;                     % Bio-Formats reader object
        metadataSwitch = true;             % Read metadata flag
        selectedDimensions = [0 0 0 0 0];   % Dimensions [x y c z t]
        seriesRealName = {''};              % Name of the selected series
    end
    
    methods
        function obj = SelectLociSeriesDlg(filename, hDataset, Font, parentGUI)
            % Constructor
            %
            % Parameters:
            %   filename: String path to the Bio-Formats file
            %   hDataset: Optional Bio-Formats reader object (pass [] to create new)
            %   Font: Structure with FontName and FontSize fields
            %   parentGUI: Handle to the parent GUI figure
            
            obj.filename = filename;
            if iscell(obj.filename); obj.filename = obj.filename{1}; end
            obj.parentGUI = parentGUI;
            
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
            % RUN Execute the dialog logic
            %
            % Returns:
            %   seriesIndex: Selected series index (1-based) or 'Cancel'
            %   hDataset: Bio-Formats reader object
            %   metaSwitch: Flag indicating whether to read metadata
            %   dimxyczt: Dimensions vector [x y c z t]
            %   seriesRealName: Cell array with series name
            
            % Check if only one series exists - auto-select and return
            if size(obj.tableData, 1) == 1
                obj.onContinue();
                varargout = obj.prepareOutput();
                return;
            end
            
            % Center window and make modal
            utils.moveWindowOutside(obj.view.gui, obj.parentGUI, 'center', 'center');
            
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
            % Load Bio-Formats library into MATLAB environment
            if ~isdeployed
                javapath = javaclasspath('-all');
                if isempty(cell2mat(strfind(javapath, 'bioformats_package.jar')))
                    javaaddpath(fullfile(fileparts(mfilename('fullpath')), 'bioformats_package.jar'));
                end
            end
        end
        
        function initView(obj)
            % Initialize view components, parse file, and setup callbacks
            
            % Setup image preview axes
            obj.view.handles.imagePreview.DataAspectRatio = [1 1 1];
            obj.view.handles.imagePreview.XTick = [];
            obj.view.handles.imagePreview.YTick = [];
            
            % Center the window relative to parent
            utils.moveWindowOutside(obj.view.gui, obj.parentGUI, 'center', 'center');

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
            % Parse Bio-Formats file and extract series information
            numSeries = obj.reader.getSeriesCount();
            obj.tableData = cell(numSeries, 6);  % prepare data for the table
            
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
            end
        end
        
        function processSelection(obj, rowIndices)
            % Process series selection
            if isempty(obj.tableData) || rowIndices(1) < 1; return; end
            
            % Update selected series
            obj.selectedSeriesIndex = rowIndices;
            rowIndex = rowIndices(1);
            obj.reader.setSeries(rowIndex - 1);
            
            % Get dimensions [x y c z t]
            obj.selectedDimensions = cell2mat(obj.tableData(rowIndex, 2:6));
            obj.seriesRealName = obj.tableData(rowIndex, 1);
            
            % Update slice slider
            obj.view.handles.sliceNumberEdit.Value = 1;
            obj.view.handles.sliceNumberEdit.Limits = [0, max(1, obj.selectedDimensions(4))];
            obj.view.handles.sliceNumberSlider.Value = 1;
            obj.view.handles.sliceNumberSlider.Limits = [0, max(1, obj.selectedDimensions(4))];
            
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
            obj.view.handles.selectedSeriesText2.Text = sprintf('%d, pixsize, x/y = %f, %f um', ...
                rowIndex, pixSizeX, pixSizeY);
            
            % Update image preview
            obj.updateImagePreview();
        end
        
        function updateImagePreview(obj, sliceNumber)
            if nargin < 2
                sliceNumber = round(obj.view.handles.sliceNumberSlider.Value); 
            end
            
            % Update image preview display
            if ~obj.view.handles.previewCheck.Value; return; end
            
            % Load and display preview image
            try
                templateImage = io.BioFormats.bfopen4(obj.reader, obj.selectedSeriesIndex(1), sliceNumber);
                templateImage = imresize(templateImage.img, obj.view.handles.imagePreview.Position(3)/size(templateImage.img, 1));
                
                % Handle grayscale vs color
                if size(templateImage, 3) == 1
                    imagesc(obj.view.handles.imagePreview, templateImage);
                    colormap(obj.view.handles.imagePreview, 'gray');
                else
                    templateImage2 = zeros([size(templateImage, 1), size(templateImage, 2), 3], class(templateImage));
                    for color = 1:min([size(templateImage, 3), 3])
                        templateImage2(:, :, color) = templateImage(:, :, color);
                    end
                    imagesc(obj.view.handles.imagePreview, templateImage2);
                end
            catch ME
                % Preview failed - ignore
                warning('Preview update failed: %s', ME.message);
            end
        end
        
        function out = prepareOutput(obj)
            % Prepare output arguments
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
            % Handle table row selection
            if isempty(event.Indices); return; end
            
            rowIndex = unique(event.Indices(:, 1));
            obj.processSelection(rowIndex);
        end
        
        function onParametersCheck(obj, src, ~)
            % Handle metadata checkbox change
            obj.metadataSwitch = src.Value;
        end
        
        function onPreviewCheck(obj, ~, ~)
            % Handle preview checkbox change
            obj.updateImagePreview();
        end
        
        function onSliceSlider(obj, src, event)
            % Handle slice slider movement
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
            % Handle slice edit field change
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
            % Handle key press in table
            if strcmp(event.Key, 'return')
                % Fix for return key shifting cell index
                obj.reader.setSeries(obj.selectedSeriesIndex(1) - 1);
                drawnow;
            end
            obj.onKeyPress([], event);
        end
        
        function onKeyPress(obj, ~, event)
            % Handle keyboard shortcuts
            if strcmp(event.Key, 'escape')
                obj.onCancel();
            elseif strcmp(event.Key, 'return')
                obj.onContinue();
            end
        end
        
        function onContinue(obj, ~, ~)
            % Handle continue button
            uiresume(obj.view.gui);
        end
        
        function onCancel(obj, ~, ~)
            % Handle cancel button
            obj.selectedSeriesIndex = 'Cancel';
            uiresume(obj.view.gui);
        end
    end
end
