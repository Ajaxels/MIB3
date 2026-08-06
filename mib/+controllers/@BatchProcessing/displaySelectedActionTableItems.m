function displaySelectedActionTableItems(obj, evnt)
% DISPLAYSELECTEDACTIONTABLEITEMS - show the appropriate editing widget for the currently highlighted row in selectedActionTable.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.displaySelectedActionTableItems(evnt)
%
% Hides all editing widgets, then makes exactly one visible based on the
% data type of the selected BatchOpt field:
% logical selectedActionTableCellCheck
% cell (strings) selectedActionTableCellPopup
% cell (numeric) selectedActionTableCellEdit
% char selectedActionTableCellEdit
% numeric selectedActionTableCellNumericEdit
%
% Input Arguments:
%   - **evnt** - [optional] CellSelectionCallback event data; when provided the
%     selected row index is read from evnt.Indices(1,1) and stored in
%     obj.selectedActionTableIndex before updating the widgets
%
% Usage:
%   Example 1::
%
%     obj.displaySelectedActionTableItems();
%
%   Example 2::
%
%     obj.displaySelectedActionTableItems(evnt);
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.displaySelectedActionTableItems: triggered\n');
end

if nargin > 1 && ~isempty(evnt.Indices)
    obj.selectedActionTableIndex = evnt.Indices(1, 1);
end

if obj.selectedActionTableIndex == 0; return; end
if isempty(obj.CurrentBatch); return; end

obj.view.handles.selectedActionTableCellCheck.Visible = 'off';
obj.view.handles.selectedActionTableCellPopup.Visible = 'off';
obj.view.handles.selectedActionTableCellEdit.Visible = 'off';
obj.view.handles.selectedActionTableCellNumericEdit.Visible = 'off';

fieldNames = fieldnames(obj.CurrentBatch);
% remove mibBatchSectionName and mibBatchActionName
fieldNames(ismember(fieldNames, {'mibBatchSectionName', 'mibBatchActionName', 'mibBatchTooltip'})) = [];

if isempty(fieldNames)
    obj.view.handles.ValueLabel.Text = '';
    return;
end

obj.view.handles.ValueLabel.Text = fieldNames{obj.selectedActionTableIndex};

if isnumeric(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}))
    obj.view.handles.selectedActionTableCellNumericEdit.Visible = 'on';
    obj.view.handles.selectedActionTableCellNumericEdit.Value = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex});
else
    switch class(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}))
        case 'cell'
            if numel(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex})) == 1
                warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
                header = 'The possible configurations for this widget were not provided!';
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Warning', warnOpts);
                obj.view.handles.selectedActionTableCellPopup.Items = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex})(1);
                obj.view.handles.selectedActionTableCellPopup.Value = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){1};
            else
                if ~isnumeric(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){1})  % dropdown
                    obj.view.handles.selectedActionTableCellPopup.Visible = 'on';
                    items = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){2};
                    obj.view.handles.selectedActionTableCellPopup.Items = items;
                    obj.view.handles.selectedActionTableCellPopup.Value = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){1};
                else    % numeric value in text edit box
                    obj.view.handles.selectedActionTableCellEdit.Visible = 'on';
                    obj.view.handles.selectedActionTableCellEdit.Value = num2str(obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex}){1});
                end
            end
        case 'logical'
            obj.view.handles.selectedActionTableCellCheck.Visible = 'on';
            obj.view.handles.selectedActionTableCellCheck.Value = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex});
        case 'char'
            obj.view.handles.selectedActionTableCellEdit.Visible = 'on';
            obj.view.handles.selectedActionTableCellEdit.Value = obj.CurrentBatch.(fieldNames{obj.selectedActionTableIndex});
    end
end

% add tooltips and comments
showTooltip = false;
if isfield(obj.CurrentBatch, 'mibBatchTooltip')
    if isfield(obj.CurrentBatch.mibBatchTooltip, fieldNames{obj.selectedActionTableIndex})
        showTooltip = true;
    end
end
if showTooltip
    tooltipStr = obj.CurrentBatch.mibBatchTooltip.(fieldNames{obj.selectedActionTableIndex});
    obj.view.handles.selectedActionTableCellEdit.Tooltip        = tooltipStr;
    obj.view.handles.selectedActionTableCellCheck.Tooltip       = tooltipStr;
    obj.view.handles.selectedActionTableCellPopup.Tooltip       = tooltipStr;
    obj.view.handles.selectedActionTableCellNumericEdit.Tooltip = tooltipStr;
    obj.view.handles.ValueLabel.Tooltip                         = tooltipStr;
    obj.view.handles.protocolComments.Value                          = {tooltipStr};
else
    obj.view.handles.ValueLabel.Tooltip = fieldNames{obj.selectedActionTableIndex};
    obj.view.handles.protocolComments.Value  = {'Provide the value'};
end
end
