function listener_updatePanelPosition(obj, src, evtData)
% LISTENER_UPDATEPANELPOSITION - Listener callback to adapt Segmentation panel layout when docked position changes.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_updatePanelPosition(src, evtData)
%
% Dynamically reconfigures the panel's grid layout and widget positions when the Segmentation panel
% is docked to different regions (left, right, or bottom) of the AppContainer. Optimizes widget
% arrangement for each docking orientation.
%
% Input Arguments:
%   - **src** - [matlab.ui.container.Panel] the panel object whose Region property changed
%   - **evtData** - [matlab.ui.eventdata.PropertyChangedData] property change event data
%
% Output Arguments:
%   None
%
% **Layout configurations:**
%
% The Segmentation panel uses a ``mainGridLayout`` with 4 rows/columns:
%
% **Left / Right docking** - vertical, 4-row layout:
%   - ``RowHeight`` = ``{26, '1x', 54, 187}``
%   - ``ColumnWidth`` = ``{'1x'}``
%   - ``topGridLayout`` (row 1): horizontal arrangement with ``ColumnWidth = {45, 45, 22, 22, '1x', 22, 22, 20}``
%   - ``middleGridLayout`` (row 3): 2-column × 2-row grid with ``ColumnWidth = {'1x', '1x'}``, ``RowHeight = {'1x', '1x'}``
%
% **Bottom docking** - horizontal, 4-column layout:
%   - ``ColumnWidth`` = ``{60, 260, '1x', 260}``
%   - ``RowHeight`` = ``{'1x'}``
%   - ``topGridLayout`` (column 1): vertical arrangement with ``RowHeight = {22, 22, 22, 22, '1x', '1x', 22, 22}``
%   - ``middleGridLayout`` (column 3): 1-column × 4-row grid with ``ColumnWidth = {'1x'}``, ``RowHeight = {'1x', '1x', '1x', '1x'}``

switch evtData.PropertyName
    case 'Region'
        children    = obj.handles.mainGridLayout.Children;
        topChildren = obj.handles.topGridLayout.Children;
        midChildren = obj.handles.middleGridLayout.Children;

        % developer mode
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibSegmentation.listener_updatePanelPosition: panel moved -> %s\n', src.Region);
        end

        switch src.Region
            case {'left', 'right'}
                % already in column layout - nothing to do
                if isscalar(obj.handles.mainGridLayout.ColumnWidth); return; end
                % transpose mainGridLayout: column index → row index, single column
                for i = 1:numel(children)
                    colIdx = children(i).Layout.Column;
                    children(i).Layout.Column = 1;
                    children(i).Layout.Row = colIdx;
                end
                obj.handles.mainGridLayout.RowHeight    = {26, '1x', 54, 187};
                obj.handles.mainGridLayout.ColumnWidth  = {'1x'};
                obj.handles.mainGridLayout.RowSpacing    = 4;
                obj.handles.mainGridLayout.ColumnSpacing = 4;
                obj.handles.mainGridLayout.Padding       = [8 8 8 8];
                % restore topGridLayout to horizontal (in case coming from bottom)
                if ~isscalar(obj.handles.topGridLayout.RowHeight)
                    for i = 1:numel(topChildren)
                        rowIdx = topChildren(i).Layout.Row;
                        topChildren(i).Layout.Row    = 1;
                        topChildren(i).Layout.Column = rowIdx;
                    end
                    obj.handles.topGridLayout.ColumnWidth  = {45, 45, 22, 22, '1x', 22, 22, 20};
                    obj.handles.topGridLayout.RowHeight    = {'1x'};
                    obj.handles.topGridLayout.ColumnSpacing = 4;
                    obj.handles.topGridLayout.RowSpacing    = 4;
                    obj.handles.topGridLayout.Padding       = [0 2 0 2];
                end
                % restore middleGridLayout to 2-column 2-row (in case coming from bottom)
                if isscalar(obj.handles.middleGridLayout.ColumnWidth)
                    for i = 1:numel(midChildren)
                        linIdx = midChildren(i).Layout.Row;   % was flattened to single column
                        midChildren(i).Layout.Row    = ceil(linIdx / 2);
                        midChildren(i).Layout.Column = mod(linIdx - 1, 2) + 1;
                    end
                    obj.handles.middleGridLayout.ColumnWidth  = {'1x', '1x'};
                    obj.handles.middleGridLayout.RowHeight    = {'1x', '1x'};
                    obj.handles.middleGridLayout.ColumnSpacing = 4;
                    obj.handles.middleGridLayout.RowSpacing    = 4;
                    obj.handles.middleGridLayout.Padding       = [0 0 0 0];
                end

            case 'bottom'
                % already in row layout - nothing to do
                if isscalar(obj.handles.mainGridLayout.RowHeight); return; end
                % transpose mainGridLayout: row index → column index, single row
                for i = 1:numel(children)
                    rowIdx = children(i).Layout.Row;
                    children(i).Layout.Row    = 1;
                    children(i).Layout.Column = rowIdx;
                end
                obj.handles.mainGridLayout.RowHeight    = {'1x'};
                obj.handles.mainGridLayout.ColumnWidth  = {60, 260, 170, 260};
                obj.handles.mainGridLayout.RowSpacing    = 4;
                obj.handles.mainGridLayout.ColumnSpacing = 12;
                obj.handles.mainGridLayout.Padding       = [8 8 8 8];
                % transpose topGridLayout to vertical (column 1 is now narrow)
                for i = 1:numel(topChildren)
                    colIdx = topChildren(i).Layout.Column;
                    topChildren(i).Layout.Column = 1;
                    topChildren(i).Layout.Row    = colIdx;
                end
                obj.handles.topGridLayout.RowHeight    = {22, 22, 22, 22, '1x', '1x', 22, 22};
                obj.handles.topGridLayout.ColumnWidth  = {'1x'};
                obj.handles.topGridLayout.RowSpacing    = 4;
                obj.handles.topGridLayout.ColumnSpacing = 4;
                obj.handles.topGridLayout.Padding       = [2 0 8 0];
                % flatten middleGridLayout from 2x2 to 1 column 4 rows (row-major order)
                for i = 1:numel(midChildren)
                    r = midChildren(i).Layout.Row;
                    c = midChildren(i).Layout.Column;
                    midChildren(i).Layout.Row    = (r - 1) * 2 + c;
                    midChildren(i).Layout.Column = 1;
                end
                obj.handles.middleGridLayout.RowHeight    = {24, 22, 22, 22};
                obj.handles.middleGridLayout.ColumnWidth  = 160;
                obj.handles.middleGridLayout.RowSpacing    = 4;
                obj.handles.middleGridLayout.ColumnSpacing = 4;
                obj.handles.middleGridLayout.Padding       = [8 0 4 0];
        end
end

end
