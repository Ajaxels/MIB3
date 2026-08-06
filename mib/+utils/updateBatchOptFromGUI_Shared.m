function BatchOpt = updateBatchOptFromGUI_Shared(BatchOpt, hObject)
% UPDATEBATCHOPTFROMGUI_SHARED - Update a BatchOpt struct field from a GUI widget value.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      BatchOpt = updateBatchOptFromGUI_Shared(BatchOpt, hObject)
%
% Used by all Batch-mode-compatible tools to synchronise a single widget
% change into the corresponding BatchOpt field.  Handles edit fields,
% checkboxes, dropdowns, radio button groups, tab groups, spinners, and
% numeric edit fields.
%
% Input Arguments:
%   - **BatchOpt** - current BatchOpt struct for the controller
%   - **hObject** - handle to the GUI widget that triggered the change
%
% Output Arguments:
%   - **BatchOpt** - updated BatchOpt struct
%
% Usage:
%
%   **Example 1** - wire a widget callback to keep BatchOpt in sync
%
%   .. code-block:: matlab
%
%      obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, src);
%

switch hObject.Type
    case 'uibuttongroup'
        hChildren = hObject.Children;
        for i=1:numel(hChildren)
            if ~isprop(hChildren(i), 'Style')    % AppDesigner GUI
                if strcmp(hChildren(i).Type, 'uiradiobutton')
                    if hChildren(i).Value == 1
                        BatchOpt.(hObject.Tag)(1) = {(hChildren(i).Tag)};
                    end
                end
            else        % GUIDE GUI 
                if strcmp(hChildren(i).Style, 'radiobutton')
                    if hChildren(i).Value == 1
                        BatchOpt.(hObject.Tag)(1) = {(hChildren(i).Tag)};
                    end
                end
            end
        end
    case 'uitabgroup'
        BatchOpt.(hObject.Tag)(1) = {hObject.SelectedTab.Tag};
    case {'uieditfield', 'uicheckbox'}  % app designer GUI
        BatchOpt.(hObject.Tag) = hObject.Value;
    case {'uinumericeditfield', 'uispinner'}   % app designer GUI
        BatchOpt.(hObject.Tag){1} = hObject.Value;
        BatchOpt.(hObject.Tag){2} = hObject.Limits;
        BatchOpt.(hObject.Tag){3} = hObject.RoundFractionalValues;
    case 'uidropdown'
        BatchOpt.(hObject.Tag)(1) = {hObject.Value};
    case 'uicontrol'        % GUIDE GUI
        switch hObject.Style
            case 'popupmenu'
                currString = hObject.String;
                if ~ischar(currString)
                    BatchOpt.(hObject.Tag)(1) = currString(hObject.Value);
                else    % when only a single entry in the popup menu
                    BatchOpt.(hObject.Tag)(1) = {currString};
                end
            case 'checkbox'
                BatchOpt.(hObject.Tag) = logical(hObject.Value);
            case 'edit'
                BatchOpt.(hObject.Tag) = hObject.String;
            case 'radiobutton'
                % find parent for the radio button
                radioParent = hObject.Parent;
                if strcmp(radioParent.Type, 'uibuttongroup') % radio button group
                    BatchOpt.(radioParent.Tag){1} = hObject.Tag;
                    % updated in MIB 2.9105 to make it better compatible with Batch processing
                    %hRadios = findobj(radioParent, 'Style', 'radiobutton');
                    %for i=1:numel(hRadios)
                    %    BatchOpt.(hRadios(i).Tag) = false;
                    %end
                    %BatchOpt.(hObject.Tag) = logical(hObject.Value);
                else % single radio button
                     BatchOpt.(hObject.Tag) = logical(hObject.Value);
                end
        end
end
end
