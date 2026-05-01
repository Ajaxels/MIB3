function updateNodeStrel(obj, nodeStrelSize)
% UPDATENODESTREL - update strel element for showing nodes as circles.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateNodeStrel(nodeStrelSize)
%
% Input Arguments:
%   - **nodeStrelSize** — radius of the strel element
%

if verLessThan('matlab', '9')
    obj.nodeStrel = strel('disk', nodeStrelSize);
else
    se = strel('sphere', nodeStrelSize);
    obj.nodeStrel = se.Neighborhood(:, :, ceil(nodeStrelSize/2));
end

end
