function updateNodeStrel(obj, nodeStrelSize)
% function updateNodeStrel(obj, nodeStrelSize)
% update strel element for showing nodes as circles
%
% Parameters:
% nodeStrelSize: radius of the strel element

if verLessThan('matlab', '9')
    obj.nodeStrel = strel('disk', nodeStrelSize);
else
    se = strel('sphere', nodeStrelSize);
    obj.nodeStrel = se.Neighborhood(:, :, ceil(nodeStrelSize/2));
end

end
