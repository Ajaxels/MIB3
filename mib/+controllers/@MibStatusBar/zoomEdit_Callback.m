function zoomEdit_Callback(obj, recenterSwitch, BatchOptIn)
% function zoomEdit_Callback(obj, recenterSwitch, BatchOptIn)
% Callback for the zoom editbox control in the status bar to change image magnification.
%
% Syntax:
%   obj.mibZoomEdit_Callback();
%   obj.mibZoomEdit_Callback([], BatchOptIn);
%   obj.mibZoomEdit_Callback(BatchOptIn);
%
% Description:
%   Handles magnification changes triggered by the 'obj.view.handles.status.zoom' UI control.
%   Supports direct UI interaction and batch processing mode.
%
% Parameters:
%   recenterSwitch: [@em optional], defines whether the image should be recentered after zoom/unzoom. Default=0
%   BatchOptIn - [struct|NaN, optional] Batch processing options.
%     When NaN, triggers a 'SyncBatch' event and returns default options.
%     Fields:
%       .Mode -[cell] Magnification mode. Options:
%           - 'Set magnification' (default),
%           - 'Fit to screen',
%           - '100%',
%           - 'Zoom in',
%           - 'Zoom out'
%       .MagnificationValue - [string] Target magnification value in percent,
%                             used when Mode is 'Set magnification'
%
% Example 1 - Set magnification to 50%:
%   BatchOpt.Mode = {'Set magnification'};
%   BatchOpt.MagnificationValue = '50';
%   obj.mibZoomEdit_Callback(BatchOpt);
%
% Example 2 - Fit image to screen:
%   BatchOpt.Mode = {'Fit to screen'};
%   obj.mibZoomEdit_Callback(BatchOpt);
%
% Example 3 - Query batch options (returns defaults via SyncBatch event):
%   obj.mibZoomEdit_Callback(NaN);
%
% Updates:
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

    % get panel positions from the layout
    leftPanelW = 0;
    if isfield(obj.view.gui.Layout.panelLayout, 'left')
        leftPanelW = obj.view.gui.Layout.panelLayout.left.freeDimension;
        if obj.view.gui.Layout.panelLayout.left.collapsed
            leftPanelW = 0;
        end
    end

    bottomPanelH = 0;
    if isfield(obj.view.gui.Layout.panelLayout, 'bottom')
        bottomPanelH = obj.view.gui.Layout.panelLayout.bottom.freeDimension;
        if obj.view.gui.Layout.panelLayout.bottom.collapsed
            bottomPanelH = 0;
        end
    end

    winBounds = obj.view.gui.WindowBounds;   % [left, top, width, height], top-left origin, virtual desktop
    posAxes = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.Position;

    % original center calculation in virtual-desktop top-based coordinates
    screenX = winBounds(1) + leftPanelW + posAxes(1) + posAxes(3)/2;
    screenY = winBounds(2) + winBounds(4) - bottomPanelH - posAxes(2) - posAxes(4)/2;

    scaling = obj.mibModel.preferences.System.GUI.systemscaling;
    monPos = get(groot, 'MonitorPositions');   % [x y width height]

    % select monitor from X position
    idx = find(screenX >= monPos(:,1) & screenX <= (monPos(:,1) + monPos(:,3) - 1), 1, 'first');
    if isempty(idx)
        [~, idx] = min(abs(screenX - (monPos(:,1) + monPos(:,3)/2)));
    end

    % convert top-based virtual Y to monitor-local Y, then to root PointerLocation Y
    monitorY0   = monPos(idx,2);
    monitorH    = monPos(idx,4);
    monitorTop  = monitorY0 + monitorH - 1;

    pointerX = round((screenX + 8) * scaling);
    pointerY = round((monitorTop - (screenY - monitorY0) + 26) * scaling);

    % % --- DIAGNOSTIC: remove after fixing ---
    % fprintf('=== zoomEdit_Callback recenter diagnostic ===\n');
    % fprintf('winBounds: [%.1f, %.1f, %.1f, %.1f]\n', winBounds);
    % fprintf('posAxes: [%.1f, %.1f, %.1f, %.1f]\n', posAxes);
    % fprintf('leftPanelW=%.1f bottomPanelH=%.1f\n', leftPanelW, bottomPanelH);
    % fprintf('screenX=%.1f screenY=%.1f\n', screenX, screenY);
    % fprintf('scaling=%.3f\n', scaling);
    % fprintf('monitor index=%d\n', idx);
    % fprintf('monitorY0=%.1f monitorH=%.1f monitorTop=%.1f\n', monitorY0, monitorH, monitorTop);
    % fprintf('pointerX=%.1f pointerY=%.1f\n', pointerX, pointerY);
    % fprintf('MonitorPositions:\n'); disp(monPos);
    % fprintf('current PointerLocation before set: [%.1f, %.1f]\n', groot().PointerLocation);
    % % --- END DIAGNOSTIC ---

    gr = groot();
    gr.PointerLocation = [pointerX, pointerY];
end

%% Execute the selected magnification mode
switch BatchOpt.Mode{1}
    case 'Fit to screen'
        Options.mode = 'fitToScreen';
        eventdata = core.ToggleEventData(Options);
        notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
        notify(obj.mibModel, 'ShowImage');
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

end
