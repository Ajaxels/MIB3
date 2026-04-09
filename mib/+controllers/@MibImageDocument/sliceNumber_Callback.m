function sliceNumber_Callback(obj, parameter, BatchOptIn)
% function sliceNumber_Callback(obj, parameter, BatchOptIn)
% Callback for changing the slices of the 3D dataset by entering a new slice number
% 
% Parameters:
% parameter: [@b optional], when provided:
% @li 0 - set dataset to the last slice, used as a callback for obj.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.lastSlice
% @li 1 - set dataset to the first slice, used as a callback for obj.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.firstSlice
% BatchOptIn: a structure for batch processing mode, when NaN return
%   a structure with default options via "syncBatch" event
% @li .SliceNumber -> string, slice number to show
%
% Return values:
%

if nargin < 3; BatchOptIn = struct; end
if nargin < 2; parameter = []; end

% if obj.mibModel.preferences.System.DeveloperMode
%     fprintf('controllers.MibImageDocument.sliceNumber_Callback: "obj.cImageDoc{%d}.handles.sliceNumber" ->slices changed (obj.mibModel.Sets.selectedSet)\n', obj.mibModel.Sets.selectedSet);
% end

if isempty(parameter); parameter = obj.handles.sliceNumber.Value; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.SliceNumber = num2str(parameter);

BatchOpt.mibBatchSectionName = 'Panel -> Image view';
BatchOpt.mibBatchActionName = 'Change slice number';

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.SliceNumber = sprintf('Enter a new slice number; use 0 to show the last slice of the dataset');

%%
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)     % when varargin{2} == NaN return possible settings
        % trigger syncBatch event to send BatchOptInOut to mibBatchController
        eventdata = ToggleEventData(BatchOpt);
        notify(obj.mibModel, 'SyncBatch', eventdata);
    else
        errorOpts.mibPath = obj.mibModel.mibPath;
        errorOpts.WindowHeight = 150;
        utils.dlgs.showErrorDialog(obj.view.gui, sprintf('A structure as the 3rd parameter is required!'), 'Error', 'Error in MibImageDocument.sliceNumber_Callback', '', errorOpts);
    end
    return;
else
    % add/update BatchOpt with the provided fields in BatchOptIn
    % combine fields from input and default structures
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

if nargin > 1
    maxVal = obj.mibModel.I{obj.mibModel.id}.image.dim_yxzct(obj.mibModel.I{obj.mibModel.id}.orientation);
    newSliceNumber = str2double(BatchOpt.SliceNumber);

    if newSliceNumber == 0
        newSliceNumber = maxVal;
    else
        if newSliceNumber > maxVal
            newSliceNumber = maxVal;
        elseif newSliceNumber < 0
            newSliceNumber = 1;
        end
    end
    BatchOpt.SliceNumber = num2str(newSliceNumber);
    obj.handles.sliceNumber.Value = newSliceNumber;
end

obj.handles.sliceNumberSlider.Value = str2double(BatchOpt.SliceNumber);
obj.sliceNumberSlider_Callback();
end

