function selectedActionTableItem_Update(obj, hObject)
% SELECTEDACTIONTABLEITEM_UPDATE - write an edited parameter value back to obj.CurrentBatch and the table cell.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selectedActionTableItem_Update(hObject)
%
% Called by ValueChangedFcn of the four editing widgets:
% selectedActionTableCellEdit, selectedActionTableCellNumericEdit,
% selectedActionTableCellPopup, selectedActionTableCellCheck.
%
% Input Arguments:
%   - **hObject** - handle to the widget that triggered the callback; Tag must be
%     one of 'selectedActionTableCellPopup', 'selectedActionTableCellCheck',
%     'selectedActionTableCellEdit', or 'selectedActionTableCellNumericEdit'
%
% **Example** - update a parameter value:
%
%   .. code-block:: matlab
%
%      obj.selectedActionTableItem_Update(obj.view.handles.selectedActionTableCellEdit);

if obj.selectedActionTableIndex == 0; return; end
fieldNames = fieldnames(obj.CurrentBatch);

% remove mibBatchSectionName and mibBatchActionName
fieldNames(ismember(fieldNames, {'mibBatchSectionName', 'mibBatchActionName', 'mibBatchTooltip'})) = [];
currIndex = obj.selectedActionTableIndex; % store the index

switch hObject.Tag
    case 'selectedActionTableCellPopup'    % for popup menus (dropdown)
        if numel(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex})) > 1
            % hObject.Value is the selected string directly
            obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex})(1) = {hObject.Value};
            obj.view.handles.selectedActionTable.Data{obj.selectedActionTableIndex,2} = hObject.Value;
        end
    case 'selectedActionTableCellCheck'     % for checkboxes
        obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}) = logical(hObject.Value);
        obj.view.handles.selectedActionTable.Data{obj.selectedActionTableIndex,2} = logical(hObject.Value);
    case 'selectedActionTableCellEdit'      % for text edits
        if iscell(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}))      % numeric value in text box
            values = str2double(hObject.Value);
            if numel(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex})) > 1     % check range
                Limits = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){2};
                if values < Limits(1) || values > Limits(2)
                    errOpts.MsgBoxOnly = true; errOpts.Icon = 'puffin_error';
                    header = sprintf('The value should be between %g and %g!', Limits(1), Limits(2));
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Value out of range', errOpts);
                    hObject.Value = num2str(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){1});
                    return;
                end
            end
            if numel(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex})) > 2     % rounding of numbers
                RoundFractionalValues = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){3};
            else
                RoundFractionalValues = 'on';
            end
            if strcmp(RoundFractionalValues, 'on'); values = round(values); end
            obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){1} = values;
            obj.view.handles.selectedActionTable.Data{obj.selectedActionTableIndex,2} = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){1};
        else    % normal text edit box
            obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}) = hObject.Value;
            obj.view.handles.selectedActionTable.Data{obj.selectedActionTableIndex,2} = hObject.Value;
        end
    case 'selectedActionTableCellNumericEdit'   % for numeric edits
        newValue = hObject.Value;   % NumericEditField.Value is already numeric
        if ismember(fieldNames{obj.selectedActionTableIndex}, {'x', 'y', 'z', 't'}) && numel(newValue) == 1 && newValue ~= 0
            newValue = [newValue newValue];
        end
        obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}) = newValue;
        obj.view.handles.selectedActionTable.Data{obj.selectedActionTableIndex,2} = num2str(newValue);
end
obj.selectedActionTableIndex = currIndex;
end
