function selectionPanelCheckboxes(obj, BatchOptIn)
% function selectionPanelCheckboxes(obj, BatchOptIn)
% Batch-compatible method to read or modify the state of checkboxes and
% the colour-channel dropdown of the Selection and View Settings panel.
%
% Each checkbox field accepts one of three string values:
%   'Unchanged' — leave the widget as-is (default for all checkboxes)
%   'Checked'   — tick the checkbox / enable the feature
%   'Unchecked' — un-tick the checkbox / disable the feature
%
% Setting ColorChannel leaves the dropdown at its current value when the
% field is empty; otherwise supply a numeric string: '0' = All channels,
% '1' = first channel, '2' = second channel, and so on.
%
% Parameters:
% BatchOptIn: [@em optional] a structure for batch processing mode; when NaN,
%   returns a structure with default options via the "SyncBatch" event
% @li .Apply3D        - cell string, {'Unchanged','Checked','Unchecked'} — Apply-in-3D checkbox
% @li .AutoFillSelection       - cell string, {'Unchanged','Checked','Unchecked'} — Auto-fill checkbox
% @li .Difference     - cell string, {'Unchanged','Checked','Unchecked'} — Difference mode checkbox (erode/dilate)
% @li .LutColors      - cell string, {'Unchanged','Checked','Unchecked'} — LUT colors checkbox
% @li .ShowModel      - cell string, {'Unchanged','Checked','Unchecked'} — Show model overlay checkbox
% @li .ShowMask       - cell string, {'Unchanged','Checked','Unchecked'} — Show mask overlay checkbox
% @li .ShowAnnotations - cell string, {'Unchanged','Checked','Unchecked'} — Show annotations/measurements checkbox
% @li .HideImage      - cell string, {'Unchanged','Checked','Unchecked'} — Hide image checkbox
% @li .OnFly          - cell string, {'Unchanged','Checked','Unchecked'} — On-fly contrast stretch checkbox
% @li .ColorChannel   - string, '' = do not modify; '0' = All channels, '1' = Ch 1, etc.
%
% Return values:
% (none)
%
%|
% @b Examples:
% @code
% % Enable Apply-in-3D mode
% BatchOptIn.Apply3D = {'Checked'};
% obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
% @endcode
%
% @code
% % Show model overlay and switch to colour channel 1
% BatchOptIn.ShowModel     = {'Checked'};
% BatchOptIn.ColorChannel  = '1';
% obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
% @endcode
%
% @code
% % Hide image and show mask only (e.g. for mask QC)
% BatchOptIn.HideImage  = {'Checked'};
% BatchOptIn.ShowMask   = {'Checked'};
% BatchOptIn.ShowModel  = {'Unchecked'};
% obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
% @endcode
%
% @code
% % Turn on LUT colors and on-fly contrast stretch simultaneously
% BatchOptIn.LutColors = {'Checked'};
% BatchOptIn.OnFly     = {'Checked'};
% obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
% @endcode
%
% @code
% % Reset all display flags to off (clean-slate view)
% BatchOptIn.ShowModel       = {'Unchecked'};
% BatchOptIn.ShowMask        = {'Unchecked'};
% BatchOptIn.ShowAnnotations = {'Unchecked'};
% BatchOptIn.HideImage       = {'Unchecked'};
% BatchOptIn.LutColors       = {'Unchecked'};
% BatchOptIn.OnFly           = {'Unchecked'};
% obj.mibController.cSelection.selectionPanelCheckboxes(BatchOptIn);
% @endcode
%
% @code
% % Populate the Batch Processing parameter table with default options
% obj.mibController.cSelection.selectionPanelCheckboxes(NaN);
% @endcode

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
BatchOpt.mibBatchTooltip.ColorChannel    = 'When empty — do not modify; otherwise index of the colour channel to set: 0 = All, 1 = first, 2 = second, etc.';

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

            case 'Difference'
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
