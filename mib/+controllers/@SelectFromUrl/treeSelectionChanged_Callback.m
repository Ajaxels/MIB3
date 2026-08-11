function treeSelectionChanged_Callback(obj, event)
% TREESELECTIONCHANGED_CALLBACK - Describe the newly selected group.
%
% Syntax:
%   .. code-block:: matlab
%
%      tree.SelectionChangedFcn = @(~,e) obj.treeSelectionChanged_Callback(e)
%
% Two small cached metadata reads per selection - the group's attributes and its
% level-0 array header. Selecting is how the user asks "what is this?", so it
% has to answer without opening anything.
%
% **Several nodes may be selected at once.** That is how a ground-truth crop is
% loaded: each COSEM class is its own group, and a useful model is a blend of
% them. The full selection is recorded in ``BatchOpt.LabelGroups`` **in click
% order**, which is load-bearing - where two classes overlap, the later pick
% wins. Only the first node is described in the info panel, since the pyramid
% geometry is shared by every group of a crop.
%
% Input Arguments:
%   - **event** - [event data] carries ``.SelectedNodes``

selectedNodes = event.SelectedNodes;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.SelectFromUrl.treeSelectionChanged_Callback: %d node(s)\n', ...
        numel(selectedNodes));
end

if isempty(selectedNodes); return; end

selectedPaths = {};
for nodeIndex = 1:numel(selectedNodes)
    nodeData = selectedNodes(nodeIndex).NodeData;
    if ~isstruct(nodeData) || ~isfield(nodeData, 'url') || isempty(nodeData.url); continue; end
    selectedPaths{end+1} = io.RemoteStore.relativePath(obj.rootUrl, nodeData.url); %#ok<AGROW>
end
if isempty(selectedPaths); return; end

obj.BatchOpt.LabelGroups = strjoin(selectedPaths, ';');

if numel(selectedPaths) > 1
    obj.setStatus(sprintf('%d groups selected; they will be blended in click order.', ...
        numel(selectedPaths)));
end

obj.probeGroup(io.RemoteStore.join(obj.rootUrl, selectedPaths{1}));
end
