function setsOps_Callbacks(obj, hWidget, hData, mode)
% SETSOPS_CALLBACKS - Callback for dataset set operations (add, rename, remove, select).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.setsOps_Callbacks(hWidget, hData, mode)
%
% Handles dataset set operations triggered by the sets dropdown and context menu items in the
% Datasets panel. Supports add, rename, remove, select, and sort operations.
%
% Input Arguments:
%   - **hWidget** - [matlab.ui.container.Menu | matlab.ui.control.DropDown | matlab.ui.control.Button] handle to the widget that triggered the callback
%   - **hData** - [matlab.ui.eventdata.MenuSelectedData | matlab.ui.eventdata.ValueChangedData | matlab.ui.eventdata.ButtonPushedData] event data from the widget
%   - **mode** - *(optional)* [char] operation mode identifier; when empty or missing, ``hWidget.Tag`` is used:
%
%     - ``'sets'`` - change the active dataset set
%     - ``'setsContextAdd'`` - add a new dataset set
%     - ``'setsContextRename'`` - rename the currently active set
%     - ``'setsContextSort'`` - sort dataset sets
%     - ``'setsContextRemove'`` - remove the currently active set
%
% Output Arguments:
%   None
%
% See Also:
%    ``models.MibModel.datasetsSetsOps``
%

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
        options.IconWidth = 48;
        options.mibPath = obj.mibModel.mibPath;
        answer = utils.dlgs.inputSingleDlg(obj.view.gui, 'Enter a new set name:', defAns, 'Add set', options);
        if isempty(answer); return; end
        BatchOpt.SetName = answer;
        %fprintf('obj.controller.datasetsSetsOps_Callbacks -> %s pressed\n', hWidget.Tag);
    case 'setsContextRename'
        BatchOpt.Mode = {'Rename set'};  % define the mode for obj.mibModel.datasetsSetsOps
        % get new name for the set
        defAns = obj.mibModel.Sets.names{obj.mibModel.Sets.selectedSet};
        options.ParentFigure = obj.view.gui;
        options.IconWidth = 48;
        options.mibPath = obj.mibModel.mibPath;
        answer = utils.dlgs.inputSingleDlg(obj.view.gui, 'Enter a new set name:', defAns, 'Add set', options);
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
