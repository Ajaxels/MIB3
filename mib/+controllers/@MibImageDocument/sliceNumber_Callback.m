function sliceNumber_Callback(obj, parameter, BatchOptIn)
% SLICENUMBER_CALLBACK - Callback for changing the slices of a 3D dataset by entering a new slice number.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.sliceNumber_Callback()
%      obj.sliceNumber_Callback(parameter)
%      obj.sliceNumber_Callback(parameter, BatchOptIn)
%
% Input Arguments:
%   - **parameter** *(optional)* - [numeric] slice number; when provided:
%
%     - ``0`` - set dataset to last slice (also used as callback for ``handles.lastSlice``)
%     - ``1`` - set dataset to first slice (also used as callback for ``handles.firstSlice``)
%     - other numeric value - slice number to display
%
%   - **BatchOptIn** *(optional)* - [struct|NaN] batch processing control
%     When ``NaN``, returns structure with default options via ``'SyncBatch'`` event:
%
%     - ``.SliceNumber`` - [char] slice number to show (use ``'0'`` for last slice)
%     - ``.mibBatchSectionName`` - [char] UI section label: ``'Panel -> Image view'``
%     - ``.mibBatchActionName`` - [char] batch action label: ``'Change slice number'``
%     - ``.mibBatchTooltip`` - [struct] tooltips for each field
%
% Output Arguments:
%   (none)
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

