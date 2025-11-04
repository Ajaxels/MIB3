classdef CounterController < handle
    %CONTROLLER Handles user interactions between View and Model
    
    properties
        Model
        View
    end
    
    methods
        function obj = CounterController(model)
            obj.Model = model;
        end
        
        function setView(obj, view)
            obj.View = view;
        end
        
        function onButtonClick(obj, buttonNum)
            % Called when dataset buttons 1-8 are clicked
            
            % Generate dummy data for demonstration if empty
            if obj.Model.getCurrentIndex() <= length(obj.Model.I)
                currentDataset = obj.Model.I{obj.Model.getCurrentIndex()};
                if isempty(currentDataset.data)
                    % Generate random data for empty datasets
                    obj.Model.setDataset(buttonNum, randn(100, 1) * 10 + buttonNum * 5);
                else
                    % Just switch to existing data
                    obj.Model.setActiveButton(buttonNum);
                end
            end
        end
        
        function onFigureClick(obj, figHandle)
            % Called when user clicks on a dataset figure window
            setNum = find(obj.View.DatasetFigs == figHandle, 1);
            
            if ~isempty(setNum)
                obj.Model.setActiveSet(setNum);
            end
        end
        
        function onAddSetButton(obj)
            % Add new set and initialize with dummy data for button 2
            obj.Model.addSet();
            
            % Switch to new set
            newSetNum = obj.Model.NumSets;
            obj.Model.setActiveSet(newSetNum);
            
            % Add dummy data to button 2 (dataset 2) of the new set
            idx = (newSetNum - 1) * obj.Model.ButtonsPerSet + 2;
            obj.Model.I{idx}.data = randn(100, 1) * 10 + 20; % Dummy data for dataset 2
            
            % Set button 2 as active and display
            obj.Model.setActiveButton(2);
        end
    end
end
