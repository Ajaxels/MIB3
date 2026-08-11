function treeNodeExpanded_Callback(obj, event)
% TREENODEEXPANDED_CALLBACK - Fill a tree node on its first expand.
%
% Syntax:
%   .. code-block:: matlab
%
%      tree.NodeExpandedFcn = @(~,e) obj.treeNodeExpanded_Callback(e)
%
% One ``ListObjectsV2`` request per expand, and only the first time a node is
% opened - the same deferred-placeholder pattern as
% ``controllers.DatasetInfo.treeNodeExpanded_Callback``. Lazy expansion is the
% whole point of this dialog: enumerating a published container up front would
% cost hundreds of requests, because the interesting image group usually sits
% beside a very large labels subtree.
%
% Input Arguments:
%   - **event** - [event data] carries ``.Node``, the node being expanded

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.SelectFromUrl.treeNodeExpanded_Callback(%s): triggered\n', event.Node.Text);
end

node = event.Node;
nodeData = node.NodeData;

if ~isstruct(nodeData) || ~isfield(nodeData, 'expanded'); return; end
if nodeData.expanded; return; end       % already filled

obj.setStatus('Listing...');
drawnow limitrate;

[childUrls, childNames] = io.RemoteStore.listChildren(nodeData.url);

delete(node.Children);      % drop the "loading..." placeholder
nodeData.expanded = true;
node.NodeData = nodeData;

for childIndex = 1:numel(childUrls)
    childNode = uitreenode(node, ...
        'Text', obj.nodeLabel(childUrls{childIndex}, childNames{childIndex}), ...
        'NodeData', struct('url', childUrls{childIndex}, 'expanded', false));
    % A placeholder gives the node an expand arrow without listing it now.
    uitreenode(childNode, 'Text', 'loading...', ...
        'NodeData', struct('url', '', 'expanded', false));
end

if isempty(childUrls)
    obj.setStatus('No sub-groups here.');
else
    obj.setStatus(sprintf('%d sub-group(s).', numel(childUrls)));
end
end
