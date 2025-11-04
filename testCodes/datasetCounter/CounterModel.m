classdef CounterModel < handle
    %MODEL Manages datasets and tracks active figure/set
    
    properties (SetAccess = private)
        % Cell array storing all datasets
        I cell = {}
        
        % Current active set (1, 2, 3, etc.)
        CurrentSet (1,1) double = 1
        
        % Current button/position for EACH set (array indexed by set number)
        CurrentButtons double = []
        
        % Number of buttons per set
        ButtonsPerSet (1,1) double = 8
        
        % Total number of sets
        NumSets (1,1) double = 0
    end
    
    events (NotifyAccess = private)
        % Event broadcast when active dataset changes
        ActiveDatasetChanged
        
        % Event broadcast when a new set is added/removed
        SetsChanged
    end
    
    methods
        function obj = CounterModel()
            % Initialize with one set
            obj.addSet();
        end
        
        function addSet(obj)
            % Add a new set of datasets
            startIdx = length(obj.I) + 1;
            
            % Increment set counter first
            obj.NumSets = obj.NumSets + 1;
            
            % Initialize current button for this set (default to 1)
            obj.CurrentButtons(obj.NumSets) = 1;
            
            % Add dummy containers for new set
            for i = 1:obj.ButtonsPerSet
                obj.I{startIdx + i - 1} = struct('data', [], ...
                                                  'setNum', obj.NumSets, ...
                                                  'buttonNum', i);
            end
            
            notify(obj, 'SetsChanged');
        end
        
        function removeSet(obj, setNum)
            % Remove a specific set
            if obj.NumSets <= 1
                warning('Cannot remove the last set');
                return;
            end
            
            % Calculate indices to remove
            startIdx = (setNum - 1) * obj.ButtonsPerSet + 1;
            endIdx = setNum * obj.ButtonsPerSet;
            
            % Remove from cell array
            obj.I(startIdx:endIdx) = [];
            
            % Remove current button for this set
            obj.CurrentButtons(setNum) = [];
            
            obj.NumSets = obj.NumSets - 1;
            
            % Update set numbers for remaining sets after removed set
            for s = setNum:obj.NumSets
                startIdx = (s - 1) * obj.ButtonsPerSet + 1;
                endIdx = s * obj.ButtonsPerSet;
                for idx = startIdx:endIdx
                    obj.I{idx}.setNum = s;
                end
            end
            
            % Adjust current set if necessary
            if obj.CurrentSet > obj.NumSets
                obj.CurrentSet = obj.NumSets;
            end
            
            notify(obj, 'SetsChanged');
            notify(obj, 'ActiveDatasetChanged');
        end
        
        function setActiveSet(obj, setNum)
            % Switch to a different set (restores last button for that set)
            if setNum < 1 || setNum > obj.NumSets
                error('Invalid set number');
            end
            
            % Only update if actually changing sets
            if obj.CurrentSet ~= setNum
                obj.CurrentSet = setNum;
                % CurrentButton is automatically restored from CurrentButtons array
                notify(obj, 'ActiveDatasetChanged');
            end
        end
        
        function setActiveButton(obj, buttonNum)
            % Switch to a different button within current set
            if buttonNum < 1 || buttonNum > obj.ButtonsPerSet
                error('Invalid button number');
            end
            
            % Save the button selection for current set
            obj.CurrentButtons(obj.CurrentSet) = buttonNum;
            notify(obj, 'ActiveDatasetChanged');
        end
        
        function button = getCurrentButton(obj)
            % Get the current button for the active set
            button = obj.CurrentButtons(obj.CurrentSet);
        end
        
        function idx = getCurrentIndex(obj)
            % Get the current index in obj.I{} array
            idx = (obj.CurrentSet - 1) * obj.ButtonsPerSet + obj.getCurrentButton();
        end
        
        function dataset = getCurrentDataset(obj)
            % Get the currently active dataset
            idx = obj.getCurrentIndex();
            if idx <= length(obj.I)
                dataset = obj.I{idx};
            else
                dataset = struct('data', [], ...
                                'setNum', obj.CurrentSet, ...
                                'buttonNum', obj.getCurrentButton());
            end
        end
        
        function setDataset(obj, buttonNum, data)
            % Set data for a specific button in current set
            idx = (obj.CurrentSet - 1) * obj.ButtonsPerSet + buttonNum;
            obj.I{idx}.data = data;
            
            % Update current button for this set and notify
            obj.CurrentButtons(obj.CurrentSet) = buttonNum;
            notify(obj, 'ActiveDatasetChanged');
        end
    end
end
