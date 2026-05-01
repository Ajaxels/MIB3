function listener_updatePanelPosition(obj, src, evtData)
% LISTENER_UPDATEPANELPOSITION - Adapt ROI panel grid layout when docked to different AppContainer region.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_updatePanelPosition(src, evtData)
%
% The ROI panel uses a mainGridLayout with sub-grids for list/buttons and manual-coordinate areas.
% Layout is transposed when the panel moves:
%
% - **Bottom** — horizontal 5-column layout:
%   ColumnWidth = ``{310, 3, 320, 3, '1x'}``; RowHeight = ``{'1x'}``
%   ColumnSpacing = 12, RowSpacing = 4; Padding = ``[10 8 10 6]``
%
% - **Left/Right** — vertical 5-row layout:
%   RowHeight = ``{130, 3, 130, 3, 1}``; ColumnWidth = ``{'1x'}``
%   RowSpacing = 12, ColumnSpacing = 4; Padding = ``[8 10 6 10]``
%
% Each child grid's ``Layout.Column`` (bottom) becomes ``Layout.Row`` (vertical) and vice-versa.
%
% Input Arguments:
%   - **obj** — [MibRoi] this controller instance
%   - **src** — [uipanel] the panel whose property changed (``obj.view.handles.panels.roiPanel``)
%   - **evtData** — [PropertyChangedData] event data; ``.PropertyName`` checked for ``'Region'``
%

switch evtData.PropertyName
    case 'Region'
        children = obj.handles.mainGridLayout.Children;
        
        % developer mode
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibRoi.listener_updatePanelPosition: panel moved -> %s\n', src.Region);
        end

        switch src.Region
            case {'left', 'right'}
                % already in column layout — nothing to do
                if isscalar(obj.handles.mainGridLayout.ColumnWidth); return; end
                % transpose: column index → row index, single column
                for i = 1:numel(children)
                    colIdx = children(i).Layout.Column;
                    children(i).Layout.Column = 1;
                    children(i).Layout.Row = colIdx;
                end
                obj.handles.mainGridLayout.RowHeight    = {130, 3, 130, 3, 1};
                obj.handles.mainGridLayout.ColumnWidth  = {'1x'};
                obj.handles.mainGridLayout.RowSpacing    = 12;
                obj.handles.mainGridLayout.ColumnSpacing = 4;
                obj.handles.mainGridLayout.Padding       = [8 10 6 10];

            case 'bottom'
                % already in row layout — nothing to do
                if isscalar(obj.handles.mainGridLayout.RowHeight)
                    return
                end
                % transpose: row index → column index, single row
                for i = 1:numel(children)
                    rowIdx = children(i).Layout.Row;
                    children(i).Layout.Row = 1;
                    children(i).Layout.Column = rowIdx;
                end
                obj.handles.mainGridLayout.RowHeight    = {'1x'};
                obj.handles.mainGridLayout.ColumnWidth  = {310, 3, 320, 3, '1x'};
                obj.handles.mainGridLayout.RowSpacing    = 4;
                obj.handles.mainGridLayout.ColumnSpacing = 12;
                obj.handles.mainGridLayout.Padding       = [10 8 10 6];
        end
end

end
