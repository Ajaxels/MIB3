function materialsTable_applyRowStyle(obj, rowIndex, isHighlighted, columnIndex, fontColor, highlightColor)
% MATERIALSTABLE_APPLYROWSTYLE - Apply highlighting style to material row.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.materialsTable_applyRowStyle(rowIndex, isHighlighted, columnIndex, fontColor, highlightColor)
%
% Input Arguments:
%   obj - Controller object
%   rowIndex - Row index to style (1-based)
%   isHighlighted - true to highlight, false to restore original color
%   columnIndex - specific column(s) to style
%   fontColor - Font color to use
%   highlightColor - Background color for highlighting (empty for the plain cell color)
%

tableHandle = obj.handles.materialsTable;

% Determine background color
if isHighlighted && ~isempty(highlightColor)
    bgColor = highlightColor;
else
    % Restore original background of columns 2-3, white or dark depending on the theme
    bgColor = utils.themeColors(obj.UIFigure).tableCell;
end

% Create and apply style
cellStyle = uistyle('BackgroundColor', bgColor, 'FontColor', fontColor);

% Apply to specified columns
for col = columnIndex
    addStyle(tableHandle, cellStyle, 'cell', [rowIndex, col]);
end

end
