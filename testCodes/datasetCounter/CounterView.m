classdef CounterView < handle
    %VIEW Creates and manages the GUI interface
    
    properties
        Controller
        
        % Main control figure
        ControlFig
        
        % Dataset display figures (one per set)
        DatasetFigs = []
        
        % UI Components
        ButtonPanel
        DatasetButtons
        AddSetButton
        RemoveSetButton
        SetDropdown        % Dropdown to select active set
        CurrentSetLabel
    end
    
    methods
        function obj = CounterView(controller)
            obj.Controller = controller;
            obj.createControlGUI();
            
            % Listen to model events
            addlistener(obj.Controller.Model, 'ActiveDatasetChanged', ...
                       @obj.onActiveDatasetChanged);
            addlistener(obj.Controller.Model, 'SetsChanged', ...
                       @obj.onSetsChanged);
        end
        
        function createControlGUI(obj)
            % Create main control figure (RESIZABLE)
            obj.ControlFig = figure('Name', 'Dataset Control Panel', ...
                                    'Position', [100, 100, 400, 400], ...
                                    'MenuBar', 'none', ...
                                    'NumberTitle', 'off', ...
                                    'Resize', 'on', ...
                                    'CloseRequestFcn', @obj.onClose);
            
            % Create panel for dataset buttons (1-8)
            obj.ButtonPanel = uipanel('Parent', obj.ControlFig, ...
                                      'Title', 'Dataset Buttons', ...
                                      'FontSize', 12, ...
                                      'FontWeight', 'bold', ...
                                      'Position', [0.05, 0.32, 0.9, 0.60]);
            
            % Create 8 dataset buttons in a 2x4 grid
            buttonWidth = 0.22;
            buttonHeight = 0.4;
            hSpacing = 0.025;
            vSpacing = 0.1;
            
            obj.DatasetButtons = gobjects(8, 1);
            
            for i = 1:8
                row = floor((i-1) / 4);  % 0 or 1
                col = mod(i-1, 4);        % 0 to 3
                
                xPos = 0.05 + col * (buttonWidth + hSpacing);
                yPos = 0.5 - row * (buttonHeight + vSpacing);
                
                obj.DatasetButtons(i) = uicontrol('Parent', obj.ButtonPanel, ...
                    'Style', 'pushbutton', ...
                    'String', num2str(i), ...
                    'FontSize', 18, ...
                    'FontWeight', 'bold', ...
                    'Units', 'normalized', ...
                    'Position', [xPos, yPos, buttonWidth, buttonHeight], ...
                    'Callback', @(src, evt) obj.onDatasetButtonClick(i));
            end
            
            % Create set selection panel
            setPanel = uipanel('Parent', obj.ControlFig, ...
                              'Title', 'Active Set Selection', ...
                              'FontSize', 11, ...
                              'FontWeight', 'bold', ...
                              'Position', [0.05, 0.18, 0.9, 0.12]);
            
            % Label for dropdown
            uicontrol('Parent', setPanel, ...
                'Style', 'text', ...
                'String', 'Select Set:', ...
                'FontSize', 10, ...
                'FontWeight', 'bold', ...
                'HorizontalAlignment', 'right', ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.25, 0.25, 0.5]);
            
            % Dropdown menu for set selection
            obj.SetDropdown = uicontrol('Parent', setPanel, ...
                'Style', 'popupmenu', ...
                'String', {'Set 1'}, ...
                'Value', 1, ...
                'FontSize', 10, ...
                'Units', 'normalized', ...
                'Position', [0.32, 0.25, 0.35, 0.5], ...
                'Callback', @obj.onSetDropdownChange);
            
            % Current Set Label (display only)
            obj.CurrentSetLabel = uicontrol('Parent', setPanel, ...
                'Style', 'text', ...
                'String', 'Set 1', ...
                'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'ForegroundColor', [0, 0.5, 0], ...
                'HorizontalAlignment', 'center', ...
                'Units', 'normalized', ...
                'Position', [0.70, 0.25, 0.25, 0.5], ...
                'BackgroundColor', [0.8, 0.9, 1]);
            
            % Create control buttons panel
            controlPanel = uipanel('Parent', obj.ControlFig, ...
                                   'Title', 'Set Management', ...
                                   'FontSize', 11, ...
                                   'FontWeight', 'bold', ...
                                   'Position', [0.05, 0.05, 0.9, 0.11]);
            
            % Add Set button
            obj.AddSetButton = uicontrol('Parent', controlPanel, ...
                'Style', 'pushbutton', ...
                'String', 'Add Set', ...
                'FontSize', 11, ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.3, 0.43, 0.6], ...
                'Callback', @obj.onAddSetClick);
            
            % Remove Set button
            obj.RemoveSetButton = uicontrol('Parent', controlPanel, ...
                'Style', 'pushbutton', ...
                'String', 'Remove Set', ...
                'FontSize', 11, ...
                'Units', 'normalized', ...
                'Position', [0.52, 0.3, 0.43, 0.6], ...
                'Callback', @obj.onRemoveSetClick);
        end
        
        function updateSetDropdown(obj)
            % Update dropdown list based on number of sets
            numSets = obj.Controller.Model.NumSets;
            
            % Create string list: 'Set 1', 'Set 2', etc.
            setStrings = cell(numSets, 1);
            for i = 1:numSets
                setStrings{i} = sprintf('Set %d', i);
            end
            
            % Update dropdown
            currentValue = get(obj.SetDropdown, 'Value');
            set(obj.SetDropdown, 'String', setStrings);
            
            % Adjust value if necessary
            if currentValue > numSets
                set(obj.SetDropdown, 'Value', numSets);
            end
        end
        
        function addDatasetFigure(obj, setNum)
            % Create a new figure for displaying datasets
            figHandle = figure('Name', sprintf('Dataset Viewer - Set %d', setNum), ...
                              'Position', [150 + setNum*50, 150 + setNum*50, 600, 500], ...
                              'NumberTitle', 'off', ...
                              'WindowButtonDownFcn', @(src, evt) obj.onFigureClick(src));
            
            % Store figure handle
            obj.DatasetFigs(setNum) = figHandle;
            
            % Create axes for displaying data
            axes('Parent', figHandle, ...
                 'Units', 'normalized', ...
                 'Position', [0.1, 0.1, 0.85, 0.85]);
            
            title(sprintf('Set %d - No Data', setNum));
            xlabel('Sample');
            ylabel('Value');
            grid on;
        end
        
        function removeDatasetFigure(obj, setNum)
            % Remove figure for a deleted set
            if setNum <= length(obj.DatasetFigs) && isgraphics(obj.DatasetFigs(setNum), 'figure')
                delete(obj.DatasetFigs(setNum));
            end
            obj.DatasetFigs(setNum) = [];
        end
        
        function updateDisplay(obj)
            % Update the display of current dataset
            dataset = obj.Controller.Model.getCurrentDataset();
            currentSet = obj.Controller.Model.CurrentSet;
            
            % Make sure figure exists and is valid
            if currentSet > length(obj.DatasetFigs) || ...
               ~isgraphics(obj.DatasetFigs(currentSet), 'figure')
                obj.addDatasetFigure(currentSet);
            end
            
            % Bring figure to front and make it active
            figHandle = obj.DatasetFigs(currentSet);
            figure(figHandle);
            cla;
            
            % Display data
            if ~isempty(dataset.data)
                plot(dataset.data, 'LineWidth', 2);
                title(sprintf('Set %d - Dataset %d', dataset.setNum, dataset.buttonNum));
            else
                text(0.5, 0.5, sprintf('Set %d - Button %d\n(No Data)', ...
                                       dataset.setNum, dataset.buttonNum), ...
                     'Units', 'normalized', ...
                     'HorizontalAlignment', 'center', ...
                     'FontSize', 14);
                title(sprintf('Set %d - Dataset %d (Empty)', dataset.setNum, dataset.buttonNum));
            end
            
            xlabel('Sample');
            ylabel('Value');
            grid on;
            
            % Update control panel label and dropdown
            set(obj.CurrentSetLabel, 'String', sprintf('Set %d', currentSet));
            set(obj.SetDropdown, 'Value', currentSet);
        end
        
        % Callback functions
        function onDatasetButtonClick(obj, buttonNum)
            % Called when dataset buttons 1-8 are clicked
            obj.Controller.onButtonClick(buttonNum);
        end
        
        function onSetDropdownChange(obj, src, ~)
            % Called when user selects a set from the dropdown
            selectedSet = get(src, 'Value');
            obj.Controller.Model.setActiveSet(selectedSet);
        end
        
        function onAddSetClick(obj, ~, ~)
            % Called when Add Set button is clicked
            obj.Controller.onAddSetButton();
            obj.updateSetDropdown();
        end
        
        function onRemoveSetClick(obj, ~, ~)
            % Called when Remove Set button is clicked
            currentSet = obj.Controller.Model.CurrentSet;
            
            if obj.Controller.Model.NumSets <= 1
                warndlg('Cannot remove the last set!', 'Warning');
                return;
            end
            
            % Confirm removal
            answer = questdlg(sprintf('Remove Set %d?', currentSet), ...
                             'Confirm Removal', 'Yes', 'No', 'No');
            
            if strcmp(answer, 'Yes')
                obj.removeDatasetFigure(currentSet);
                obj.Controller.Model.removeSet(currentSet);
                obj.updateSetDropdown();
            end
        end
        
        function onFigureClick(obj, figHandle)
            % Called when a dataset figure is clicked
            setNum = find(obj.DatasetFigs == figHandle, 1);
            if ~isempty(setNum)
                obj.Controller.onFigureClick(figHandle);
            end
        end
        
        function onActiveDatasetChanged(obj, ~, ~)
            % Listener callback when active dataset changes
            obj.updateDisplay();
        end
        
        function onSetsChanged(obj, ~, ~)
            % Listener callback when sets are added/removed
            numSets = obj.Controller.Model.NumSets;
            
            % Add new figure if needed
            if numSets > length(obj.DatasetFigs)
                obj.addDatasetFigure(numSets);
            end
            
            % Update dropdown
            obj.updateSetDropdown();
        end
        
        function onClose(obj, ~, ~)
            % Close all dataset figures
            for i = 1:length(obj.DatasetFigs)
                if isgraphics(obj.DatasetFigs(i), 'figure')
                    delete(obj.DatasetFigs(i));
                end
            end
            delete(obj.ControlFig);
        end
    end
end
