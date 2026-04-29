function updateBatchOptFromGUI(obj, hObject, ~)
% UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a changed widget using the shared utility.
%
% Syntax:
%   function updateBatchOptFromGUI(obj, hObject, ~)
%
% Delegates to utils.updateBatchOptFromGUI_Shared which reads the widget's
% Tag and Value and writes the matching BatchOpt field.  The second event
% argument (~) is accepted but ignored for AppDesigner compatibility.
%
% Input Arguments:
%   - **hObject** — handle to the AppDesigner widget whose value changed
%     ~: ignored ValueChangedData argument (AppDesigner passes it automatically)
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks for multiple widgets:
%
%   Example 2::
%
%     h.DatasetType.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
%

% Updates
%

obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
end
