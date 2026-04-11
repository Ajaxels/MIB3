function partnerId = getLinkedDataset(obj, id)
% function partnerId = getLinkedDataset(obj, id)
% Return the global dataset ID of the linked partner, or [] if not linked.
%
% Searches @code obj.linkedPairs @endcode (n×2 array of [idA idB] global ID
% pairs) for a row that contains @em id and returns the other column value.
%
% Parameters:
% id: (1,1) double, global dataset ID to look up
%
% Return values:
% partnerId: scalar double with the partner's global ID, or [] if id is not
%   part of any linked pair

%|
% @b Examples:
% @code partnerId = obj.mibModel.getLinkedDataset(3); @endcode

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
