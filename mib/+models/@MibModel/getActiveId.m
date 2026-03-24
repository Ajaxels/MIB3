function id = getActiveId(obj)
% function id = getActiveId(obj)
% Compute the correct dataset index from Sets.selectedSet
%
% In split-panel mode, mouse motion over a different document silently
% updates obj.id via gui_WinMouseMotionFcn.  This makes obj.id unreliable
% when used as a default in BatchOpt initialisation.  This method computes
% the id from Sets.selectedSet and Sets.selectedDataset, which are only
% changed through the full UI chain and are therefore always correct.
%
% Parameters:
%   none
%
% Return values:
% id: numeric, the dataset index (1..datasetsInSet*numberOfSets)
%
%|
% @b Examples:
% @code id = obj.mibModel.getActiveId();  // get the reliable dataset index @endcode

% Updates

selSet = obj.Sets.selectedSet;
id = obj.Sets.selectedDataset(selSet) + (selSet - 1) * obj.Sets.datasetsInSet;
end
