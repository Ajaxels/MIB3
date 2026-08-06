function lutTable_CellSelection(obj, hWidget, hData)
% LUTTABLE_CELLSELECTION - callbacks for cell selection in the LUT table (obj.handles.lutTable) of the Selection and Image View panel.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.lutTable_CellSelection(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** - [uitable] handle to the LUT table widget
%   - **hData** - [CellSelectionChangeData] cell selection event data with properties:
%
%     - ``.Indices`` - [M×2 numeric] indices of selected cells ``[row, col]``
%     - ``.DisplayIndices`` - [M×2 numeric] display indices of selected cells
%     - ``.Source`` - [uitable] handle to the table (lutTable)
%     - ``.EventName`` - ``'CellSelection'`` event name
%

if isempty(hData.Indices); return; end
indices = hData.Indices;

obj.handles.lutTable.UserData = indices;   % store selected position

if indices(1, 2) == 3 % start color selection dialog
    if obj.mibModel.preferences.System.DeveloperMode
        fprintf('controllers.MibSelection.lutTable_CellSelection: "obj.view.handles.panels.selection.handles.lutTable" -> cell selected\n');
    end
    
    if obj.handles.lutColors.Value == 0
        uialert(obj.view.gui, ...
            sprintf(['The colors for the color channels may be selected only in the LUT mode!\n\n' ...
                     'To enable the LUT mode please select the LUT checkbox\n' ...
                     '(Selection and View Settings Panel->LUT checkbox)']), 'Requires LUT color mode!', ...
                     'Icon', 'warning');
        return;
    end

    figTitle = sprintf('Set color for channel %d', indices(1));
    lutColors = obj.mibModel.I{obj.mibModel.id}.image.lutColors;
    c = uisetcolor(lutColors(indices(1),:), figTitle);
    if isscalar(c); return; end % cancel

    lutColors(indices(1),:) = c;

    obj.mibModel.I{obj.mibModel.id}.image.lutColors = lutColors;
    
    % redraw the table
    obj.lutTable_update_fromModel();
    
    % Clear the selection to show the true background color
    obj.handles.lutTable.Selection = [];
    drawnow;

    % redraw image in the im_browser axes
    notify(obj.mibModel, 'ShowImage');
end

end
