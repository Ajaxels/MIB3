function partnerId = getLinkedDataset(obj, id)
% GETLINKEDDATASET - Return the global dataset ID of the linked partner, or [] if not linked.
%
% Syntax:
%   .. code-block:: matlab
%
%       partnerId = obj.getLinkedDataset(id)
%
% Searches ``obj.linkedPairs`` (n×2 array of [idA idB] global ID
% pairs) for a row that contains *id* and returns the other column value.
%
% Input Arguments:
%   - **id** — (1,1) double, global dataset ID to look up
%
% Output Arguments:
%   - **partnerId** — scalar double with the partner's global ID, or [] if id is not
%     part of any linked pair
%
% Usage:
%   **Example 1** — look up the linked partner for dataset 3
%
%   .. code-block:: matlab
%
%      partnerId = obj.mibModel.getLinkedDataset(3);
%

if isempty(obj.linkedPairs)
    partnerId = [];
    return;
end

rowA = obj.linkedPairs(:,1) == id;
rowB = obj.linkedPairs(:,2) == id;

if any(rowA)
    partnerId = obj.linkedPairs(find(rowA, 1), 2);
elseif any(rowB)
    partnerId = obj.linkedPairs(find(rowB, 1), 1);
else
    partnerId = [];
end
end
