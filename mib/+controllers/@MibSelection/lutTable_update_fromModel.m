function lutTable_update_fromModel(obj)
% LUTTABLE_UPDATE_FROMMODEL - Update obj.view.handles.panels.selection.handles.lutTable table and.
%
% Syntax:
%   function lutTable_update_fromModel(obj)
%
% obj.view.handles.panels.selection.handles.colChannel color dropdown from
% obj.mibModel
%
% Input Arguments:
%
% Output Arguments:
%

% Updates
% 

% update color combo box and channel mixer table
%pause(0.1);

maxColors = obj.mibModel.I{obj.mibModel.id}.image.colors;
slices = obj.mibModel.I{obj.mibModel.id}.slices;
lutColors = obj.mibModel.I{obj.mibModel.id}.image.lutColors;

% Create channel names
col_channels = ['All', arrayfun(@(x) sprintf('Ch %d', x), 1:maxColors, 'UniformOutput', false)];

% Check which channels are visualized using slices{4}
data = ismember(1:maxColors, slices{4})';
% Update dropdown (uidropdown) for App Designer
obj.view.handles.panels.selection.handles.colChannel.Items = col_channels;
obj.view.handles.panels.selection.handles.colChannel.Value = col_channels{obj.mibModel.I{obj.mibModel.id}.selectedColorChannel+1};

% generate tableData
numChannels = numel(data);
tableData = [num2cell((1:numChannels)'), num2cell(data), repmat({''}, numChannels, 1)];
useLut = obj.view.handles.panels.selection.handles.lutColors.Value;
displayedLutColors = nan(numChannels, 3);
bgColors = ones(numChannels, 3);

if useLut
    % LUT mode: simple vectorized assignment
    activeChannels = data == 1;
    displayedLutColors(activeChannels, :) = lutColors(activeChannels, :);
    bgColors(activeChannels, :) = lutColors(activeChannels, :);
else
    % Non-LUT mode: compute color assignments
    numActive = sum(data);
    activeIndices = find(data);

    if numActive == 1
        % Single channel: black
        displayedLutColors(activeIndices, :) = [0, 0, 0];
        bgColors(activeIndices, :) = [0, 0, 0];
    elseif numActive == 2
        if maxColors < 4 || activeIndices(end) < 4
            % 3 or fewer channels: preserve RGB mapping
            colorMap = [1 0 0; 0 1 0; 0 0 1];
            for i = 1:numActive
                idx = activeIndices(i);
                if idx <= 3
                    displayedLutColors(idx, :) = colorMap(idx, :);
                    bgColors(idx, :) = colorMap(idx, :);
                end
            end
        else
            % 4+ channels: use red and green for first two
            colorMap = [1 0 0; 0 1 0];
            for i = 1:min(2, numActive)
                idx = activeIndices(i);
                displayedLutColors(idx, :) = colorMap(i, :);
                bgColors(idx, :) = colorMap(i, :);
            end
        end
    else % 3 or more active channels
        % Show first 3 as RGB
        colorMap = [1 0 0; 0 1 0; 0 0 1];
        for i = 1:min(3, numActive)
            idx = activeIndices(i);
            displayedLutColors(idx, :) = colorMap(i, :);
            bgColors(idx, :) = colorMap(i, :);
        end
    end

    % Mark inactive channels with 'X'
    inactiveChannels = data == 0;
    tableData(inactiveChannels, 3) = {'X'};
end

% Update obj.view.handles.panels.selection.handles.lutTable
obj.view.handles.panels.selection.handles.lutTable.Data = tableData;
obj.view.handles.panels.selection.handles.lutTable.ColumnWidth = {25, 35, '1x'};
obj.view.handles.panels.selection.handles.lutTable.ColumnEditable = [false, true, false];

% remove headers from the table (removed in MibView.addSelectionViewSettingsPanel)
%obj.view.handles.panels.selection.handles.lutTable.ColumnName = {};

% Apply row-based styling using uistyle (App Designer approach)
% Remove any existing styles first
removeStyle(obj.view.handles.panels.selection.handles.lutTable);

% Apply background colors to the color column (column 3)
for rowId = 1:size(bgColors, 1)
    if ~any(isnan(displayedLutColors(rowId, :)))
        s = uistyle('BackgroundColor', bgColors(rowId, :));
        addStyle(obj.view.handles.panels.selection.handles.lutTable, s, 'cell', [rowId, 3]);
    end
end

%obj.mibModel.displayedLutColors = displayedLutColors;
end
