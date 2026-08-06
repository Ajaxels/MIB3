function id = getActiveId(obj)
% GETACTIVEID - Compute the correct dataset index from Sets.selectedSet.
%
% Syntax:
%   .. code-block:: matlab
%
%       id = obj.getActiveId()
%
% In split-panel mode, mouse motion over a different document silently
% updates obj.id via gui_WinMouseMotionFcn.  This makes obj.id unreliable
% when used as a default in BatchOpt initialisation.  This method computes
% the id from Sets.selectedSet and Sets.selectedDataset, which are only
% changed through the full UI chain and are therefore always correct.
%
% Output Arguments:
%   - **id** - [numeric] the dataset index (1..datasetsInSet*numberOfSets)
%
% **Example 1** - get the reliable dataset index:
%
%   .. code-block:: matlab
%
%      id = obj.mibModel.getActiveId();

% Updates

selSet = obj.Sets.selectedSet;
id = obj.Sets.selectedDataset(selSet) + (selSet - 1) * obj.Sets.datasetsInSet;
end
