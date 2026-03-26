function statTable_CellSelectionCallback(obj, indices, parameter)
% function statTable_CellSelectionCallback(obj, indices, parameter)
% Handle cell selection in statTable and optionally highlight objects.
%
% Called both from the table's CellSelectionCallback and from context menu
% items.  Navigates to the slice containing the selected object and,
% depending on parameter, highlights it in the selection layer.
%
% Parameters:
% indices: numeric [N×2] array of [row, col] indices of selected cells,
%   as provided by AppDesigner CellSelectionCallback evnt.Indices;
%   pass [] to use the last saved selection (obj.indices)
% parameter: string controlling highlight behaviour
% @li 'skip' - navigate to slice but only highlight if highlightOnClick
%     is on; Ctrl+click forces 'Remove'
% @li 'Add'     - add selected objects to selection layer
% @li 'Remove'  - remove selected objects from selection layer
% @li 'Replace' - replace selection layer with selected objects
% @li 'obj2model' - convert each selected object to a new model material
%
%|
% @b Examples:
% @code % wired in addCallbacks: @endcode
% @code h.statTable.CellSelectionCallback = @(~,evnt) obj.statTable_CellSelectionCallback(evnt.Indices, 'skip'); @endcode
% @code obj.statTable_CellSelectionCallback([], 'Replace');  // from context menu @endcode

% Updates
%

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};
modifier = obj.view.gui.CurrentModifier;

if strcmp(parameter, 'obj2model')
    answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf(['!!! Warning !!!\n\nYou are going to create a new model where each selected' ...
                 'object gets its own index (new material).\n\nATTENTION: The current model will be deleted!']), ...
        'Convert models', 'Continue', 'Cancel', 'Cancel');
    if strcmp(answer, 'Cancel'); return; end
end

data = obj.view.handles.statTable.Data;
if isempty(data); return; end
if iscell(data(1)); return; end

if strcmp(parameter, 'skip')
    if isempty(indices); return; end

    % Find the newly added row index
    newIndex = NaN;
    if ~isempty(obj.indices)
        newIndex = find(~ismember(indices(:,1), obj.indices(:,1)), 1);
        if size(indices, 1) == 1
            newIndex = indices(1,:);
        elseif size(indices, 1) > 1 && ~isempty(newIndex)
            newIndex = indices(newIndex,:);
        end
    else
        newIndex = indices(1,:);
    end

    obj.indices = indices;

    if size(newIndex, 1) == 1 && ~isnan(newIndex(1))
        rowNames = obj.view.handles.statTable.RowName;
        rowIdx = min(newIndex(1,1), numel(rowNames));
        objId = str2double(rowNames{rowIdx});

        dataset.moveView(obj.STATS(objId).Centroid(1), obj.STATS(objId).Centroid(2));

        % update slice slider
        sliceNo = data(newIndex(1,1), 3);
        orient = dataset.orientation;
        dataset.slices{orient}(1) = sliceNo;
        dataset.slices{orient}(2) = sliceNo;
        notify(obj.mibModel, 'SliceChanged');

        if dataset.image.time > 1
            timePnt = data(newIndex(1,1), 4);
            dataset.slices{5}(1) = timePnt;
            dataset.slices{5}(2) = timePnt;
            notify(obj.mibModel, 'FrameChanged');
        end
    end

    if ~obj.view.handles.highlightOnClick.Value; return; end

    if ~isempty(modifier) && strcmp(modifier{1}, 'control')
        parameter = 'Remove';
    else
        parameter = obj.view.handles.selectionModePanel.SelectedObject.Text;
    end
end

if isempty(obj.indices); return; end
rowIndices = unique(obj.indices(:,1));
rowNames = obj.view.handles.statTable.RowName;
object_list = str2num(cell2mat(rowNames(rowIndices))); %#ok<ST2NM>
sliceNumbers = data(rowIndices, 3);
obj.highlightSelection(object_list, parameter, sliceNumbers);
end
