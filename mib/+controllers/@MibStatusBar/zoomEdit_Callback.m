function zoomEdit_Callback(obj, BatchOptIn)
% function zoomEdit_Callback(obj, BatchOptIn)
% Callback for the mibZoomEdit control to change image magnification.
%
% Syntax:
%   obj.mibZoomEdit_Callback();
%   obj.mibZoomEdit_Callback(BatchOptIn);
%
% Description:
%   Handles magnification changes triggered by the 'obj.view.handles.status.zoom' UI control.
%   Supports direct UI interaction and batch processing mode.
%
% Parameters:
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
    BatchOptIn {mustBeA(BatchOptIn, ["struct", "double"])} = struct()
end

%% Focus the zoom edit control when called from UI (no BatchOptIn provided)
if isempty(fieldnames(BatchOptIn))
    focus(obj.view.handles.panels.dirContentsPanel.Figure); % remove focus from hObject
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

%% Execute the selected magnification mode
switch BatchOpt.Mode{1}
    case 'Fit to screen'
        Options.mode = 'resize';
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
    obj.view.handles.status.zoom.Value = '100%';
end

newMagFactor = 100 / zoom;

Options.mode = 'zoom';
Options.newMagFactor = newMagFactor;
eventdata = core.ToggleEventData(Options);
notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
notify(obj.mibModel, 'ShowImage');

end
