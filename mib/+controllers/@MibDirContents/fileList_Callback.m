function fileList_Callback(obj, hWidget, hData)
% function fileList_Callback(obj, hWidget, hData)
% callback for double click on a filename in obj.handles.panels.dirContents.handles.fileList
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibDirContents
    hWidget matlab.ui.control.ListBox
    hData {matlab.ui.eventdata.DoubleClickedData, matlab.ui.eventdata.ClickedData}
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContents.fileList_Callback: Double clicked on: obj.handles.panels.dirContents.handles.fileList\n');
end

% Persistent variables to protect mibModel.id across Clicked/DoubleClicked.
% The Clicked handler's drawnow processes the UI event queue, which may
% include AppContainer PropertyChanged (LastSelected) events that trigger
% listener_appStateChanged -> setsOps_Callbacks -> datasetsSetsOps and
% corrupt mibModel.id / Sets.selectedSet.  The DoubleClicked callback can
% fire INSIDE that drawnow, so we save the correct id here for the
% DoubleClicked handler to restore before calling loadImages.
persistent savedId savedSelectedSet

% single click to select files
if strcmp(hData.EventName, 'Clicked')
    % Note! This does not handle Ctrl+A selection of all files; that case
    % is handled in MibDirContents.fileList_ContextMenu
    % remove [.] and [..]
    % Compute id from selectedSet (reliable) rather than reading mibModel.id
    % directly, because mouse motion over the other document in split-panel
    % mode can silently change mibModel.id without updating selectedSet.
    savedSelectedSet = obj.mibModel.Sets.selectedSet;
    savedId = obj.mibModel.Sets.selectedDataset(savedSelectedSet) + ...
        (savedSelectedSet - 1) * obj.mibModel.Sets.datasetsInSet;
    drawnow; % needed, otherwise the Shift+click does not give the list of the selected files
    obj.mibModel.selectedFiles = hWidget.Value(~ismember(hWidget.Value, {'[.]','[..]'}));
    return;
end

% require the double click to proceed further
if ~strcmp(hData.EventName, 'DoubleClicked'); return; end

% Restore mibModel.id and Sets.selectedSet if the Clicked handler's
% drawnow processed AppContainer events that spuriously switched the
% active set (common in split-panel mode when Dir Contents is adjacent
% to a different document panel).
if ~isempty(savedId)
    obj.mibModel.id = savedId;
    obj.mibModel.Sets.selectedSet = savedSelectedSet;
    savedId = []; savedSelectedSet = [];
end

% get the entry upon the double clicked
filename = hWidget.Value{1};

if strcmp(filename, '[.]')
    if ispc()
        dirname = fileparts(obj.mibModel.currentDirectory);
        obj.mibModel.currentDirectory = dirname(1:3);
    else
        obj.mibModel.currentDirectory = '/';
    end
    obj.mibController.cDirContents.updateFileList_Callback();
    obj.mibController.cStatus.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
elseif strcmp(filename, '[..]')
    [dirname, oldDir] = fileparts(obj.mibModel.currentDirectory);
    if ~isequal(dirname, obj.mibModel.currentDirectory)
        obj.mibModel.currentDirectory = dirname;
        obj.mibController.cDirContents.updateFileList_Callback(['[', oldDir, ']']);  % the squares are required because the directory is reported as [dirname] in obj.updateFilelist function
    end
    obj.mibController.cStatus.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
elseif filename(1) == '['
    dirname = fullfile(obj.mibModel.currentDirectory, filename(2:end-1));
    obj.mibModel.currentDirectory = dirname;
    obj.mibController.cDirContents.updateFileList_Callback();
    obj.mibController.cStatus.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
else
    obj.mibModel.loadImages('Combine datasets');
    focus(obj.view.handles.panels.dirContentsPanel.Figure); % remove focus from hObject
end


end
