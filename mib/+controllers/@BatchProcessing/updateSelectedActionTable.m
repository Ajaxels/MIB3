function updateSelectedActionTable(obj, BatchOpt)
% UPDATESELECTEDACTIONTABLE - populate selectedActionTable from a BatchOpt structure.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateSelectedActionTable(BatchOpt)
%
% Also updates obj.selectedSection, obj.selectedAction and obj.CurrentBatch.
%
% Input Arguments:
%   - **BatchOpt** - [struct] action parameters. Field types that drive widget rendering in displaySelectedActionTableItems:
%
%     - Logical scalar → checkbox
%     - Cell {value; {list}} → dropdown
%     - Cell {numeric; [limits]; rounding} → numeric text edit
%     - Char string → text edit field
%     - Plain numeric → numeric edit field
%
%   Required meta-fields (removed from table display):
%
%     - ``.mibBatchSectionName`` - section name string
%     - ``.mibBatchActionName`` - action name string
%     - ``.mibBatchTooltip`` *(optional)* - struct with per-field tooltip strings
%
% **Example** - populate parameter table from BatchOpt:
%
%   .. code-block:: matlab
%
%      BatchOpt.colChannel = {1; {1,2,3}};
%      BatchOpt.showWaitbar = true;
%      BatchOpt.mibBatchSectionName = 'Menu -> Image';
%      BatchOpt.mibBatchActionName  = 'Invert image';
%      obj.updateSelectedActionTable(BatchOpt);

% update sections list
obj.selectedSection = find(ismember({obj.Sections.Name}, BatchOpt.mibBatchSectionName) == 1);
% update actions list
if ~isempty(obj.selectedSection)
    obj.selectedAction = find(ismember({obj.Sections(obj.selectedSection).Actions.Name}, BatchOpt.mibBatchActionName));
else
    obj.selectedAction = [];
end

% Sync section + action dropdowns without triggering selectProtocolSection_Callback.
% Disconnecting ValueChangedFcn prevents re-entrant eval calls.
h = obj.view.handles;
cbSection = h.selectProtocolSection.ValueChangedFcn;
cbAction  = h.selectProtocolAction.ValueChangedFcn;
h.selectProtocolSection.ValueChangedFcn = [];
h.selectProtocolAction.ValueChangedFcn  = [];

sectionItems = {obj.Sections.Name}';
h.selectProtocolSection.Items = sectionItems;
if ~isempty(obj.selectedSection)
    h.selectProtocolSection.Value = sectionItems{obj.selectedSection};
end

actionItems = {};
if ~isempty(obj.selectedSection)
    actionItems = {obj.Sections(obj.selectedSection).Actions.Name}';
    h.selectProtocolAction.Items = actionItems;
end
if ~isempty(obj.selectedAction)
    h.selectProtocolAction.Value = actionItems{obj.selectedAction};
end

h.selectProtocolSection.ValueChangedFcn = cbSection;
h.selectProtocolAction.ValueChangedFcn  = cbAction;

obj.CurrentBatch = BatchOpt;
fieldNames = fieldnames(BatchOpt);

% remove mibBatchSectionName and mibBatchActionName
fieldNames(ismember(fieldNames, {'mibBatchSectionName', 'mibBatchActionName', 'mibBatchTooltip'})) = [];

tData = cell([numel(fieldNames), 2]);
tData(:,1) = fieldNames;    % plain text; bold applied via uistyle below

for rowId = 1:numel(fieldNames)
    val = BatchOpt.(fieldNames{rowId});
    if iscell(val)
        val = val{1};           % first element = selected value / current value
        if iscell(val)          % nested cell (shouldn't happen, but guard anyway)
            val = val{1};
        end
    end
    % Normalise to a type accepted by AppDesigner Table: char, logical, or scalar numeric
    if isstring(val); val = char(val); end  % convert MATLAB string object to char
    if islogical(val)
        tData{rowId,2} = val(1);        % scalar logical
    elseif ischar(val)
        tData{rowId,2} = val;           % char vector - keep as is
    elseif isnumeric(val)
        tData{rowId,2} = num2str(val);  % numeric → display string
    else
        tData{rowId,2} = class(val);    % fallback: show type name
    end
end
obj.view.handles.selectedActionTable.Data = tData;

% bold first column (AppDesigner uistyle API, R2022b+)
removeStyle(obj.view.handles.selectedActionTable);
addStyle(obj.view.handles.selectedActionTable, uistyle('FontWeight', 'bold'), 'column', 1);

% fit columns to the current table container width
obj.fitTableColumns();
end
