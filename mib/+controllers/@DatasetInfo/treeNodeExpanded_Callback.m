function treeNodeExpanded_Callback(obj, ~, event)
% TREENODEEXPANDED_CALLBACK - Populate a deferred tree node on first expand.
%
% Syntax:
%   .. code-block:: matlab
%
%      tree.NodeExpandedFcn = @obj.treeNodeExpanded_Callback
%
% Fired by ``uitree.NodeExpandedFcn``.  When a section was created with a
% ``'Loading...'`` placeholder child (deferred by :meth:`updateWidgets`),
% this callback removes the placeholder and inserts real child nodes from
% the active dataset metadata.  After populating, the node is kept expanded
% and the flat search index is refreshed.

node = event.Node;
nodeData = node.NodeData;

% Only act on deferred nodes that still carry the loading placeholder.
if isempty(node.Children); return; end
if ~isfield(node.Children(1).NodeData, 'key'); return; end
if ~strcmp(node.Children(1).NodeData.key, '__loading__'); return; end

% Remove the placeholder before adding real children.
delete(node.Children);

datasetId = obj.mibModel.getActiveId();
meta = obj.mibModel.I{datasetId}.image.getMeta();

switch nodeData.populationType
    case 'struct_fields'
        value = meta{nodeData.key};
        fieldNamesList = fieldnames(value);
        for fieldIdx = 1:numel(fieldNamesList)
            fieldValue = value.(fieldNamesList{fieldIdx});
            if isnumeric(fieldValue)
                displayText = sprintf('%s: %s', fieldNamesList{fieldIdx}, num2str(fieldValue));
            else
                displayText = sprintf('%s: %s', fieldNamesList{fieldIdx}, char(string(fieldValue)));
            end
            uitreenode(node, 'Text', displayText, ...
                'NodeData', struct('key', nodeData.key, 'subIndex', fieldNamesList{fieldIdx}, 'populationType', ''));
        end

    case 'cell_items'
        value = meta{nodeData.key};
        for itemIdx = 1:numel(value)
            uitreenode(node, 'Text', char(string(value{itemIdx})), ...
                'NodeData', struct('key', nodeData.key, 'subIndex', itemIdx, 'populationType', ''));
        end

    case 'matrix_rows'
        value = meta{nodeData.key};
        for rowIdx = 1:size(value, 1)
            uitreenode(node, 'Text', num2str(value(rowIdx, :)), ...
                'NodeData', struct('key', nodeData.key, 'subIndex', rowIdx, 'populationType', ''));
        end

    case 'customMeta'
        customMetaValue = meta{'customMeta'};
        addStructToTree(node, customMetaValue);

    case 'pyramid_levels'
        pyramid = obj.mibModel.I{datasetId}.image.pyramid;
        nLevels = size(pyramid.levelScaleFactors, 1);
        for levelIdx = 1:nLevels
            scale  = pyramid.levelScaleFactors(levelIdx, 1);
            dims   = pyramid.levelImageSizes(levelIdx, 1:2);     % [Y X] pixels

            levelText = sprintf('Level %d (%c%g): %d %c %d px', ...
                levelIdx, char(215), scale, dims(2), char(215), dims(1));

            % chunk dimensions (last 2 elements of TCZYX shape = Y, X)
            if iscell(pyramid.chunkSizes) && levelIdx <= numel(pyramid.chunkSizes) ...
                    && ~isempty(pyramid.chunkSizes{levelIdx})
                chunkShape = pyramid.chunkSizes{levelIdx};
                if numel(chunkShape) >= 2
                    chunkYX = chunkShape(end-1:end);
                    levelText = [levelText, sprintf('  chunk %d%c%d', ...
                        chunkYX(1), char(215), chunkYX(2))]; %#ok<AGROW>
                end
            end

            % shard dimensions (same TCZYX convention)
            if iscell(pyramid.shardSizes) && levelIdx <= numel(pyramid.shardSizes) ...
                    && ~isempty(pyramid.shardSizes{levelIdx})
                shardShape = pyramid.shardSizes{levelIdx};
                if numel(shardShape) >= 2
                    shardYX = shardShape(end-1:end);
                    levelText = [levelText, sprintf('  shard %d%c%d', ...
                        shardYX(1), char(215), shardYX(2))]; %#ok<AGROW>
                end
            end

            % effective voxel size: per-level row if Zarr, else scale the full-res row
            if ~isempty(pyramid.levelVoxelSizes)
                if size(pyramid.levelVoxelSizes, 1) >= levelIdx
                    voxelX = pyramid.levelVoxelSizes(levelIdx, 2);
                else
                    voxelX = pyramid.levelVoxelSizes(1, 2) * scale;
                end
                levelText = [levelText, sprintf('  %.4g %sm/px', voxelX, char(956))]; %#ok<AGROW>
            end

            uitreenode(node, 'Text', levelText, ...
                'NodeData', struct('key', '__pyramid__', 'subIndex', levelIdx, 'populationType', ''));
        end

    case 'extras'
        scalarKeyNames = ["Filename", "Height", "Width", "Depth", "Time", ...
            "Colors", "ColorType", "imgClass", "MaxInt", "ImageDescription"];
        structKeyNames  = ["pixSize", "viewPort"];
        cellKeyNames    = ["SliceName", "ActionLog"];
        matrixKeyNames  = ["lutColors", "Colormap", "SliceSize"];
        processedKeyNames = [scalarKeyNames, structKeyNames, cellKeyNames, matrixKeyNames, "customMeta"];
        allKeys = keys(meta);
        extraKeyNames = allKeys(~ismember(allKeys, processedKeyNames));
        for keyIdx = 1:numel(extraKeyNames)
            try
                value = meta{extraKeyNames(keyIdx)};
                addExtraNode(node, extraKeyNames(keyIdx), value);
            catch
                % skip entries that cannot be displayed
            end
        end
