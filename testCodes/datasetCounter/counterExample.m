function counterExample()
    % Clear workspace
    % clear;
    % close all;
    % clc;
    
    % Create Model
    model = CounterModel();
    
    % Create Controller
    controller = CounterController(model);
    
    % Create View (GUI)
    view = CounterView(controller);
    
    % Link view to controller
    controller.setView(view);
    
    % Create initial dataset figure
    view.addDatasetFigure(1);
    
    % Display initial empty state
    view.updateDisplay();
    
    fprintf('Application started successfully!\n');
    fprintf('- Click buttons 1-8 to load/view datasets\n');
    fprintf('- Click "Add Set" to create a new dataset set\n');
    fprintf('- Click on figure windows to switch between sets\n');
end