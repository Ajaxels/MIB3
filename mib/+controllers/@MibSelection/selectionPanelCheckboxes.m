function selectionPanelCheckboxes(obj, BatchOptIn)
% SELECTIONPANELCHECKBOXES - Read or modify checkbox states and color-channel dropdown in Selection panel.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectionPanelCheckboxes(BatchOptIn)
%
% Batch-compatible method for the Selection and View Settings panel. Checkbox fields accept
% three string values: ``'Unchanged'`` (leave as-is, default), ``'Checked'`` (enable feature),
% or ``'Unchecked'`` (disable feature). ColorChannel: empty string = do not modify;
% ``'0'`` = All channels; ``'1'``, ``'2'``, etc. = individual channels.
%
% Input Arguments:
%   - **BatchOptIn** - [struct] batch options structure with fields:
%
%     - ``.Apply3D`` - [cell] checkbox state (``'Unchanged'``, ``'Checked'`` or ``'Unchecked'``) - Apply-in-3D checkbox
%     - ``.AutoFillSelection`` - [cell] checkbox state - Auto-fill checkbox
%     - ``.Difference`` - [cell] checkbox state - Difference mode checkbox (erode/dilate)
%     - ``.LutColors`` - [cell] checkbox state - LUT colors checkbox
%     - ``.ShowModel`` - [cell] checkbox state - Show model overlay checkbox
%     - ``.ShowMask`` - [cell] checkbox state - Show mask overlay checkbox
%     - ``.ShowAnnotations`` - [cell] checkbox state - Show annotations/measurements checkbox
%     - ``.HideImage`` - [cell] checkbox state - Hide image checkbox
%     - ``.OnFly`` - [cell] checkbox state - On-fly contrast stretch checkbox
%     - ``.ColorChannel`` - [char] channel selection: ``''`` (do not modify), ``'0'`` (All channels), ``'1'``/``'2'``/… (specific channels)
%
% **Example 1** - Enable Apply-in-3D mode:
%
%   .. code-block:: matlab
%
%      BatchOptIn.Apply3D = {'Checked'};
%      obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
%
% **Example 2** - Show model overlay and switch to color channel 1:
%
%   .. code-block:: matlab
%
%      BatchOptIn.ShowModel    = {'Checked'};
%      BatchOptIn.ColorChannel = '1';
%      obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
%
% **Example 3** - Hide image and show mask only (mask QC):
%
%   .. code-block:: matlab
%
%      BatchOptIn.HideImage  = {'Checked'};
%      BatchOptIn.ShowMask   = {'Checked'};
%      BatchOptIn.ShowModel  = {'Unchecked'};
%      obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
%
% **Example 4** - Enable LUT colors and on-fly contrast stretch:
%
%   .. code-block:: matlab
%
%      BatchOptIn.LutColors = {'Checked'};
%      BatchOptIn.OnFly     = {'Checked'};
%      obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
%
% **Example 5** - Reset all display flags (clean-slate view):
%
%   .. code-block:: matlab
%
%      BatchOptIn.ShowModel       = {'Unchecked'};
%      BatchOptIn.ShowMask        = {'Unchecked'};
%      BatchOptIn.ShowAnnotations = {'Unchecked'};
%      BatchOptIn.HideImage       = {'Unchecked'};
%      BatchOptIn.LutColors       = {'Unchecked'};
%      BatchOptIn.OnFly           = {'Unchecked'};
%      obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
%
%
%   Example 6 - Populate the Batch Processing parameter table with default options::
%
%     % Populate the Batch Processing parameter table with default options
%     obj.mibController.cSelection.selectionPanelCheckboxes(NaN);
%

% Updates
%

if nargin < 2; BatchOptIn = struct(); end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
availableOptions = {'Unchanged', 'Checked', 'Unchecked'};

BatchOpt.Apply3D         = {'Unchanged'}; BatchOpt.Apply3D{2}         = availableOptions;
BatchOpt.AutoFillSelection        = {'Unchanged'}; BatchOpt.AutoFillSelection{2}        = availableOptions;
BatchOpt.Difference      = {'Unchanged'}; BatchOpt.Difference{2}      = availableOptions;
BatchOpt.LutColors       = {'Unchanged'}; BatchOpt.LutColors{2}       = availableOptions;
BatchOpt.ShowModel       = {'Unchanged'}; BatchOpt.ShowModel{2}       = availableOptions;
BatchOpt.ShowMask        = {'Unchanged'}; BatchOpt.ShowMask{2}        = availableOptions;
BatchOpt.ShowAnnotations = {'Unchanged'}; BatchOpt.ShowAnnotations{2} = availableOptions;
BatchOpt.HideImage       = {'Unchanged'}; BatchOpt.HideImage{2}       = availableOptions;
BatchOpt.OnFly           = {'Unchanged'}; BatchOpt.OnFly{2}           = availableOptions;
BatchOpt.ColorChannel    = '';   % '' = do not modify; '0'=All, '1'=Ch1, etc.

