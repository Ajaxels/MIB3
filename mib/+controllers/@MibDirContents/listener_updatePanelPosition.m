function listener_updatePanelPosition(obj, src, evtData)
% function listener_updatePanelPosition(obj, src, evtData)
% Listener callback: adapt the Directory contents panel grid layout when the
% panel is docked to a new region of the AppContainer (bottom, left, or right).
%
% The Directory contents panel uses a mainGridLayout with 3 rows × 6 columns:
%
%   Left / Right — vertical, 3-row × 6-column layout:
%               RowHeight    = {'1x', 22, 2}
%               ColumnWidth  = {34, 84, 40, '1x', 50, 18}
%               ColumnSpacing = 5, RowSpacing = 6, Padding = [8 8 8 8]
%               Row 1 — fileList, spanning cols [1 6]
%               Row 2 — 5 toolbar widgets at cols 1, 2, 3, 5, 6 (col 4 = spacer)
%               Row 3 — dividerPanel, spanning cols [1 6]
%
%   Bottom — 6-row × 3-column layout:
%               ColumnWidth  = {'1x', 130, 2}
%               RowHeight    = {22, 22, 22, '1x', 22, 22}
%               ColumnSpacing = 5, RowSpacing = 6, Padding = [8 8 8 8]
%               Col 1 — fileList, spanning rows [1 6]
%               Col 2 — 5 toolbar widgets at rows 1,2,3,5,6 (row 4 = spacer)
%               Col 3 — dividerPanel, spanning rows [1 6]

switch evtData.PropertyName
    case 'Region'
        children = obj.handles.mainGridLayout.Children;
        
        % developer mode
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibDirContents.listener_updatePanelPosition: panel moved -> %s\n', src.Region);
        end
        
        switch src.Region
            case {'left', 'right'}
                % already in left/right layout (3 rows) — nothing to do
                if numel(obj.handles.mainGridLayout.RowHeight) == 3; return; end
                % restore: col index → row / spanning cols back to [1 6]
                for i = 1:numel(children)
                    c = children(i).Layout.Column;
                    if c == 1         % fileList
                        children(i).Layout.Row    = 1;
                        children(i).Layout.Column = [1 6];
                    elseif c == 2     % toolbar widgets: their row was the original col
                        children(i).Layout.Column = children(i).Layout.Row;
                        children(i).Layout.Row    = 2;
                    elseif c == 3     % dividerPanel
                        children(i).Layout.Row    = 3;
                        children(i).Layout.Column = [1 6];
                    end
                end
                obj.handles.mainGridLayout.RowHeight    = {'1x', 22, 2};
                obj.handles.mainGridLayout.ColumnWidth  = {34, 84, 40, '1x', 50, 18};
                obj.handles.mainGridLayout.ColumnSpacing = 5;
                obj.handles.mainGridLayout.RowSpacing    = 6;
                obj.handles.mainGridLayout.Padding       = [8 8 8 8];

            case 'bottom'
                % already in bottom layout (6 rows) — nothing to do
                if numel(obj.handles.mainGridLayout.RowHeight) == 6; return; end
                % transpose: row 1 → col 1 (spanning), row 2 → col 2 (per widget),
                %            row 3 → col 3 (spanning)
                for i = 1:numel(children)
                    r = children(i).Layout.Row;
                    if r == 1         % fileList
                        children(i).Layout.Row    = [1 6];
                        children(i).Layout.Column = 1;
                    elseif r == 2     % toolbar widgets: col index becomes row index
                        children(i).Layout.Row    = children(i).Layout.Column;
                        children(i).Layout.Column = 2;
                    elseif r == 3     % dividerPanel
                        children(i).Layout.Row    = [1 6];
                        children(i).Layout.Column = 3;
                    end
                end
                obj.handles.mainGridLayout.RowHeight    = {22, 22, 22, '1x', 22, 22};
                obj.handles.mainGridLayout.ColumnWidth  = {240, 130, 2};
                obj.handles.mainGridLayout.ColumnSpacing = 5;
                obj.handles.mainGridLayout.RowSpacing    = 6;
                obj.handles.mainGridLayout.Padding       = [8 8 8 8];
        end
end

end
