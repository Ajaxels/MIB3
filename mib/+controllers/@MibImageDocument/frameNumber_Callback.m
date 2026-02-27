function frameNumber_Callback(obj, parameter, BatchOptIn)
% function frameNumber_Callback(obj, parameter, BatchOptIn)
% Callback for changing the time points of the dataset by entering a new time value
%
% Handles input from the frame number edit box in the MIB image document
% view. Validates and clamps the requested frame number, then delegates
% the actual frame update to frameNumberSlider_Callback. Also supports
% MIB batch processing via the BatchOpt mechanism.
%
% Syntax:
%   obj.frameNumber_Callback()
%   obj.frameNumber_Callback(parameter)
%   obj.frameNumber_Callback(parameter, BatchOptIn)
%   obj.frameNumber_Callback(parameter, NaN)   % returns batch settings
%
% Inputs:
%   obj        - MibImageDocument controller instance (handle)
%   parameter  - (optional) numeric. The requested frame number.
%                If omitted or empty, reads from obj.handles.frameNumber.Value.
%   BatchOptIn - (optional) struct or NaN.
%                  struct : fields are merged into the default BatchOpt,
%                           allowing programmatic/batch override of FrameNumber.
%                  NaN    : triggers 'SyncBatch' event and returns immediately,
%                           sending current BatchOpt settings to mibBatchController.
%                  Omitted: defaults to an empty struct (interactive mode).
%
% BatchOpt Fields:
%   FrameNumber          - char. Requested frame number as a string.
%                          Use '0' to jump to the last time point.
%   mibBatchSectionName  - char. UI section label: 'Panel -> Image view'
%   mibBatchActionName   - char. Batch action label: 'Change frame/time number'
%   mibBatchTooltip      - struct. Tooltips for each BatchOpt field.
%
% Frame Number Clamping:
%   - value == 0 or value > maxTime  →  clamped to maxTime (last frame)
%   - value < 0                      →  clamped to 1       (first frame)
%   - otherwise                      →  used as-is
%
% Notes:
%   - This function is the edit-box counterpart to frameNumberSlider_Callback.
%     It validates input, then syncs the slider value and calls
%     frameNumberSlider_Callback() to apply the change to the model.
%   - In DeveloperMode, a diagnostic message is printed to the command window.
%   - If BatchOptIn is not a struct and not NaN, an error dialog is shown.
%
% MVC Role:
%   Controller (MibImageDocument) — processes View input (edit box),
%   updates the View (slider), and triggers a Model update via
%   frameNumberSlider_Callback.
%
% Example:
%   % Programmatically navigate to frame 5:
%   obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumber_Callback(5, struct());
%
%   % Jump to the last frame using the shorthand value 0:
%   obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumber_Callback(0, struct());
%
%   % Query available batch settings:
%   obj.cImageDoc{obj.mibModel.Sets.selectedSet}.frameNumber_Callback([], NaN);

if nargin < 3; BatchOptIn = struct; end
if nargin < 2; parameter = []; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibImageDocument.frameNumber_Callback: "obj.cImageDoc{%d}.handles.frameNumber" ->slices changed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet);
end

if isempty(parameter); parameter = obj.handles.frameNumber.Value; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.FrameNumber = num2str(parameter);

BatchOpt.mibBatchSectionName = 'Panel -> Image view';
BatchOpt.mibBatchActionName = 'Change frame/time number';

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.FrameNumber = sprintf('Enter a new frame number; use 0 to show the last time point of the dataset');

if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)     % when varargin{2} == NaN return possible settings
        % trigger syncBatch event to send BatchOptInOut to mibBatchController
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);
    else
        errorOpts.mibPath = obj.mibModel.mibPath;
        errorOpts.WindowHeight = 150;
        utils.dlgs.showErrorDialog(obj.view.gui, sprintf('A structure as the 3rd parameter is required!'), 'Error', 'Error in MibImageDocument.frameNumber_Callback', '', errorOpts);
    end
    return;
else
    % add/update BatchOpt with the provided fields in BatchOptIn
    % combine fields from input and default structures
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

if nargin > 1
    maxTime = obj.mibModel.I{obj.mibModel.id}.image.time;
    newFrameNumber = str2double(BatchOpt.FrameNumber);
    if newFrameNumber == 0 || newFrameNumber > maxTime
        newFrameNumber = maxTime;
    elseif newFrameNumber < 0
        newFrameNumber = 1;
    end
    BatchOpt.FrameNumber = num2str(newFrameNumber);
    obj.handles.frameNumberSlider.Value = newFrameNumber;
end

obj.handles.frameNumberSlider.Value = str2double(BatchOpt.FrameNumber);
obj.frameNumberSlider_Callback();
end