function zoomEdit_Callback(obj, recenterSwitch, BatchOptIn)
% ZOOMEDIT_CALLBACK - Callback for zoom editbox control in status bar to change image magnification.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.zoomEdit_Callback()
%      obj.zoomEdit_Callback(recenterSwitch, BatchOptIn)
%
% Handles magnification changes triggered by ``obj.view.handles.status.zoom`` UI control.
% Supports direct UI interaction and batch processing mode.
%
% Input Arguments:
%   - **recenterSwitch** *(optional)* — [logical] whether to recenter image after zoom (default: ``false``)
%   - **BatchOptIn** *(optional)* — [struct|NaN] batch processing options. When ``NaN``, triggers ``'SyncBatch'`` event and returns defaults:
%
%     - ``.Mode`` — [cell] magnification mode:
%
%       - ``'Set magnification'`` — (default)
%       - ``'Fit to screen'``
%       - ``'100%'``
%       - ``'Zoom in'``
%       - ``'Zoom out'``
%
%     - ``.MagnificationValue`` — [char] target magnification in percent (used when Mode is ``'Set magnification'``)
%
% **Example 1** — Set magnification to 50%:
%
%   .. code-block:: matlab
%
%      BatchOpt.Mode = {'Set magnification'};
%      BatchOpt.MagnificationValue = '50';
%      obj.zoomEdit_Callback([], BatchOpt);
%
% **Example 2** — Fit image to screen:
%
%   .. code-block:: matlab
%
%      BatchOpt.Mode = {'Fit to screen'};
%      obj.zoomEdit_Callback([], BatchOpt);
%
% **Example 3** — Query batch options (returns defaults via SyncBatch event):
%
%   .. code-block:: matlab
%
%      obj.zoomEdit_Callback([], NaN);
%

arguments
    obj controllers.MibStatusBar
    recenterSwitch logical = []
    BatchOptIn {mustBeA(BatchOptIn, ["struct", "double"])} = struct()
end

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    devText = 'obj.mibController.cStatus.handles.zoom';
    %if ~isempty(fieldnames(BatchOptIn)); devText = BatchOptIn.Mode; end
    fprintf('controllers.MibStatusBar.zoomEdit_Callback: pressed %s\n', devText);
end

% %% Focus the zoom edit control when called from UI (no BatchOptIn provided)
if isstruct(BatchOptIn) && isempty(fieldnames(BatchOptIn))
    focus(obj.view.handles.panels.dirContentsPanel.Figure); % remove focus from hObject
end
if isempty(recenterSwitch); recenterSwitch = false; end

if recenterSwitch
    % With multiple documents selectedSet can be stale when the cursor is over
    % a document that is not the currently "active" set. Detect the document the
    % cursor is physically over before doing anything document-specific
    % (CurrentPoint, convertMouseToDataCoordinates, moveView, centerCursorInAxes).
    numDocs = numel(obj.mibController.cImageDoc);
    if numDocs > 1
        % isInsideAxes is set by each document's own mouse-motion handler, so it
        % is correct regardless of docked/floating and tabbed/split layout (the
        % previous docEdge width heuristic was wrong for stacked tabs and always
        % selected doc 1).
        detectedDocIdx = obj.mibModel.Sets.selectedSet;
        for iDoc = 1:numDocs
            if obj.mibController.cImageDoc{iDoc}.isInsideAxes
                detectedDocIdx = iDoc;
                break;
            end
        end
        if detectedDocIdx ~= obj.mibModel.Sets.selectedSet
            obj.mibModel.Sets.selectedSet = detectedDocIdx;
            obj.mibModel.id = obj.mibModel.Sets.selectedDataset(detectedDocIdx) + ...
                (detectedDocIdx - 1) * obj.mibModel.Sets.datasetsInSet;
        end
    end

    xy = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.CurrentPoint;

    [xy2(1),xy2(2)] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown');
    xy2 = ceil(xy2);
end

newZoomValue = obj.view.handles.status.zoom.Value;
newZoomValue = newZoomValue(1:end-1);    % strip trailing ' %'

%% Define default BatchOpt structure
BatchOpt = struct();
BatchOpt.Mode = {'Set magnification'};
BatchOpt.Mode{2} = {'Set magnification', 'Fit to screen', '100%', 'Zoom in', 'Zoom out'};
BatchOpt.MagnificationValue = newZoomValue;
BatchOpt.mibBatchSectionName = 'Quick access bar';
BatchOpt.mibBatchActionName  = 'Change magnification';

% Tooltips shown in the batch processing GUI
BatchOpt.mibBatchTooltip.Mode = 'Select a magnification mode';
BatchOpt.mibBatchTooltip.MagnificationValue = '[Set magnification] Desired magnification value in %';

%% Handle batch mode: NaN input triggers SyncBatch event
if ~isstruct(BatchOptIn)
    if isnan(BatchOptIn)
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);
    else
        errorOpts.mibPath = obj.mibModel.mibPath;
        errorOpts.WindowHeight = 150;
        utils.dlgs.showErrorDialog(obj.view.gui, 'A structure is required as the input parameter!', 'Wrong function input', 'Error in MibStatusBar.zoomEdit_Callback', '', errorOpts);
    end
    return;
end

% Merge provided BatchOptIn fields into the default BatchOpt
BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);

if recenterSwitch && ismember(BatchOpt.Mode{1}, {'Zoom in', 'Zoom out'})
    obj.mibModel.I{obj.mibModel.id}.moveView(xy2(1), xy2(2));
    obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.centerCursorInAxes(true);  % cursor is over the axes
end

%% Execute the selected magnification mode
switch BatchOpt.Mode{1}
    case 'Fit to screen'
        Options.mode = 'fitToScreen';
        eventdata = core.ToggleEventData(Options);
        notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
        notify(obj.mibModel, 'ShowImage');
        obj.updatePyramidInfoLabel();
        return;
    case '100%'
        BatchOpt.MagnificationValue = '100';
    case 'Zoom in'
        BatchOpt.MagnificationValue = num2str(str2double(newZoomValue) * 2);
    case 'Zoom out'
        BatchOpt.MagnificationValue = num2str(str2double(newZoomValue) / 2);
end

%% Apply the magnification value
zoom = str2double(BatchOpt.MagnificationValue);
if isnan(zoom)
    zoom = 100;
    obj.view.handles.status.zoom.Value = '100 %';
end

newMagFactor = 100 / zoom;

Options.mode = 'zoom';
Options.newMagFactor = newMagFactor;
eventdata = core.ToggleEventData(Options);
notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
notify(obj.mibModel, 'ShowImage');
obj.updatePyramidInfoLabel();

end