end

% Keep the node expanded now that real children are in place.
expand(node);

% Refresh flat node list so the search covers newly populated nodes.
obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);
end

% =====================================================================
%  Local helper — adds a single extra-key node (any value type)
% =====================================================================
function addExtraNode(parentNode, keyName, value)

if isnumeric(value) && numel(value) <= 10
    displayText = sprintf('%s: %s', keyName, num2str(value));
    uitreenode(parentNode, 'Text', displayText, ...
        'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));

elseif ischar(value) || isstring(value)
    displayText = sprintf('%s: %s', keyName, char(value));
    uitreenode(parentNode, 'Text', displayText, ...
        'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));

elseif iscell(value)
    if numel(value) == 1
        displayText = sprintf('%s: %s', keyName, char(string(value{1})));
        uitreenode(parentNode, 'Text', displayText, ...
            'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));
    else
        cellParent = uitreenode(parentNode, 'Text', char(keyName), ...
            'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));
        for itemIdx = 1:numel(value)
            uitreenode(cellParent, 'Text', char(string(value{itemIdx})), ...
                'NodeData', struct('key', keyName, 'subIndex', itemIdx, 'populationType', ''));
        end
    end

elseif isstruct(value)
    structParent = uitreenode(parentNode, 'Text', char(keyName), ...
        'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));
    fieldNamesList = fieldnames(value);
    for fieldIdx = 1:numel(fieldNamesList)
        fieldValue = value.(fieldNamesList{fieldIdx});
        if isnumeric(fieldValue)
            displayText = sprintf('%s: %s', fieldNamesList{fieldIdx}, num2str(fieldValue));
        elseif ~isstruct(fieldValue)
            displayText = sprintf('%s: %s', fieldNamesList{fieldIdx}, char(string(fieldValue)));
        else
            displayText = fieldNamesList{fieldIdx};
        end
        uitreenode(structParent, 'Text', displayText, ...
            'NodeData', struct('key', keyName, 'subIndex', fieldNamesList{fieldIdx}, 'populationType', ''));
    end

elseif isnumeric(value)
    displayText = sprintf('%s: [%s]', keyName, num2str(size(value)));
    uitreenode(parentNode, 'Text', displayText, ...
        'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));

else
    displayText = sprintf('%s: %s', keyName, char(string(value)));
    uitreenode(parentNode, 'Text', displayText, ...
        'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));
end
end

% =====================================================================
%  Local helper — recursively add a struct to the tree
%  (for BioFormats XML customMeta etc.)
% =====================================================================
function addStructToTree(parentNode, s)

fieldNamesList = fieldnames(s);
for fieldIdx = 1:numel(fieldNamesList)
    fieldName = fieldNamesList{fieldIdx};

    % Substitute special characters from struct2xml encoding.
    displayName = strrep(fieldName, '_dash_', '-');
    displayName = strrep(displayName, '_colon_', ':');
    displayName = strrep(displayName, '_dot_', '.');

    fieldValue = s.(fieldName);

    if strcmp(fieldName, 'Attributes')
        if isstruct(fieldValue)
            addStructToTree(parentNode, fieldValue);
        end
        continue;
    elseif strcmp(fieldName, 'AttributesText')
        continue;
    elseif strcmp(fieldName, 'Text')
        if ~isempty(fieldValue)
            uitreenode(parentNode, 'Text', char(string(fieldValue)), ...
                'NodeData', struct('key', 'customMeta', 'subIndex', fieldName, 'populationType', ''));
        end
    elseif isstruct(fieldValue)
        childNode = uitreenode(parentNode, 'Text', displayName, ...
            'NodeData', struct('key', 'customMeta', 'subIndex', fieldName, 'populationType', ''));
        addStructToTree(childNode, fieldValue);
    elseif iscell(fieldValue)
        for cellIdx = 1:numel(fieldValue)
            childNode = uitreenode(parentNode, 'Text', sprintf('%s (%d)', displayName, cellIdx), ...
                'NodeData', struct('key', 'customMeta', 'subIndex', fieldName, 'cellIndex', cellIdx, 'populationType', ''));
            if isstruct(fieldValue{cellIdx})
                addStructToTree(childNode, fieldValue{cellIdx});
            end
        end
    else
        displayText = sprintf('%s: %s', displayName, char(string(fieldValue)));
        uitreenode(parentNode, 'Text', displayText, ...
            'NodeData', struct('key', 'customMeta', 'subIndex', fieldName, 'populationType', ''));
    end
end
end
