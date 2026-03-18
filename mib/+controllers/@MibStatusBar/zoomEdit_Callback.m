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
%   19.09.2019 - Added batch mode support
%   27.02.2026 - Updated to MIB3 syntax

arguments
    obj controllers.MibStatusBar
    recenterSwitch logical = []
    BatchOptIn {mustBeA(BatchOptIn, ["struct", "double"])} = struct()
end

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibStatusBar.zoomEdit_Callback: pressed %s\n', BatchOptIn.Mode);
end

%% Focus the zoom edit control when called from UI (no BatchOptIn provided)
if isempty(fieldnames(BatchOptIn))
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
BatchOpt.mibBatchSectionName = 'Quick access bar -> Zoom';
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
        leftPanelW   = obj.view.gui.Layout.panelLayout.left.freeDimension;
        if obj.view.gui.Layout.panelLayout.left.collapsed; leftPanelW   = 0; end
    end
    bottomPanelH = 0;
    if isfield(obj.view.gui.Layout.panelLayout, 'bottom')
        bottomPanelH = obj.view.gui.Layout.panelLayout.bottom.freeDimension;
        if obj.view.gui.Layout.panelLayout.bottom.collapsed; bottomPanelH = 0; end
    end
    
    

    winBounds = obj.view.gui.WindowBounds;   % % main GUI position, [left, top, width, height], top-left origin
    posAxes = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.Position;  % image view axes position, [left, bottom, width, height], bottom-left origin within document

    % screenX: window left + left panel + axes left offset + half axes width
    screenX = winBounds(1) + leftPanelW + posAxes(1) + posAxes(3)/2;

    % screenY: window top + window height - bottom panel - axes bottom offset - half axes height
    % (posAxes y is from document bottom upward, so invert within document height)
    screenY = winBounds(2) + winBounds(4) - bottomPanelH - posAxes(2) - posAxes(4)/2;

    % flip the the y-axis and scale depending on the system scaling factor
    scaling = obj.mibModel.preferences.System.GUI.systemscaling;
    screenSize = get(0, 'ScreenSize');
    pointerX = (screenX+8) * scaling;  % 8 pixels is correction due to some margin
    pointerY = (screenSize(4) - screenY + 26) * scaling;  % 26 pixels is correction due to some margin and the status bar height

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
