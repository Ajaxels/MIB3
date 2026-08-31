function objectTable_SelectionChanged(obj, eventData)
% OBJECTTABLE_SELECTIONCHANGED - Row selection in the object list.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.objectTable_SelectionChanged(eventData)
%
% Rows are resolved to object indices through the table's ``DisplayData`` rather
% than through the order they were written in: the table is sortable, so the
% row number on screen is not the row number in ``obj.displayedIds`` once the
% user has clicked a column header.
%
% Selecting a single row also navigates the image to that object - the list is
% useless for proofreading if finding the object it names is a manual hunt.
%
% Input Arguments:
%   - **eventData** - the ``SelectionChangedFcn`` event; ``.Selection`` holds the
%     selected row numbers
%
% Output Arguments:
%   (none)

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.objectTable_SelectionChanged: triggered\n');
end

rows = eventData.Selection;
if isempty(rows); return; end

displayed = obj.view.handles.objectTable.DisplayData;
if isempty(displayed); return; end
rows = rows(rows <= height(displayed));
if isempty(rows); return; end

obj.selectedObjects = displayed.Index(rows)';
obj.updateSelectedList();
obj.highlightObjects();

if isscalar(rows)
    obj.goToObject(displayed.Index(rows));
end
end
