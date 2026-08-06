classdef SelectHDFSeries < handle
% SELECTHDFSERIES - Controller for HDF5 series/dataset selection dialog.
%
% Ported from legacy selectHDFSeries.m to support App Designer views.
% Provides interactive dialog for users to browse and select datasets
% from HDF5 files, with dimension reordering and metadata options.
%
% **Typical usage:**
%
%   .. code-block:: matlab
%
%      % Initialize the controller for HDF5 file selection dialog
%      controller = utils.dlgs.SelectHDFSeries('myfile.h5', ParentFigure, Font);
%      % Run the controller to acquire user input
%      [dataset, metaFlag, dims, transMat] = controller.run();

    properties (Access = private)
        view            % handle to the App Designer view
        filename        % path to HDF5 file
        ParentFigure       % handle to the parent GUI
        
        % Internal Data State
        tableData       % Cell array storing table content
        dataDimMap      % Map or Cell array storing dimension tags (axistags)
        
        % Output State 
        selectedDatasetName = 'Cancel';
        metadataSwitch = false;
        selectedDimensions = [NaN NaN NaN NaN NaN]; % [y x z c t]
        transformationMatrix = NaN;
    end

    methods
        function obj = SelectHDFSeries(filename, ParentFigure, Font)
            % SELECTHDFSERIES - Constructor for SelectHDFSeries controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      controller = utils.dlgs.SelectHDFSeries(filename, ParentFigure, Font)
            %
            % Input Arguments:
            %   - **filename** - [char|cell] path to HDF5 file. If cell array,
            %     uses the first element.
            %   - **ParentFigure** - [handle] parent window for dialog attachment
            %   - **Font** - [struct] font configuration with ``.FontSize`` and ``.FontName``
            %
            % Output Arguments:
            %   - **obj** - instance of SelectHDFSeries controller
            
            obj.ParentFigure = ParentFigure;
            obj.view = views.SelectHDFSeriesGUI;
            % update font size
            if obj.view.handles.selectdatasettoloadLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.selectdatasettoloadLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            
            if iscell(filename)
                obj.filename = filename{1};
            else
                obj.filename = filename;
            end
            
            % Initialize
            obj.initView();

            obj.view.gui.Visible = true;
        end

        function varargout = run(obj)
            % RUN - Block execution until user selection and return results.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [dataset, metaFlag, dims, transMat] = controller.run()
            %
            % Displays the HDF5 series selection dialog modally and waits for
            % user input (continue or cancel). Returns selection results.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **varargout{1}** - [char] selected dataset path; ``'Cancel'`` if cancelled
            %   - **varargout{2}** - [logical] metadata inclusion flag
            %   - **varargout{3}** - [1×5 numeric] dimensions ``[y, x, z, c, t]``
            %     with ``0`` for unspecified dimensions (legacy behavior)
            %   - **varargout{4}** - [1×5 numeric] transformation matrix for dimension reordering,
            %     or ``NaN`` if no reordering requested
            
            %obj.view.gui.WindowStyle = 'modal';
            
            % Block execution until uiresume is called (in onContinue/onCancel)
            uiwait(obj.view.gui);
            
            % Check if valid selection was made
            if ~isvalid(obj.view)
                % Window closed abruptly
                varargout{1} = 'Cancel';
                varargout{2} = 0;
                varargout{3} = [NaN NaN NaN NaN NaN];
                varargout{4} = NaN;
                return;
            end

            % Return outputs
            varargout{1} = obj.selectedDatasetName;
            varargout{2} = obj.metadataSwitch;
            
            % Fill NaNs with 0 for dimensions (legacy behavior)
            dims = obj.selectedDimensions;
            dims(isnan(dims)) = 0;
            varargout{3} = dims;
            
            varargout{4} = obj.transformationMatrix;
            
            % Cleanup
            delete(obj.view);
        end
    end

    methods (Access = private)
        function initView(obj)
            % INITVIEW - Initialize view UI, parse HDF5, and attach callbacks.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.initView()
            %
            % Parses HDF5 file, populates table with datasets, positions window,
            % and wires all UI callbacks.
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   (none)
            %
            utils.moveWindowOutside(obj.view.gui, obj.ParentFigure, 'center', 'center');
            % add icon
            obj.view.gui.Icon = 'mib_icon_16px.png';
            % Parse HDF5 and populate the view
            try
                info = h5info(obj.filename);
            catch ME
                uialert(obj.view.gui, ['Error reading HDF5 file: ' ME.message], 'Error');
                return;
            end
            
            tableRows = {};
            obj.dataDimMap = {}; 
            idx = 1;

            % parse Root Datasets
            if ~isempty(info.Datasets)
                for i = 1:numel(info.Datasets)
                    [row, dimTags] = obj.parseDatasetInfo(info.Datasets(i), '');
                    tableRows(idx, :) = row;
                    obj.dataDimMap{idx} = dimTags;
                    idx = idx + 1;
                end
            end

            % parse Groups
            for g = 1:numel(info.Groups)
                for d = 1:numel(info.Groups(g).Datasets)
                    [row, dimTags] = obj.parseDatasetInfo(info.Groups(g).Datasets(d), info.Groups(g).Name);
                    tableRows(idx, :) = row;
                    obj.dataDimMap{idx} = dimTags;
                    idx = idx + 1;
                end
            end

            % Populate View Table
            % Assuming View has a UITable named 'seriesTable'
            obj.view.seriesTable.Data = tableRows;
            %obj.view.seriesTable.ColumnName = {'Dataset', 'Dim1', 'Dim2', 'Dim3', 'Dim4', 'Dim5', 'Class'};
            
            % Attach Callbacks
            obj.view.handles.seriesTable.CellSelectionCallback = @obj.onTableSelection;
            obj.view.handles.reorderDims.ValueChangedFcn = @obj.onReorderDimsCheck;
            obj.view.handles.readMetadata.ValueChangedFcn = @obj.onMetadataCheck;
            obj.view.handles.continueButton.ButtonPushedFcn = @obj.onContinue;
            obj.view.handles.cancelButton.ButtonPushedFcn = @obj.onCancel;
            obj.view.gui.WindowKeyPressFcn = @obj.onKeyPress;
            
            % Initial Selection
            if ~isempty(tableRows)
                % Select first row programmatically if possible 
                % (App Designer tables don't always support easy programmatic selection without interaction)
                % But we can simulate the internal state:
                obj.processSelection(1);
            end
        end

        function [row, dimTags] = parseDatasetInfo(~, dataset, groupName)
            % PARSEDATASETINFO - Extract dataset info and axis tags for table display.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [row, dimTags] = obj.parseDatasetInfo(dataset, groupName)
            %
            % Extracts full path, dimensions, data type, and Ilastik-style axis tags
            % from HDF5 dataset metadata.
            %
            % Input Arguments:
            %   - **dataset** - struct from ``h5info``, HDF5 dataset metadata
            %   - **groupName** - [char] parent group path (empty for root datasets)
            %
            % Output Arguments:
            %   - **row** - cell array ``{fullPath, dim1, dim2, dim3, dim4, dim5, dataClass}``
            %   - **dimTags** - [char] flipped axis tag string from ``axistags`` attribute
            %     (e.g. ``'ctzyx'`` from Ilastik); empty if not present
            %
            
            dsName = dataset.Name;
            if isempty(groupName)
                if dsName(1) ~= '/', dsName = ['/' dsName]; end
                fullName = dsName;
            else
                fullName = [groupName '/' dsName];
            end
            
            row{1} = fullName;
            
            % Dimensions
            dims = dataset.Dataspace.Size;
            for k = 1:5
                if k <= numel(dims)
                    row{1+k} = num2str(dims(k));
                else
                    row{1+k} = '';
                end
            end
            
            row{7} = dataset.Datatype.Class;
            
            % Axis Tags (Ilastik check)
            dimTags = '';
            if ~isempty(dataset.Attributes)
                attrNames = {dataset.Attributes.Name};
                attrIdx = find(strcmp(attrNames, 'axistags'));
                
                if ~isempty(attrIdx)
                    val = dataset.Attributes(attrIdx).Value;
                    if iscell(val), val = val{1}; end
                    % Parse JSON-like string for keys
                    jsonStruct = jsondecode(val);
                    dimTags = fliplr([jsonStruct.axes.key]); % flip the order
                end
            end
        end

        function processSelection(obj, rowIndex)
            % PROCESSSELECTION - Update internal state when user selects a dataset row.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.processSelection(rowIndex)
            %
            % Updates ``selectedDatasetName``, ``selectedDimensions``, UI labels,
            % and calculates transformation matrix for the selected row.
            %
            % Input Arguments:
            %   - **rowIndex** - [numeric] 1-based row index in seriesTable
            %
            % Output Arguments:
            %   (none)
            %
            if isempty(obj.view.seriesTable.Data) || rowIndex < 1
                return;
            end
            
            rowData = obj.view.seriesTable.Data(rowIndex, :);
            obj.selectedDatasetName = rowData{1};
            
            % Update Label in View
            obj.view.handles.selectedSeries.Text = obj.selectedDatasetName;
            
            % Parse Dimensions [y x z c t]
            % Columns 2-6 contain dimension sizes
            dimVals = zeros(1, 5);
            for k = 1:5
                val = str2double(rowData{1+k});
                if isnan(val), val = NaN; end
                dimVals(k) = val;
            end
            obj.selectedDimensions = dimVals;
            
            % Calculate Transformation Matrix
            obj.calculateTransMatrix(rowIndex);
        end
        
        function calculateTransMatrix(obj, rowIndex)
            % CALCULATETRANSMATRIX - Calculate dimension permutation matrix for selected dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.calculateTransMatrix(rowIndex)
            %
            % Maps dataset dimensions to output order ``[y, x, z, c, t]`` using
            % Ilastik-style axis tags. Handles missing dimensions and updates
            % ``newDimOrder`` UI control.
            %
            % Input Arguments:
            %   - **rowIndex** - [numeric] 1-based row index in seriesTable
            %
            % Output Arguments:
            %   (none)
            %
            transMat = NaN;
            
            if rowIndex <= numel(obj.dataDimMap) && ~isempty(obj.dataDimMap{rowIndex})
                dataDim = obj.dataDimMap{rowIndex}; % e.g., 'tzyxc'
                outputDim = 'yxzct';
                
                % Find missing axis
                % missingAxis = find(~ismember(outputDim, dataDim)); 
                
                % Map logic
                currentTrans = zeros(1, numel(outputDim));
                missingIndex = 1;
                missingAxisIndices = find(~ismember(outputDim, dataDim));
                
                for i = 1:numel(outputDim)
                    keyPosition = find(dataDim == outputDim(i));
                    
                    if ~isempty(keyPosition)
                        currentTrans(i) = keyPosition;
                    else
                        % If axis not found in data, assign a missing index
                        % Logic from original: transMatrix(i) = numel(dataDim) + missingIndex
                        if missingIndex <= numel(missingAxisIndices)
                            currentTrans(i) = numel(dataDim) + missingIndex;
                            missingIndex = missingIndex + 1;
                        else
                             currentTrans(i) = 0; % Fallback
                        end
                    end
                end
                
                % Update newDimOrder
                obj.view.handles.newDimOrder.Value = upper(outputDim(currentTrans));
                transMat = currentTrans;
            end
            obj.transformationMatrix = transMat;
        end

        % ----------------------
        % View Callbacks
        % ----------------------

        function onTableSelection(obj, ~, event)
            % ONTABLESELECTION - UITable selection callback; extract row index and process.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onTableSelection(source, event)
            %
            % App Designer table selection callback that extracts the selected row
            % index from event data and calls ``processSelection``.
            %
            % Input Arguments:
            %   - **source** - [handle] table widget (unused)
            %   - **event** - [struct] table selection event with ``Selection`` field
            %
            % Output Arguments:
            %   (none)
            %
            
            % For single selection:
            indices = event.Source.Selection; 
            % 'Selection' usually returns the row index in App Designer specific configurations
            % If using UITable with 'Row' selection type:
            if isempty(indices); return; end
            
            % Assuming indices is just the row number
            obj.processSelection(indices(1)); 
        end
        
        function onReorderDimsCheck(obj, ~, ~)
            if obj.view.handles.reorderDims.Value
                obj.view.handles.newDimOrder.Enable = true;
            else
                obj.view.handles.newDimOrder.Enable = false;
            end
            %obj.calculateTransMatrix(obj.view.handles.seriesTable.DisplaySelection);
        end
        
        function onMetadataCheck(obj, ~, ~)
            obj.metadataSwitch = obj.view.handles.readMetadata.Value;
        end

        function onKeyPress(obj, ~, evt)
            if isprop(evt, 'Key') && strcmp(evt.Key, 'escape')
                obj.onCancel();
                return;
            end

            if isprop(evt, 'Key') && (strcmp(evt.Key, 'return') || strcmp(evt.Key, 'enter'))
                obj.onContinue();
            end
        end

        function onContinue(obj, ~, ~)
            % ONCONTINUE - Continue button callback; process manual transpose if enabled.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.onContinue(source, event)
            %
            % When dimension reordering is enabled, parses the user-supplied dimension
            % order string and constructs transformation matrix. Then resumes execution.
            %
            % Input Arguments:
            %   - **source** - [handle] button widget (unused)
            %   - **event** - [struct] button event (unused)
            %
            % Output Arguments:
            %   (none)
            %
            if obj.view.handles.reorderDims.Value
                % Logic to parse manual transpose string (from original code)
                transStr = lower(obj.view.handles.newDimOrder.Value);
                outputDim = 'yxzct';

                % This part reconstructs the matrix based on user string
                transMat = NaN(1,5);
                for i = 1:numel(outputDim)
                    idx = strfind(transStr, outputDim(i));
                    if ~isempty(idx)
                        transMat(i) = idx;
                    end
                end
                obj.transformationMatrix = transMat;
            else
                obj.transformationMatrix = NaN;
            end
            
            uiresume(obj.view.gui);
        end

        function onCancel(obj, ~, ~)
            obj.selectedDatasetName = 'Cancel';
            uiresume(obj.view.gui);
        end
    end
end
