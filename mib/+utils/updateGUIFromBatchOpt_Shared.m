function View = updateGUIFromBatchOpt_Shared(View, BatchOpt)
% UPDATEGUIFROMBATCHOPT_SHARED - Populate GUI widgets from a BatchOpt struct.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      View = updateGUIFromBatchOpt_Shared(View, BatchOpt)
%
% Used by all Batch-mode-compatible tools to initialise the dialog
% widgets from a BatchOpt struct - e.g. when opening a dialog with a
% previously saved configuration.  Handles edit fields, checkboxes,
% dropdowns, radio button groups, tab groups, spinners, and numeric edit fields.
%
% Input Arguments:
%   - **View** - View class of the controller (must expose ``View.Figure``)
%   - **BatchOpt** - BatchOpt struct whose fields drive the widget update
%
% Output Arguments:
%   - **View** - View class with updated widget values
%
% Usage:
%
%   **Example 1** - restore widget state when opening a dialog
%
%   .. code-block:: matlab
%
%      obj.View = utils.updateGUIFromBatchOpt_Shared(obj.View, obj.BatchOpt);
%

fieldNames = fieldnames(BatchOpt);
for fieldId = 1:numel(fieldNames)
    % if fieldId==45
    %     0
    % end
    if ~isempty(View.Figure)        % for GUIs made with AppDesigner
        if isprop(View.Figure, fieldNames{fieldId})
            switch View.Figure.(fieldNames{fieldId}).Type
                case 'uieditfield'
                    View.Figure.(fieldNames{fieldId}).Value = BatchOpt.(fieldNames{fieldId});
                case {'uinumericeditfield', 'uispinner'}
                    if numel(BatchOpt.(fieldNames{fieldId})) >= 2
                        if BatchOpt.(fieldNames{fieldId}){2}(1) == BatchOpt.(fieldNames{fieldId}){2}(2)     % limits can't be the same value
                            BatchOpt.(fieldNames{fieldId}){2}(2) = BatchOpt.(fieldNames{fieldId}){2}(2) + .0001;
                        end
                        View.Figure.(fieldNames{fieldId}).Limits = BatchOpt.(fieldNames{fieldId}){2};
                    end
                    if numel(BatchOpt.(fieldNames{fieldId})) >= 3
                        View.Figure.(fieldNames{fieldId}).RoundFractionalValues = BatchOpt.(fieldNames{fieldId}){3};
                    end
                    try
                        View.Figure.(fieldNames{fieldId}).Value = BatchOpt.(fieldNames{fieldId}){1};
                    catch err
                        fprintf('Field id: %s\n', fieldNames{fieldId});
                        err
                    end
                case 'uicheckbox'
                    View.Figure.(fieldNames{fieldId}).Value = BatchOpt.(fieldNames{fieldId});
                case 'uibuttongroup'
                    radioChildren = View.Figure.(fieldNames{fieldId}).Children;
                    for i=1:numel(radioChildren)
                        if strcmp(radioChildren(i).Tag, BatchOpt.(fieldNames{fieldId}){1})
                            radioChildren(i).Value = 1;
                        end
                    end
                case {'uidropdown', 'uilistbox'}
                    if numel(BatchOpt.(fieldNames{fieldId})) == 2   % populate the contents of the dropdown
                        % check whether the item exist in the list
                        View.Figure.(fieldNames{fieldId}).Items = BatchOpt.(fieldNames{fieldId}){2};
                    end
                    try
                        View.Figure.(fieldNames{fieldId}).Value = BatchOpt.(fieldNames{fieldId}){1};
                    catch err
                        fprintf('Field id: %s\n', fieldNames{fieldId});
                        err
                    end
            end
            if isfield(BatchOpt, 'mibBatchTooltip')
                if isfield(BatchOpt.mibBatchTooltip, fieldNames{fieldId})
                    View.Figure.(fieldNames{fieldId}).Tooltip = BatchOpt.mibBatchTooltip.(fieldNames{fieldId});
                end
            end
        end
    else    % for GUIs made with GUIDE
        if isfield(View.handles, fieldNames{fieldId})
            if strcmp(View.handles.(fieldNames{fieldId}).Type, 'uibuttongroup')     % radio buttons
                radioChildren = View.handles.(fieldNames{fieldId}).Children;
                for i=1:numel(radioChildren)
                    if strcmp(radioChildren(i).Tag, BatchOpt.(fieldNames{fieldId}){1})
                        radioChildren(i).Value = 1;
                    end
                end
            else
                switch View.handles.(fieldNames{fieldId}).Style
                    case 'popupmenu'
                        if numel(BatchOpt.(fieldNames{fieldId})) == 2   % populate the contents of the dropdown
                            View.handles.(fieldNames{fieldId}).String = BatchOpt.(fieldNames{fieldId}){2};
                        end
                        View.handles.(fieldNames{fieldId}).Value = find(ismember(BatchOpt.(fieldNames{fieldId}){2}, BatchOpt.(fieldNames{fieldId}){1}));
                    case 'edit'
                        View.handles.(fieldNames{fieldId}).String = BatchOpt.(fieldNames{fieldId});
                    case 'checkbox'
                        View.handles.(fieldNames{fieldId}).Value = BatchOpt.(fieldNames{fieldId});

                end
            end
        end
    end
    
end
