function setActiveNode(obj, x, y, z, orientation)
% SETACTIVENODE - Set the active node closest to a given coordinate.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setActiveNode(x, y, z, orientation)
%
% Activates the node that is closest to the specified point coordinates.
%
% Input Arguments:
%   - **x** - [numeric] x coordinate of the reference point
%   - **y** - [numeric] y coordinate of the reference point
%   - **z** - [numeric] z coordinate of the reference point
%   - **orientation** - *(optional)* [numeric] image orientation; allowed values:
%
%     - ``3`` - YX plane (default)
%     - ``1`` - XZ plane
%     - ``2`` - YZ plane
%

if nargin < 5; orientation = 3; end

nodeId = obj.findClosestNode(x, y, z, orientation);
if isempty(nodeId); return; end     % no node
obj.activeNodeId = nodeId(1);

end
