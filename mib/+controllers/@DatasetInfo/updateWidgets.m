function updateWidgets(obj)
% UPDATEWIDGETS - Build the metadata tree skeleton from the active dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateWidgets()
%
% Builds only the first-level skeleton: scalar leaf nodes are rendered
% immediately; any section that would contain multiple child nodes
% (pixSize, SliceName, Colormap, Extras, customMeta, …) gets a single
% ``'Loading…'`` placeholder child instead.  Real children are populated
% on demand by :meth:`treeNodeExpanded_Callback` when the user expands a
% section.  This makes every dataset-switch update nearly instantaneous
% regardless of dataset size.

tree = obj.view.handles.metaTree;
tree.NodeExpandedFcn = @obj.treeNodeExpanded_Callback;

if ~isempty(tree.Children)
    delete(tree.Children);
end

% Suppress per-node redraws while building the skeleton.
tree.Visible = 'off';

obj.foundNodeIndex = 0;
obj.allTreeNodes = {};

datasetId = obj.mibModel.getActiveId();
meta = obj.mibModel.I{datasetId}.image.getMeta();
allKeys = keys(meta);

% root node
rootNode = uitreenode(tree, ...
    'Text', 'meta', ...
    'NodeData', struct('key', 'meta', 'subIndex', [], 'populationType', ''));

% ---- Scalar keys — rendered immediately as leaf nodes ----
scalarKeyNames = ["Filename", "Height", "Width", "Depth", "Time", ...
    "Colors", "ColorType", "imgClass", "MaxInt", "ImageDescription"];
presentMask = isKey(meta, scalarKeyNames);

for keyIdx = find(presentMask)
    keyName = scalarKeyNames(keyIdx);
    value = meta{keyName};

    if isnumeric(value) && numel(value) <= 1
        displayText = sprintf('%s: %s', keyName, num2str(value));
    elseif ischar(value) || isstring(value)
        displayText = sprintf('%s: %s', keyName, char(value));
    else
        displayText = sprintf('%s: %s', keyName, mat2str(value));
    end

    uitreenode(rootNode, ...
        'Text', displayText, ...
        'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));
end

% ---- Struct keys — deferred ----
structKeyNames = ["pixSize", "viewPort"];
presentMask = isKey(meta, structKeyNames);

for keyIdx = find(presentMask)
    keyName = structKeyNames(keyIdx);
    value = meta{keyName};
    if ~isstruct(value); continue; end

    parentNode = uitreenode(rootNode, ...
        'Text', char(keyName), ...
        'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', 'struct_fields'));
    addLoadingPlaceholder(parentNode);
end

% ---- Cell array keys — deferred for multi-item ----
cellKeyNames = ["SliceName", "ActionLog"];
presentMask = isKey(meta, cellKeyNames);

for keyIdx = find(presentMask)
    keyName = cellKeyNames(keyIdx);
    value = meta{keyName};
    if isempty(value) || ~iscell(value); continue; end

    if numel(value) == 1
        displayText = sprintf('%s: %s', keyName, char(string(value{1})));
        uitreenode(rootNode, ...
            'Text', displayText, ...
            'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));
    else
        parentNode = uitreenode(rootNode, ...
            'Text', char(keyName), ...
            'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', 'cell_items'));
        addLoadingPlaceholder(parentNode);
    end
end

% ---- Matrix keys — deferred for multi-row ----
matrixKeyNames = ["lutColors", "Colormap", "SliceSize"];
presentMask = isKey(meta, matrixKeyNames);

for keyIdx = find(presentMask)
    keyName = matrixKeyNames(keyIdx);
    value = meta{keyName};
    if isempty(value) || ~isnumeric(value); continue; end

    if size(value, 1) == 1
        displayText = sprintf('%s: %s', keyName, num2str(value));
        uitreenode(rootNode, ...
            'Text', displayText, ...
            'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', ''));
    else
        parentNode = uitreenode(rootNode, ...
            'Text', char(keyName), ...
            'NodeData', struct('key', keyName, 'subIndex', [], 'populationType', 'matrix_rows'));
        addLoadingPlaceholder(parentNode);
    end
end

% ---- customMeta — deferred ----
if isKey(meta, 'customMeta')
    customMetaValue = meta{'customMeta'};
    if isstruct(customMetaValue) && ~isempty(fieldnames(customMetaValue))
        customMetaNode = uitreenode(rootNode, ...
            'Text', 'customMeta', ...
            'NodeData', struct('key', 'customMeta', 'subIndex', [], 'populationType', 'customMeta'));
        addLoadingPlaceholder(customMetaNode);
    end
end

% ---- Extras — deferred ----
processedKeyNames = [scalarKeyNames, structKeyNames, cellKeyNames, matrixKeyNames, "customMeta"];
extraKeyNames = allKeys(~ismember(allKeys, processedKeyNames));

if ~isempty(extraKeyNames)
    extrasNode = uitreenode(rootNode, ...
        'Text', 'Extras', ...
        'NodeData', struct('key', '__extras__', 'subIndex', [], 'populationType', 'extras'));
    addLoadingPlaceholder(extrasNode);
end

% ---- Image pyramid (BigData / pyramidal Virtual datasets) — deferred ----
pyramid = obj.mibModel.I{datasetId}.image.pyramid;
if ~isempty(pyramid.levelNames)
    nLevels = size(pyramid.levelScaleFactors, 1);
    scaleCoarsest = pyramid.levelScaleFactors(end, 1);
    pyramidNode = uitreenode(rootNode, ...
        'Text', sprintf('Image pyramid: %d levels  (%c1 … %c%g)', ...
            nLevels, char(215), char(215), scaleCoarsest), ...
        'NodeData', struct('key', '__pyramid__', 'subIndex', [], 'populationType', 'pyramid_levels'));
    addLoadingPlaceholder(pyramidNode);
end

% Restore rendering and expand root to show first level.
tree.Visible = 'on';
expand(rootNode);

% Build flat node list for search (skeleton only; updated on each expansion).
obj.allTreeNodes = obj.flattenTreeNodes(tree);

% Build complete metadata search list (includes collapsed sections).
obj.metaSearchList = obj.buildMetaSearchList();

% Restore selection — works for first-level nodes; child nodes inside a
% deferred section are not found until that section is expanded.
if ~isempty(obj.selectedNodeText) && ~isempty(obj.allTreeNodes)
    searchPrefix = [obj.selectedNodeText, ':'];
    for nodeIdx = 1:numel(obj.allTreeNodes)
        nodeText = obj.allTreeNodes{nodeIdx}.Text;
        if strcmp(nodeText, obj.selectedNodeText) || startsWith(nodeText, searchPrefix)
            obj.view.handles.metaTree.SelectedNodes = obj.allTreeNodes{nodeIdx};
            scroll(obj.view.handles.metaTree, obj.allTreeNodes{nodeIdx});
            break;
        end
    end
end
end

% =====================================================================
%  Local helper — insert a 'Loading…' sentinel as the sole child of a
%  deferred parent so the tree widget shows an expand arrow.
% =====================================================================
function addLoadingPlaceholder(parentNode)
uitreenode(parentNode, ...
    'Text', 'Loading...', ...
    'NodeData', struct('key', '__loading__', 'subIndex', [], 'populationType', ''));
end
