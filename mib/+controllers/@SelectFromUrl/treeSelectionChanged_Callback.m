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
% Input Arguments:
%   - **event** - [event data] carries ``.SelectedNodes``

selectedNodes = event.SelectedNodes;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.SelectFromUrl.treeSelectionChanged_Callback: triggered\n');
end

if isempty(selectedNodes); return; end

nodeData = selectedNodes(1).NodeData;
if ~isstruct(nodeData) || ~isfield(nodeData, 'url') || isempty(nodeData.url); return; end

obj.probeGroup(nodeData.url);
end
