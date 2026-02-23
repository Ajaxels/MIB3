function setsOps_Callbacks(obj, hWidget, hData, mode)
% function setsOps_Callbacks(obj, hWidget, hData, mode)
% callbacks for press of sets-related widgets in obj.view.handles.panels.activeDataset.handles
% Handles the following widgets:
% - obj.view.handles.panels.activeDataset.handles.sets -> select set
% - obj.view.handles.panels.activeDataset.handles.setsContextRename -> context menu for sets dropdown, rename the selected set
% - obj.view.handles.panels.activeDataset.handles.setsContextAdd -> context menu for sets dropdown, add a new set
% - obj.view.handles.panels.activeDataset.handles.setsContextRemove -> context menu for sets dropdown, remove the selected set
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

% arguments (Input)
%     obj controllers.MibActiveDataset
%     hWidget {mustBeA(hWidget, {'matlab.ui.container.Menu', 'matlab.ui.control.DropDown', 'matlab.ui.control.Button'})}
%     hData {mustBeA(hData, {'matlab.ui.eventdata.MenuSelectedData', 'matlab.ui.eventdata.ValueChangedData', 'matlab.ui.eventdata.ButtonPushedData'})}
%     mode char = ''
% end

if nargin < 4; mode = []; end

if isempty(mode); mode = hWidget.Tag; end

% define BatchOpt structure for mibModel callback
BatchOpt = struct;

noSets = numel(obj.mibModel.Sets.names); % current number of sets

switch mode
    case 'sets'
        %fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
        BatchOpt.Mode = {'Select set'}; 
        BatchOpt.SetName = obj.view.handles.panels.activeDataset.handles.sets.Value;
    case 'setsContextAdd'
        BatchOpt.Mode = {'Add set'}; % define the mode for obj.mibModel.datasetsSetsOps
        BatchOpt.DatasetType = {'Standard'}; % standard dataset type
        % get the name for a new set
        defAns = sprintf('Set %d', noSets+1);
        options.ParentFigure = obj.view.gui;
        options.IconWidth = 48;
        answer = utils.dlgs.mibInputSingleDlg(obj.mibModel.mibPath, 'Enter a new set name:', defAns, 'Add set', options);
        if isempty(answer); return; end
        BatchOpt.SetName = answer;
        %fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
    case 'setsContextRename'
        BatchOpt.Mode = {'Rename set'};  % define the mode for obj.mibModel.datasetsSetsOps
        % get new name for the set
        defAns = obj.mibModel.Sets.names{obj.mibModel.Sets.selectedSet};
        options.ParentFigure = obj.view.gui;
        options.IconWidth = 48;
        answer = utils.dlgs.mibInputSingleDlg(obj.mibModel.mibPath, 'Enter a new set name:', defAns, 'Add set', options);
        if isempty(answer); return; end
        BatchOpt.SetName = answer;
        %fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
    case 'setsContextSort'
        BatchOpt.Mode = {'Sort sets'};  % define the mode for obj.mibModel.datasetsSetsOps
    case 'setsContextRemove'
        selection = uiconfirm(obj.view.gui, ...
            sprintf('!!! Warning !!!\n\nYou are going to remove "%s" from MIB!\nAll datasets from the set will be closed.\n\nAre you sure?', obj.mibModel.Sets.names{obj.mibModel.Sets.selectedSet}), ...
            'Remove set', 'Icon', 'warning', 'DefaultOption', 2);
        if strcmp(selection, 'Cancel'); return; end

        BatchOpt.Mode = {'Remove set'}; 
        % fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
    otherwise
        error('controllers.MibActiveDataset.setsOps_Callbacks: this option (%s) is not implemented!\n', mode);       
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('obj.mibController.cActiveDataset.setsOps_Callbacks (controllers.MibActiveDataset.setsOps_Callbacks) -> %s pressed\n', mode);
end

% call method of MibModel class
obj.mibModel.datasetsSetsOps(BatchOpt);