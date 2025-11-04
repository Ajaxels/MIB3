function datasetsSetsOps_Callbacks(obj, hWidget, hData, mode)
% function datasetsSetsOps_Callbacks(obj, hWidget, hData, mode)
% callbacks for press of sets-related widgets in obj.view.handles.panels.datasets.handles
% Handles the following widgets:
% - obj.view.handles.panels.datasets.handles.sets -> select set
% - obj.view.handles.panels.datasets.handles.setsContextRename -> context menu for sets dropdown, rename the selected set
% - obj.view.handles.panels.datasets.handles.setsContextAdd -> context menu for sets dropdown, add a new set
% - obj.view.handles.panels.datasets.handles.setsContextRemove -> context menu for sets dropdown, remove the selected set
%
% Parameters:
% hWidget: handle to the pressed widget: dropdown or button
% hData: handle to supporting data class
% mode: char, optional identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier:
% 'sets' -> selected set
% 'setsContextAdd' -> add a new set
% 'setsContextRename' -> rename the current set
% 'setsContextRemove' -> remove the current set

arguments (Input)
    obj controllers.MibController
    hWidget {mustBeA(hWidget, {'matlab.ui.container.Menu', 'matlab.ui.control.DropDown', 'matlab.ui.control.Button'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.MenuSelectedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ButtonPushedData'})}
    mode char = ''
end

if isempty(mode); mode = hWidget.Tag; end

% define BatchOpt structure for mibModel callback
BatchOpt = struct;

noSets = numel(obj.mibModel.Set.setNames); % current number of sets

switch mode
    case 'sets'
        %fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
        BatchOpt.Mode = {'Select set'}; 
        BatchOpt.SetName = obj.view.handles.panels.datasets.handles.sets.Value;
    case 'setsContextAdd'
        BatchOpt.Mode = {'Add set'}; % define the mode for obj.mibModel.datasetsSetsOps
        % get the name for a new set
        defAns = sprintf('Set %d', noSets+1);
        options.ParentFigure = obj.view.gui;
        options.IconWidth = 48;
        answer = utils.mibInputSingleDlg(obj.mibPath, 'Enter a new set name:', defAns, 'Add set', options);
        if isempty(answer); return; end
        BatchOpt.SetName = answer;
        %fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
    case 'setsContextRename'
        BatchOpt.Mode = {'Rename set'};  % define the mode for obj.mibModel.datasetsSetsOps
        % get new name for the set
        defAns = obj.mibModel.Set.setNames{obj.mibModel.Set.setId};
        options.ParentFigure = obj.view.gui;
        options.IconWidth = 48;
        answer = utils.mibInputSingleDlg(obj.mibPath, 'Enter a new set name:', defAns, 'Add set', options);
        if isempty(answer); return; end
        BatchOpt.SetName = answer;
        %fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
    case 'setsContextRemove'
        htmlContent = '<html><body><h3>Important Message</h3><p>This is a message box with <b>rich text</b> formatting.</p><ul><li>Item 1</li><li>Item 2</li></ul></body></html>';
        dlgTitle = 'Information';
        options.MsgBoxOnly = true;
        options.Title = 'Please Read';
        options.WindowWidth = 600;
        options.OkBtnText = 'OK';
        options.Icon = 'question';
        options.DoNotShowAgain = true;
        options.ParentFigure = obj.view.gui;
        options.DoNotShowAgainText = 'Do not show this again';
        [answer, selIndex, dontShow] = utils.mibInputUniversalDlg(obj.mibPath, {}, {htmlContent}, dlgTitle, options);


        fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
        BatchOpt.Mode = {'Remove set'}; 
    otherwise
        error('MibController.datasetsSetsOps_Callbacks: this option (%s) is not implemented!\n', mode)
end
% call method of MibModel class
obj.mibModel.datasetsSetsOps(BatchOpt);