BatchOpt.mibBatchSectionName = 'Panel -> Selection and View Settings';
BatchOpt.mibBatchActionName  = 'Modify parameters';
BatchOpt.mibBatchTooltip.Apply3D         = 'Tweak the state of the "Apply in 3D" checkbox; perform some segmentation tools in 3D';
BatchOpt.mibBatchTooltip.AutoFillSelection        = 'Tweak the state of the "Auto fill" checkbox; autofill selections';
BatchOpt.mibBatchTooltip.Difference      = 'Tweak the state of the "differenceSelection" checkbox (erode/dilate mode); results in selection composed only of difference vs original selection';
BatchOpt.mibBatchTooltip.LutColors       = 'Tweak the state of the "LUT colors" checkbox';
BatchOpt.mibBatchTooltip.ShowModel       = 'Tweak the state of the "Show model" checkbox';
BatchOpt.mibBatchTooltip.ShowMask        = 'Tweak the state of the "Show mask" checkbox';
BatchOpt.mibBatchTooltip.ShowAnnotations = 'Tweak the state of the "Ann/Measure" (annotations) checkbox';
BatchOpt.mibBatchTooltip.HideImage       = 'Tweak the state of the "Hide image" checkbox';
BatchOpt.mibBatchTooltip.OnFly           = 'Tweak the state of the "on-fly" contrast stretch checkbox';
BatchOpt.mibBatchTooltip.ColorChannel    = 'When empty - do not modify; otherwise index of the colour channel to set: 0 = All, 1 = first, 2 = second, etc.';

%% Batch mode check actions
if nargin == 2
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)    % when NaN return default options
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            utils.dlgs.showErrorDialog(obj.view.gui, ...
                'A structure as the 2nd parameter is required!', 'Error');
        end
        return;
    else
        % combine fields from input and default structures
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% Apply changes
% Strip meta-fields so we iterate only over the payload fields.
metaFields = {'mibBatchSectionName', 'mibBatchActionName', 'mibBatchTooltip'};
BatchOpt2  = rmfield(BatchOpt, metaFields);
fieldNames = fieldnames(BatchOpt2);

needRedraw = false;   % set when a display-affecting property changes

for fieldId = 1:numel(fieldNames)
    fieldName = fieldNames{fieldId};
    val       = BatchOpt2.(fieldName);

    if iscell(val)
        % ---- checkbox-type field ----------------------------------------
        if strcmp(val{1}, 'Unchanged'); continue; end
        state = strcmp(val{1}, 'Checked');   % logical true = checked

        switch fieldName
            case 'Apply3D'
                obj.handles.applySegmentationIn3D.Value = state;
                obj.mibModel.applySegmentationIn3D = state;
                
            case 'AutoFillSelection'
                obj.handles.autoFillSelection.Value = state;
                obj.mibModel.autoFillSelection = state;

            case 'DifferenceSelection'
                obj.handles.differenceSelection.Value = state;
                obj.mibModel.differenceSelection = state;
               
            case 'LutColors'
                obj.handles.lutColors.Value = state;
                obj.mibModel.I{obj.mibModel.id}.useLUT = state;
                obj.lutTable_update_fromModel();
                needRedraw = true;

            case 'ShowModel'
                obj.handles.showModel.Value = state;
                obj.mibModel.showModel = state;
                needRedraw = true;

            case 'ShowMask'
                obj.handles.showMask.Value = state;
                obj.mibModel.showMask = state;
                needRedraw = true;

            case 'ShowAnnotations'
                obj.handles.showAnnotations.Value = state;
                obj.mibModel.showAnnotations = state;
                needRedraw = true;

            case 'HideImage'
                obj.handles.hideImage.Value = state;
                obj.mibModel.hideImage = state;
                needRedraw = true;

            case 'OnFly'
                obj.handles.onFly.Value = state;
                obj.mibModel.onFlyImageStretch = state;
                needRedraw = true;
        end

    elseif ischar(val) || isstring(val)
        % ---- string-type field ------------------------------------------
        if isempty(val); continue; end

        switch fieldName
            case 'ColorChannel'
                chIdx    = str2double(val);           % 0 = All, 1 = Ch 1, …
                numItems = numel(obj.handles.colChannel.Items);
                chIdx    = max(0, min(chIdx, numItems - 1));   % clamp
                obj.handles.colChannel.Value = obj.handles.colChannel.Items{chIdx + 1};
                obj.mibModel.I{obj.mibModel.id}.selectedColorChannel = chIdx;
        end
    end
end

if needRedraw
    notify(obj.mibModel, 'ShowImage');
end

%% Notify batch mode
eventdata = core.ToggleEventData(BatchOpt);
notify(obj.mibModel, 'SyncBatch', eventdata);
end
