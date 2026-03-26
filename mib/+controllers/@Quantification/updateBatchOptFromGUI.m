function updateBatchOptFromGUI(obj, hObject, ~)
% function updateBatchOptFromGUI(obj, hObject, ~)
% Sync BatchOpt from a changed widget using the shared utility.
%
% Delegates to utils.updateBatchOptFromGUI_Shared which reads the widget's
% Tag and Value and writes the matching BatchOpt field.  The second event
% argument (~) is accepted but ignored for AppDesigner compatibility.
%
% Parameters:
% hObject: handle to the AppDesigner widget whose value changed
% ~: ignored ValueChangedData argument (AppDesigner passes it automatically)
%
%|
% @b Examples:
% @code % wired in addCallbacks for multiple widgets: @endcode
% @code h.DatasetType.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj); @endcode

% Updates
%

obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
end
